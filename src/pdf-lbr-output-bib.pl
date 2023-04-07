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
use pdflibrarian::title_abbr qw(get_aas_macros abbr_iso4_title);
use pdflibrarian::util qw(find_pdf_files);

=pod

=head1 NAME

B<pdf-lbr-output-bib> - Output BibTeX bibliographic metadata from PDF files.

=head1 SYNOPSIS

B<pdf-lbr-output-bib> B<--help>|B<-h>

B<pdf-lbr-output-bib> [ B<--clipboard>|B<-c> ] [ B<--max-authors>|B<-m> I<count> [ B<--only-first-author>|B<-f> ] ] [ B<--filter>|B<-F> [I<type>B<:>]I<field>B<=>I<spec> ... ] [ B<--abbreviate>|B<-a> I<scheme> ... ] [ B<--pdf-file-comment>|B<-P> ] I<files>|I<directories> ...

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

=item B<--filter>|B<-F> [I<type>B<:>]I<field>B<=>I<spec> ...

Apply the filter I<spec> to the BibTeX I<field>. If given, I<type> applies filter only to BibTeX entries of that type. Possible I<spec> are:

=over 4

=item B<d>

Exclude I<field> from output.

=item B<=>I<value>

Set I<field> to I<value> in output.

=item B<s>B</>I<pattern>B</>I<replacement>[B</>I<pattern>B</>I<replacement>...]B</>

Replace each regular expression I<pattern> with I<replacement> in output.

=back

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

=item B<--pdf-file-comment>|B<-P>

If true, output the PDF filename as a comment before each BibTeX entry. Default is false. (The PDF filename is never included in the BibTeX entry itself.)

=back

=head1 PART OF

PDF Librarian version @VERSION@

=cut

# handle help options
my ($version, $help, $clipboard, $max_authors, $only_first_author, %filter, @abbreviate_schemes, $pdf_file_comment);
$max_authors = 0;
$pdf_file_comment = 0;
GetOptions(
           "version|v" => \$version,
           "help|h" => \$help,
           "clipboard|c" => \$clipboard,
           "max-authors|m=i" => \$max_authors,
           "only-first-author|f" => \$only_first_author,
           "filter|F=s" => \%filter,
           "abbreviate|a=s" => \@abbreviate_schemes,
           "pdf-file-comment|P" => \$pdf_file_comment,
          ) or croak "$Script: could not parse options";
if ($version) { print "PDF Librarian version @VERSION@\n"; exit 1; }
pod2usage(-verbose => 2, -exitval => 1) if ($help);
croak "$Script: --max-authors must be positive" if $max_authors < 0;

# get list of PDF files
my @pdffiles = find_pdf_files(@ARGV);
croak "$Script: no PDF files to read from" unless @pdffiles > 0;

# read BibTeX entries from PDF metadata
my @bibentries = read_bib_from_pdf(@pdffiles);

# use default field filter if none given
if (scalar(%filter) == 0) {
  %filter = %default_filter;
}

# print field filters
foreach my $field (sort { $filter{$a} cmp $filter{$b} || $a cmp $b } keys %filter) {
  my $bibfield = $field;
  my $bibselect = "BibTeX field '$bibfield'";
  if ($bibfield =~ /^([^:]*):(.*)$/) {
    $bibfield = $2;
    $bibselect = "BibTeX field '$2' (in entries of type '$1')";
  }
  my $spec = $filter{$field};
  if ($spec =~ /^d/) {
    printf STDERR "$Script: excluding $bibselect from output\n";
  } elsif ($spec =~ s/^=//) {
    printf STDERR "$Script: setting $bibselect to value '$spec' in output\n";
  } elsif ($spec =~ s|^s/(.*)/$|$1|) {
    my @spec_regex = split(m|/|, $1, -1);
    if (@spec_regex == 0 || @spec_regex % 2 != 0) {
      croak "$Script: regular expression filter '$spec' must have form '/pattern/replacement[/pattern/replacement...]/'";
    }
    while (@spec_regex) {
      my $patt = shift @spec_regex;
      my $repl = shift @spec_regex;
      printf STDERR "$Script: replacing regular expression '$patt' with '$repl' in output $bibselect\n";
    }
  } else {
    croak "$Script: invalid spec '$bibfield=$spec' passed to --filter/-F";
  }
}

# apply field filters
foreach my $bibentry (@bibentries) {
  foreach my $field (keys %filter) {
    my $bibfield = $field;
    if ($bibfield =~ /^([^:]*):(.*)$/) {
      $bibfield = $2;
      next if $bibentry->type ne $1;
    }
    my $spec = $filter{$field};
    if ($spec =~ /^d/) {
      $bibentry->delete($bibfield);
    } elsif ($spec =~ s/^=//) {
      $bibentry->set($bibfield, $spec);
    } elsif ($spec =~ s|^s/(.*)/$|$1|) {
      if ($bibentry->exists($bibfield)) {
        my @spec_regex = split(m|/|, $1, -1);
        my $bibfieldvalue = $bibentry->get($bibfield);
        while (@spec_regex) {
          my $patt = shift @spec_regex;
          my $repl = shift @spec_regex;
          $bibfieldvalue =~ s/$patt/$repl/g;
        }
        $bibentry->set($bibfield, $bibfieldvalue);
      }
    }
  }
}

# error if duplicate BibTeX keys are found
my @dupkeys = find_dup_bib_keys(@bibentries);
croak "$Script: BibTeX entries contain duplicate keys: @dupkeys" if @dupkeys > 0;

# abbreviate journal/series titles
foreach my $bibentry (@bibentries) {
  foreach my $titlefield (qw(journal series)) {

    # skip missing fields
    next unless $bibentry->exists($titlefield);

    # abbreviate title by applying schemes
    my $title = $bibentry->get($titlefield);
    foreach my $scheme (@abbreviate_schemes) {

      if ($scheme =~ /^aas$/) {

        # abbreviate title
        my %aas_macros = get_aas_macros();
        while (my ($key, $value) = each %aas_macros) {
          last if $title =~ s/^\s*$value\s*$/\\$key/i;
        }

      } elsif ($scheme =~ /^iso4([~])?$/) {

        # parse ISO4 options
        my $separator = $1 // ' ';

        # abbreviate title
        $title = abbr_iso4_title($separator, $title);

      } else {
        croak "$Script: unrecognised abbreviation scheme '$scheme'";
      }

      # stop if scheme has renamed title
      last if $title ne $bibentry->get($titlefield);

    }
    $bibentry->set($titlefield, $title);

  }
}

# write BibTeX entries to string
my $bibstring = "";
{
  open(my $fh, "+<", \$bibstring);
  write_bib_to_fh( {
                    fh => $fh,
                    max_authors => $max_authors,
                    only_first_author => $only_first_author,
                    pdf_file => $pdf_file_comment ? "comment" : "none"
                   },
                   @bibentries
                 );
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
