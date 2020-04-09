# Copyright (C) 2016--2018 Karl Wette
#
# This file is part of PDF Librarian.
#
# PDF Librarian is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
#
# PDF Librarian is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with PDF Librarian. If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;

package pdflibrarian::bibtex;
use Exporter 'import';

use Capture::Tiny;
use Carp;
use Digest::SHA;
use Encode;
use File::Temp;
use FindBin qw($Script);
use List::Util qw(max);
use Scalar::Util qw(blessed);
use Text::BibTeX::Bib;
use Text::BibTeX::NameFormat;
use Text::BibTeX;
use Text::Unidecode;
use Text::Wrap;
use XML::LibXML;
use XML::LibXSLT;

use pdflibrarian::config;
use pdflibrarian::util qw(open_pdf_file keyword_display_str parallel_loop remove_tex_markup remove_short_words);

our @EXPORT_OK = qw(bib_checksum read_bib_from_str read_bib_from_file read_bib_from_pdf write_bib_to_fh write_bib_to_pdf edit_bib_in_fh find_dup_bib_keys format_bib_authors generate_bib_keys);

# BibTeX database structure
my $structure = new Text::BibTeX::Structure('Bib');
foreach my $type ($structure->types()) {
  $structure->add_fields($type, [qw(keyword file title year)], [qw(collaboration)]);
}

1;

sub bib_checksum {
  my ($bibentry, @exclude) = @_;

  # generate a checksum for a BibTeX entry
  push @exclude, 'checksum';
  my $digest = Digest::SHA->new();
  $digest->add($bibentry->type, $bibentry->key);
  foreach my $bibfield (sort { $a cmp $b } $bibentry->fieldlist()) {
    next if grep /^$bibfield$/, @exclude;
    $digest->add($bibfield, $bibentry->get($bibfield));
  }

  return $digest->hexdigest;
}

sub read_bib_from_str {
  my ($bibstr) = @_;

  # read BibTeX entry from a string
  my $bibentry = new Text::BibTeX::BibEntry $bibstr;
  croak "$Script: failed to parse BibTeX entry" unless $bibentry->parse_ok;
  $bibentry->{structure} = $structure;

  return $bibentry;
}

sub read_bib_from_file {
  my ($errors, $bibentries, $filename) = @_;
  die unless ref($errors) eq 'ARRAY';
  die unless ref($bibentries) eq 'ARRAY';

  # initialise output arrays
  @$errors = ();
  @$bibentries = ();

  # check that the file contains non-comment, non-enpty lines
  {
    my $nonempty = 1;
    open(my $fh, $filename) or croak "$Script: could not open file '$filename': $!";
    while (<$fh>) {
      next if /^%/;
      next if /^\s*$/;
      $nonempty = 0;
      last;
    }
    $fh->close();
    return if $nonempty;
  }

  # parse the BibTeX file, capturing any error messages
  my $errmsgs;
  {
    my $bib = new Text::BibTeX::File $filename or croak "$Script: could not open file '$filename'";
    $bib->{structure} = $structure;
    $errmsgs = Capture::Tiny::capture_merged {
      while (my $bibentry = new Text::BibTeX::BibEntry $bib) {
        next unless $bibentry->parse_ok;
        next unless $bibentry->check();
        push @$bibentries, $bibentry;
      }
    };
    $bib->close();
  }

  # remove 'file' field from Text::BibTeX::BibEntry, since it
  # contains a GLOB item that cannot be serialised by Storable
  foreach my $bibentry (@$bibentries) {
    delete($bibentry->{file}) if defined($bibentry->{file});
  }

  # format error messages, if any
  if (length($errmsgs) > 0) {
    foreach my $msg (split(/\n/, $errmsgs)) {
      $msg =~ s/^$filename,\s*//;
      if ($msg =~ /^line (\d+)[,:]?\s*(.*)$/) {
        push @$errors, { from => $1, msg => $2 };
      } elsif ($msg =~ /^lines (\d+)-(\d+)[,:]?\s*(.*)$/) {
        push @$errors, { from => $1, to => $2, msg => $3 };
      } else {
        push @$errors, { msg => $msg };
      }
    }
  }

}

