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
use pdflibrarian::bibtex qw(read_bib_from_pdf find_dup_bib_keys format_bib format_bib_authors write_bib_to_fh);
use pdflibrarian::title_abbr qw(get_aas_macros abbr_iso4_title);
use pdflibrarian::util qw(get_file_list find_pdf_files remove_tex_markup);

=pod

=head1 NAME

B<pdf-lbr-output-bib> - Output BibTeX bibliographic metadata from PDF files.

=head1 SYNOPSIS

B<pdf-lbr-output-bib> B<--help>|B<-h>

B<pdf-lbr-output-bib> [ B<--clipboard>|B<-c> ] [ B<--max-authors>|B<-m> I<count> [ B<--only-first-author>|B<-f> ] ] [ B<--filter>|B<-F> [I<type>B<:>]I<field>[B<?>I<iffield>|B<!>I<ifnotfield>...]B<=>I<spec> ... ] [ B<--no-default-filter>|B<-N> ] [ B<--abbreviate>|B<-a> I<scheme> ... ] [ B<--output-text-format>|B<-o> I<type>=<format> ... | B<--output-text>|B<-O> | B<--pdf-file-comment>|B<-P> ] I<files>|I<directories> ...

... I<files>|I<directories> ... B<|> B<pdf-lbr-output-bib> ...

=head1 DESCRIPTION

B<pdf-lbr-output-bib> reads BibTeX bibliographic metadata embedded in PDF I<files> and/or any PDF files in I<directories>. If I<files>|I<directories> are not given on the command line, they are read from standard input, one per line.

The BibTeX metadata is then printed to standard output; if B<--clipboard> is given, it is instead copied to the clipboard.

=head1 OPTIONS

=over 4

=item B<--max-authors>|B<-m> I<count> [ B<--only-first-author>|B<-f> ]

If the number of authors is greater than I<count>, and

=over 4

=item * If B<--only-first-author> is given, output only the first author, followed by "and others".

=item * Otherwise, output the first I<count> authors, followed by "and others".

=back

=item B<--filter>|B<-F> [I<type>B<:>]I<field>[B<?>I<iffield>|B<!>I<ifnotfield>...]B<=>I<spec> ... [ B<--no-default-filter>|B<-N> ]

Apply the filter I<spec> to the BibTeX I<field>. If given, I<type> applies filter only to BibTeX entries of that type, I<iffield> applies filter only to BibTeX entries where <iffield> is defined, and I<ifnotfield> applies filter only to BibTeX entries where <ifnotfield> is not defined. Possible I<spec> are:

=over 4

=item B<d>

Exclude I<field> from output.

=item B<=>I<value>

Set I<field> to I<value> in output.

=item B<s>B</>I<pattern>B</>I<replacement>[B</>I<pattern>B</>I<replacement>...]B</>

Replace each regular expression I<pattern> with I<replacement> in output.

=back

If no B<--filter> arguments are given, default filters given in the configuration file are applied (unless B<--no-default-filter> is given).

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

=item B<--output-text-format>|B<-o> I<type>=<format>

Instead of outputting a BibTeX entry, output plain text, formatting entries of type I<type> with format I<format>. BibTeX I<field>s may be substituted into I<format> with the syntax I<%field>.

The I<author> and I<editor> fields must include one of the suffixes I<:fvlj> or I<:vljf> to indicate the citation style: I<author:fvlj> cites authors with initials then last name; I<author:vljf> cites authors with last name then initials.

Format text surrounded by curly braces is removed if it contains a I<%> from an unexpanded I<field>. Curly braces may be nested to define alternatives for missing fields, e.g. I<{DOI:%doi{URL:%url}}> provides a URL only if the DOI field is missing.

=item B<--output-text>|B<-O>

Instead of outputting a BibTeX entry, output plain text, formatting entries with formats given in the configuration file.

=back

=head1 PART OF

PDF Librarian version @VERSION@

=cut

# handle help options
my ($version, $help, $clipboard, $max_authors, $only_first_author, %filter, $no_default_filter, @abbreviate_schemes, $pdf_file_comment, %output_text_format, $output_text);
$max_authors = 0;
$pdf_file_comment = 0;
GetOptions(
           "version|v" => \$version,
           "help|h" => \$help,
           "clipboard|c" => \$clipboard,
           "max-authors|m=i" => \$max_authors,
           "only-first-author|f" => \$only_first_author,
           "filter|F=s" => \%filter,
           "no-default-filter|N" => \$no_default_filter,
           "abbreviate|a=s" => \@abbreviate_schemes,
           "pdf-file-comment|P" => \$pdf_file_comment,
           "output-text-format|o=s" => \%output_text_format,
           "output-text|O" => \$output_text,
          ) or croak "$Script: could not parse options";
