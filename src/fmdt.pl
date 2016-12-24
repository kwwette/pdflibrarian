#!@PERL@

# Copyright (C) 2016 Karl Wette
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

use v@PERLVERSION@;
use strict;
use warnings;
no warnings 'experimental::smartmatch';
use feature qw/switch/;

use Carp;
use Getopt::Long qw(:config pass_through);

@perl_use_lib@;
use fmdtools::pdf;

# handle help options
my $help = 0;
GetOptions(
    "help|h" => \$help,
    ) or croak "$0: could not parse options";
if ($help) {
    my $prefix = "@prefix@";
    my $datarootdir = "@datarootdir@";
    system("@MAN@ @mandir@/man1/fmdt.1") == 0 or croak "$0: @MAN@ failed";
    exit 1;
}

# handle toolsets and actions
my $toolset = shift @ARGV // croak "$0: no toolset given";
my $action = shift @ARGV // croak "$0: no action given";
given ($toolset) {

    # unknown toolset
    default {
        croak "$0: unknown toolset '$toolset'";
    }

}
