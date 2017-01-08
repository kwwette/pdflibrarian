# Copyright (C) 2016--2017 Karl Wette
#
# This file is part of fmdtools.
#
# fmdtools is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# fmdtools is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fmdtools. If not, see <http://www.gnu.org/licenses/>.

package fmdtools::pdf::bib;

use strict;
use warnings;
no warnings 'experimental::smartmatch';
use feature qw/switch/;

use Carp;
use Scalar::Util qw(blessed);
use List::Util qw(max);
use Digest::SHA;
use Encode;
use File::Temp;
use Capture::Tiny;
use PDF::API2;
use Text::BibTeX;
use Text::BibTeX::Bib;
use Text::BibTeX::NameFormat;
use XML::LibXML;
use XML::LibXSLT;

use fmdtools;
use fmdtools::pdf;

# BibTeX database structure
my $structure = new Text::BibTeX::Structure('Bib');
foreach my $type ($structure->types()) {
  $structure->add_fields($type, [qw(keyword file title year)], [qw(collaboration)]);
}

1;

sub bib_checksum {
  my ($bibentry) = @_;

  # generate a checksum for a BibTeX entry
  my $digest = Digest::SHA->new();
  $digest->add($bibentry->type, $bibentry->key);
  foreach my $bibfield (sort { $a cmp $b } $bibentry->fieldlist()) {
    next if $bibfield eq 'checksum';
    $digest->add($bibfield, $bibentry->get($bibfield));
  }

  return $digest->hexdigest;
}

sub read_bib_from_str {
  my ($bibstr) = @_;

  # read BibTeX entry from a string
  my $bibentry = new Text::BibTeX::BibEntry $bibstr;
  croak "$0: failed to parse BibTeX entry" unless $bibentry->parse_ok;
  $bibentry->{structure} = $structure;

  return $bibentry;
}

