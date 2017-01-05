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
no warnings 'experimental::smartmatch';
use feature qw/switch/;

use Carp;
use File::Spec;
use File::Find;
use File::stat;
use Sys::CPU;
use Parallel::Iterator qw(iterate_as_array);
use File::chmod qw(chmod);
use File::Basename qw(dirname basename);
use Text::Unidecode;

$File::chmod::UMASK = 0;

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

sub is_in_dir {
    my ($indir, $dir) = @_;

    # return true if directory '$dir' is in directory '$indir', false otherwise
    my @indir = File::Spec->splitdir($indir);
    my @dir = File::Spec->splitdir($dir);
    return 0 if @indir > @dir;
    while (@indir) {
        return 0 if shift(@indir) ne shift(@dir);
    }

    return 1;
}

sub get_library_dir {
    my ($type) = @_;

    # determine library directory
    my $libdir;
    given ($type) {
        when ('PDF') {
            my $homedir = $ENV{'HOME'} // croak "$0: could not determine home directory";
            $libdir = File::Spec->catdir($homedir, 'PDFLibrary');
        }
        default {
            croak "$0: unknown library type '$type'";
        }
    }
    $libdir = File::Spec->rel2abs($libdir);

    # make library directory
    if (! -d $libdir) {
        mkdir($libdir) or croak "$0: could not make directory '$libdir': $!";
    }

    return $libdir;
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

sub abbreviate_words {
    my ($words) = @_;

    # remove most non-alphanumeric characters
    $words =~ s/[^\w\d\s.-]//g;

    # remove words from abreviation
    my @abbrev;
    foreach my $word (split /\s+/, $words) {
        next if grep { $word =~ /^$_$/i } qw(
            a
            an   as   at   by   if   in   of   on   or   so   to   up
            and  but  for  nor  now  off  per  the  via
            amid down from into like near once onto over past than than
            that upon when with
        );
        push @abbrev, $word;
    }
    $words = join(' ', @abbrev);

    return $words;
}

sub make_library_filenames {
    my ($libdir, $newfile, @shelves) = @_;
    die unless @shelves > 0;

    # make shelves into library filenames to be linked
    my @newfiles;
    foreach (@shelves) {
        my @path = @{$_};
        $path[-1] .= " $newfile";
        foreach (@path) {
            $_ = unidecode($_);
            s/[\s~@&_=+,]/-/g;
            s/[^\w\d.-]//g;
            s/--+/-/;
            s/^-+//;
            s/-+$//;
        }
        push @newfiles, File::Spec->catfile($libdir, @path);
    }

    return @newfiles;
}

sub make_library_links {
    my ($libdir, $file2inode, $inode2files, $file, @newfiles) = @_;
    die unless @newfiles > 0;

    # get inode of '$file'
    my $inode = $$file2inode{$file};
    croak "$0: unknown file '$file'" if !defined($inode);

    # make filenames to be linked
    my %files;
    foreach (@newfiles) {
        $files{$_} = 'link';
    }

    # mark filenames to be unlinked, or do not create links if they already exist
    foreach (@{$$inode2files{$inode}}) {
        if (defined($files{$_})) {
            delete($files{$_});
        } else {
            $files{$_} = 'unlink';
        }
    }

    # filenames to link and unlink
    my @linkfiles = grep { $files{$_} eq 'link' } keys(%files);
    my @unlinkfiles = grep { $files{$_} eq 'unlink' } keys(%files);

    # check that either '$linkfile' does not exist or its inode matches '$file'
    foreach my $linkfile (@linkfiles) {
        if (defined($$file2inode{$linkfile})) {
            croak "$0: inode of '$linkfile' differs from '$file'" unless $$file2inode{$linkfile} == $inode;
        } else {
            croak "$0: file '$linkfile' should not exist" if -e $linkfile;
        }
    }

    # create parent directories of links
    foreach my $linkfile (@linkfiles) {
        my $linkdir = dirname($linkfile);
        if (! -d $linkdir) {
            my @path = File::Spec->splitdir(File::Spec->abs2rel($linkdir, $libdir));
            my @mkpath = ($libdir);
            foreach (@path) {
                my $parentdir = File::Spec->catdir(@mkpath);
                chmod("+w", $parentdir) or croak "$0: could not set permissions on directory '$parentdir': $!";
                push @mkpath, $_;
                my $dir = File::Spec->catdir(@mkpath);
                if (! -d $dir) {
                    mkdir($dir) or croak "$0: could not make directory '$dir': $!";
                }
                chmod("a-w", $parentdir) or croak "$0: could not set permissions on directory '$linkdir': $!";
            }
        }
    }

    # create links
    foreach my $linkfile (@linkfiles) {
        my $linkdir = dirname($linkfile);
        my $islinkdirinlib = is_in_dir($libdir, $linkdir);
        if ($islinkdirinlib) {
            chmod("+w", $linkdir) or croak "$0: could not set permissions on directory '$linkdir': $!";
        }
        link($file, $linkfile) or croak "$0: could not link '$file' to '$linkfile': $!";
        if ($islinkdirinlib) {
            chmod("u=rw,g=r,o=", $linkfile) or croak "$0: could not set permissions on file '$linkfile': $!";
            chmod("a-w", $linkdir) or croak "$0: could not set permissions on directory '$linkdir': $!";
        }
        $$file2inode{$linkfile} = $inode;
    }

    # remove links
    foreach my $unlinkfile (@unlinkfiles) {
        my $linkdir = dirname($unlinkfile);
        my $islinkdirinlib = is_in_dir($libdir, $linkdir);
        if ($islinkdirinlib) {
            chmod("+w", $linkdir) or croak "$0: could not set permissions on directory '$linkdir': $!";
        }
        {
            my $st = stat $unlinkfile or croak "$0: could not stat '$unlinkfile': $!";
            croak "$0: refusing to delete '$unlinkfile'" unless $st->nlink > 1;
            unlink($unlinkfile) or croak "$0: could not unlink '$unlinkfile': $!";
        }
        if ($islinkdirinlib) {
            chmod("a-w", $linkdir) or croak "$0: could not set permissions on directory '$linkdir': $!";
        }
        delete($$file2inode{$unlinkfile});
    }

    # update hashes
    @{$$inode2files{$inode}} = @linkfiles;

}

sub remove_library_links {
    my ($libdir, $file2inode, $inode2files, $file, $removedir) = @_;

    # remove library link, but keep one link to '$file' in '$removedir'
    croak "$0: file '$file' is not in library" unless is_in_dir($libdir, $file);
    my $newfile = File::Spec->catfile($removedir, basename($file));
    make_library_links($libdir, $file2inode, $inode2files, $file, $newfile);

}

sub finalise_library {
    my ($libdir) = @_;

    # remove any empty directories
    {
        my %dirs;
        my $wanted = sub {
            return unless -d $_;
            chmod("+w", $File::Find::dir) or croak "$0: could not set permissions on directory '$File::Find::dir': $!";
            rmdir $_;
            chmod("a-w", $File::Find::dir) or croak "$0: could not set permissions on directory '$File::Find::dir': $!";
        };
        find({wanted => \&$wanted, bydepth => 1, no_chdir => 1}, $libdir);
    }

    # set permissions
    {
        my $wanted = sub {
            if (-d $_) {
                chmod("u=rx,g=rx,o=", $_) or croak "$0: could not set permissions on directory '$_': $!";
            } else {
                chmod("u=rw,g=r,o=", $_) or croak "$0: could not set permissions on file '$_': $!";
            }
        };
        find({wanted => \&$wanted, bydepth => 1, no_chdir => 1}, $libdir);
    }

}
