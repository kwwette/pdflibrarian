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
use FindBin qw($Script);
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;

@perl_use_lib@;
use pdflibrarian::bibtex qw(read_bib_from_str generate_bib_keys read_bib_from_pdf format_bib write_bib_to_fh edit_bib_in_fh write_bib_to_pdf);
use pdflibrarian::config;
use pdflibrarian::library qw(update_pdf_lib make_pdf_links cleanup_links);
use pdflibrarian::query_dialog qw(extract_query_values_from_pdf do_query_dialog);
use pdflibrarian::util qw(find_pdf_files run_async kill_async);

=pod

=head1 NAME

B<pdf-lbr-import-pdf> - Import PDF files into the PDF library.

=head1 SYNOPSIS

B<pdf-lbr-import-pdf> B<--help>|B<-h>

B<pdf-lbr-import-pdf> [B<--no-pdf-bib>] I<files>|I<directories> ...

=head1 DESCRIPTION

B<pdf-lbr-import-pdf> imports PDF I<files> and/or any PDF files in I<directories> into the PDF library. If B<--no-pdf-bib> is specified, any BibTeX metadata embedded in the PDF files will be ignored.

The user will be asked to select an online query database and supply a query value which uniquely identifies the paper(s), in order for PDF Librarian to retrieve a BibTeX record for the paper(s).

By default PDF Librarian tries to extract a Digital Object Identifier from the PDF paper(s) for use in the query.

If the query is successful, the user will have an opportunity to edit the BibTeX record(s) before the PDF I<files> are added to the library.

=head1 PART OF

PDF Librarian version @VERSION@

=cut

# handle help options
my ($version, $help, $no_pdf_bib);
GetOptions(
           "version|v" => \$version,
           "help|h" => \$help,
           "no-pdf-bib" => \$no_pdf_bib,
          ) or croak "$Script: could not parse options";
if ($version) { print "PDF Librarian version @VERSION@\n"; exit 1; }
pod2usage(-verbose => 2, -exitval => 1) if ($help);

# get list of PDF files
my @pdffiles = find_pdf_files(@ARGV);
croak "$Script: no PDF files to import" unless @pdffiles > 0;

# pass PDF files through ghostscript to fix any issues
my $npdffile = 0;
foreach my $pdffile (@pdffiles) {
  printf STDERR "$Script: passing %i/%i PDF files through ghostscript\n", $npdffile++, scalar(@pdffiles);
  flush STDERR;

  # save XMP metadata
  my $xmp = "";
  eval {
    my $pdf = PDF::API2->open($pdffile);
    $xmp = $pdf->xmpMetadata() // "";
  };

  # try to run ghostscript conversion on PDF file
  my $fh = File::Temp->new(SUFFIX => '.pdf', EXLOCK => 0) or croak "$Script: could not create temporary file";
  my $cmd = "'$ghostscript' -dSAFER -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -o '@{[$fh->filename]}' '$pdffile' >/dev/null 2>&1";
  printf STDERR "$Script: running $cmd ...\n";
  flush STDERR;
  system($cmd) == 0 or croak "$Script: could not run $cmd";

  # try to open ghostscript-converted PDF file, and restore XMP metadata
  eval {
    my $pdf = PDF::API2->open($fh->filename);
    $pdf->xmpMetadata($xmp);
    $pdf->update();
    $pdf->end();
    1;
  } or do {
    chomp(my $error = $@);
    croak "$Script: could not open PDF file '@{[$fh->filename]}': $error";
  };

  # use converted PDF file
  $fh->unlink_on_destroy(0);
  link($pdffile, "$pdffile.bak") or croak "$Script: could not link '$pdffile' to '$pdffile.bak': $!";
  rename($fh->filename, $pdffile) or croak "$Script: could not rename '@{[$fh->filename]}' to '$pdffile': $!";
  unlink("$pdffile.bak") or croak "$Script: could not unlink '$pdffile.bak': $!";

}

# add PDF files with existing BibTeX entries to library (unless --no-pdf-bib was specified)
if (!$no_pdf_bib) {

  # read BibTeX entries (if any) from PDF metadata
  my @allbibentries = read_bib_from_pdf(@pdffiles);

  # separate valid BibTeX entries, save PDF files without valid BibTeX entries
  my @bibentries;
  @pdffiles = ();
  foreach my $bibentry (@allbibentries) {
    if ($bibentry->key ne ":") {
      push @bibentries, $bibentry;
    } else {
      push @pdffiles, $bibentry->get("file");
    }
  }
  undef @allbibentries;

  if (@bibentries > 0) {

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

  }

  # return if there are no PDF files remaining
  if (@pdffiles == 0) {
    exit 0;
  }

}

# process IDs of PDF files opened in external viewer
my @pids;

# try to retrieve BibTeX records for all PDF files, and write BibTeX data to a temporary file for editing
my $fh = File::Temp->new(SUFFIX => '.bib', EXLOCK => 0) or croak "$Script: could not create temporary file";
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
    my $query_action = '';
    ($query_action, $query_db_name, $query_value) = do_query_dialog($pdffile, $query_db_name, $query_value, \@query_values, $error_message);

    # take action
    if ($query_action eq 'exit') {

      # cancel all imports and exit
      kill_async $pid, @pids;
      print STDERR "$Script: all imports have been cancelled\n";
      exit 0;

    } elsif ($query_action eq 'cancel') {

      # skip import of PDF
      kill_async $pid;
      print STDERR "$Script: import of PDF file '$pdffile' has been skipped\n";
      next PDFFILE;

    } elsif ($query_action eq 'manual') {

      # try to read existing BibTeX entry from PDF metadata, or else return a blank entry
      $bibstr = '@article{key,}';
      eval {
        my @bibentries = read_bib_from_pdf($pdffile);
        $bibstr = $bibentries[0]->print_s();
      };
      $error_message = '';

    } elsif ($query_action eq 'query') {

      # run query of database with given query value
      my $query_cmd = $query_databases{$query_db_name};
      $query_cmd =~ s/\s+/' '/g;
      $query_cmd = sprintf($query_cmd, $query_value);
      $query_cmd = "'" . File::Spec->catfile($bindir, $query_cmd) . "'";
      my $exit_status;
      ($bibstr, $error_message, $exit_status) = Capture::Tiny::capture {
        system($query_cmd);
        if ($? == -1) {
          print STDERR "\n$query_cmd failed to execute: $!\n";
        } elsif ($? & 127) {
          printf STDERR "\n$query_cmd died with signal %d, %s coredump\n", ($? & 127),  ($? & 128) ? 'with' : 'without';
        } elsif ($? != 0) {
          printf STDERR "\n$query_cmd exited with value %d\n", $? >> 8;
        }
      };
      $bibstr =~ s/^\s+//;
      $bibstr =~ s/\s+$//;
      $error_message =~ s/^\s+//;
      $error_message =~ s/\s+$//;

    } else {
      croak "$Script: invalid action '$query_action'";
    }

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

    # write formatted BibTeX entry
    write_bib_to_fh({ fh => $fh }, format_bib({}, $bibentry));
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