sub read_bib_from_PDF {
  my (@pdffiles) = @_;

  # read BibTeX entries from PDF files
  my $body = sub {
    my ($pdffile) = @_;

    # open PDF file and read XMP metadata
    my $pdf = PDF::API2->open($pdffile);
    my $xmp = $pdf->xmpMetadata();
    $xmp =~ s/\s*<\?xpacket .*\?>\s*//g;
    $pdf->end();

    # convert BibTeX XML (if any) to parsed BibTeX entry
    my $bibstr = '@article{key,}';
    if (length($xmp) > 0) {
      my $xml = XML::LibXML->load_xml(string => $xmp);
      my $xslt = XML::LibXSLT->new();
      my $xsltstylesrc = XML::LibXML->load_xml(location => fmdtools::get_data_file("bibtex.xsl"));
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
  my @bibentries = fmdtools::parallel_loop("reading %i/%i BibTeX entries from PDF", \@pdffiles, $body);

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

    # arrange BibTeX fields in the following order
    my %order;
    my $orderidx;
    foreach my $bibfield (
                          qw(keyword),
                          $structure->required_fields($bibentry->type),
                          $structure->optional_fields($bibentry->type),
                          qw(eid doi archiveprefix primaryclass eprint oai2identifier url adsurl adsnote),
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
    open(my $fh, $filename) or croak "$0: could not open file '$filename': $!";
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
    my $bib = new Text::BibTeX::File $filename or croak "$0: could not open file '$filename'";
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
      given ($msg) {
        when (/^line (\d+)[,:]?\s*(.*)$/) {
          push @$errors, { from => $1, msg => $2 };
        }
        when (/^lines (\d+)-(\d+)[,:]?\s*(.*)$/) {
          push @$errors, { from => $1, to => $2, msg => $3 };
        }
        default {
          push @$errors, { msg => $msg };
        }
      }
    }
  }

}

sub write_bib_to_PDF {
  my (@bibentries) = @_;

  # filter out unmodified BibTeX entries
  my @modbibentries;
  foreach my $bibentry (@bibentries) {
    my $checksum = bib_checksum($bibentry);
    next if ($bibentry->get('checksum') // "") eq $checksum;
    push @modbibentries, $bibentry;
    $bibentry->set('checksum', $checksum);
  }
  fmdtools::progress("not writing %i unmodified BibTeX entries\n", @bibentries - @modbibentries) if @modbibentries < @bibentries;

  # write modified BibTeX entries to PDF files
  my $body = sub {
    my ($bibentry) = @_;

    # get name of PDF file
    my $pdffile = $bibentry->get('file');

    # check for existence of PDF file
    croak "$0: BibTeX entry @{[$bibentry->key]} cannot be written to missing PDF file '$pdffile'" unless -f $pdffile;

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
    my $xsltstylesrc = XML::LibXML->load_xml(location => fmdtools::get_data_file("dublincore.xsl"));
    my $xsltstyle = $xslt->parse_stylesheet($xsltstylesrc);
    my $xmldc = $xsltstyle->transform($xml);
    my $xmldcentry = $xmldc->documentElement()->cloneNode(1);
    $xml->adoptNode($xmldcentry);
    $xmlmeta->insertBefore($xmldcentry, $xmlbibentry);

    # open PDF file
    my $pdf = PDF::API2->open($pdffile);

    # write document information to PDF file
    my %pdfinfo = $pdf->info();
    $pdfinfo{Author} = $bibentry->get("author");
    $pdfinfo{Author} =~ s/[{}\\]//g;
    $pdfinfo{Author} =~ s/~/ /g;
    $pdfinfo{Title} = $bibentry->get("title");
    $pdfinfo{Title} =~ s/[{}\\]//g;
    $pdfinfo{Title} =~ s/\$.*?\$//g;
    $pdfinfo{Subject} = $bibentry->get("abstract");
    $pdf->infoMetaAttributes(keys(%pdfinfo));
    $pdf->info(%pdfinfo);
    $pdf->preferences(-displaytitle => 1);

    # write XMP metadata to PDF file
    my $xmp = $pdf->xmpMetadata();
    croak "$0: PDF metadata is not an XMP packet" unless !defined($xmp) || $xmp =~ /^<\?xpacket[^?]*\?>/;
    croak "$0: PDF XMP packet cannot be updated" unless !defined($xmp) || $xmp =~ /<\?xpacket end=['"]w['"]\?>$/;
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
  fmdtools::parallel_loop("writing %i/%i BibTeX entries to PDF", \@modbibentries, $body);

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

    # save number of errors in previous edit
    my $nerrors = @errors;

    # write new temporary file for editing, including any error messages
    my $fh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$0: could not create temporary file";
    binmode($fh, ":encoding(iso-8859-1)");
    print $fh <<"EOF";
%% Edits to the following BibTeX entries will be written back
%% to the PDF file given by the 'file' field in each entry.
%%
%% To ABORT ANY CHANGES from being written, simply delete
%% the relevant entries, or the entire contents of this file.
%%
%% Any errors encountered while parsing/writing BibTeX entries
%% are reported below, and must be corrected:
%%
EOF
    foreach (@errors) {
      if (defined($_->{from})) {
        if (defined($_->{to})) {
          print $fh "%% ERROR at lines $_->{from}-$_->{to}: $_->{msg}\n";
        } else {
          print $fh "%% ERROR at line $_->{from}: $_->{msg}\n";
        }
      } else {
        print $fh "%% ERROR: $_->{msg}\n";
      }
    }
    $oldfh->flush();
    $oldfh->seek(0, SEEK_SET);
    while (<$oldfh>) {
      next if /^%/;
      print $fh $_;
    }
    $fh->flush();

    # save handle to new temporary file; old temporary file is deleted
    $oldfh = $fh;

    # edit BibTeX entries
    fmdtools::edit_file($fh->filename);

    # try to re-read BibTeX entries
    read_bib_from_file(\@errors, \@bibentries, $fh->filename);

    # error if duplicate BibTeX keys are found
    foreach my $dupkey (find_duplicate_keys(@bibentries)) {
      push @errors, { msg => "duplicated key '$dupkey'" };
    }

    # BibTeX entries have been successfully read
    last if @errors == 0;

    # save error messages with adjusted line numbers
    foreach (@errors) {
      my $linediff = @errors - $nerrors;
      $_->{from} += $linediff if defined($_->{from});
      $_->{to} += $linediff if defined($_->{to});
    }

  }

  # restore checksums of BibTeX entries
  foreach my $bibentry (@bibentries) {
    $bibentry->set('checksum', $checksums{$bibentry->get('file')});
  }

  return @bibentries;
}

sub find_duplicate_keys {
  my (@bibentries) = @_;

  # find duplicate keys in BibTeX entries
  my %keycount;
  foreach my $bibentry (@bibentries) {
    ++$keycount{$bibentry->key};
  }

  return grep { $keycount{$_} > 1 } keys(%keycount);
}
