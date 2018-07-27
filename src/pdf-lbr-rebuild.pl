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
use Getopt::Long;
use Pod::Usage;

@perl_use_lib@;
use pdflibrarian::bibtex qw(read_bib_from_pdf generate_bib_keys);
use pdflibrarian::config;
use pdflibrarian::library qw(update_pdf_lib make_pdf_links cleanup_links);
use pdflibrarian::util qw(find_pdf_files);

=pod

=head1 NAME

B<pdf-lbr-rebuild> - Rebuild the PDF links directory.

=head1 SYNOPSIS

B<pdf-lbr-rebuild> B<--help>|B<-h>

B<pdf-lbr-rebuild>

=head1 DESCRIPTION

B<pdf-lbr-rebuild> rebuilds the PDF links directory.

=head1 PART OF

PDF Librarian, version @VERSION@.

=cut

# handle help options
my ($help);
GetOptions(
           "help|h" => \$help,
          ) or croak "$Script: could not parse options";
pod2usage(-verbose => 2, -exitval => 1) if ($help);

# get list of PDF files in library
my @pdffiles = find_pdf_files($pdffiledir);

# read BibTeX entries from PDF metadata
my @bibentries = read_bib_from_pdf(@pdffiles);

# regenerate keys for BibTeX entries
generate_bib_keys(@bibentries);

# ensure all PDF files are part of library
update_pdf_lib(@bibentries);

# cleanup all PDF links directory
cleanup_links('all');

# make links in PDF links directory to real PDF files
make_pdf_links(@bibentries);

# cleanup PDF links directory
cleanup_links();

exit 0;
