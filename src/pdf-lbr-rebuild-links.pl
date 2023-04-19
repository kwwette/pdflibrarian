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
use File::Copy;
use File::Spec;
use File::stat;
use FindBin qw($Script);
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;

@perl_use_lib@;
use pdflibrarian::bibtex qw(read_bib_from_pdf generate_bib_keys format_bib write_bib_to_fh edit_bib_in_fh write_bib_to_pdf);
use pdflibrarian::config;
use pdflibrarian::library qw(update_pdf_lib make_pdf_links cleanup_links);
use pdflibrarian::util qw(find_pdf_files);

=pod

=head1 NAME

B<pdf-lbr-rebuild-links> - Rebuild the PDF links directory.

=head1 SYNOPSIS

B<pdf-lbr-rebuild-links> B<--help>|B<-h>

B<pdf-lbr-rebuild-links> [B<-o> I<output-directory>]

=head1 DESCRIPTION

B<pdf-lbr-rebuild-links> rebuilds the PDF links directory.

All BibTeX metadata is written to a temporary file, which is then opened in an editing program to check for errors. The editing program is given either by the B<$VISUAL> or B<$EDITOR> environment variables, or else the program B<@fallback_editor@>.

PDF files for any BibTeX entries removing during editing are moved to the directory I<output-directory>, or else to the user's home directory.

=head1 PART OF

PDF Librarian version @VERSION@

=cut

# handle help options
my ($version, $help, $outdir);
GetOptions(
           "version|v" => \$version,
           "help|h" => \$help,
           "output-directory|o=s" => \$outdir,
          ) or croak "$Script: could not parse options";
if ($version) { print "PDF Librarian version @VERSION@\n"; exit 1; }
pod2usage(-verbose => 2, -exitval => 1) if ($help);
$outdir = $ENV{HOME} unless defined($outdir);

# check input
croak "$Script: '$outdir' is not a directory" unless -d $outdir;

# get list of PDF files in library
print STDERR "$Script: finding PDF files in library directory '$pdflibrarydir' ...\n";
my @pdffiles = find_pdf_files($pdflibrarydir);

# read BibTeX entries from PDF metadata
my @bibentries = read_bib_from_pdf(@pdffiles);

# write formatted BibTeX entries to a temporary file for editing
my $fh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$Script: could not create temporary file";
binmode($fh, ":encoding(iso-8859-1)");
write_bib_to_fh({ fh => $fh }, format_bib({}, @bibentries));

# edit BibTeX entries in PDF files
@bibentries = edit_bib_in_fh($fh, @bibentries);
exit 0 unless @bibentries > 0;

# find any PDF files without a BibTeX entry
my %bibentryfiles;
foreach my $bibentry (@bibentries) {
  $bibentryfiles{$bibentry->get('file')} = 1;
}
foreach my $pdffile (@pdffiles) {
  if (!defined($bibentryfiles{$pdffile})) {
    my ($vol, $dir, $file) = File::Spec->splitpath($pdffile);
    my $removedpdffile = File::Spec->catfile($outdir, $file);
    move($pdffile, $removedpdffile) or croak "$Script: could not move '$pdffile' to '$removedpdffile': $!";
    print STDERR "$Script: removed PDF file '$file' to '$outdir'\n";
  }
}

# regenerate keys for BibTeX entries
generate_bib_keys(@bibentries);

# rewrite all BibTeX entries to PDF metadata
foreach my $bibentry (@bibentries) {
  $bibentry->delete('checksum');
}
write_bib_to_pdf(@bibentries);

# ensure all PDF files are part of library
update_pdf_lib(@bibentries);

# make links in PDF links directory to real PDF files
make_pdf_links(@bibentries);

# cleanup PDF links directory
cleanup_links();

exit 0;
