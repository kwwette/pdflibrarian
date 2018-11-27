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

package pdflibrarian::library;
use Exporter 'import';

use Carp;
use File::Copy;
use File::Find;
use File::Path;
use File::Spec;
use File::stat;
use FindBin qw($Script);
use Text::Unidecode;

use pdflibrarian::bibtex qw(bib_checksum format_bib_authors);
use pdflibrarian::config;
use pdflibrarian::util qw(is_in_dir remove_tex_markup remove_short_words);

our @EXPORT_OK = qw(update_pdf_lib make_pdf_links cleanup_links);

1;

sub update_pdf_lib {
  my (@bibentries) = @_;
  return unless @bibentries > 0;

  # add PDF files in BibTeX entries to PDF library
  my @newbibentries;
  foreach my $bibentry (@bibentries) {

    # get name of PDF file
    my $pdffile = $bibentry->get('file');

    # record which PDF files are new to the library
    push @newbibentries, $bibentry unless is_in_dir($pdffiledir, $pdffile);

    # compute checksum of BibTeX entry (except from PDF filename)
    my $checksum = bib_checksum($bibentry, 'file');

    # create name of PDF file in library:
    # - organise PDF files under '$pdffiledir' directory, then directory which is first character of checksum
    # - name PDF files after checksum with '.pdf' extension
    my $pdflibfile = File::Spec->catfile($pdffiledir, substr($checksum, 0, 1), "$checksum.pdf");

    # move PDF file into library, including if library PDF filename has changed
    if ($pdffile ne $pdflibfile) {
      move($pdffile, $pdflibfile) or croak "$Script: could not move '$pdffile' to '$pdflibfile': $!";
      $pdffile = $pdflibfile;
    }

    # record new PDF filename
    $bibentry->set('file', $pdflibfile);

  }
  printf STDERR "$Script: added %i PDF files to '$pdffiledir'\n", scalar(@newbibentries) if @newbibentries > 0;

  return @newbibentries;
}

