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
  my $newbibentries = 0;
  foreach my $bibentry (@bibentries) {

    # get name of PDF file
    my $pdffile = $bibentry->get('file');

    # record which PDF files are new to the library
    ++$newbibentries unless is_in_dir($pdffiledir, $pdffile);

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
  printf STDERR "$Script: added %i PDF files to '$pdffiledir'\n", $newbibentries if $newbibentries > 0;

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
    my @collaborations = format_bib_authors("vl", 3, "", $bibentry->names("collaboration"));

    # format and abbreviate title
    my $title = remove_tex_markup($bibentry->get("title") // "NO-TITLE");
    $title = join(' ', map { ucfirst($_) } remove_short_words(split(/\s+/, $title)));

    # make PDF link name; should be unique within library
    my $pdflinkfile;
    {

      # start with first non-empty of authoring collaborations, individual authors, and/or editors
      $pdflinkfile = "@collaborations";
      $pdflinkfile = "@authors" unless length($pdflinkfile) > 0;
      $pdflinkfile = "@editors ed" unless length($pdflinkfile) > 0;

      # append title
      $pdflinkfile .= " $title";

      # append volume number (if any) for books and proceedings
      $pdflinkfile .= " vol" . $bibentry->get("volume") if (grep { $bibentry->type eq $_ } qw(book inbook proceedings)) && $bibentry->exists("volume");

      # append year
      $pdflinkfile .= " " . $bibentry->get("year");

    }

    # list of symbolic links to make
    my @links;

    # make links by DOI
    if ($bibentry->exists('doi')) {
      my @doidirs = grep(/./, File::Spec->splitdir($bibentry->get('doi')));
      push @links, ["DOIs", @doidirs];
    }

    # make links by listed collaborations, authors, and editors
    for my $author (@collaborations, @authors) {
      next if $author eq "" || $author eq "et al";
      push @links, ["Authors", $author, "$pdflinkfile"];
    }
    for my $editor (@editors) {
      next if $editor eq "" || $editor eq "et al";
      push @links, ["Authors", "$editor ed", "$pdflinkfile"];
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

    # make links by pre-print server
    if ($bibentry->exists('archiveprefix')) {
      my $archiveprefix = $bibentry->get('archiveprefix');
      my $eprint = "NO-EPRINT";
      my $eprintprefix = $eprint;
      if ($bibentry->exists('eprint')) {
        $eprint = $bibentry->get('eprint');
        $eprintprefix = $eprint;
        $eprintprefix =~ s/[^\d]//g;
        $eprintprefix = substr($eprintprefix, 0, 2);
      }
      push @links, ["Pre Prints", "$archiveprefix", "$eprintprefix", "$eprint $pdflinkfile"];
    }

    if (grep { $bibentry->type eq $_ } qw(article)) {

      # make links to articles by journal and/or pre-print server
      my $journal = remove_tex_markup($bibentry->get("journal")) // "NO-JOURNAL";
      my $archiveprefix = $bibentry->get('archiveprefix') // "";
      if ($journal ne $archiveprefix) {
        my $volume = $bibentry->get("volume") // "NO-VOLUME";
        my $pages = $bibentry->get("pages") // "NO-PAGES";
        push @links, ["Journals", "$journal", "v$volume", "p$pages $pdflinkfile"];
      }

    } elsif (grep { $bibentry->type eq $_ } qw(techreport)) {

      # make links to technical reports by institution
      my $institution = remove_tex_markup($bibentry->get("institution")) // "NO-INSTITUTION";
      my $number = "NO-NUMBER";
      my $numberprefix = $number;
      if ($bibentry->exists('number')) {
        $number = $bibentry->get('number');
        $numberprefix = $number;
        $numberprefix =~ s/[^\d]//g;
        $numberprefix = substr($numberprefix, 0, 2);
      }
      push @links, ["Tech Reports", "$institution", "$numberprefix", "$number $pdflinkfile"];

    } elsif (grep { $bibentry->type eq $_ } qw(book inbook proceedings)) {

      # make links to books and (whole) proceedings
      push @links, ["Books", "$pdflinkfile"];

    } elsif (grep { $bibentry->type eq $_ } qw(conference incollection inproceedings)) {

      # make links to articles in collections and proceedings
      my $booktitle = remove_tex_markup($bibentry->get("booktitle")) // "NO-BOOKTITLE";
      my $pages = $bibentry->get("pages") // "NO-PAGES";
      $booktitle = join(' ', map { ucfirst($_) } remove_short_words(split(/\s+/, $booktitle)));
      push @links, ["In", $booktitle, "p$pages $pdflinkfile"];
      if ($bibentry->exists("series")) {
        my $series = remove_tex_markup($bibentry->get("series"));
        my $volume = $bibentry->get("volume") // "NO-VOLUME";
        push @links, ["In", "$series", "v$volume", "p$pages $pdflinkfile"];
      }

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
        s/[`'"]//g;
        s/[^-+.A-Za-z0-9]/_/g;
        s/[-_][-_]+/_/g;
        s/^_+//;
        s/_+$//;
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