sub read_bib_from_pdf {
  my (@pdffiles) = @_;

  # get location of BibTeX XSLT style file
  my $xsltbibtex = File::Spec->catfile($xsltdir, 'bibtex.xsl');
  croak "$Script: missing XSLT style file '$xsltbibtex'" unless -f $xsltbibtex;

  # read BibTeX entries from PDF files
  my $body = sub {
    my ($pdffile) = @_;

    # open PDF file and read XMP metadata
    my $pdf = open_pdf_file($pdffile);
    my $xmp = "";
    eval {
      $xmp = $pdf->xmpMetadata() // "";
    };
    $xmp = "" unless $xmp =~ /<\?xpacket /;
    $xmp =~ s/\s*<\?xpacket .*\?>\s*//g;
    $pdf->end();

    # convert BibTeX XML (if any) to parsed BibTeX entry
    my $bibstr = '@article{key,}';
    if (length($xmp) > 0) {
      my $xml = XML::LibXML->load_xml(string => $xmp);
      my $xslt = XML::LibXSLT->new();
      my $xsltstylesrc = XML::LibXML->load_xml(location => $xsltbibtex);
      my $xsltstyle = $xslt->parse_stylesheet($xsltstylesrc);
      my $bib = $xsltstyle->transform($xml);
      my $bibtext = $bib->textContent();
      $bibtext =~ s/^\s+//;
      $bibtext =~ s/\s+$//;
      if (length($bibtext) > 0) {
        $bibstr = $bibtext;
      }
    }
    my $bibentry = read_bib_from_str($bibstr);

    # save name of PDF file
    $bibentry->set('file', $pdffile);

    return $bibentry;
  };
  my @bibentries = parallel_loop("reading BibTeX entries from %i/%i PDF files", \@pdffiles, $body);

  # add checksums to BibTeX entries
  foreach my $bibentry (@bibentries) {
    my $checksum = bib_checksum($bibentry);
    $bibentry->set('checksum', $checksum);
  }

  return @bibentries;
}

sub write_bib_to_fh {
  my ($fh, @bibentries) = @_;

  # print BibTeX entries
  for my $bibentry (sort { $a->key cmp $b->key } @bibentries) {

    # create a copy of BibTeX entry
    $bibentry = $bibentry->clone();

    # remove checksum before printing
    $bibentry->delete('checksum');

    # regularise BibTeX 'month' field
    my $month = $bibentry->get('month');
    if (defined($month)) {
      $month =~ s/\s//g;
      $month =~ s/^jan.*$/January/i;
      $month =~ s/^feb.*$/February/i;
      $month =~ s/^mar.*$/March/i;
      $month =~ s/^apr.*$/April/i;
      $month =~ s/^may.*$/May/i;
      $month =~ s/^jun.*$/June/i;
      $month =~ s/^jul.*$/July/i;
      $month =~ s/^aug.*$/August/i;
      $month =~ s/^sep.*$/September/i;
      $month =~ s/^oct.*$/October/i;
      $month =~ s/^nov.*$/November/i;
      $month =~ s/^dec.*$/December/i;
      $bibentry->set('month', $month);
    }

    # double-quote BibTeX 'title' fields
    foreach my $bibfield ($bibentry->fieldlist()) {
      if ($bibfield =~ /title$/) {
        my $title = $bibentry->get($bibfield);
        $title =~ s/^{*/{/;
        $title =~ s/}*$/}/;
        $bibentry->set($bibfield, $title);
      }
    }

    # arrange BibTeX fields in the following order
    my %order;
    my $orderidx;
    foreach my $bibfield (
                          qw(keyword),
                          $structure->required_fields($bibentry->type),
                          $structure->optional_fields($bibentry->type),
                          qw(eid doi archiveprefix primaryclass eprint),
                          sort { $a cmp $b } $bibentry->fieldlist()
                         ) {
      $order{$bibfield} = ++$orderidx if $bibentry->exists($bibfield) && !defined($order{$bibfield});
    }
    foreach my $bibfield (
                          qw(abstract comments file)
                         ) {
      $order{$bibfield} = ++$orderidx if $bibentry->exists($bibfield);
    }
    my @fieldlist = sort { $order{$a} <=> $order{$b} } keys(%order);
    $bibentry->set_fieldlist(\@fieldlist);

    # print entry
    my $bibstr = $bibentry->print_s();
    $bibstr =~ s/^\s+//g;
    $bibstr =~ s/\s+$//g;
    print $fh "\n", encode('iso-8859-1', $bibstr, Encode::FB_CROAK), "\n";

  }

}