sub make_pdf_links {
  my (@bibentries) = @_;
  return unless @bibentries > 0;

  # make symbolic links in PDF links directory to real PDF files
  foreach my $bibentry (@bibentries) {

    # get name of PDF file
    my $pdffile = $bibentry->get('file');

    # format authors, editors, and collaborations
    my @authors = format_bib_authors("vl", 2, "et al", $bibentry->names("author"));
    my @editors = format_bib_authors("vl", 2, "et al", $bibentry->names("editor"));
    my @collaborations = format_bib_authors("vl", 2, "et al", $bibentry->names("collaboration"));

    # format and abbreviate title
    my $title = remove_tex_markup($bibentry->get("title") // "NO-TITLE");
    $title = join(' ', map { ucfirst($_) } remove_short_words(split(/\s+/, $title)));

    # make PDF link name; should be unique within library
    my $pdflinkfile = "@collaborations";
    $pdflinkfile = "@authors" unless length($pdflinkfile) > 0;
    $pdflinkfile = "@editors" unless length($pdflinkfile) > 0;
    $pdflinkfile .= " $title";
    {

      # append report number (if any) for technical reports
      $pdflinkfile .= " no" . $bibentry->get("number") if $bibentry->type eq "techreport" && $bibentry->exists("number");

      # append volume number (if any) for books and proceedings
      $pdflinkfile .= " vol" . $bibentry->get("volume") if (grep { $bibentry->type eq $_ } qw(book inbook proceedings)) && $bibentry->exists("volume");

    }

    # list of symbolic links to make
    my @links;

    # make links by DOI
    if ($bibentry->exists('doi')) {
      my @doidirs = grep(/./, File::Spec->splitdir($bibentry->get('doi')));
      push @links, ["DOIs", @doidirs];
    }

    # make links by first author and collaboration
    if (@authors > 0) {
      push @links, ["Authors", $authors[0], "$pdflinkfile"];
    }
    if (@editors > 0) {
      push @links, ["Authors", $editors[0], "$pdflinkfile"];
    }
    if (@collaborations > 0) {
      push @links, ["Authors", $collaborations[0], "$pdflinkfile"];
    }

    # make links by first word of title
    my $firstword = ucfirst($title);
    $firstword =~ s/\s.*$//;
    push @links, ["Titles", $firstword, "$pdflinkfile"];

    # make links by year
    my $year = $bibentry->get("year") // "NO-YEAR";
    push @links, ["Years", $year, "$pdflinkfile"];

    # make links by keyword(s)
    my %keywords;
    foreach (split /[,;]/, $bibentry->get("keyword")) {
      next if /^\s*$/;
      $keywords{$_} = 1;
    }
    if (keys %keywords == 0) {
      $keywords{"NO-KEYWORDS"} = 1;
    }
    foreach my $keyword (keys %keywords) {
      my @subkeywords = split /:|(?: - )/, $keyword;
      s/\b(\w)/\U$1\E/g for @subkeywords;
      push @links, ["Keywords", @subkeywords, "$pdflinkfile"];
    }

    if ($bibentry->type eq "article") {

      # make links to articles by journal
      my $journal = $bibentry->get("journal") // "NO-JOURNAL";
      if ($journal !~ /arxiv/i) {
        my $volume = $bibentry->get("volume") // "NO-VOLUME";
        my $pages = $bibentry->get("pages") // "NO-PAGES";
        push @links, ["Journals", $journal, "v$volume", "p$pages $pdflinkfile"];
      }

      # make links to articles by pre-print server
      if ($bibentry->exists('archiveprefix')) {
        my $archiveprefix = $bibentry->get('archiveprefix');
        my $eprint = $bibentry->get("eprint") // "NO-EPRINT";
        push @links, ["Pre Prints", "$archiveprefix", $year, "$eprint $pdflinkfile"];
      }

    } elsif ($bibentry->type eq "techreport") {

      # make links to technical reports by institution
      my $institution = $bibentry->get("institution") // "NO-INSTITUTION";
      push @links, ["Tech Reports", $institution, "$pdflinkfile"];

    } elsif (grep { $bibentry->type eq $_ } qw(book inbook proceedings)) {

      # make links to books and (whole) proceedings
      push @links, ["Books", "$pdflinkfile"];

    } elsif (grep { $bibentry->type eq $_ } qw(conference incollection inproceedings)) {

      # make links to articles in collections and proceedings
      my $booktitle = remove_tex_markup($bibentry->get("booktitle") // "NO-BOOKTITLE");
      $booktitle = join(' ', map { ucfirst($_) } remove_short_words(split(/\s+/, $booktitle)));
      push @links, ["In", $booktitle, "$pdflinkfile"];

    } elsif (grep { $bibentry->type eq $_ } qw(mastersthesis phdthesis)) {

      # make links to theses
      push @links, ["Theses", "$pdflinkfile"];

    } else {

      # make links to everything else
      push @links, ["Misc", "$pdflinkfile"];

    }

    # make symbolic links
    foreach (@links) {

      # normalise elements of symbolic link path
      my @linkpath = @{$_};
      foreach (@linkpath) {
        die unless defined($_) && $_ ne "";
        $_ = unidecode($_);
        s/[^\w\d]/-/g;
        s/--+/-/g;
        s/^-+//;
        s/-+$//;
      }

      # make symbolic link path directories
      my $linkfilebase = pop @linkpath;
      my $linkdir = File::Spec->catdir($pdflinkdir, @linkpath);
      File::Path::make_path($linkdir);

      # make symbolic link file
      my $linkfile = File::Spec->catfile($linkdir, "$linkfilebase.pdf");
      if (-l $linkfile) {
        unlink($linkfile) or croak "$Script: could not unlink '$linkfile': $!";
      }
      symlink($pdffile, $linkfile) or croak "$Script: could not link '$linkfile' to '$pdffile': $!"

    }

  }
  printf STDERR "$Script: made links to %i PDF files in '$pdflinkdir'\n", scalar(@bibentries);

}

sub cleanup_links {
  my ($all) = @_;
  $all = defined($all) && $all eq 'all';

  # remove broken links and empty directories
  my $wanted = sub {
    if (-d $_) {
      rmdir $_;
    }
    if (-l $_) {
      my $unlink = $all;
      stat($_) or $unlink = 1;
      if ($unlink) {
        unlink($_) or croak "$Script: could not unlink '$_': $!";
      }
    }
  };
  find({wanted => \&$wanted, bydepth => 1, no_chdir => 1}, $pdflinkdir);
  printf STDERR "$Script: cleaned up PDF file links in '$pdflinkdir'\n" unless $all;

}
