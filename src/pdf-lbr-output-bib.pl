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
use Clipboard;
use FindBin qw($Script);
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;

@perl_use_lib@;
use pdflibrarian::config;
use pdflibrarian::bibtex qw(read_bib_from_pdf find_dup_bib_keys write_bib_to_fh);
use pdflibrarian::title_abbr qw(%aas_macros abbr_iso4_title);
use pdflibrarian::util qw(find_pdf_files);

=pod

=head1 NAME

B<pdf-lbr-output-bib> - Output BibTeX bibliographic metadata from PDF files.

=head1 SYNOPSIS

B<pdf-lbr-output-bib> B<--help>|B<-h>

B<pdf-lbr-output-bib> [ B<--clipboard>|B<-c> ] [ B<--max-authors>|B<-m> I<count> [ B<--only-first-author>|B<-f> ] ] [ B<--exclude>|B<-e> I<field> | B<--no-exclude>|B<-E> ] [ B<--set>|B<-s> I<field>B<=>I<value> ... ] [ B<--abbreviate>|B<-a> I<scheme> ... ] I<files>|I<directories> ...

=head1 DESCRIPTION

B<pdf-lbr-output-bib> reads BibTeX bibliographic metadata embedded in PDF I<files> and/or any PDF files in I<directories>.

The BibTeX metadata is then printed to standard output; if B<--clipboard> or B<-c> is given, it is instead copied to the clipboard.

=head1 OPTIONS

=over 4

=item B<--max-authors>|B<-m> I<count> [ B<--only-first-author>|B<-f> ]

If the number of authors is greater than I<count>, and

=over 4

=item * If B<--only-first-author> is given, output only the first author, followed by "and others".

=item * Otherwise, output the first I<count> authors, followed by "and others".

=back

=item B<--exclude>|B<-e> I<field>

Exclude the BibTeX I<field> from the output. If not set, a default list of fields given in the configuration file is excluded.

=item B<--no-exclude>|B<-E>

Do not exclude any the BibTeX fields from the output.

=item B<--set>|B<-s> I<field>B<=>I<value> ...

Set each BibTeX I<field> to the given I<value> before printing.

=item B<--abbreviate>|B<-a> I<scheme> ...

Abbreviate journal/series titles according to the given I<scheme>, applied in the order given on the command line. Available I<scheme>s:

=over 4

=item I<aas>

AAS macros for astronomy journals, used by the NASA Astrophysics Data System.

=item I<iso4>

ISO4 abbreviations using the ISSN List of Title Word Abbreviations.

=item I<iso4~>

Same as I<iso4> but separate words with tildes instead of spaces.

=back

=back

=head1 PART OF

PDF Librarian version @VERSION@

=cut

# handle help options
my ($version, $help, $clipboard, $max_authors, $only_first_author, @exclude, $no_exclude, %set, @abbreviate_schemes);
$max_authors = 0;
GetOptions(
           "version|v" => \$version,
           "help|h" => \$help,
           "clipboard|c" => \$clipboard,
           "max-authors|m=i" => \$max_authors,
           "only-first-author|f" => \$only_first_author,
           "exclude|e=s" => \@exclude,
           "no-exclude|E" => \$no_exclude,
           "set|s=s" => \%set,
           "abbreviate|a=s" => \@abbreviate_schemes,
          ) or croak "$Script: could not parse options";
if ($version) { print "PDF Librarian version @VERSION@\n"; exit 1; }
pod2usage(-verbose => 2, -exitval => 1) if ($help);
croak "$Script: --max-authors must be positive" if $max_authors < 0;
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
  printf STDERR "$Script: excluding BibTeX fields '%s' from output\n", join("', '", @exclude);
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

# abbreviate journal/series titles
foreach my $bibentry (@bibentries) {
  foreach my $bibfield (qw(journal series)) {
    next unless $bibentry->exists($bibfield);
    foreach my $scheme (@abbreviate_schemes) {

      if ($scheme =~ /^aas$/) {

        # abbreviate journal title
        my $journal = $bibentry->get($bibfield);
        while (my ($key, $value) = each %aas_macros) {
          last if $journal =~ s/^\s*$value\s*$/\\$key/i;
        }
        $bibentry->set($bibfield, $journal);

      } elsif ($scheme =~ /^iso4([~])?$/) {

        # parse ISO4 options
        my $separator = $1 // ' ';

        # abbreviate journal title
        my $journal = $bibentry->get($bibfield);
        $journal = abbr_iso4_title($separator, $journal);
        $bibentry->set($bibfield, $journal);

      } else {
        croak "$Script: unrecognised abbreviation scheme '$scheme'";
      }

    }
  }
}

# write BibTeX entries to string
my $bibstring = "";
{
  open(my $fh, "+<", \$bibstring);
  write_bib_to_fh { fh => $fh, max_authors => $max_authors, only_first_author => $only_first_author }, @bibentries;
  close($fh);
}

# output BibTeX entries
if ($clipboard) {
  Clipboard->copy_to_all_selections($bibstring);
  printf STDERR "$Script: BibTeX metadata has been copied to the clipboard\n";
} else {
  print "$bibstring";
}

exit 0;
