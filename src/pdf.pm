# Copyright (C) 2016 Karl Wette
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

package fmdtools::pdf;

use strict;
use warnings;
no warnings 'experimental::smartmatch';
use feature qw/switch/;

use Carp;
use Getopt::Long;
use Scalar::Util qw(blessed);
use Encode;
use File::Spec;
use File::Temp;
use Capture::Tiny;
use Digest::SHA;
use PDF::API2;
use XML::LibXML;
use XML::LibXSLT;
use Text::BibTeX;
use Text::BibTeX::Bib;
use Text::BibTeX::NameFormat;
use Text::Unidecode;

use fmdtools;

# PDF library location
my $pdflibdir = fmdtools::get_library_dir('PDF');

# BibTeX database structure
my $structure = new Text::BibTeX::Structure('Bib');
foreach my $type ($structure->types()) {
    $structure->add_fields($type, [qw(keyword file title year)], [qw(collaboration)]);
}

1;

sub act {
    my ($action, @args) = @_;

    # handle action
    given ($action) {

        when ("edit") {
            croak "$0: action '$action' requires arguments" unless @args > 0;

            # get list of unique PDF files
            my @pdffiles = fmdtools::find_unique_files('pdf', @args);
            croak "$0: no PDF files to edit" unless @pdffiles > 0;

            # read BibTeX entries from PDF metadata
            my @bibentries = read_bib_from_PDF(@pdffiles);

            # generate initial keys for BibTeX entries
            generate_bib_keys(@bibentries);

            # coerse entries into BibTeX database structure
            foreach my $bibentry (@bibentries) {
              $bibentry->silently_coerce();
            }

            # write BibTeX entries to a temporary file for editing
            my $fh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$0: could not create temporary file";
            binmode($fh, ":encoding(iso-8859-1)");
            write_bib_to_fh($fh, @bibentries);

            # edit BibTeX entries in PDF files
            @bibentries = edit_bib_in_fh($fh, @bibentries);

            # regenerate keys for modified BibTeX entries
            generate_bib_keys(@bibentries);

            # write BibTeX entries to PDF metadata
            @bibentries = write_bib_to_PDF(@bibentries);

            # filter BibTeX entries of PDF files in library
            @bibentries = grep { fmdtools::is_in_dir($pdflibdir, $_->get('file')) } @bibentries;

            # reorganise any PDF files already in library
            organise_library_PDFs(@bibentries) if @bibentries > 0;

        }

        when ("export") {
            croak "$0: action '$action' requires arguments" unless @args > 0;

            # handle options
            my @exclude;
            my $parser = Getopt::Long::Parser->new;
            $parser->getoptionsfromarray(\@args,
                                         "exclude|e=s" => \@exclude,
                ) or croak "$0: could not parse options for action '$action'";

            # get list of unique PDF files
            my @pdffiles = fmdtools::find_unique_files('pdf', @args);
            croak "$0: no PDF files to read from" unless @pdffiles > 0;

            # read BibTeX entries from PDF metadata
            my @bibentries = read_bib_from_PDF(@pdffiles);

            # exclude BibTeX fields
            foreach my $bibfield (('file', @exclude)) {
                foreach my $bibentry (@bibentries) {
                    $bibentry->delete($bibfield);
                }
            }

            # print BibTeX entries
            write_bib_to_fh(\*STDOUT, @bibentries);

        }

        when ("add") {
            croak "$0: action '$action' requires arguments" unless @args > 0;

            # get list of unique PDF files
            my @pdffiles = fmdtools::find_unique_files('pdf', @args);
            croak "$0: no PDF files to read from" unless @pdffiles > 0;

            # read BibTeX entries from PDF metadata
            my @bibentries = read_bib_from_PDF(@pdffiles);

            # add PDF files to library
            organise_library_PDFs(@bibentries);

        }

        when ("remove") {
            croak "$0: action '$action' requires arguments" unless @args > 0;

            # handle options
            my $removedir = File::Spec->tmpdir();
            my $parser = Getopt::Long::Parser->new;
            $parser->getoptionsfromarray(\@args,
                                         "remove-to|r=s" => \$removedir,
                ) or croak "$0: could not parse options for action '$action'";
            croak "$0: '$removedir' is not a directory" unless -d $removedir;

            # remove PDF files from library
            remove_library_PDFs($removedir, @args);

        }

        when ("reorganise") {
            croak "$0: action '$action' takes no arguments" unless @args == 0;

            # get list of unique PDF files in library
            my @pdffiles = fmdtools::find_unique_files('pdf', $pdflibdir);
            croak "$0: no PDF files in library $pdflibdir" unless @pdffiles > 0;

            # read BibTeX entries from PDF metadata
            my @bibentries = read_bib_from_PDF(@pdffiles);

            # regenerate keys for all BibTeX entries
            generate_bib_keys(@bibentries);

            # write BibTeX entries to PDF metadata
            write_bib_to_PDF(@bibentries);

            # reorganise PDF files in library
            organise_library_PDFs(@bibentries);

        }

        # unknown action
        default {
            croak "$0: unknown action '$action'";
        }

    }

    return 0;
}

