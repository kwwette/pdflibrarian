# Copyright (C) 2022 Karl Wette
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

use strict;
use warnings;

package pdflibrarian::title_abbr;
use Exporter 'import';

use Carp;
use Carp::Assert;
use File::Spec;
use FindBin qw($Script);
use Text::CSV::Encoded;

use pdflibrarian::config;

our @EXPORT_OK = qw(%aas_macros abbr_iso4_title);

my %aas_macros;

my @iso4_word_abbr;
my $iso4_title_abbr_cachefile;
my %iso4_title_abbr_cache;
my $iso4_title_abbr_cache_new = 0;

1;

INIT {

  # get location of AAS macro/journal title data
  my $aasdata = File::Spec->catfile($pkgdatadir, 'title_abbr_aas.csv');
  croak "$Script: missing AAS data '$aasdata'" unless -f $aasdata;

  # load AAS macro/journal title data
  my $csv = Text::CSV::Encoded->new({ encoding_in => 'utf-8', encoding_out => 'utf-8', sep_char => ';' });
  open(my $fh, '<:encoding(utf-8)', $aasdata) or croak "$Script: could not open file '$aasdata': $!";

  # check columns
  my $row = $csv->getline($fh);
  assert(@{$row} == 2);
  assert($row->[0] eq 'MACRO');
  assert($row->[1] eq 'JOURNAL TITLE');

  # parse data
  while ($row = $csv->getline($fh)) {
    $aas_macros{$row->[0]} = $row->[1];
  }

  close($fh);

}

INIT {

  # get location of ISO4 word abbreviation data
  my $iso4data = File::Spec->catfile($pkgdatadir, 'title_abbr_iso4.csv');
  croak "$Script: missing ISO4 data '$iso4data'" unless -f $iso4data;

  # load ISO4 word abbreviation data
  my $csv = Text::CSV::Encoded->new({ encoding_in => 'utf-8', encoding_out => 'utf-8', sep_char => ';' });
  open(my $fh, '<:encoding(utf-8)', $iso4data) or croak "$Script: could not open file '$iso4data': $!";

  # check columns
  my $row = $csv->getline($fh);
  assert(@{$row} == 3);
  assert($row->[0] eq 'WORDS');
  assert($row->[1] eq 'ABBREVIATIONS');
  assert($row->[2] eq 'LANGUAGES');

  # parse data
  while ($row = $csv->getline($fh)) {
    push @iso4_word_abbr, [$row->[0], $row->[1]];
  }

  close($fh);

  # sort from longest to shortest
  @iso4_word_abbr = sort { length($b->[0]) <=> length($a->[0]) } @iso4_word_abbr;

}

INIT {

  # load ISO4 title abbreviation cache
  $iso4_title_abbr_cachefile = File::Spec->catfile($cfgdir, "iso4_title_abbr_cache.txt");
  if (-f $iso4_title_abbr_cachefile) {
    open(my $fh, '<:encoding(utf-8)', $iso4_title_abbr_cachefile) or croak "$Script: could not open file '$iso4_title_abbr_cachefile': $!";
    while (<$fh>) {
      chomp;
      s/^\s+//;
      s/\s+$//;
      my ($title, $abbr_title) = split(/\s*=\s*/);
      $iso4_title_abbr_cache{$title} = $abbr_title;
    }
    close($fh);
  }

}

END {

  # load ISO4 title abbreviation cache
  open(my $fh, '>:encoding(utf-8)', $iso4_title_abbr_cachefile) or croak "$Script: could not open file '$iso4_title_abbr_cachefile': $!";
  foreach my $title (sort(keys(%iso4_title_abbr_cache))) {
    print $fh "$title = $iso4_title_abbr_cache{$title}\n";
  }
  close($fh);
  if ($iso4_title_abbr_cache_new > 0) {
    printf STDERR "$Script: cached $iso4_title_abbr_cache_new new ISO4 title abbreviations in '$iso4_title_abbr_cachefile'\n";
  }

}

sub abbr_iso4_title {
  my ($separator, $title) = @_;

  # return cached abbreviated titles
  return $iso4_title_abbr_cache{$title} if defined($iso4_title_abbr_cache{$title});

  my $abbr_title;

  # split title
  my @words = split(/\s+/, $title);
  if (@words == 1) {
    $abbr_title = $title;
  } else {

  # abbreviate words
    my @abbr_words;
    while (@words) {
      my $word = shift @words;

      # delete lowercase words
      next if $word =~ /^\p{Ll}/;

      # skip non-alphabetic words
      next if $word =~ /^\W+$/;

      # keep single uppercase letters as last word
      if ($word =~ /^\p{Lu}$/ && @words == 0) {
        push @abbr_words, $word;
        next;
      }

      # loop over abbreviations (sorted from longest to shortest)
      foreach my $entry (@iso4_word_abbr) {
        my ($patt, $abbr) = @{$entry};

        # skip patterns without an abbreviation
        next if $abbr eq 'n.a.';

        # apply suffix patterns
        if ($patt =~ /^-(.*)$/) {
          my $regex = '^.*' . $1 . '$';
          last if $word =~ s/$regex/$abbr/;
        }

        # apply prefix patterns
        if ($patt =~ /^(.)(.*)-$/) {
          my $p1 = $1;
          my $pr = $2;
          my $regex = '^' . $p1 . $pr . '.*$';
          last if $word =~ s/$regex/$abbr/;
          if ($word =~ /^\p{Lu}/) {
            my $regex_uc = '^' . uc($p1) . $pr . '.*$';
            my $abbr_uc = $abbr;
            $abbr_uc =~ s{^(.)}{ uc($1) }e;
            last if $word =~ s/$regex_uc/$abbr_uc/;
          }
        }

        # apply whole word patterns
        if ($patt =~ /^([^-])(.*[^-])$/) {
          my $p1 = $1;
          my $pr = $2;
          my $regex = '^' . $p1 . $pr . '$';
          last if $word =~ s/$regex/$abbr/;
          if ($word =~ /^\p{Lu}/) {
            my $regex_uc = '^' . uc($p1) . $pr . '$';
            my $abbr_uc = $abbr;
            $abbr_uc =~ s{^(.)}{ uc($1) }e;
            last if $word =~ s/$regex_uc/$abbr_uc/;
          }
        }

      }

      push @abbr_words, $word;

    }

    # rejoin words
    $abbr_title = join($separator, @abbr_words);

  }

  # add to cache
  $iso4_title_abbr_cache{$title} = $abbr_title;
  ++$iso4_title_abbr_cache_new;
  printf STDERR "$Script: ISO4 title abbreviation for '$title': '$abbr_title'\n";

  return $abbr_title;

}
