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

use strict;
use warnings;

package pdflibrarian::util;
use Exporter 'import';

use Carp;
use File::Find;
use File::MimeInfo::Magic;
use File::Spec;
use Parallel::Iterator;
use Sys::CPU;

use pdflibrarian::config;

our @EXPORT_OK = qw(find_pdf_files progress parallel_loop remove_tex_markup remove_short_words);

1;

sub find_pdf_files {

  # return unique found PDF files
  my %pdffiles;
  my $wanted = sub { 
    return unless -f && mimetype($_) eq 'application/pdf';
    $pdffiles{File::Spec->rel2abs($_)} = 1;
  };

  # find PDF files in the given list of search paths
  foreach (@_) {
    if (-d $_) {
      find({wanted => \&$wanted, no_chdir => 1}, $_);
    } elsif (-f $_) {
      &$wanted($_);
    } elsif (!File::Spec->file_name_is_absolute($_) && -d File::Spec->catdir($pdflinkdir, $_)) {
      find({wanted => \&$wanted, no_chdir => 1}, File::Spec->catdir($pdflinkdir, $_));
    } elsif (!File::Spec->file_name_is_absolute($_) && -f File::Spec->catfile($pdflinkdir, $_)) {
      &$wanted(File::Spec->catfile($pdflinkdir, $_));
    } else {
      croak "$0: '$_' is neither a file nor a directory, either by itself or within '$pdflinkdir'";
    }
  }

  return keys %pdffiles;
}

sub progress {

  # print progress
  my $fmt = shift(@_);
  my $msg = sprintf($fmt, @_);
  print STDERR "$0: $msg";
  flush STDERR;

}

sub parallel_loop {
  my ($progfmt, $inarray, $body) = @_;
  die unless ref($inarray) eq 'ARRAY';
  die unless ref($body) eq 'CODE';

  # return if '@$inarray' is empty
  return () unless @$inarray > 0;

  # run code '$body' over all elements of '@$inarray', return the results
  # in '@outarray', and print occasional progress messages using '$progfmt'
  my $ncpus = Sys::CPU::cpu_count();
  my $total = scalar(@$inarray);
  my $worker = sub {
    my ($id, $in) = @_;
    progress($progfmt . "\r", $id, $total) if $id % (3 * $ncpus) == 0;
    my $out = &$body($in);
    return $out;
  };
  my @outarray = Parallel::Iterator::iterate_as_array( { workers => $ncpus, batch => 1 }, \&$worker, $inarray );
  progress($progfmt . "\n", $total, $total);

  return @outarray;
}

sub remove_tex_markup {
  my (@words) = @_;

  # remove TeX markup
  foreach (@words) {
    if (!defined($_)) {
      $_ = "";
    } else {
      s/~/ /g;
      s/\\\w+//g;
      s/\\.//g;
      s/[{}]//g;
      s/\$//g;
    }
  }

  return wantarray ? @words : "@words";
}

sub remove_short_words {
  my (@words) = @_;

  # remove short words
  my @short_words =
    qw(
        a
        an   as   at   by   if   in   is   of   on   or   so   to   up
        and  are  but  for  its  nor  now  off  per  the  via
        amid down from into like near once onto over past than than that upon when with
     );
  @words = grep { my $word = $_; ! scalar grep { $word =~ /^$_$/i } @short_words } @words;

  return wantarray ? @words : "@words";
}
