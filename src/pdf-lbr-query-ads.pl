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

use Carp;
use FindBin qw($Script);
use Getopt::Long qw(:config no_ignore_case);
use HTTP::Request;
use JSON;
use LWP::UserAgent;
use Pod::Usage;
use Text::Unidecode;
use URI;

@perl_use_lib@;
use pdflibrarian::config;
use pdflibrarian::title_abbr qw(get_aas_macros);

=pod

=head1 NAME

B<pdf-lbr-query-ads> - Query the NASA Astrophysics Data System for BibTeX bibliographic record.

=head1 SYNOPSIS

B<pdf-lbr-query-ads> B<--help>|B<-h>

B<pdf-lbr-query-ads> B<--query>|B<-q> I<query>

B<pdf-lbr-query-ads> B<--set-api-token>|B<-s> I<token>

=head1 DESCRIPTION

B<pdf-lbr-query-ads> sends the I<query> to the Astrophysics Data System, and if successful extracts the BibTeX bibliographic record from the response.

The BibTeX record is then printed to standard output.

In order to query the Astrophysics Data System, you must supply a personal ADS API token; see below.

=head1 OPTIONS

=over 4

=item B<--query>|B<-q> I<query>

Send the I<query> to the Astrophysics Data System.

=item B<--set-api-token>|B<-s> I<token>

In order to query the Astrophysics Data System, you must set up an ADS account; see L<https://ui.adsabs.harvard.edu/#user/account/login>.

From the account page you can find your personal ADS API token.

Finally you must run B<pdf-lbr-query-ads> with this option to store the API token in the configuration file.

=back

=head1 PART OF

PDF Librarian version @VERSION@

=cut

# handle help options
my ($version, $help, $query, $api_token);
GetOptions(
           "version|v" => \$version,
           "help|h" => \$help,
           "query|q=s" => \$query,
           "set-api-token|s=s" => \$api_token,
          ) or croak "$Script: could not parse options";
if ($version) { print "PDF Librarian version @VERSION@\n"; exit 1; }
pod2usage(-verbose => 2, -exitval => 1) if ($help);

# get location of configuration file
my $cfgfile = File::Spec->catfile($cfgdir, 'ads.ini');

# read configuration file
my $cfg = new Config::Simple(syntax => 'ini');
if (-f $cfgfile) {
  $cfg->read($cfgfile);
}

# set ADS API token
if ($api_token) {
  $cfg->param('api_token', $api_token);
  $cfg->save($cfgfile);
}

# return if no query
exit 0 unless defined($query);

# get ADS API token
$api_token = $cfg->param('api_token');
croak "$Script: missing personal ADS API token" unless defined($api_token);

# user agent for web queries
my $useragent = LWP::UserAgent->new;
$useragent->agent("$PACKAGE/$VERSION");

# escape any colons and parentheses in query value
$query =~ s{^([^:]*):(.*)$}{ my $k = $1; my $v = $2; $v =~ s|:|\\:|g; "$k:$v" }e;
$query =~ s/([()])/\\$1/g;

# send query to ADS
my $querycontent;
{
  my $adsuri = URI->new('https://api.adsabs.harvard.edu/v1/search/query');
  $adsuri->query_form(rows => 1, fl => 'bibcode', 'q' => $query);
  my $request = HTTP::Request->new('GET', $adsuri);
  $request->header('Authorization' => "Bearer $api_token");
  my $result = $useragent->request($request);
  if (!$result->is_success) {
    my $status = $result->status_line;
    croak "$Script: ADS query failed: $status";
  }
  $querycontent = $result->content;
}

# parse ADS query response from JSON
my $queryjson;
eval {
  $queryjson = decode_json($querycontent);
  1;
} or do {
  croak "$Script: could not parse ADS query response from JSON: $@";
};
croak "$Script: could not understand ADS query response" unless defined($queryjson->{response}) && defined($queryjson->{response}->{numFound});
croak "$Script: ADS query failed, no records returned" unless $queryjson->{response}->{numFound} && defined($queryjson->{response}->{docs});
croak "$Script: could not understand ADS query response" unless @{$queryjson->{response}->{docs}} > 0 && defined($queryjson->{response}->{docs}->[0]->{bibcode});

# construct ADS export request into JSON
my $exportcontent;
eval {
  $exportcontent = encode_json({ bibcode => [$queryjson->{response}->{docs}->[0]->{bibcode}]});
  1;
} or do {
  croak "$Script: could not construct ADS export request: $@";
};

# export BibTeX record from ADS
{
  my $adsuri = URI->new('https://api.adsabs.harvard.edu/v1/export/bibtex');
  my $request = HTTP::Request->new('POST', $adsuri);
  $request->header('Authorization' => "Bearer $api_token");
  $request->header('Content-Type' => 'application/json');
  $request->content($exportcontent);
  my $result = $useragent->request($request);
  if (!$result->is_success) {
    my $status = $result->status_line;
    croak "$Script: ADS export failed: $status";
  }
  $exportcontent = $result->content;
}

# parse ADS export response from JSON
my $exportjson;
eval {
  $exportjson = decode_json($exportcontent);
  1;
} or do {
  croak "$Script: could not parse ADS export response from JSON: $@";
};
croak "$Script: could not understand ADS export response" unless defined($exportjson->{export});

# extract BibTeX record
my $bibstr = $exportjson->{export};
croak "$Script: BibTeX missing from ADS export response" unless length($bibstr) > 0;
$bibstr = unidecode($bibstr);
$bibstr =~ s/^\s+//;
$bibstr =~ s/\s+$//;

# replace journal abbreviations in exported ADS BibTeX
my %aas_macros = get_aas_macros();
while (my ($key, $value) = each %aas_macros) {
  $bibstr =~ s/{\\$key}/{$value}/;
}

# print BibTeX record
print "$bibstr\n";

exit 0;
