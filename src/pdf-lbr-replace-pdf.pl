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
use pdflibrarian::bibtex qw(read_bib_from_pdf write_bib_to_pdf);
use pdflibrarian::config;
use pdflibrarian::library qw(update_pdf_lib make_pdf_links cleanup_links);
use pdflibrarian::util qw(is_in_dir find_pdf_files);

=pod

=head1 NAME

B<pdf-lbr-replace-pdf> - Replace a PDF file in the PDF library with a new PDF file.

=head1 SYNOPSIS

B<pdf-lbr-replace-pdf> B<--help>|B<-h>

B<pdf-lbr-replace-pdf> [-o I<output-directory>] I<old-link> I<new-file>

=head1 DESCRIPTION

B<pdf-lbr-replace-pdf> replaces a PDF file, given by a I<old-link> in the PDF links directory, with a new PDF I<file>.

The replaced PDF file is moved to the directory I<output-directory>, or else to the user's home directory.

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
croak "$Script: requires two arguments" unless @ARGV == 2;
my $pdflink = $ARGV[0];
croak "$Script: '$pdflink' is not in the PDF library" unless is_in_dir($pdflinkdir, $pdflink);
croak "$Script: '$pdflink' is not a symbolic link" unless -l $pdflink;
my @newpdffile = find_pdf_files($ARGV[1]);
croak "$Script: '$ARGV[1]' is not a PDF file" unless @newpdffile == 1;

# try to resolve symbolic link
my $pdffile = readlink($pdflink) or croak "$Script: could not resolve '$pdflink': %!";
croak "$Script: '$pdflink' is not in the PDF library" unless is_in_dir($pdffiledir, $pdffile);

# read BibTeX entry from PDF metadata
my @bibentry = read_bib_from_pdf($pdffile);

# move old PDF file to output directory, with same name as link
my ($linkvol, $linkdir, $linkfile) = File::Spec->splitpath($pdflink);
my $removedpdffile = File::Spec->catfile($outdir, $linkfile);
move($pdffile, $removedpdffile) or croak "$Script: could not move '$pdffile' to '$removedpdffile': $!";
print STDERR "$Script: removed PDF file to '$removedpdffile'\n";

# modify BibTeX entry to point to new PDF file
$bibentry[0]->delete('checksum');
$bibentry[0]->set('file', $newpdffile[0]);

# write BibTeX entry to PDF metadata
write_bib_to_pdf(@bibentry);

# ensure all PDF files are part of library
update_pdf_lib(@bibentry);

# update links in PDF links directory to real PDF files
make_pdf_links(@bibentry);

# cleanup PDF links directory
cleanup_links();

exit 0;