if ($version) { print "PDF Librarian version @VERSION@\n"; exit 1; }
pod2usage(-verbose => 2, -exitval => 1) if ($help);
croak "$Script: --max-authors must be positive" if $max_authors < 0;

# use default field filter if --no-default-filter is not given
if ($no_default_filter) {
  printf STDERR "$Script: using no default field filters\n";
} else {
  printf STDERR "$Script: using default field filters from configuration file\n";
  foreach my $field (keys %default_filter) {
    if (!defined($filter{$field})) {
      $filter{$field} = $default_filter{$field};
    }
  }
}

# parse field filters
my %filterbibtype;
my %filterbibfield;
my %filteriffields;
my %filterifnotfields;
foreach my $field (keys %filter) {
  my @tokens = split(/([:?!])/, $field);

  # parse [type:]field
  if (@tokens == 1) {
    $filterbibtype{$field} = ".";
    $filterbibfield{$field} = shift @tokens;
  } elsif ($tokens[1] eq ":") {
    $filterbibtype{$field} = shift @tokens;
    shift @tokens;
    $filterbibfield{$field} = shift @tokens;
  } else {
    $filterbibtype{$field} = ".";
    $filterbibfield{$field} = shift @tokens;
  }

  # parse [?iffield|!ifnotfield]
  $filteriffields{$field} = [];
  $filterifnotfields{$field} = [];
  while (@tokens > 0) {
    my $cond =  shift @tokens;
    my $condfield = shift @tokens;
    if ($cond eq "?") {
      push @{$filteriffields{$field}}, $condfield;
    } elsif ($cond eq "!") {
      push @{$filterifnotfields{$field}}, $condfield;
    } else {
      croak "$Script: unrecognised field condition '$cond'";
    }
  }

}

# print field filters
foreach my $field (sort { $filterbibtype{$a} cmp $filterbibtype{$b} || $filterbibfield{$a} cmp $filterbibfield{$b} } keys %filter) {
  my $bibtype = $filterbibtype{$field};
  my $bibfield = $filterbibfield{$field};

  # build field filter description
  my $filterdesc = "BibTeX field '$bibfield'";
  my @filterdescextra;
  if ($bibtype ne ".") {
    push @filterdescextra, "in entries of type '$bibtype'";
  }
  foreach my $iffield (sort { $a cmp $b } @{$filteriffields{$field}}) {
    push @filterdescextra, "if field '$iffield' is defined";
  }
  foreach my $ifnotfield (sort { $a cmp $b } @{$filterifnotfields{$field}}) {
    push @filterdescextra, "if field '$ifnotfield' is not defined";
  }
  if (@filterdescextra > 0) {
    $filterdesc .= " (" . join(", ", @filterdescextra) . ")";
  }

  # print field filter actions
  my $spec = $filter{$field};
  if ($spec eq "d") {

    printf STDERR "$Script: excluding $filterdesc from output\n";

  } elsif ($spec =~ s/^=//) {

    printf STDERR "$Script: setting $filterdesc to value '$spec' in output\n";

  } elsif ($spec =~ s|^s/(.*)/$|$1|) {

    my @spec_regex = split(m|/|, $1, -1);
    if (@spec_regex == 0 || @spec_regex % 2 != 0) {
      croak "$Script: regular expression filter '$spec' must have form '/pattern/replacement[/pattern/replacement...]/'";
    }
    while (@spec_regex) {
      my $patt = shift @spec_regex;
      my $repl = shift @spec_regex;
      printf STDERR "$Script: replacing regular expression '$patt' with '$repl' in output $filterdesc\n";
    }

  } else {

    croak "$Script: invalid spec '$bibfield=$spec' passed to --filter/-F";

  }

}

# get list of PDF files
my @pdffiles = find_pdf_files(get_file_list());
croak "$Script: no PDF files to read from" unless @pdffiles > 0;

# read BibTeX entries from PDF metadata
my @bibentries = read_bib_from_pdf(@pdffiles);

# format BibTeX entries
@bibentries = format_bib(
                         {
                          max_authors => $max_authors,
                          only_first_author => $only_first_author,
                         },
                         @bibentries
                        );

