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

package fmdtools::pdf;

use strict;
use warnings;
no warnings 'experimental::smartmatch';
use feature qw/switch/;

use Carp;
use File::Spec;
use Getopt::Long;

use fmdtools;
use fmdtools::pdf::bib;
use fmdtools::pdf::org;

# PDF library configuration
our %config = fmdtools::get_library_config('pdf');

1;

sub act {
  my ($action, @args) = @_;

  # handle action
  given ($action) {

    when ("edit") {
      croak "$0: action '$action' requires arguments" unless @args > 0;

      # get list of unique PDF files
      my @pdffiles = fmdtools::find_unique_files('pdf', @args);
      croak "$0: no PDF files to edit" unless @pdffiles > 0;

      # read BibTeX entries from PDF metadata
      my @bibentries = fmdtools::pdf::bib::read_bib_from_PDF(@pdffiles);

      # generate initial keys for BibTeX entries
      fmdtools::pdf::org::generate_bib_keys(@bibentries);

      # coerse entries into BibTeX database structure
      foreach my $bibentry (@bibentries) {
        $bibentry->silently_coerce();
      }

      # write BibTeX entries to a temporary file for editing
      my $fh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$0: could not create temporary file";
      binmode($fh, ":encoding(iso-8859-1)");
      fmdtools::pdf::bib::write_bib_to_fh($fh, @bibentries);

      # edit BibTeX entries in PDF files
      @bibentries = fmdtools::pdf::bib::edit_bib_in_fh($fh, @bibentries);

      # regenerate keys for modified BibTeX entries
      fmdtools::pdf::org::generate_bib_keys(@bibentries);

      # write BibTeX entries to PDF metadata
      @bibentries = fmdtools::pdf::bib::write_bib_to_PDF(@bibentries);

      # filter BibTeX entries of PDF files in library
      @bibentries = grep { fmdtools::is_in_dir($config{libdir}, $_->get('file')) } @bibentries;

      # reorganise any PDF files already in library
      fmdtools::pdf::org::organise_library_PDFs(@bibentries) if @bibentries > 0;

    }

    when ("export") {
      croak "$0: action '$action' requires arguments" unless @args > 0;

      # handle options
      my @exclude;
      my $parser = Getopt::Long::Parser->new;
      $parser->getoptionsfromarray(\@args,
                                   "exclude|e=s" => \@exclude,
                                  ) or croak "$0: could not parse options for action '$action'";

      # get list of unique PDF files
      my @pdffiles = fmdtools::find_unique_files('pdf', @args);
      croak "$0: no PDF files to read from" unless @pdffiles > 0;

      # read BibTeX entries from PDF metadata
      my @bibentries = fmdtools::pdf::bib::read_bib_from_PDF(@pdffiles);

      # exclude BibTeX fields
      foreach my $bibfield (('file', @exclude)) {
        foreach my $bibentry (@bibentries) {
          $bibentry->delete($bibfield);
        }
      }

      # error if duplicate BibTeX keys are found
      my @dupkeys = fmdtools::pdf::bib::find_duplicate_keys(@bibentries);
      croak "$0: exported BibTeX entries contain duplicate keys: @dupkeys" if @dupkeys > 0;

      # print BibTeX entries
      fmdtools::pdf::bib::write_bib_to_fh(\*STDOUT, @bibentries);

    }

    when ("add") {
      croak "$0: action '$action' requires arguments" unless @args > 0;

      # get list of unique PDF files
      my @pdffiles = fmdtools::find_unique_files('pdf', @args);
      croak "$0: no PDF files to read from" unless @pdffiles > 0;

      # read BibTeX entries from PDF metadata
      my @bibentries = fmdtools::pdf::bib::read_bib_from_PDF(@pdffiles);

      # add PDF files to library
      fmdtools::pdf::org::organise_library_PDFs(@bibentries);

    }

    when ("remove") {
      croak "$0: action '$action' requires arguments" unless @args > 0;

      # handle options
      my $removedir = File::Spec->tmpdir();
      my $parser = Getopt::Long::Parser->new;
      $parser->getoptionsfromarray(\@args,
                                   "remove-to|r=s" => \$removedir,
                                  ) or croak "$0: could not parse options for action '$action'";
      croak "$0: '$removedir' is not a directory" unless -d $removedir;

      # remove PDF files from library
      fmdtools::pdf::org::remove_library_PDFs($removedir, @args);

    }

    when ("reorganise") {
      croak "$0: action '$action' takes no arguments" unless @args == 0;

      # get list of unique PDF files in library
      my @pdffiles = fmdtools::find_unique_files('pdf', $config{libdir});
      croak "$0: no PDF files in library $config{libdir}" unless @pdffiles > 0;

      # read BibTeX entries from PDF metadata
      my @bibentries = fmdtools::pdf::bib::read_bib_from_PDF(@pdffiles);

      # regenerate keys for all BibTeX entries
      fmdtools::pdf::org::generate_bib_keys(@bibentries);

      # write BibTeX entries to PDF metadata
      fmdtools::pdf::bib::write_bib_to_PDF(@bibentries);

      # reorganise PDF files in library
      fmdtools::pdf::org::organise_library_PDFs(@bibentries);

    }

    # unknown action
    default {
      croak "$0: unknown action '$action'";
    }

  }

  return 0;
}
