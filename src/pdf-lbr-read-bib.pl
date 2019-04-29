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
use pdflibrarian::bibtex qw(read_bib_from_pdf find_dup_bib_keys write_bib_to_fh);
use pdflibrarian::util qw(find_pdf_files);

=pod

=head1 NAME

B<pdf-lbr-read-bib> - Read BibTeX bibliographic metadata from PDF files.

=head1 SYNOPSIS

B<pdf-lbr-read-bib> B<--help>|B<-h>

B<pdf-lbr-read-bib> [ B<--exclude>|B<-e> I<field> | B<--no-exclude>|B<-E> ] [ B<--set>|B<-s> I<field>B<=>I<value> ... ] I<files>|I<directories> ...

=head1 DESCRIPTION

B<pdf-lbr-read-bib> reads BibTeX bibliographic metadata embedded in PDF I<files> and/or any PDF files in I<directories>.

The BibTeX metadata is then printed to standard output.

=head1 OPTIONS

=over 4

=item B<--exclude>|B<-e> I<field>

Exclude the BibTeX I<field> from the printed output. If not set, a default list of fields given in the configuration file is excluded.

=item B<--no-exclude>|B<-E>

Do not exclude any the BibTeX fields from the printed output.

=item B<--set>|B<-s> I<field>B<=>I<value> ...

Set each BibTeX I<field> to the given I<value> before printing.

=back

=head1 PART OF

PDF Librarian, version @VERSION@.

=cut

# handle help options
my ($help, @exclude, $no_exclude, %set);
GetOptions(
           "help|h" => \$help,
           "exclude|e=s" => \@exclude,
           "no-exclude|E" => \$no_exclude,
           "set|s=s" => \%set,
          ) or croak "$Script: could not parse options";
pod2usage(-verbose => 2, -exitval => 1) if ($help);
croak "$Script: --exclude and --no-exclude are mutually exclusive" if (@exclude > 0 and $no_exclude);

# get list of PDF files
my @pdffiles = find_pdf_files(@ARGV);
croak "$Script: no PDF files to read from" unless @pdffiles > 0;

# read BibTeX entries from PDF metadata
my @bibentries = read_bib_from_pdf(@pdffiles);

# use default exclude fields if --no-exclude is not given
if (!$no_exclude && @exclude == 0) {
  @exclude = @default_exclude;
}
if (@exclude > 0) {
  printf STDERR "$Script: excluding BibTeX fields '%s' from printed output\n", join("', '", @exclude);
}

foreach my $bibentry (@bibentries) {

  # exclude BibTeX fields ('file' is always excluded)
  foreach my $bibfield (('file', @exclude)) {
    $bibentry->delete($bibfield);
  }

  # set BibTeX fields
  while (my ($bibfield, $bibvalue) = each %set) {
    $bibentry->set($bibfield, $bibvalue);
  }

}

# error if duplicate BibTeX keys are found
my @dupkeys = find_dup_bib_keys(@bibentries);
croak "$Script: BibTeX entries contain duplicate keys: @dupkeys" if @dupkeys > 0;

# print BibTeX entries
write_bib_to_fh(\*STDOUT, @bibentries);

exit 0;