sub write_bib_to_pdf {
  my (@bibentries) = @_;

  # get location of DublinCore XSLT style file
  my $xsltdublincore = File::Spec->catfile($xsltdir, 'dublincore.xsl');
  croak "$Script: missing XSLT style file '$xsltdublincore'" unless -f $xsltdublincore;

  # filter out unmodified BibTeX entries
  my @modbibentries;
  foreach my $bibentry (@bibentries) {
    my $checksum = bib_checksum($bibentry);
    next if ($bibentry->get('checksum') // "") eq $checksum;
    push @modbibentries, $bibentry;
    $bibentry->set('checksum', $checksum);
  }
  printf STDERR "$Script: not writing %i unmodified BibTeX entries\n", @bibentries - @modbibentries if @modbibentries < @bibentries;

  # write modified BibTeX entries to PDF files
  my $body = sub {
    my ($bibentry) = @_;

    # get name of PDF file
    my $pdffile = $bibentry->get('file');

    # check for existence of PDF file
    croak "$Script: BibTeX entry @{[$bibentry->key]} cannot be written to missing PDF file '$pdffile'" unless -f $pdffile;

    # create XML document
    my $xml = XML::LibXML::Document->new('1.0', 'utf-8');
    my $xmlmeta = $xml->createElementNS("adobe:ns:meta/", "xmpmeta");
    $xmlmeta->setNamespace("adobe:ns:meta/", "x", 1);
    $xml->setDocumentElement($xmlmeta);

    # convert BibTeX into XML
    my $xmlbibentry = $xml->createElementNS("http://bibtexml.sf.net/", "entry");
    $xmlbibentry->setNamespace("http://bibtexml.sf.net/", "bibtex", 1);
    $xmlbibentry->setAttribute("id" => $bibentry->key);
    $xmlmeta->appendChild($xmlbibentry);
    my $xmlbibtype = $xml->createElementNS("http://bibtexml.sf.net/", lc($bibentry->type));
    $xmlbibtype->setNamespace("http://bibtexml.sf.net/", "bibtex", 1);
    $xmlbibentry->appendChild($xmlbibtype);
    foreach my $bibfield ($bibentry->fieldlist()) {
      next if grep { $bibfield eq $_ } qw(checksum file);
      next unless length($bibentry->get($bibfield)) > 0;
      my $xmlbibfield = $xml->createElementNS("http://bibtexml.sf.net/", lc($bibfield));
      $xmlbibfield->setNamespace("http://bibtexml.sf.net/", "bibtex", 1);
      $xmlbibfield->appendTextNode($bibentry->get($bibfield));
      $xmlbibtype->appendChild($xmlbibfield);
    }

    # convert BibTeX XML to DublinCore XML and append
    my $xslt = XML::LibXSLT->new();
    my $xsltstylesrc = XML::LibXML->load_xml(location => $xsltdublincore);
    my $xsltstyle = $xslt->parse_stylesheet($xsltstylesrc);
    my $xmldc = $xsltstyle->transform($xml);
    my $xmldcentry = $xmldc->documentElement()->cloneNode(1);
    $xml->adoptNode($xmldcentry);
    $xmlmeta->insertBefore($xmldcentry, $xmlbibentry);

    # open PDF file
    my $pdf = open_pdf_file($pdffile);

    # write document information to PDF file
    my %pdfinfo;
    eval {
      %pdfinfo = $pdf->info();
    };
    $pdfinfo{Author} = $bibentry->get("author") // $bibentry->get("editor") // "";
    $pdfinfo{Author} =~ s/[{}\\]//g;
    $pdfinfo{Author} =~ s/~/ /g;
    $pdfinfo{Title} = $bibentry->get("title") // "";
    $pdfinfo{Title} =~ s/[{}\\]//g;
    $pdfinfo{Title} =~ s/\$.*?\$//g;
    $pdfinfo{Subject} = $bibentry->get("abstract") // "";
    $pdf->infoMetaAttributes(keys(%pdfinfo));
    $pdf->info(%pdfinfo);
    $pdf->preferences(-displaytitle => 1);

    # write XMP metadata to PDF file
    my $xmp = "";
    eval {
      $xmp = $pdf->xmpMetadata() // "";
    };
    my $xmphead = "<?xpacket begin='﻿' id='W5M0MpCehiHzreSzNTczkc9d'?>\n";
    my $xmpdata = encode('utf-8', $xml->documentElement()->toString(0), Encode::FB_CROAK);
    my $xmptail = "\n<?xpacket end='w'?>";
    my $xmplen = length($xmphead) + length($xmpdata) + length($xmptail);
    my $xmppadlen = length($xmp) - $xmplen;
    if ($xmppadlen <= 0) {
      $xmppadlen = max(4096, 2*length($xmp), 2*length($xmpdata)) - $xmplen;
    }
    my $xmppad = ((" " x 99) . "\n") x int(1 + $xmppadlen / 100);
    my $newxmp = $xmphead . $xmpdata . substr($xmppad, 0, $xmppadlen) . $xmptail;
    $pdf->xmpMetadata($newxmp);

    # write PDF file
    $pdf->update();
    $pdf->end();

  };
  parallel_loop("writing BibTeX entries to %i/%i PDF files", \@modbibentries, $body);

  return @modbibentries;
}

sub edit_bib_in_fh {
  my ($oldfh, @bibentries) = @_;
  die unless blessed($oldfh) eq 'File::Temp';

  # save checksums of BibTeX entries
  my %checksums;
  foreach my $bibentry (@bibentries) {
    $checksums{$bibentry->get('file')} = $bibentry->get('checksum');
  }

  # edit and re-read BibTeX entries, allowing for errors
  my @errors;
  while (1) {

    # open new temporary file for editing BibTeX entries
    my $fh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$Script: could not create temporary file";
    binmode($fh, ":encoding(iso-8859-1)");

    # write header message
    if (@errors > 0) {
      print $fh wrap("% ", "% ", <<"EOF");
$PACKAGE_NAME has encountered several errors in parsing the following BibTeX records. These errors are indicated with comments next to the line where the errors occurred.

All errors MUST be corrected before the BibTeX records can be written back to the PDF file given by the 'file' field in each record.

To ABORT ANY CHANGES from being written, simply delete the relevant records, or the entire contents of this file.
EOF
    } else {
      print $fh wrap("% ", "% ", <<"EOF");
$PACKAGE_NAME has extracted the following BibTeX records for editing. Any changes to the records will be written back to the PDF file given by the 'file' field in each record.

To ABORT ANY CHANGES from being written, simply delete the relevant records, or the entire contents of this file.
EOF
    }
    print $fh "\n";

    # build hash of errors by line number
    my %errorsbyline;
    foreach (@errors) {
      if (defined($_->{from})) {
        push @{$errorsbyline{$_->{from}}}, $_->{msg};
      } else {
        push @{$errorsbyline{0}}, $_->{msg};
      }
    }

    # write any error messages without line numbers
    if (defined($errorsbyline{0})) {
      foreach (@{$errorsbyline{0}}) {
        print $fh "% ERROR: $_\n";
      }
      delete $errorsbyline{0};
      print $fh "\n";
    }

    # write contents of old temporary file, with any error messages inline
    $oldfh->flush();
    $oldfh->seek(0, SEEK_SET);
    while (<$oldfh>) {
      chomp;
      my $line = sprintf("%i", $oldfh->input_line_number);
      foreach (@{$errorsbyline{$line}}) {
        print $fh "% ERROR: $_\n";
      }
      delete $errorsbyline{$line};
      s/\s+$//;
      next if /^%/;
      next if /^$/;
      print $fh "$_\n";
      if (/^}$/) {
        print $fh "\n";
      }
    }
    $fh->flush();

    # write any remaining error messages
    foreach (keys %errorsbyline) {
      foreach (@{$errorsbyline{$_}}) {
        print $fh "% ERROR: $_\n";
      }
    }

    # print index of all currently-defined keywords
    print $fh keyword_display_str();

    # save handle to new temporary file; old temporary file is deleted
    $oldfh = $fh;

    # edit BibTeX entries
    my $editor = $ENV{'VISUAL'} // $ENV{'EDITOR'} // $fallback_editor;
    system($editor, $fh->filename) == 0 or croak "$Script: could not edit file '$fh->filename' with editing program '$editor'";

    # try to re-read BibTeX entries
    read_bib_from_file(\@errors, \@bibentries, $fh->filename);

    # error if duplicate BibTeX keys are found
    foreach my $dupkey (find_dup_bib_keys(@bibentries)) {
      push @errors, { msg => "duplicated key '$dupkey'" };
    }

    # error if BibTeX entries contain field names which differ by 's', e.g. 'keyword' and 'keywords'
    foreach my $bibentry (@bibentries) {
      foreach my $bibfield ($bibentry->fieldlist()) {
        if ($bibentry->exists($bibfield) && $bibentry->exists($bibfield . "s")) {
          push @errors, { msg => "entry @{[$bibentry->key]} contains possibly duplicate fields '${bibfield}' and '${bibfield}s'" };
        }
      }
    }

    # BibTeX entries have been successfully read
    last if @errors == 0;

  }

  # restore checksums of BibTeX entries
  foreach my $bibentry (@bibentries) {
    $bibentry->set('checksum', $checksums{$bibentry->get('file')});
  }

  return @bibentries;
}

