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

our $combo;
our $text;
our $buttonok;

sub new {
  my ($class, $pdffile, $query_db_name, $query_text, $error_message) = @_;

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
PDF Librarian has queries online database '$query_db_name' with the query value '$query_text'. Unfortunately the query returned the following errors:

$error_message

Please correct the query value and/or select a different online database, and try again.

Please press the 'Run Query' button (or the Enter key) when ready to run the query, or else the 'Cancel Query' button (or the Esc key) to cancel the import of the PDF paper.

EOM
  } else {
    $message = <<"EOM";
PDF Librarian would like to query an online database for a BibTeX record for the paper

$pdffile

in order to import the file into the PDF library.

Please select the online database below, and supply a query value which uniquely identified the paper. By default PDF Librarian tries to extract a Digital Object Identifier from the PDF paper for use in the query.

Please press the 'Run Query' button (or the Enter key) when ready to run the query, or else the 'Cancel Query' button (or the Esc key) to cancel the import of the PDF paper.

EOM
  }
  $topsizer->Add(Wx::StaticText->new($panel, -1, $message, [-1, -1], [500, 300]), 1, wxEXPAND | wxALL, 10);

  # add combo box for query database
  my @query_db_names = sort { $a cmp $b } keys(%query_databases);
  $combo = Wx::ComboBox->new($panel, -1, $query_db_name, [-1, -1], [500, 30], \@query_db_names, wxCB_READONLY | wxTE_PROCESS_ENTER);
  $topsizer->Add($combo, 0, wxEXPAND | wxALL, 10);

  # add text box for DOI
  $text = Wx::TextCtrl->new($panel, -1, $query_text, [-1, -1], [500, 30], wxTE_PROCESS_ENTER);
  $topsizer->Add($text, 0, wxEXPAND | wxALL, 10);

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
  EVT_TEXT($self, $combo, \&on_text);
  EVT_TEXT($self, $text, \&on_text);
  EVT_TEXT_ENTER($self, $combo, \&on_enter);
  EVT_TEXT_ENTER($self, $text, \&on_enter);
  on_text();

  return $self;
}

sub get_data {

  # get query database name
  my $combo_value = $combo->GetValue();
  $combo_value =~ s/^\s+//;
  $combo_value =~ s/\s+$//;

  # get query text
  my $text_value = $text->GetValue();
  $text_value =~ s/^\s+//;
  $text_value =~ s/\s+$//;

  return ($combo_value, $text_value);
}

sub on_text {
  my ($self, $event) = @_;

  # query database and query text
  my ($query_db_name, $query_text) = get_data();

  # enable/disable "Run Query" button
  $buttonok->Enable(length($query_db_name) > 0 && length($query_text) > 0);

}

sub on_enter {
  my ($self, $event) = @_;

  $self->EndModal(wxID_OK);

}

#----------------------------------------------------------------------#

package pdflibrarian::query_dialog;
use Exporter 'import';

use Wx qw(:id);

our @EXPORT_OK = qw(do_query_dialog);

sub do_query_dialog {
  my ($pdffile, $query_db_name, $query_text, $error_message) = @_;
  my ($ui_query_db_name, $ui_query_text);

  # show dialog
  my $dialog = pdflibrarian::query_dialog::dialog->new($pdffile, $query_db_name, $query_text, $error_message);
  if ($dialog->ShowModal() == wxID_OK) {

    # query database and query text
    ($ui_query_db_name, $ui_query_text) = $dialog->get_data();

  }

  return ($ui_query_db_name, $ui_query_text);
}
