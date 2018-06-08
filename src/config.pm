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

package pdflibrarian::config;
use Exporter 'import';

use Carp;
use Config::Simple;
use File::HomeDir;
use File::Path;
use File::Spec;

our @EXPORT;

push @EXPORT, '$PACKAGE';
our $PACKAGE = "@PACKAGE@";
push @EXPORT, '$VERSION';
our $VERSION = "@VERSION@";

my $prefix = "@prefix@";
my $exec_prefix = "@exec_prefix@";
my $datarootdir = "@datarootdir@";

push @EXPORT, '$bindir';
our $bindir = "@bindir@";
push @EXPORT, '$pkgdatadir';
our $pkgdatadir = "@datadir@/@PACKAGE@";

push @EXPORT, '$fallback_editor';
our $fallback_editor = "@fallback_editor@";
push @EXPORT, '$ghostscript';
our $ghostscript = "@ghostscript@";

push @EXPORT, '$cfgdir';
our $cfgdir;
push @EXPORT, '$pdffiledir';
our $pdffiledir;
push @EXPORT, '$pdflinkdir';
our $pdflinkdir;

1;

INIT {

  # get location of configuration file
  $cfgdir = File::HomeDir->my_dist_config('pdflibrarian', { create => 1 });
  my $cfgfile = File::Spec->catfile($cfgdir, 'pdflibrarian.ini');

  # read configuration file
  my $cfg = new Config::Simple(syntax => 'ini');
  if (-f $cfgfile) {
    $cfg->read($cfgfile);
  }

  # ensure default configuration values are set
  my %config = (
                'general.pdflinkdir'    => File::Spec->catdir(File::HomeDir->my_home, 'PDFLibrary'),
                );
  while (my ($key, $value) = each %config) {
    $cfg->param($key, $value) unless defined($cfg->param($key)) && length($cfg->param($key)) > 0;
  }

  # ensure configuration file exists
  $cfg->save($cfgfile);

  # import configuration
  %config = $cfg->vars();

  # set PDF links directory
  $pdflinkdir = $config{'general.pdflinkdir'};

  # create directories for PDF files
  $pdffiledir = File::HomeDir->my_dist_data('pdflibrarian', { create => 1 });
  for (my $i = 0; $i < 16; ++$i) {
    my $dir = File::Spec->catdir($pdffiledir, sprintf("%x", $i));
    File::Path::make_path($dir);
  }

  # create directory for PDF links
  File::Path::make_path($pdflinkdir);

}
