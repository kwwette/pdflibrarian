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

#----------------------------------------------------------------------#

package pdflibrarian::query_dialog::dialog;

use Wx qw(:dialog :statictext :combobox :textctrl :sizer :panel :window :id);
use Wx::Event qw(EVT_TEXT EVT_TEXT_ENTER);

use base qw(Wx::Dialog);

use pdflibrarian::config;

our $query_db_name_combo;
our $query_value_combo;
our $buttonok;

sub new {
  my ($class, $pdffile, $query_db_name, $query_value, $query_values, $error_message) = @_;

  # create dialog
  my $self = $class->SUPER::new(undef, -1, "Import $pdffile - PDF Librarian", &Wx::wxDefaultPosition, &Wx::wxDefaultSize, wxDIALOG_NO_PARENT | wxDEFAULT_DIALOG_STYLE);

  # create panel and sizer
  my $topsizer = Wx::BoxSizer->new(wxVERTICAL);
  my $panel = Wx::Panel->new($self, -1, [-1, -1], [-1, -1], wxTAB_TRAVERSAL | wxBORDER_NONE);
  $panel->SetSizer($topsizer);

  # add static text box for message
  my $message;
  if ($error_message ne '') {
    $message = <<"EOM";
PDF Librarian has queries online database '$query_db_name' with the query value '$query_value'. Unfortunately the query returned the following errors:

$error_message

Please correct the query value and/or select a different online database, and try again.

Please press the 'Run Query' button (or the Enter key) when ready to run the query, or else the 'Cancel Query' button (or the Esc key) to cancel the import of the PDF paper.

EOM
  } else {
    $message = <<"EOM";
PDF Librarian would like to query an online database for a BibTeX record for the paper

$pdffile

in order to import the file into the PDF library.

Please select the online database below, and supply a query value which uniquely identified the paper. By default PDF Librarian tries to extract a Digital Object Identifier from the PDF paper for use in the query, but this may well be incorrect and therefore should be double-checked.

Please press the 'Run Query' button (or the Enter key) when ready to run the query, or else the 'Cancel Query' button (or the Esc key) to cancel the import of the PDF paper.

EOM
  }
  $topsizer->Add(Wx::StaticText->new($panel, -1, $message, [-1, -1], [500, 300]), 1, wxEXPAND | wxALL, 10);

  # add read-only combo box for query database
  my @query_db_names = sort { $a cmp $b } keys(%query_databases);
  $query_db_name_combo = Wx::ComboBox->new($panel, -1, $query_db_name, [-1, -1], [500, 30], \@query_db_names, wxCB_READONLY | wxTE_PROCESS_ENTER);
  $topsizer->Add($query_db_name_combo, 0, wxEXPAND | wxALL, 10);

  # add editable combo box for DOI
  $query_value_combo = Wx::ComboBox->new($panel, -1, $query_value, [-1, -1], [500, 30], \@{$query_values}, wxTE_PROCESS_ENTER);
  $topsizer->Add($query_value_combo, 0, wxEXPAND | wxALL, 10);

  # create buttons and sizer
  my $buttonsizer = Wx::BoxSizer->new(wxHORIZONTAL);
  $buttonok = Wx::Button->new($panel, wxID_OK, 'Run Query');
  $buttonsizer->Add($buttonok, 0, wxALL, 10);
  my $buttoncancel = Wx::Button->new($panel, wxID_CANCEL, 'Cancel Query');
  $buttonsizer->Add($buttoncancel, 0, wxALL, 10);

  # add buttons to sizer
  $topsizer->Add($buttonsizer, 0, wxALIGN_CENTER);

  # perform final layout
  my $mainsizer = Wx::BoxSizer->new(wxVERTICAL);
  $mainsizer->Add($panel, 1, wxEXPAND | wxALL, 0);
  $self->SetSizerAndFit($mainsizer);

  # register events
  EVT_TEXT($self, $query_db_name_combo, \&on_text);
  EVT_TEXT($self, $query_value_combo, \&on_text);
  EVT_TEXT_ENTER($self, $query_db_name_combo, \&on_enter);
  EVT_TEXT_ENTER($self, $query_value_combo, \&on_enter);
  on_text();

  return $self;
}

sub get_data {

  # get query database name
  my $query_db_name_combo_value = $query_db_name_combo->GetValue();
  $query_db_name_combo_value =~ s/^\s+//;
  $query_db_name_combo_value =~ s/\s+$//;

  # get query value
  my $query_value_combo_value = $query_value_combo->GetValue();
  $query_value_combo_value =~ s/^\s+//;
  $query_value_combo_value =~ s/\s+$//;

  return ($query_db_name_combo_value, $query_value_combo_value);
}

sub on_text {
  my ($self, $event) = @_;

  # query database and query value
  my ($query_db_name, $query_value) = get_data();

  # enable/disable "Run Query" button
  $buttonok->Enable(length($query_db_name) > 0 && length($query_value) > 0);

}

sub on_enter {
  my ($self, $event) = @_;

  $self->EndModal(wxID_OK);

}

#----------------------------------------------------------------------#

package pdflibrarian::query_dialog;
use Exporter 'import';

use CAM::PDF;
use Wx qw(:id);

use pdflibrarian::util qw(unique_list open_pdf_file);

our @EXPORT_OK = qw(extract_query_values_from_pdf do_query_dialog);

sub extract_query_values_from_pdf {
  my ($pdffile) = @_;

  # try to extract possible query values
  my @query_values;

  {
    # open PDF file (with PDF::AP2)
    my $pdf = open_pdf_file($pdffile);

    # try to extract a DOI from PDF info structure
    my @pdfinfotags = $pdf->infoMetaAttributes();
    push @pdfinfotags, qw(DOI doi);
    $pdf->infoMetaAttributes(@pdfinfotags);
    my %pdfinfo = $pdf->info();
    while (my ($key, $value) = each %pdfinfo) {
      if ($key =~ /^doi$/i) {
        push @query_values, $value;
      }
    }

    # try to extract a DOI from PDF info structure
    my $xmp = $pdf->xmpMetadata() // "";
    $xmp =~ s/\s+//g;
    while ($xmp =~ m|doi>([^<]+)<|ig) {
      push @query_values, $1;
    }
  }

  if (@query_values == 0 ) {

    # open PDF file with CAM::PDF
    my $pdf = CAM::PDF->new($pdffile);

    # try to extract a DOI from PDF text
    for (my $i = 1; $i <= $pdf->numPages(); ++$i) {
      my $text = $pdf->getPageText($i);
      if (defined($text)) {
        $text =~ s/\s+/ /g;
        while ($text =~ m|doi: *([^ ]+)|ig) {
          push @query_values, $1;
        }
      }
    }

  }

  return unique_list(@query_values);
}

sub do_query_dialog {
  my ($pdffile, $query_db_name, $query_value, $query_values, $error_message) = @_;
  my ($ui_query_db_name, $ui_query_value);

  # show dialog
  my $dialog = pdflibrarian::query_dialog::dialog->new($pdffile, $query_db_name, $query_value, $query_values, $error_message);
  if ($dialog->ShowModal() == wxID_OK) {

    # query database and query value
    ($ui_query_db_name, $ui_query_value) = $dialog->get_data();

  }

  return ($ui_query_db_name, $ui_query_value);
}
