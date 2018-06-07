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

use Carp;
use File::Spec;
use Getopt::Long;

use fmdtools;
use fmdtools::pdf::bib;
use fmdtools::pdf::org;
use fmdtools::pdf::www;

# PDF library configuration
our %config = fmdtools::get_library_config('pdf',
                                           'libdir' => File::Spec->catdir(fmdtools::get_home_dir(), 'PDFLibrary'),
                                           'object_id_regex' => '[A-Z]+\s*[A-Z]*?\d{5,}',
                                          );
my $pdflibdir = $config{libdir};

1;

sub act {
  my ($action, @args) = @_;

  # handle action
  if ($action eq "import") {
    croak "$0: action '$action' requires arguments" unless @args > 0;

    # handle options
    my $add = 0;
    my $source = 'ADS';
    my $parser = Getopt::Long::Parser->new;
    $parser->getoptionsfromarray(\@args,
                                 "from|f=s" => \$source,
                                ) or croak "$0: could not parse options for action '$action'";
    croak "$0: action '$action' takes no more than 2 arguments" unless @args <= 2;
    my ($pdffile, $query) = @args;

    # check for existence of PDF file
    croak "$0: PDF file '$pdffile' does not exist" unless -f $pdffile;
    $pdffile = File::Spec->rel2abs($pdffile);

    # check existence of source
    my %sources = (
                   ADS => \&fmdtools::pdf::www::query_ads
                  );
    croak "$0: unknown source '$source'" unless defined($sources{$source});

    # prompt for query, if not given
    if (!defined($query)) {
      $query = fmdtools::prompt("query to send to $source");
      croak "$0: no query for PDF file '$pdffile'" unless $query ne "";
    }

    # retrieve BibTeX data
    my $bibstr = $sources{$source}($query);
    $bibstr =~ s/^\s+//;
    $bibstr =~ s/\s+$//;

    # write BibTeX data to a temporary file for editing
    my $fh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$0: could not create temporary file";
    binmode($fh, ":encoding(iso-8859-1)");
    {

      # try to parse BibTeX data
      my $bibentry;
      eval {
        $bibentry = fmdtools::pdf::bib::read_bib_from_str($bibstr);
      };
      if (defined($bibentry)) {

        # set name of PDF file
        $bibentry->set('file', $pdffile);

        # generate initial key for BibTeX entry
        fmdtools::pdf::org::generate_bib_keys(($bibentry));

        # coerse entry into BibTeX database structure
        $bibentry->silently_coerce();

        # write BibTeX entry
        fmdtools::pdf::bib::write_bib_to_fh($fh, ($bibentry));

      } else {

        # try to add 'file' field to BibTeX data manually
        $bibstr =~ s/\s*}$/,\n  file = {$pdffile}\n}/;

        # write BibTeX data
        print $fh "\n$bibstr\n";

      }
    }

    # edit BibTeX data
    my @bibentries = fmdtools::pdf::bib::edit_bib_in_fh($fh, ());

    # regenerate key for modified BibTeX entries
    fmdtools::pdf::org::generate_bib_keys(@bibentries);

    # write BibTeX entries to PDF metadata
    @bibentries = fmdtools::pdf::bib::write_bib_to_PDF(@bibentries);

    # add PDF files to library and/or reorganise any PDF files already in library
    fmdtools::pdf::org::organise_library_PDFs(@bibentries);

  } elsif ($action eq "edit") {
    croak "$0: action '$action' requires arguments" unless @args > 0;

    # get list of unique PDF files
    my @pdffiles = fmdtools::find_unique_files($pdflibdir, 'pdf', @args);
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

    # filter BibTeX entries of PDF files in library (unless --add was given)
    @bibentries = grep { fmdtools::is_in_dir($pdflibdir, $_->get('file')) } @bibentries;

    # add PDF files to library and/or reorganise any PDF files already in library
    fmdtools::pdf::org::organise_library_PDFs(@bibentries);

  } elsif ($action eq "add") {
    croak "$0: action '$action' requires arguments" unless @args > 0;

    # get list of unique PDF files
    my @pdffiles = fmdtools::find_unique_files($pdflibdir, 'pdf', @args);
    croak "$0: no PDF files to read from" unless @pdffiles > 0;

    # read BibTeX entries from PDF metadata
    my @bibentries = fmdtools::pdf::bib::read_bib_from_PDF(@pdffiles);

    # add PDF files to library
    fmdtools::pdf::org::organise_library_PDFs(@bibentries);

  } elsif ($action eq "remove") {
    croak "$0: action '$action' requires arguments" unless @args > 0;

    # handle options
    my $removedir = File::Spec->tmpdir();
    my $parser = Getopt::Long::Parser->new;
    $parser->getoptionsfromarray(\@args,
                                 "to|t=s" => \$removedir,
                                ) or croak "$0: could not parse options for action '$action'";
    croak "$0: '$removedir' is not a directory" unless -d $removedir;

    # remove PDF files from library
    fmdtools::pdf::org::remove_library_PDFs($removedir, @args);

  } elsif ($action eq "export") {
    croak "$0: action '$action' requires arguments" unless @args > 0;

    # handle options
    my ($minimal, @exclude, %set);
    my $parser = Getopt::Long::Parser->new;
    $parser->getoptionsfromarray(\@args,
                                 "minimal|m" => \$minimal,
                                 "exclude|e=s" => \@exclude,
                                 "set|s=s" => \%set,
                                ) or croak "$0: could not parse options for action '$action'";

    # get list of unique PDF files
    my @pdffiles = fmdtools::find_unique_files($pdflibdir, 'pdf', @args);
    croak "$0: no PDF files to read from" unless @pdffiles > 0;

    # read BibTeX entries from PDF metadata
    my @bibentries = fmdtools::pdf::bib::read_bib_from_PDF(@pdffiles);

    # exclude pre-defined BibTeX fields if mimial entry is requested
    unshift @exclude, qw(keyword abstract) if $minimal;

    foreach my $bibentry (@bibentries) {

      # exclude BibTeX fields
      foreach my $bibfield (('file', @exclude)) {
        $bibentry->delete($bibfield);
      }

      # set BibTeX fields
      while (my ($bibfield, $bibvalue) = each %set) {
        $bibentry->set($bibfield, $bibvalue);
      }

    }

    # error if duplicate BibTeX keys are found
    my @dupkeys = fmdtools::pdf::bib::find_duplicate_keys(@bibentries);
    croak "$0: exported BibTeX entries contain duplicate keys: @dupkeys" if @dupkeys > 0;

    # print BibTeX entries
    fmdtools::pdf::bib::write_bib_to_fh(\*STDOUT, @bibentries);

  } elsif ($action eq "reorganise") {
    croak "$0: action '$action' takes no arguments" unless @args == 0;

    # get list of unique PDF files in library
    my @pdffiles = fmdtools::find_unique_files($pdflibdir, 'pdf', $pdflibdir);
    croak "$0: no PDF files in library $pdflibdir" unless @pdffiles > 0;

    # read BibTeX entries from PDF metadata
    my @bibentries = fmdtools::pdf::bib::read_bib_from_PDF(@pdffiles);

    # regenerate keys for all BibTeX entries
    fmdtools::pdf::org::generate_bib_keys(@bibentries);

    # write BibTeX entries to PDF metadata
    fmdtools::pdf::bib::write_bib_to_PDF(@bibentries);

    # reorganise PDF files in library
    fmdtools::pdf::org::organise_library_PDFs(@bibentries);

  } else {
    croak "$0: unknown action '$action'";
  }

  return 0;
}
