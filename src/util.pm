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
use PDF::API2;
use Parallel::Iterator;
use Sys::CPU;

use pdflibrarian::config;

our @EXPORT_OK = qw(unique_list is_in_dir find_pdf_files open_pdf_file progress parallel_loop remove_tex_markup remove_short_words);

1;

sub unique_list {

  # return a list containing only unique elements
  my %seen;
  grep !$seen{$_}++, @_;

}

sub is_in_dir {
  my ($dir, $path) = @_;

  # return true if '$path' is in '$dir', false otherwise
  sub spliteverything {
    my ($v, $d, $f) = File::Spec->splitpath(File::Spec->rel2abs($_[0]));
    my @d = File::Spec->splitdir(File::Spec->catdir($d));
    ($v, @d, $f)
  }
  my @dir = spliteverything($dir);
  my @path = spliteverything($path);
  return 0 if @dir > @path;
  while (@dir) {
    return 0 if shift(@dir) ne shift(@path);
  }

  return 1;
}

sub find_pdf_files {

  # return unique found PDF files
  my %pdffiles;
  my $wanted = sub {
    if (-l $_) {
      $_ = readlink($_) or croak "$0: could not resolve '$_': %!";
    }
    return unless -f && mimetype($_) eq 'application/pdf';
    $pdffiles{File::Spec->rel2abs($_)} = 1;
  };

  # find PDF files in the given list of search paths
  foreach (@_) {
    if (-d $_) {
      find({wanted => \&$wanted, no_chdir => 1}, $_);
    } elsif (-r $_) {
      &$wanted($_);
    } elsif (!File::Spec->file_name_is_absolute($_) && -d File::Spec->catdir($pdflinkdir, $_)) {
      find({wanted => \&$wanted, no_chdir => 1}, File::Spec->catdir($pdflinkdir, $_));
    } elsif (!File::Spec->file_name_is_absolute($_) && -r File::Spec->catfile($pdflinkdir, $_)) {
      &$wanted(File::Spec->catfile($pdflinkdir, $_));
    } else {
      croak "$0: '$_' is neither a file nor a directory, either by itself or within '$pdflinkdir'";
    }
  }

  return keys %pdffiles;
}

sub open_pdf_file {
  my ($pdffile) = @_;

  # try to open PDF file
  my $pdf;
  eval {
    $pdf = PDF::API2->open($pdffile);
  } or do {
    my $error = $@;

    # do we have ghostscript?
    if (!defined($ghostscript)) {
      die $error;
    }

    # try to run ghostscript conversion on PDF file
    my $fh = File::Temp->new(SUFFIX => '.pdf', EXLOCK => 0) or croak "$0: could not create temporary file";
    system($ghostscript, '-q', '-dSAFER', '-sDEVICE=pdfwrite', '-dCompatibilityLevel=1.4', '-o', $fh->filename, $pdffile) == 0 or croak "$0: could not run ghostscript on '$pdffile'";
    eval {
      $pdf = PDF::API2->open($fh->filename);
    } or do {
      croak "$0: $error";
    };

    # use converted PDF file
    $fh->unlink_on_destroy(0);
    link($pdffile, "$pdffile.bak") or croak "$0: could not link '$pdffile' to '$pdffile.bak': $!";
    rename($fh->filename, $pdffile) or croak "$0: could not rename '@{[$fh->filename]}' to '$pdffile': $!";
    unlink("$pdffile.bak") or croak "$0: could not unlink '$pdffile.bak': $!";
    $pdf = PDF::API2->open($pdffile);

  };

  return $pdf;
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
