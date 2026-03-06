#!@PERL@

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

use v@PERLVERSION@;
use strict;
use warnings;

use Carp;
use Clipboard;
use FindBin qw($Script);
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;

@perl_use_lib@;
use pdflibrarian::config;
use pdflibrarian::title_abbr qw(get_aas_macros abbr_iso4_title);

=pod

=head1 NAME

B<pdf-lbr-iso4-abbr> - Output ISO4 abbreviations.

=head1 SYNOPSIS

B<pdf-lbr-iso4-abbr> B<--help>|B<-h>

B<pdf-lbr-iso4-abbr> [ B<--separator>|B<-s> ] I<words> ...

=head1 DESCRIPTION

B<pdf-lbr-iso4-abbr> outputs the ISO4 abbreviation of I<words> using the ISSN List of Title Word Abbreviations. The abbreviation is also copied to the clipboard.

=head1 OPTIONS

=over 4

=item B<--separator>|B<-s>

Separate the abbreviated words with the given character. Default is space.

=back

=head1 PART OF

PDF Librarian version @VERSION@

=cut

# handle help options
my ($version, $help, $separator);
$separator = " ";
GetOptions(
           "version|v" => \$version,
           "help|h" => \$help,
           "separator|s=s" => \$separator,
          ) or croak "$Script: could not parse options";
if ($version) { print "PDF Librarian version @VERSION@\n"; exit 1; }
pod2usage(-verbose => 2, -exitval => 1) if ($help);

# get title from command line
my $title = join(" ", @ARGV);
$title =~ s/^\s+//;
$title =~ s/\s+$//;
croak "$Script: no title supplied" if $title eq "";

# abbreviate title
$title = abbr_iso4_title($separator, $title, 0);

# output title
print "$title\n";
Clipboard->copy_to_all_selections($title);

exit 0;
