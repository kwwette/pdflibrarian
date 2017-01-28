# Copyright (C) 2016--2017 Karl Wette
#
# This file is part of fmdtools.
#
# fmdtools is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# fmdtools is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fmdtools. If not, see <http://www.gnu.org/licenses/>.

package fmdtools::pdf::org;

use strict;
use warnings;

use Carp;
use File::Spec;
use Text::Unidecode;

use fmdtools;
use fmdtools::pdf;

1;

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

sub format_bib_authors {
  my ($nameformat, $maxauthors, $etal, @authors) = @_;

  # format authors
  my $authorformat = new Text::BibTeX::NameFormat($nameformat);
  foreach my $author (@authors) {
    $author = $authorformat->apply($author);
    $author = remove_tex_markup($author);
    if ($author =~ /\sCollaboration$/i) {
      $author =~ s/\s.*$//;
    }
  }

  if (@authors > 0) {

    # limit number of authors to '$maxathors'
    @authors = ($authors[0], $etal) if defined($maxauthors) && @authors > $maxauthors;

    # replace 'others' with preferred form of 'et al.'
    $authors[-1] = $etal if $authors[-1] eq "others";

  }

  return @authors;
}

sub generate_bib_keys {
  my (@bibentries) = @_;

  # get regular expression which matches object identifiers in titles
  my $objid_re;
  {
    my $objid_re_str = $fmdtools::pdf::config{object_id_regex} // "";
    $objid_re = qr/$objid_re_str/ if length($objid_re_str) > 0;
  }

  # generate keys for BibTeX entries
  my $keys = 0;
  foreach my $bibentry (@bibentries) {
    my $key = "";

    # add formatted authors, editors, or collaborations
    {
      my @authors = format_bib_authors("l", 2, "EtAl", $bibentry->names("collaboration"));
      @authors = format_bib_authors("l", 2, "EtAl", $bibentry->names("author")) unless @authors > 0;
      @authors = format_bib_authors("l", 2, "EtAl", $bibentry->names("editor")) unless @authors > 0;
      $key .= join('', map { $_ =~ s/\s//g; substr($_, 0, 4) } @authors);
    }

    # add year
    my $year = $bibentry->get("year") // "";
    $key .= $year;

    # add abbreviated title
    {
      my $title = remove_tex_markup($bibentry->get("title"));
      $title =~ s/[^\w\d\s]//g;
      my $suffix = "";

      # extract any object identifiers, add the longest identifier found to suffix
      if (defined($objid_re)) {
        my $longest_objid = "";
        while ($title =~ /\b$objid_re/g) {
          $longest_objid = $& if length($longest_objid) < length($&);
        }
        $suffix .= ':' . $longest_objid if length($longest_objid) > 0;
        $title =~ s/\b$objid_re//g;
      }

      # abbreviate title words
      my @words = fmdtools::remove_short_words(split(/\s+/, $title));
      my @wordlens = (3, 3, 2, 2, 2);
      foreach my $word (sort { length($b) <=> length($a) } @words) {

        # add any Roman numeral to suffix, and stop processing title
        if (grep { $word eq $_ } qw(II III IV V VI VII VIII IX)) {
          $suffix .= ":$word";
          last;
        }

        # always include numbers in full
        next if $word =~ /^\d+$/;

        # abbreviate word to the next available length, after removing vowels
        my $wordlen = shift(@wordlens) // 1;
        my $shrt = ucfirst($word);
        $shrt =~ s/[aeiou]//g;
        $shrt = substr($shrt, 0, $wordlen);

        map { s/^$word$/$shrt/ } @words;
      }

      unless (length($suffix) > 0) {

        # add volume number (if any) to suffix for books and proceedings
        $suffix .= ':v' . $bibentry->get("volume") if (grep { $bibentry->type eq $_ } qw(book inbook proceedings)) && $bibentry->exists("volume");

      }

      # add abbreviated title and suffix to key
      $key .= ':' . join('', @words);
      $key .= $suffix if length($suffix) > 0;

    }

    # sanitise key
    $key = unidecode($key);
    $key =~ s/[^\w\d:]//g;

    # set key to generated key, unless start of key matches generated key
    # - this is so user can further customise key by appending characters
    unless ($bibentry->key =~ /^$key($|:)/) {
      $bibentry->set_key($key);
      ++$keys;
    }

  }
  fmdtools::progress("generated keys for %i BibTeX entries\n", $keys) if $keys > 0;

}

sub organise_library_PDFs {
  my (@bibentries) = @_;
  return unless @bibentries > 0;

  # get PDF library location
  my $pdflibdir = $fmdtools::pdf::config{libdir};
  croak "$0: could not determine PDF library location" unless defined($pdflibdir);

  # find PDF files to organise
  my (@files_dirs, %file2inode, %inode2files);
  fmdtools::find_files($pdflibdir, \%file2inode, \%inode2files, 'pdf', map { $_->get('file') } @bibentries);

  # get list of unique PDF files
  my @pdffiles = map { @{$_}[0] } values(%inode2files);
  croak "$0: no PDF files to organise" unless @pdffiles > 0;

  # add existing PDF files in library to file/inode hashes
  fmdtools::find_files($pdflibdir, \%file2inode, \%inode2files, 'pdf', $pdflibdir);

  # organise PDFs in library
  foreach my $bibentry (@bibentries) {
    my $pdffile = $bibentry->get('file');

    # format authors, editors, and collaborations
    my @authors = format_bib_authors("vl", 2, "et al", $bibentry->names("author"));
    my @editors = format_bib_authors("vl", 2, "et al", $bibentry->names("editor"));
    my @collaborations = format_bib_authors("vl", 2, "et al", $bibentry->names("collaboration"));

    # format and abbreviate title
    my $title = remove_tex_markup($bibentry->get("title") // "NO-TITLE");
    $title = join(' ', map { ucfirst($_) } fmdtools::remove_short_words(split(/\s+/, $title)));

    # make new name for PDF; should be unique within library
    my $newpdffile = "@collaborations";
    $newpdffile = "@authors" unless length($newpdffile) > 0;
    $newpdffile = "@editors" unless length($newpdffile) > 0;
    $newpdffile .= " $title";
    {

      # append report number (if any) for technical reports
      $newpdffile .= " no" . $bibentry->get("number") if $bibentry->type eq "techreport" && $bibentry->exists("number");

      # append volume number (if any) for books and proceedings
      $newpdffile .= " vol" . $bibentry->get("volume") if (grep { $bibentry->type eq $_ } qw(book inbook proceedings)) && $bibentry->exists("volume");

    }

    # list of shelves to organise this file under
    my @shelves;

    # organise by first author and collaboration
    push @shelves, ["Authors", $authors[0], ""];
    if (@collaborations > 0) {
      push @shelves, ["Authors", $collaborations[0], ""];
    }

    # organise by first word of title
    my $firstword = ucfirst($title);
    $firstword =~ s/\s.*$//;
    push @shelves, ["Titles", $firstword, ""];

    # organise by year
    my $year = $bibentry->get("year") // "NO-YEAR";
    push @shelves, ["Years", $year, ""];

    # organise by keyword(s)
    my %keywords;
    foreach (split ';', $bibentry->get("keyword")) {
      next if /^\s*$/;
      $keywords{$_} = 1;
    }
    if (keys %keywords == 0) {
      $keywords{"NO-KEYWORDS"} = 1;
    }
    foreach my $keyword (keys %keywords) {
      my @subkeywords = split ',', $keyword;
      s/\b(\w)/\U$1\E/g for @subkeywords;
      push @shelves, ["Keywords", @subkeywords, ""];
    }

    if ($bibentry->type eq "article") {

      # organise articles by journal
      my $journal = $bibentry->get("journal") // "NO-JOURNAL";
      if ($journal =~ /arxiv/i) {
        my $eprint = $bibentry->get("eprint") // "NO-EPRINT";
        push @shelves, ["Articles", "arXiv", "$eprint"];
      } else {
        my $volume = $bibentry->get("volume") // "NO-VOLUME";
        my $pages = $bibentry->get("pages") // "NO-PAGES";
        push @shelves, ["Articles", $journal, "v$volume", "p$pages"];
      }

    } elsif ($bibentry->type eq "techreport") {

      # organise technical reports by institution
      my $institution = $bibentry->get("institution") // "NO-INSTITUTION";
      push @shelves, ["Tech Reports", $institution, ""];

    } elsif (grep { $bibentry->type eq $_ } qw(book inbook proceedings)) {

      # organise books and (whole) proceedings
      push @shelves, ["Books", ""];

    } elsif (grep { $bibentry->type eq $_ } qw(conference incollection inproceedings)) {

      # organise articles in collections and proceedings
      my $booktitle = remove_tex_markup($bibentry->get("booktitle") // "NO-BOOKTITLE");
      $booktitle = join(' ', map { ucfirst($_) } fmdtools::remove_short_words(split(/\s+/, $booktitle)));
      push @shelves, ["In", $booktitle, ""];

    } elsif (grep { $bibentry->type eq $_ } qw(mastersthesis phdthesis)) {

      # organise theses
      push @shelves, ["Theses", ""];

    } else {

      # organise everything else
      push @shelves, ["Misc", ""];

    }

    # make shelves into library filenames
    my @newpdffiles = fmdtools::make_library_filenames($pdflibdir, $newpdffile, 'pdf', @shelves);

    # create library links
    fmdtools::make_library_links($pdflibdir, \%file2inode, \%inode2files, $pdffile, @newpdffiles);

  }
  fmdtools::progress("organised %i PDFs in $pdflibdir\n", scalar(@bibentries));

  # finalise library organisation
  fmdtools::finalise_library($pdflibdir);

}

sub remove_library_PDFs {
  my ($removedir, @files_dirs) = @_;

  # get PDF library location
  my $pdflibdir = $fmdtools::pdf::config{libdir};
  croak "$0: could not determine PDF library location" unless defined($pdflibdir);

  # find PDF files to organise
  my (%file2inode, %inode2files);
  fmdtools::find_files($pdflibdir, \%file2inode, \%inode2files, 'pdf', @files_dirs);

  # get list of unique PDF files
  my @pdffiles = map { @{$_}[0] } values(%inode2files);
  croak "$0: no PDF files to organise" unless @pdffiles > 0;

  # add existing PDF files in library to file/inode hashes
  fmdtools::find_files($pdflibdir, \%file2inode, \%inode2files, 'pdf', $pdflibdir);

  # remove PDFs from library
  foreach my $pdffile (@pdffiles) {
    fmdtools::remove_library_links($pdflibdir, \%file2inode, \%inode2files, $pdffile, $removedir);
  }
  fmdtools::progress("removed %i PDFs to $removedir\n", scalar(@pdffiles));

  # finalise library organisation
  fmdtools::finalise_library($pdflibdir);

}
