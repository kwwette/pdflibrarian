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

package fmdtools;

use strict;
use warnings;

use Carp;
use File::Spec;
use File::Find;
use File::stat;
use Sys::CPU;
use Parallel::Iterator qw(iterate_as_array);

my $prefix = "@prefix@";
my $datarootdir = "@datarootdir@";
my $pkgdatadir = "@datadir@/@PACKAGE@";
my $fallback_editor = "@fallback_editor@";

1;

sub progress {

    # print progress
    my $fmt = shift(@_);
    my $msg = sprintf($fmt, @_);
    print STDERR "$0: $msg";
    flush STDERR;

}

sub get_data_file {
    my (@path) = @_;

    # get location of data file
    return File::Spec->catfile($pkgdatadir, @path);

}

sub edit_file {
    my ($filename) = @_;

    # edit file
    my $editor = $ENV{'VISUAL'} // $ENV{'EDITOR'} // $fallback_editor;
    system($editor, $filename) == 0 or croak "$0: could not edit file '$filename' with editing program '$editor'";

}

sub find_files {
    my ($file2inode, $inode2files, $extn, @files_dirs) = @_;

    # return hashes to/from files and their inodes
    my $wanted = sub {
        return unless -f && /\Q.${extn}\E$/i;
        my $file = File::Spec->rel2abs($_);
        my $st = stat $file or croak "$0: could not stat '$file': $!";
        if (defined($$file2inode{$file})) {
            croak "$0: file '$file' has inconsistent inodes" unless $$file2inode{$file} == $st->ino;
        } else {
            $$file2inode{$file} = $st->ino;
        }
        if (! grep { $_ eq $file } @{$$inode2files{$st->ino}}) {
            push @{$$inode2files{$st->ino}}, $file;
        }
    };

    # find files with a given extension in the given list of files/directories
    foreach (@files_dirs) {
        if (-d $_) {
            find({wanted => \&$wanted, no_chdir => 1}, $_);
        } elsif (-f $_) {
            &$wanted($_);
        } else {
            croak "$0: '$_' is neither a file nor a directory";
        }
    }

}

sub find_unique_files {
    my ($extn, @files_dirs) = @_;

    # return list of unique files
    my (%file2inode, %inode2files);
    find_files(\%file2inode, \%inode2files, $extn, @files_dirs);
    my @uniqfiles = map { @{$_}[0] } values(%inode2files);

    return @uniqfiles;
}

sub parallel_loop {
    my ($progfmt, $inarray, $body) = @_;
    die unless ref($inarray) eq 'ARRAY';
    die unless ref($body) eq 'CODE';

    # return if '@$inarray' is empty
    return () unless @$inarray > 0;

    # run code '$body' over all elements of '@$inarray', return the results
    # in '@outarray', and print occasional progress messages using '$progfmt'
    my $ncpus = Sys::CPU::cpu_count();
    my $total = scalar(@$inarray);
    my $worker = sub {
        my ($id, $in) = @_;
        progress($progfmt . "\r", $id, $total) if $id % (3 * $ncpus) == 0;
        my $out = &$body($in);
        return $out;
    };
    my @outarray = iterate_as_array(
        { workers => $ncpus, batch => 1 },
        \&$worker, $inarray
        );
    progress($progfmt . "\n", $total, $total);

    return @outarray;
}
