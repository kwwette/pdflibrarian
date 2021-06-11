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
use pdflibrarian::config;
use pdflibrarian::bibtex qw(read_bib_from_pdf generate_bib_keys write_bib_to_fh edit_bib_in_fh write_bib_to_pdf);
use pdflibrarian::library qw(update_pdf_lib make_pdf_links cleanup_links);
use pdflibrarian::util qw(is_in_dir unique_list find_pdf_files);

=pod

=head1 NAME

B<pdf-lbr-edit-bib> - Edit BibTeX bibliographic metadata in PDF files.

=head1 SYNOPSIS

B<pdf-lbr-edit-bib> B<--help>|B<-h>

B<pdf-lbr-edit-bib> I<links>|I<link-directories> ...

=head1 DESCRIPTION

B<pdf-lbr-edit-bib> reads BibTeX bibliographic metadata embedded in PDF files given by I<links> and/or within I<link-directories> in the PDF links directory.

The BibTeX metadata is written to a temporary file, which is then opened in an editing program, given either by the B<$VISUAL> or B<$EDITOR> environment variables, or else the program B<@fallback_editor@>.

Any modifications are then written back to the PDF files given by the I<file> field in each BibTeX entry, and the PDF library links rebuilt as needed.

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

# get list of PDF files
my @pdffiles = find_pdf_files(@ARGV);
croak "$Script: no PDF files to edit" unless @pdffiles > 0;
for my $pdffile (@pdffiles) {
  croak "$Script: '$pdffile' is not in the PDF library" unless is_in_dir($pdffiledir, $pdffile);
}

# read BibTeX entries from PDF metadata
my @bibentries = read_bib_from_pdf(@pdffiles);

# generate initial keys for BibTeX entries
generate_bib_keys(@bibentries);

# coerse entries into BibTeX database structure
foreach my $bibentry (@bibentries) {
  $bibentry->silently_coerce();
}

# write BibTeX entries to a temporary file for editing
my $fh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$Script: could not create temporary file";
binmode($fh, ":encoding(iso-8859-1)");
write_bib_to_fh { fh => $fh }, @bibentries;

# edit BibTeX entries in PDF files
@bibentries = edit_bib_in_fh($fh, @bibentries);

# regenerate keys for modified BibTeX entries
generate_bib_keys(@bibentries);

# write BibTeX entries to PDF metadata; return modified BibTeX entries
@bibentries = write_bib_to_pdf(@bibentries);

# ensure all PDF files are part of library
update_pdf_lib(@bibentries);

# update links in PDF links directory to real PDF files
make_pdf_links(@bibentries);

# cleanup PDF links directory
cleanup_links();

exit 0;
