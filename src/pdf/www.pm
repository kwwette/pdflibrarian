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

package fmdtools::pdf::www;

use strict;
use warnings;

use Carp;
use HTTP::Request;
use JSON;
use LWP::UserAgent;
use URI;

use fmdtools;
use fmdtools::pdf;

# user agent for web queries
my $useragent = LWP::UserAgent->new;
$useragent->agent("$fmdtools::PACKAGE/$fmdtools::VERSION");

# journal abbreviations in exported ADS BibTeX
use constant AAS_MACROS =>
  {
   aj         => 'Astronomical Journal',
   actaa      => 'Acta Astronomica',
   araa       => 'Annual Review of Astronomy and Astrophys',
   apj        => 'Astrophysical Journal',
   apjl       => 'Astrophysical Journal Letters',
   apjs       => 'Astrophysical Journal Supplement',
   ao         => 'Applied Optics',
   apss       => 'Astrophysics and Space Science',
   aap        => 'Astronomy and Astrophysics',
   aapr       => 'Astronomy and Astrophysics Reviews',
   aaps       => 'Astronomy and Astrophysics Supplement',
   azh        => 'Astronomicheskii Zhurnal',
   baas       => 'Bulletin of the AAS',
   bac        => 'Bulletin of the Astronomical Institutes of Czechoslovakia',
   caa        => 'Chinese Astronomy and Astrophysics',
   cjaa       => 'Chinese Journal of Astronomy and Astrophysics',
   icarus     => 'Icarus',
   jcap       => 'Journal of Cosmology and Astroparticle Physics',
   jrasc      => 'Journal of the Royal Astronomical Society of Canada',
   memras     => 'Memoirs of the Royal Astronomical Society',
   mnras      => 'Monthly Notices of the Royal Astronomical Society',
   na         => 'New Astronomy',
   nar        => 'New Astronomy Review',
   pra        => 'Physical Review A',
   prb        => 'Physical Review B',
   prc        => 'Physical Review C',
   prd        => 'Physical Review D',
   pre        => 'Physical Review E',
   prl        => 'Physical Review Letters',
   pasa       => 'Publications of the Astronomical Society of Australia',
   pasp       => 'Publications of the Astronomical Society of the Pacific',
   pasj       => 'Publications of the Astronomical Society of Japan',
   rmxaa      => 'Revista Mexicana de Astronomia y Astrofisica',
   qjras      => 'Quarterly Journal of the Royal Astronomical Society',
   skytel     => 'Sky and Telescope',
   solphys    => 'Solar Physics',
   sovast     => 'Soviet Astronomy',
   ssr        => 'Space Science Reviews',
   zap        => 'Zeitschrift fuer Astrophysik',
   nat        => 'Nature',
   iaucirc    => 'IAU Cirulars',
   aplett     => 'Astrophysics Letters',
   apspr      => 'Astrophysics Space Physics Research',
   bain       => 'Bulletin Astronomical Institute of the Netherlands',
   fcp        => 'Fundamental Cosmic Physics',
   gca        => 'Geochimica Cosmochimica Acta',
   grl        => 'Geophysics Research Letters',
   jcp        => 'Journal of Chemical Physics',
   jgr        => 'Journal of Geophysics Research',
   jqsrt      => 'Journal of Quantitiative Spectroscopy and Radiative Transfer',
   memsai     => 'Memorie della Societ\`a Astronomica Italiana',
   nphysa     => 'Nuclear Physics A',
   physrep    => 'Physics Reports',
   physscr    => 'Physica Scripta',
   planss     => 'Planetary Space Science',
   procspie   => 'Proceedings of the SPIE',
  };

1;

sub query_ads {
  my ($query) = @_;

  # check for ADS API token
  my $apitoken = $fmdtools::pdf::config{ads_api_token};
  croak "$0: could not determine ADS API token" unless defined($apitoken);

  # perform common replacements to aid user cut-and-pasting
  $query =~ s|^http://dx.doi.org/|doi:|;

  # send query to ADS
  my $querycontent;
  {
    fmdtools::progress("sending query to ADS ...\n");
    my $adsuri = URI->new('https://api.adsabs.harvard.edu/v1/search/query');
    $adsuri->query_form(rows => 1, fl => 'bibcode', 'q' => $query);
    my $request = HTTP::Request->new('GET', $adsuri);
    $request->header('Authorization' => "Bearer $apitoken");
    my $result = $useragent->request($request);
    if (!$result->is_success) {
      my $status = $result->status_line;
      croak "$0: ADS query failed: $status";
    }
    $querycontent = $result->content;
  }

  # parse ADS query response from JSON
  my $queryjson;
  eval {
    $queryjson = decode_json($querycontent);
    1;
  } or do {
    croak "$0: could not parse ADS query response from JSON: $@";
  };
  croak "$0: could not understand ADS query response" unless defined($queryjson->{response}) && defined($queryjson->{response}->{numFound});
  croak "$0: ADS query failed, no records returned" unless $queryjson->{response}->{numFound} && defined($queryjson->{response}->{docs});
  croak "$0: could not understand ADS query response" unless @{$queryjson->{response}->{docs}} > 0 && defined($queryjson->{response}->{docs}->[0]->{bibcode});

  # construct ADS export request into JSON
  my $exportcontent;
  eval {
    $exportcontent = encode_json({ bibcode => [$queryjson->{response}->{docs}->[0]->{bibcode}]});
    1;
  } or do {
    croak "$0: could not construct ADS export request: $@";
  };

  # export BibTeX from ADS
  {
    fmdtools::progress("exporting BibTeX data from ADS ...\n");
    my $adsuri = URI->new('https://api.adsabs.harvard.edu/v1/export/bibtex');
    my $request = HTTP::Request->new('POST', $adsuri);
    $request->header('Authorization' => "Bearer $apitoken");
    $request->header('Content-Type' => 'application/json');
    $request->content($exportcontent);
    my $result = $useragent->request($request);
    if (!$result->is_success) {
      my $status = $result->status_line;
      croak "$0: ADS export failed: $status";
    }
    $exportcontent = $result->content;
  }

  # parse ADS export response from JSON
  my $exportjson;
  eval {
    $exportjson = decode_json($exportcontent);
    1;
  } or do {
    croak "$0: could not parse ADS export response from JSON: $@";
  };
  croak "$0: could not understand ADS export response" unless defined($exportjson->{export});

  # extract BibTeX data
  my $bibstr = $exportjson->{export};
  croak "$0: BibTeX missing from ADS export response" unless length($bibstr) > 0;

  # replace journal abbreviations in exported ADS BibTeX
  while (my ($key, $value) = each %{AAS_MACROS()}) {
    $bibstr =~ s/{\\$key}/{$value}/;
  }

  return $bibstr;
}
