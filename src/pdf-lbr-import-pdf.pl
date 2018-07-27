#!@PERL@

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

use v@PERLVERSION@;
use strict;
use warnings;

use Capture::Tiny;
use Carp;
use Getopt::Long;
use Pod::Usage;

@perl_use_lib@;
use pdflibrarian::config;
use pdflibrarian::util qw(find_pdf_files run_async kill_async);
use pdflibrarian::query_dialog qw(extract_query_values_from_pdf do_query_dialog);
use pdflibrarian::bibtex qw(read_bib_from_str generate_bib_keys write_bib_to_fh edit_bib_in_fh write_bib_to_pdf);
use pdflibrarian::library qw(update_pdf_lib make_pdf_links cleanup_links);

=pod

=head1 NAME

B<pdf-lbr-import-pdf> - Import PDF files into the PDF library.

=head1 SYNOPSIS

B<pdf-lbr-import-pdf> B<--help>|B<-h>

B<pdf-lbr-import-pdf> I<files>|I<directories> ...

=head1 DESCRIPTION

B<pdf-lbr-import-pdf> imports PDF I<files> and/or any PDF files in I<directories> into the PDF library.

The user will be asked to select an online query database and supply a query value which uniquely identifies the paper(s), in order for PDF Librarian to retrieve a BibTeX record for the paper(s).

By default PDF Librarian tries to extract a Digital Object Identifier from the PDF paper(s) for use in the query.

If the query is successful, the user will have an opportunity to edit the BibTeX record(s) before the PDF I<files> are added to the library.

=head1 PART OF

PDF Librarian, version @VERSION@.

=cut

# handle help options
my ($help);
GetOptions(
           "help|h" => \$help,
          ) or croak "$0: could not parse options";
pod2usage(-verbose => 2, -exitval => 1) if ($help);

# get list of PDF files
my @pdffiles = find_pdf_files(@ARGV);
croak "$0: no PDF files to import" unless @pdffiles > 0;

# process IDs of PDF files opened in external viewer
my @pids;

# try to retrieve BibTeX records for all PDF files, and write BibTeX data to a temporary file for editing
my $fh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$0: could not create temporary file";
binmode($fh, ":encoding(iso-8859-1)");
my $havebibstr = 0;
PDFFILE: foreach my $pdffile (@pdffiles) {

  # open PDF file in external viewer
  my $pid = run_async $external_pdf_viewer, $pdffile;

  # extract a DOI from PDF file, use for default query text
  my @query_values = extract_query_values_from_pdf($pdffile);
  my $query_value = (@query_values > 0) ? $query_values[0] : "";

  # ask user for query database and query text
  my $query_db_name = $pref_query_database;
  my $bibstr;
  my $error_message = '';
  do {

    # ask user for query database and query text
    ($query_db_name, $query_value) = do_query_dialog($pdffile, $query_db_name, $query_value, \@query_values, $error_message);
    if (!defined($query_db_name)) {
      kill_async $pid;
      print STDERR "$0: import of PDF file '$pdffile' has been cancelled\n";
      next PDFFILE;
    }

    # run query command
    my $query_cmd = File::Spec->catfile($bindir, sprintf("$query_databases{$query_db_name}", $query_value));
    my $exit_status;
    ($bibstr, $error_message, $exit_status) = Capture::Tiny::capture {
      system($query_cmd);
      if ($? == -1) {
        print STDERR "\n'$query_cmd' failed to execute: $!\n";
      } elsif ($? & 127) {
        printf STDERR "\n'$query_cmd' died with signal %d, %s coredump\n", ($? & 127),  ($? & 128) ? 'with' : 'without';
      } elsif ($? != 0) {
        printf STDERR "\n'$query_cmd' exited with value %d\n", $? >> 8;
      }
    };
    $bibstr =~ s/^\s+//;
    $bibstr =~ s/\s+$//;
    $error_message =~ s/^\s+//;
    $error_message =~ s/\s+$//;

  } while ($error_message ne '');

  # store process ID of PDF external viewer
  push @pids, $pid;

  # try to parse BibTeX data
  my $bibentry;
  eval {
    $bibentry = read_bib_from_str($bibstr);
  };
  if (defined($bibentry)) {

    # set name of PDF file
    $bibentry->set('file', $pdffile);

    # generate initial key for BibTeX entry
    generate_bib_keys(($bibentry));

    # coerse entry into BibTeX database structure
    $bibentry->silently_coerce();

    # write BibTeX entry
    write_bib_to_fh($fh, ($bibentry));
    $havebibstr = 1;

  } else {

    # try to add 'file' field to BibTeX data manually
    $bibstr =~ s/\s*}$/,\n  file = {$pdffile}\n}/;

    # write BibTeX data
    print $fh "\n$bibstr\n";
    $havebibstr = 1;

  }

}

# return if there are no BibTeX records to edit
if (!$havebibstr) {
  kill_async @pids;
  exit 0;
}

# edit BibTeX records
my @bibentries = edit_bib_in_fh($fh, ());

# regenerate keys for BibTeX entry
generate_bib_keys(@bibentries);

# write BibTeX entry to PDF metadata
write_bib_to_pdf(@bibentries);

# add PDF file to library
update_pdf_lib(@bibentries);

# add links in PDF links directory to real PDF file
make_pdf_links(@bibentries);

# cleanup PDF links directory
cleanup_links();

# close external PDF viewers
kill_async @pids;

exit 0;
