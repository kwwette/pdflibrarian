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

our @EXPORT_OK = qw(%aas_macros);

my %aas_macros;

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