sub find_dup_bib_keys {
  my (@bibentries) = @_;

  # find duplicate keys in BibTeX entries
  my %keycount;
  foreach my $bibentry (@bibentries) {
    ++$keycount{$bibentry->key};
  }

  return grep { $keycount{$_} > 1 } keys(%keycount);
}

sub format_bib_authors {
  my ($nameformat, $maxauthors, $etal, @authors) = @_;

  # format authors
  my $authorformat = new Text::BibTeX::NameFormat($nameformat);
  foreach my $author (@authors) {
    $author = $authorformat->apply($author);
    $author = remove_tex_markup($author);
    if ($author =~ /\sCollaboration$/i) {
      $author =~ s/\s.*$//;
    }
  }

  if (@authors > 0) {

    # limit number of authors to '$maxathors'
    @authors = ($authors[0], $etal) if defined($maxauthors) && @authors > $maxauthors;

    # replace 'others' with preferred form of 'et al.'
    $authors[-1] = $etal if $authors[-1] eq "others";

  }

  return @authors;
}

sub generate_bib_keys {
  my (@bibentries) = @_;

  # generate keys for BibTeX entries
  my $keys = 0;
  foreach my $bibentry (@bibentries) {
    my $key = "";

    # add formatted authors, editors, or collaborations
    {
      my @authors = format_bib_authors("l", 3, "", $bibentry->names("collaboration"));
      @authors = format_bib_authors("l", 2, "EtAl", $bibentry->names("author")) unless @authors > 0;
      @authors = format_bib_authors("l", 2, "EtAl", $bibentry->names("editor")) unless @authors > 0;
      $key .= join('', map { $_ =~ s/\s//g; substr($_, 0, 4) } @authors);
    }

    # add year
    my $year = $bibentry->get("year") // "";
    $key .= $year;

    # add abbreviated title
    {
      my $title = remove_tex_markup($bibentry->get("title"));
      $title =~ s/[^\w\d\s]//g;
      my $suffix = "";

      # abbreviate title words
      my @words = remove_short_words(split(/\s+/, $title));
      my @wordlens = (3, 3, 2, 2, 2);
      foreach my $word (sort { length($b) <=> length($a) } @words) {

        # add any Roman numeral to suffix, and stop processing title
        if (grep { $word eq $_ } qw(II III IV V VI VII VIII IX)) {
          $suffix .= ":$word";
          last;
        }

        # always include numbers in full
        next if $word =~ /^\d+$/;

        # abbreviate word to the next available length, after removing vowels
        my $wordlen = shift(@wordlens) // 1;
        my $shrt = ucfirst($word);
        $shrt =~ s/[aeiou]//g;
        $shrt = substr($shrt, 0, $wordlen);

        map { s/^$word$/$shrt/ } @words;
      }

      unless (length($suffix) > 0) {

        # add volume number (if any) to suffix for books and proceedings
        $suffix .= ':v' . $bibentry->get("volume") if (grep { $bibentry->type eq $_ } qw(book inbook proceedings)) && $bibentry->exists("volume");

      }

      # add abbreviated title and suffix to key
      $key .= ':' . join('', @words);
      $key .= $suffix if length($suffix) > 0;

    }

    # sanitise key
    $key = unidecode($key);
    $key =~ s/[^\w\d:]//g;

    # set key to generated key, unless start of key matches generated key
    # - this is so user can further customise key by appending characters
    unless ($bibentry->key =~ /^$key($|:)/) {
      $bibentry->set_key($key);
      ++$keys;
    }

  }
  printf STDERR "$Script: generated keys for %i BibTeX entries\n", $keys if $keys > 0;

}