sub bibentry_checksum {
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

sub read_bib_from_PDF {
    my (@pdffiles) = @_;

    # read BibTeX entries from PDF files
    my @bibentries = fmdtools::parallel_loop("reading %i/%i BibTeX entries from PDF", \@pdffiles, sub {
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
        my $bibentry = new Text::BibTeX::BibEntry $bibstr;
        croak "$0: failed to parse BibTeX entry" unless $bibentry->parse_ok;
        $bibentry->{structure} = $structure;

        # save name of PDF file
        $bibentry->set('file', $pdffile);

        return $bibentry;
    });

    # add checksums to BibTeX entries
    foreach my $bibentry (@bibentries) {
        my $checksum = bibentry_checksum($bibentry);
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
            )
        {
            $order{$bibfield} = ++$orderidx if $bibentry->exists($bibfield) && !defined($order{$bibfield});
        }
        foreach my $bibfield (
            qw(abstract comments file)
            )
        {
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
    my ($filename) = @_;

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
        return (1, ()) if $nonempty;
    }

    # parse the BibTeX file, capturing any error messages
    my $errmsgs;
    my @bibentries;
    {
        my $bib = new Text::BibTeX::File $filename or croak "$0: could not open file '$filename'";
        $bib->{structure} = $structure;
        $errmsgs = Capture::Tiny::capture_merged {
            while (my $bibentry = new Text::BibTeX::BibEntry $bib) {
                next unless $bibentry->parse_ok;
                next unless $bibentry->check();
                push @bibentries, $bibentry;
            }
        };
        $bib->close();
    }

    # if parsing was unsuccessful, return error messages
    if (length($errmsgs) > 0) {
        my @errors;
        foreach my $msg (split(/\n/, $errmsgs)) {
            $msg =~ s/^$filename,\s*//;
            given ($msg) {
                when (/^line (\d+)[,:]?\s*(.*)$/) {
                    push @errors, { from => $1, msg => $2 };
                }
                when (/^lines (\d+)-(\d+)[,:]?\s*(.*)$/) {
                    push @errors, { from => $1, to => $2, msg => $3 };
                }
                default {
                    push @errors, { msg => $msg };
                }
            }
        }
        return (0, @errors);
    }

    # remove 'file' field from Text::BibTeX::BibEntry, since it
    # contains a GLOB item that cannot be serialised by Storable
    foreach my $bibentry (@bibentries) {
        delete($bibentry->{file}) if defined($bibentry->{file});
    }

    return (1, @bibentries);
}

sub write_bib_to_PDF {
    my (@bibentries) = @_;

    # filter out unmodified BibTeX entries
    my @modbibentries;
    foreach my $bibentry (@bibentries) {
        my $checksum = bibentry_checksum($bibentry);
        next if ($bibentry->get('checksum') // "") eq $checksum;
        push @modbibentries, $bibentry;
        $bibentry->set('checksum', $checksum);
    }
    fmdtools::progress("not writing %i unmodified BibTeX entries\n", @bibentries - @modbibentries) if @modbibentries < @bibentries;

    # write modified BibTeX entries to PDF files
    fmdtools::parallel_loop("writing %i/%i BibTeX entries to PDF", \@modbibentries, sub {
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
            $xmppadlen = List::Util->max(4096, 2*length($xmp), 2*length($xmpdata))  - $xmplen;
        }
        my $xmppad = ((" " x 99) . "\n") x int(1 + $xmppadlen / 100);
        my $newxmp = $xmphead . $xmpdata . substr($xmppad, 0, $xmppadlen) . $xmptail;
        $pdf->xmpMetadata($newxmp);

        # write PDF file
        $pdf->update();
        $pdf->end();

    });

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
        my ($success, @retn) = read_bib_from_file($fh->filename);

        # BibTeX entries have been successfully read
        if ($success) {
            @bibentries = @retn;
            last;
        }

        # save error messages with adjusted line numbers
        my $linediff = @retn - @errors;
        @errors = @retn;
        foreach (@errors) {
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

sub remove_tex_markup {
    my (@words) = @_;

    # remove TeX markup
    foreach (@words) {
        s/~/ /g;
        s/\\\w+//g;
        s/\\.//g;
        s/[{}]//g;
        s/\$//g;
    }

    return wantarray ? @words : "@words";
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
        my @authors = format_bib_authors("l", 2, "EtAl", $bibentry->names("collaboration"));
        @authors = format_bib_authors("l", 2, "EtAl", $bibentry->names("editor")) unless @authors > 0;
        @authors = format_bib_authors("l", 2, "EtAl", $bibentry->names("author")) unless @authors > 0;
        $key .= join('', map { $_ =~ s/\s//g; substr($_, 0, 4) } @authors);

        # add year
        $key .= $bibentry->get("year");

        # add abbreviated title
        my $title = remove_tex_markup($bibentry->get("title"));
        $title =~ tr/@/A/;
        $title =~ s/[^\w\d\s-]//g;
        my @words;
        foreach my $word (fmdtools::remove_short_words(split(/\s+/, $title))) {
            $word = ucfirst($word);
            if (scalar(() = $word =~ /[A-Z]/g) > 1) {
                $word =~ s/[^A-Z]//g;
            } else {
                $word =~ s/[aeiou]//g;
            }
            $word = substr($word, 0, 3);
            push @words, $word if @words < 4 || grep { $word eq $_ } qw(I II III IV V VI VII VIII IX);
        }
        $key .= ':' . join('', @words);
        given ($bibentry->type) {

            # append volume number (if any) for books
            when (/book$/) {
                my $volume = $bibentry->get("volume");
                if (defined($volume)) {
                    $key .= ".$volume";
                }
            }

        }

        # sanitise key
        $key = unidecode($key);
        $key =~ s/[^\w\d:]//g;

        # set key to generated key, unless start of key matches generated key
        # - this is so user can further customise key by appending characters
        unless ($bibentry->key =~ /^$key/) {
            $bibentry->set_key($key);
            ++$keys;
        }

    }
    fmdtools::progress("generated keys for %i BibTeX entries\n", $keys) if $keys > 0;

}

sub organise_library_PDFs {
    my (@bibentries) = @_;

    # find PDF files to organise
    my (@files_dirs, %file2inode, %inode2files);
    fmdtools::find_files(\%file2inode, \%inode2files, 'pdf', map { $_->get('file') } @bibentries);

    # get list of unique PDF files
    my @pdffiles = map { @{$_}[0] } values(%inode2files);
    croak "$0: no PDF files to organise" unless @pdffiles > 0;

    # add existing PDF files in library to file/inode hashes
    fmdtools::find_files(\%file2inode, \%inode2files, 'pdf', $pdflibdir);

    # organise PDFs in library
    foreach my $bibentry (@bibentries) {
        my $pdffile = $bibentry->get('file');

        # format authors, editors, and collaborations
        my @authors = format_bib_authors("vl", 2, "et al", $bibentry->names("author"));
        my @editors = format_bib_authors("vl", 2, "et al", $bibentry->names("editor"));
        my @collaborations = format_bib_authors("vl", 2, "et al", $bibentry->names("collaboration"));

        # format and abbreviate title
        my $title = remove_tex_markup($bibentry->get("title"));
        $title = join(' ', map { ucfirst($_) } fmdtools::remove_short_words(split(/\s+/, $title)));

        # make new name for PDF; should be unique within library
        my $newpdffile = "@collaborations";
        $newpdffile = "@editors" unless length($newpdffile) > 0;
        $newpdffile = "@authors" unless length($newpdffile) > 0;
        $newpdffile .= " $title";
        given ($bibentry->type) {

            # append report number (if any) for technical reports
            when ("techreport") {
                $newpdffile .= " no" . $bibentry->get("number") if $bibentry->exists("number");
            }

            # append volume number (if any) for books
            when (/book$/) {
                $newpdffile .= " v" . $bibentry->get("volume") if $bibentry->exists("volume");
            }

        }
        $newpdffile .= ".pdf";

        # list of shelves to organise this file under
        my @shelves;

        # organise by first author and collaboration
        push @shelves, ["Authors", $authors[0], ""];
        if (@collaborations > 0) {
            push @shelves, ["Authors", $collaborations[0], ""];
        }

        # organise by first word of title
        my $firstword = ucfirst($title);
        $firstword =~ s/\s.*$//;
        push @shelves, ["Titles", $firstword, ""];

        # organise by year
        my $year = $bibentry->get("year");
        push @shelves, ["Years", $year, ""];

        # organise by keyword(s)
        my %keywords;
        foreach (split ';', $bibentry->get("keyword")) {
            next if /^\s*$/;
            $keywords{$_} = 1;
        }
        if (keys %keywords == 0) {
            $keywords{"NO KEYWORDS"} = 1;
        }
        foreach my $keyword (keys %keywords) {
            my @subkeywords = split ',', $keyword;
            s/\b(\w)/\U$1\E/g for @subkeywords;
            push @shelves, ["Keywords", @subkeywords, ""];
        }

        given ($bibentry->type) {

            # organise articles by journal
            when ("article") {
                my $journal = $bibentry->get("journal") // "NO JOURNAL";
                if ($journal =~ /arxiv/i) {
                    my $eprint = $bibentry->get("eprint") // "NO EPRINT";
                    push @shelves, ["Articles", "arXiv", "$eprint"];
                } else {
                    my $volume = $bibentry->get("volume") // "NO VOLUME";
                    my $pages = $bibentry->get("pages") // "NO PAGES";
                    push @shelves, ["Articles", $journal, "v$volume", "p$pages"];
                }
            }

            # organise technical reports by institution
            when ("techreport") {
                my $institution = $bibentry->get("institution") // "NO INSTITUTION";
                push @shelves, ["Tech Reports", $institution, ""];
            }

            # organise books
            when (/book$/) {
                push @shelves, ["Books", ""];
            }

            # organise theses
            when (/thesis$/) {
                push @shelves, ["Theses", ""];
            }

        }

        # make shelves into library filenames
        my @newpdffiles = fmdtools::make_library_filenames($pdflibdir, $newpdffile, 'pdf', @shelves);

        # create library links
        fmdtools::make_library_links($pdflibdir, \%file2inode, \%inode2files, $pdffile, @newpdffiles);

    }
    fmdtools::progress("organised %i PDFs in $pdflibdir\n", scalar(@bibentries));

    # finalise library organisation
    fmdtools::finalise_library($pdflibdir);

}

sub remove_library_PDFs {
    my ($removedir, @files_dirs) = @_;

    # find PDF files to organise
    my (%file2inode, %inode2files);
    fmdtools::find_files(\%file2inode, \%inode2files, 'pdf', @files_dirs);

    # get list of unique PDF files
    my @pdffiles = map { @{$_}[0] } values(%inode2files);
    croak "$0: no PDF files to organise" unless @pdffiles > 0;

    # add existing PDF files in library to file/inode hashes
    fmdtools::find_files(\%file2inode, \%inode2files, 'pdf', $pdflibdir);

    # remove PDFs from library
    foreach my $pdffile (@pdffiles) {
        fmdtools::remove_library_links($pdflibdir, \%file2inode, \%inode2files, $pdffile, $removedir);
    }
    progress("removed %i PDFs to $removedir\n", scalar(@pdffiles));

    # finalise library organisation
    fmdtools::finalise_library($pdflibdir);

}
