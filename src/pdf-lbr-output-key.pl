#!@PERL@

# Copyright (C) 2016--2023 Karl Wette
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
use Clipboard;
use FindBin qw($Script);
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;

@perl_use_lib@;
use pdflibrarian::config;
use pdflibrarian::util qw(get_file_list find_pdf_files);

=pod

=head1 NAME

B<pdf-lbr-output-key> - Output BibTeX bibliographic keys from PDF files.

=head1 SYNOPSIS

B<pdf-lbr-output-key> B<--help>|B<-h>

B<pdf-lbr-output-key> [ B<--clipboard>|B<-c> ] I<files>|I<directories> ...

... I<files>|I<directories> ... B<|> B<pdf-lbr-output-key> ...

=head1 DESCRIPTION

B<pdf-lbr-output-key> reads BibTeX bibliographic keys for PDF I<files> and/or any PDF files in I<directories>. If I<files>|I<directories> are not given on the command line, they are read from standard input, one per line.

The BibTeX keys are then printed to standard output, separated by commas; if B<--clipboard> is given, they are instead copied to the clipboard.

=cut

# handle help options
my ($version, $help, $clipboard);
GetOptions(
           "version|v" => \$version,
           "help|h" => \$help,
           "clipboard|c" => \$clipboard,
          ) or croak "$Script: could not parse options";
if ($version) { print "PDF Librarian version @VERSION@\n"; exit 1; }
pod2usage(-verbose => 2, -exitval => 1) if ($help);

# iterate over arguments to preserve order
my %keys;
my $keycount = 0;
foreach my $arg (get_file_list()) {

  # get list of PDF files
  my @pdffiles = find_pdf_files($arg);
  croak "$Script: no PDF files to read from '$arg'" unless @pdffiles > 0;
  foreach my $pdffile (@pdffiles) {

    # get key from PDF filename
    my ($vol, $dir, $file) = File::Spec->splitpath($pdffile);
    my $key = $file;
    $key =~ s/\.pdf$//;

    # store key, pruning duplicates
    $keys{$key} = $keycount++ unless defined($keys{$key});

  }
}

# make comma-separated list of keys
my $keystring = join(", ", sort({$keys{$a} <=> $keys{$b}} keys(%keys)));

# output BibTeX keys
if ($clipboard) {
  Clipboard->copy_to_all_selections($keystring);
  printf STDERR "$Script: BibTeX keys have been copied to the clipboard\n";
} else {
  print "$keystring\n";
}

exit 0;
