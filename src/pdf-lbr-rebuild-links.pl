#!@PERL@

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

use v@PERLVERSION@;
use strict;
use warnings;

use Carp;
use FindBin qw($Script);
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;

@perl_use_lib@;
use pdflibrarian::bibtex qw(read_bib_from_pdf generate_bib_keys write_bib_to_fh edit_bib_in_fh write_bib_to_pdf);
use pdflibrarian::config;
use pdflibrarian::library qw(update_pdf_lib make_pdf_links cleanup_links);
use pdflibrarian::util qw(find_pdf_files);

=pod

=head1 NAME

B<pdf-lbr-rebuild-links> - Rebuild the PDF links directory.

=head1 SYNOPSIS

B<pdf-lbr-rebuild-links> B<--help>|B<-h>

B<pdf-lbr-rebuild-links>

=head1 DESCRIPTION

B<pdf-lbr-rebuild-links> rebuilds the PDF links directory.

All BibTeX metadata is written to a temporary file, which is then opened in an editing program to check for errors. The editing program is given either by the B<$VISUAL> or B<$EDITOR> environment variables, or else the program B<@fallback_editor@>.

=head1 PART OF

PDF Librarian version @VERSION@

=cut

# handle help options
my ($version, $help);
GetOptions(
           "version|v" => \$version,
           "help|h" => \$help,
          ) or croak "$Script: could not parse options";
if ($version) { print "PDF Librarian version @VERSION@\n"; exit 1; }
pod2usage(-verbose => 2, -exitval => 1) if ($help);

# get list of PDF files in library
my @pdffiles = find_pdf_files($pdffiledir);

# read BibTeX entries from PDF metadata
my @bibentries = read_bib_from_pdf(@pdffiles);

# write BibTeX entries to a temporary file for editing
my $fh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$Script: could not create temporary file";
binmode($fh, ":encoding(iso-8859-1)");
write_bib_to_fh { fh => $fh }, @bibentries;

# edit BibTeX entries in PDF files
edit_bib_in_fh($fh, @bibentries);

# regenerate keys for BibTeX entries
generate_bib_keys(@bibentries);

# write BibTeX entries to PDF metadata
write_bib_to_pdf(@bibentries);

# ensure all PDF files are part of library
update_pdf_lib(@bibentries);

# cleanup all PDF links directory
cleanup_links('all');

# make links in PDF links directory to real PDF files
make_pdf_links(@bibentries);

# cleanup PDF links directory
cleanup_links();

exit 0;