# apply field filters
foreach my $bibentry (@bibentries) {
  foreach my $field (sort { $a cmp $b } keys %filter) {
    my $bibtype = $filterbibtype{$field};
    my $bibfield = $filterbibfield{$field};

    # determine whether to apply field filter
    my $apply = ($bibentry->type =~ /$bibtype/);
    foreach my $iffield (sort { $a cmp $b } @{$filteriffields{$field}}) {
      $apply &&= $bibentry->exists($iffield);
    }
    foreach my $ifnotfield (sort { $a cmp $b } @{$filterifnotfields{$field}}) {
      $apply &&= ! $bibentry->exists($ifnotfield);
    }
    next unless $apply;

    # execute field filter
    my $spec = $filter{$field};
    if ($spec eq "d") {

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

# format BibTeX entries for output
foreach my $bibentry (@bibentries) {

  # quote capital letters in BibTeX 'title' fields
  foreach my $bibfield ($bibentry->fieldlist()) {
    if ($bibfield =~ /title$/) {
      my $title = $bibentry->get($bibfield);
      my @words = split /\s+/, $title;
      foreach my $word (@words) {
        $word =~ s/[{}]//g;
        $word =~ s/((?:\\.)?[A-Z]+)/\{$1\}/g;
        $word =~ s/\$\{([A-Z]+)\}\$/{\$$1\$}/g;
      }
      $title = join(" ", @words);
      $title =~ s/^\{([A-Z])\}/$1/;
      $bibentry->set($bibfield, $title);
    }
  }

  # abbreviate journal/series titles
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

# use default output text formats if requested
if ($output_text) {
  foreach my $type (keys %default_output_text_format) {
    if (!defined($output_text_format{$type})) {
      $output_text_format{$type} = $default_output_text_format{$type};
    }
  }
}
foreach my $bibtype (keys %output_text_format) {
  $output_text = 1;
  if (defined($default_output_text_format{$bibtype})) {
    printf STDERR "$Script: using output format for '$bibtype' entries from configuration file\n";
  } else {
    printf STDERR "$Script: using output format for '$bibtype' entries from command line\n";
  }
}

# write BibTeX entries to string
my $bibstring = "";
if ($output_text) {

  # preserve input order of files in output plain text entries
  my %pdffileorder;
  my $order = 0;
  foreach my $pdffile (@pdffiles) {
    $pdffileorder{$pdffile} = ++$order;
  }

  # write plain text
  foreach my $bibentry (sort { $pdffileorder{$a->get("file")} <=> $pdffileorder{$b->get("file")} } @bibentries) {

    # get plain text format
    my $bibtype = $bibentry->type;
    my $bibstr = $output_text_format{$bibtype} or croak "$Script: no output format defined for '$bibtype' entries";

    # get BibTeX fields
    my %bibfields;
    foreach my $bibfield ($bibentry->fieldlist()) {
      if ($bibfield eq "author" or $bibfield eq "editor") {

        # format authors/editors
        foreach my $authorformat (qw(fvlj vljf)) {
          my @names = format_bib_authors($authorformat, $max_authors, "et al.", $bibentry->names($bibfield));
          my $joined_names = join(", ", @names);
          $joined_names =~ s/, et al/ et al/;
          $bibfields{"${bibfield}:${authorformat}"} = $joined_names;
        }

      } elsif ($bibfield eq "collaboration") {

        # format collaborations
        my @names = format_bib_authors("l", $max_authors, "et al.", $bibentry->names($bibfield));
        my $joined_names = join(", ", @names);
        $joined_names =~ s/, et al/ et al/;
        $bibfields{$bibfield} = $joined_names;

      } else {
        $bibfields{$bibfield} = remove_tex_markup($bibentry->get($bibfield));
      }
    }

    # replace fields in format
    # - ensure that field replacements do not introduce duplicate periods
    foreach my $bibfield (keys %bibfields) {
      my $bibfieldvalue = $bibfields{$bibfield};
      my $bibfieldvalue_with_period = $bibfieldvalue;
      $bibfieldvalue_with_period =~ s/\.*$/./;
      $bibstr =~ s/%${bibfield}\./${bibfieldvalue_with_period}/g;
      $bibstr =~ s/%${bibfield}/${bibfieldvalue}/g;
    }

    # remove unused fields within curly braces
    $bibstr =~ s/{[^{}]*%[^{}]*((?:{[^{%}]*})?)}/$1/g;
    $bibstr =~ s/[{}]//g;

    # add to output string
    $bibstring .= "\n$bibstr\n";

  }

} else {

  # write BibTeX entries
  open(my $fh, "+<", \$bibstring);
  write_bib_to_fh({
                   fh => $fh,
                   pdf_file => $pdf_file_comment ? "comment" : "none"
                  },
                  @bibentries);
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
