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
use pdflibrarian::config;
use pdflibrarian::library qw(cleanup_links);
use pdflibrarian::util qw(is_in_dir);

=pod

=head1 NAME

B<pdf-lbr-remove-pdf> - Remove a PDF file from the PDF library.

=head1 SYNOPSIS

B<pdf-lbr-remove-pdf> B<--help>|B<-h>

B<pdf-lbr-remove-pdf> [-o I<output-directory>] I<link>

=head1 DESCRIPTION

B<pdf-lbr-remove-pdf> removes a PDF file, given by a I<link> in the PDF links directory, from the PDF library.

The PDF file is moved to the directory I<output-directory>, or else to the user's home directory.

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
croak "$Script: requires a single argument" unless @ARGV == 1;
my $pdflink = $ARGV[0];
croak "$Script: '$pdflink' is not in the PDF library" unless is_in_dir($pdflinkdir, $pdflink);
croak "$Script: '$pdflink' is not a symbolic link" unless -l $pdflink;

# try to resolve symbolic link
my $pdffile = readlink($pdflink) or croak "$Script: could not resolve '$pdflink': %!";
croak "$Script: '$pdflink' is not in the PDF library" unless is_in_dir($pdffiledir, $pdffile);

# move PDF file to output directory, with same name as link
my ($linkvol, $linkdir, $linkfile) = File::Spec->splitpath($pdflink);
my $removedpdffile = File::Spec->catfile($outdir, $linkfile);
move($pdffile, $removedpdffile) or croak "$Script: could not move '$pdffile' to '$removedpdffile': $!";
print STDERR "$Script: removed PDF file to '$removedpdffile'\n";

# cleanup PDF links directory
cleanup_links();

exit 0;
