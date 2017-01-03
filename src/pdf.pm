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
use Encode;
use File::Temp;
use Capture::Tiny;
use Digest::SHA;
use PDF::API2;
use XML::LibXML;
use XML::LibXSLT;
use Text::BibTeX;
use Text::BibTeX::Bib;

use fmdtools;

# BibTeX database structure
my $structure = new Text::BibTeX::Structure('Bib');
foreach my $type ($structure->types()) {
    $structure->add_fields($type, [qw(keyword file)]);
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

            # edit BibTeX entries in PDF files
            edit_bib_in_PDFs(@pdffiles);

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

        # unknown action
        default {
            croak "$0: unknown action '$action'";
        }

    }

    return 0;
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

        # save name of PDF file
        $bibentry->set('file', $pdffile);

        return $bibentry;
    });

    return @bibentries;
}

sub write_bib_to_fh {
    my ($fh, @bibentries) = @_;

    # print BibTeX entries
    for my $bibentry (sort { $a->key cmp $b->key } @bibentries) {

        # set BibTeX database structure
        $bibentry->{structure} = $structure;

        # coerse entry into BibTeX database structure
        $bibentry->silently_coerce();

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

    # parse BibTeX entries
    my @errmsgs;
    my @bibentries;
    {

        # open file
        open(my $fh, $filename) or croak "$0: could not open '$filename': $!";

        # check that the file contains non-comment, non-enpty lines
        my $doparse = 0;
        while (<$fh>) {
            next if /^%/;
            next if /^\s*$/;
            $doparse = 1;
            last;
        }
        $fh->seek(0, SEEK_SET);

        # the btparse library used by Text::BibTeX uses static memory
        # to store its parsing state, which means that a file MUST be
        # parsed IN ITS ENTIRETY (i.e. to end-of-file) before the library
        # can parse another file; this needs careful handling to get right!
        while ($doparse) {

            # try to parse a BibTeX entry, capturing any error messages
            my $bibentry;
            my $errout = Capture::Tiny::capture_merged {
                $bibentry = new Text::BibTeX::BibEntry $filename, $fh;
            };

            # if error messages were printed, parsing failed
            if (length($errout) > 0) {

                # save error messages
                push @errmsgs, split(/\n/, $errout);

                # we MUST get to end-of-file in order for the btparse
                # library to reset itself; so seek to end-of-file then
                # try to parse a final BibTeX entry
                $fh->sysseek(0, SEEK_END);
                $errout = Capture::Tiny::capture_merged {
                    $bibentry = new Text::BibTeX::BibEntry $filename, $fh;
                };

                last;

            }

            # if $bibentry is false, there are no more BibTeX
            # entries and parsing has successfully completed
            last if !$bibentry;

            # save BibTeX entry
            push @bibentries, $bibentry;

        }

        # close file
        $fh->close();

    }

    # check entries are conformant with BibTeX database structure
    foreach my $bibentry (@bibentries) {

        # set BibTeX database structure
        $bibentry->{structure} = $structure;

        # check entry
        my $errout = Capture::Tiny::capture_merged {
            $bibentry->check();
        };

        # if error messages were printed, check failed
        if (length($errout) > 0) {

            # save error messages
            push @errmsgs, split(/\n/, $errout);

            last;

        }

    }

    # if errors were encountered, return unsuccessfully
    if (@errmsgs > 0) {
        return (0, @errmsgs);
    }

    return (1, @bibentries);
}

sub write_bib_to_PDF {
    my (@bibentries) = @_;

    # write BibTeX entries to PDF files
    fmdtools::parallel_loop("writing %i/%i BibTeX entries to PDF", \@bibentries, sub {
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
            next if $bibfield eq 'file';
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

}

sub edit_bib_in_PDFs {
    my (@pdffiles) = @_;

    # generate a checksum for a BibTeX entry
    my $bibentry_checksum = sub {
        my ($bibentry) = @_;
        my $digest = Digest::SHA->new();
        $digest->add($bibentry->type, $bibentry->key);
        foreach my $bibfield (sort { $a cmp $b } $bibentry->fieldlist()) {
            $digest->add($bibfield, $bibentry->get($bibfield));
        }
        return $digest->hexdigest;
    };

    # read BibTeX entries from PDF metadata
    my @bibentries = read_bib_from_PDF(@pdffiles);

    # create checksums of BibTeX entries
    my %checksums;
    foreach my $bibentry (@bibentries) {
        $checksums{$bibentry->get('file')} = &$bibentry_checksum($bibentry);
    }

    # write BibTeX entries to a temporary file for editing
    my $oldfh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$0: could not create temporary file";
    binmode($oldfh, ":encoding(iso-8859-1)");
    write_bib_to_fh($oldfh, @bibentries);
    $oldfh->flush();

    # edit and re-read BibTeX entries, allowing for errors
    my @errmsg;
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
        foreach (@errmsg) {
            print $fh "%% ERROR: $_\n";
        }
        $oldfh->sysseek(0, SEEK_SET);
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
        my $linediff = @retn - @errmsg;
        @errmsg = @retn;
        foreach (@errmsg) {
            s{^.*, line (\d+)}{ 'line ' . ($1 + $linediff) }e;
        }

    }

    # filter out BibTeX entries that have not been modified
    my @modbibentries = grep { &$bibentry_checksum($_) ne $checksums{$_->get('file')} } @bibentries;
    fmdtools::progress("not writing %i unmodified BibTeX entries\n", @bibentries - @modbibentries) if @modbibentries < @bibentries;

    # write BibTeX entries to PDF metadata
    write_bib_to_PDF(@modbibentries);

    return @modbibentries;
}
