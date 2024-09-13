# Copyright (C) 2016--2023 Karl Wette
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
use Config::IniFiles;
use File::BaseDir;
use File::Path;
use File::Spec;
use FindBin qw($Script);
use Text::BibTeX;

our @EXPORT;

push @EXPORT, '$PACKAGE';
our $PACKAGE = "@PACKAGE@";
push @EXPORT, '$PACKAGE_NAME';
our $PACKAGE_NAME = "@PACKAGE_NAME@";
push @EXPORT, '$VERSION';
our $VERSION = "@VERSION@";

my $prefix = "@prefix@";
my $exec_prefix = "@exec_prefix@";
my $datarootdir = "@datarootdir@";

push @EXPORT, '$bindir';
our $bindir = "@bindir@";
push @EXPORT, '$datadir';
our $datadir = "@datadir@";
push @EXPORT, '$pkgdatadir';
our $pkgdatadir = "@pkgdatadir@";

push @EXPORT, '$fallback_editor';
our $fallback_editor = "@fallback_editor@";
push @EXPORT, '$external_pdf_viewer';
our $external_pdf_viewer = "@external_pdf_viewer@";
push @EXPORT, '$ghostscript';
our $ghostscript = "@ghostscript@";
push @EXPORT, '$pdftotext';
our $pdftotext = "@pdftotext@";

push @EXPORT, '$cfgdir';
our $cfgdir;
push @EXPORT, '$pdflibrarydir';
our $pdflibrarydir;

push @EXPORT, '$pref_query_database';
our $pref_query_database;
push @EXPORT, '%query_databases';
our %query_databases;

push @EXPORT, '%default_filter';
our %default_filter;

push @EXPORT, '%bibtex_macros';
our %bibtex_macros;

1;

INIT {

  # allow printing of UTF-8 characters
  binmode(STDOUT, "encoding(utf-8)");

  # check for user home directory
  croak "$Script: could not determine user home directory" unless defined($ENV{HOME}) && -d $ENV{HOME};

  # create configuration directory
  $cfgdir = File::BaseDir->config_home("$PACKAGE");
  File::Path::make_path($cfgdir);

  # read configuration file
  my $cfgfile = File::Spec->catfile($cfgdir, "$PACKAGE.ini");
  my $cfg = Config::IniFiles->new();
  if (-f $cfgfile) {
    $cfg->SetFileName($cfgfile);
    $cfg->ReadConfig();
  }

  # ensure default configuration values are set
  {
    my %default_config =
      (
       'general.pdflibrarydir' => File::Spec->catdir($ENV{HOME}, 'PDFLibrary'),
       'general.prefquery' => 'Astrophysics Data System using Digital Object Identifier',
       'general.default_filter' => 'keyword=d abstract=d',
       'query-ads doi.name' => 'Astrophysics Data System using Digital Object Identifier',
       'query-ads doi.cmd' => 'pdf-lbr-query-ads --query doi:%s',
       'query-ads arxiv.name' => 'Astrophysics Data System using arXiv Article Identifier',
       'query-ads arxiv.cmd' => 'pdf-lbr-query-ads --query arxiv:%s',
      );
    while (my ($section_key, $value) = each %default_config) {
      my ($section, $key) = split /[.]/, $section_key;
      if ($cfg->exists($section, $key)) {
        if (length($cfg->val($section, $key)) == 0) {
          $cfg->setval($section, $key, $value);
        }
      } else {
        $cfg->newval($section, $key, $value);
      }
    }
  }

  # ensure configuration file exists
  $cfg->RewriteConfig();

  # set PDF library directory
  $pdflibrarydir = $cfg->val('general', 'pdflibrarydir');
  File::Path::make_path($pdflibrarydir);

  # set query database
  $pref_query_database = $cfg->val('general', 'prefquery');
  foreach my $section ($cfg->GroupMembers('query-ads')) {
    my $name = $cfg->val($section, 'name');
    my $cmd = $cfg->val($section, 'cmd');
    if ($cmd =~ /^[^%]+[%]s[^%]*$/) {
      $query_databases{$name} = $cmd;
    } else {
      croak "$Script: invalid query command '$cmd' for database '$name'";
    }
  }

  # create default field filter for printed BibTeX output
  foreach my $arg (split /\s+/, $cfg->val('general', 'default_filter')) {
    my ($bibfield, $spec) = split(/\s*=\s*/, $arg, 2);
    $default_filter{$bibfield} = $spec;
  }

  # read in BibTeX macros to define by default
  foreach my $key ($cfg->Parameters('macros')) {
    my $macro = lc($key);
    $bibtex_macros{$macro} = $cfg->val('macros', $key);
  }

}
