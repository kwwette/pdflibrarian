#!/usr/bin/env perl

use strict;

use File::Spec;
use IO::Scalar;
use Pod::Markdown::Github;
use Pod::Select;

sub get_markdown {

  # extract POD from application
  my $pod_content = '';
  my $pod_fh = IO::Scalar->new(\$pod_content);
  podselect({ -output => $pod_fh }, File::Spec->catfile(@_));
  close $pod_fh;

  # convert POD to Github-flavoured Markdown
  my $markdown_output = '';
  my $parser = Pod::Markdown::Github->new;
  $parser->output_string(\$markdown_output);
  $parser->parse_string_document($pod_content);

  return split /\n/, $markdown_output;

}

# open README
open OUT, ">README.md" or die "$!";

# get top-level documentation
my @topmd = get_markdown("lib", "App", "PDFLibrarian.pm");
while (@topmd) {
  my $topln = shift @topmd;

  if ($topln =~ /^# APPLICATIONS/) {
    print OUT "$topln\n\n";

    # insert application documentation
    while (@topmd && $topmd[0] !~ /^#/) {
      $topln = shift @topmd;
      if ($topln =~ /^- [*]*(pdf-lbr-[a-z0-9-]+)/) {
        my @appmd = get_markdown("bin", $1);
        while (@appmd) {
          my $appln = shift @appmd;

          # extract NAME for application header
          if ($appln =~ /^# NAME/) {
            while (@appmd && $appmd[0] =~ /^\s*$/) {
              shift @appmd;
            }
            $appln = shift @appmd;
            print OUT "## $appln\n\n";
          }

          # extract other sections
          if ($appln =~ /^# / && $appln !~ /PART OF|COPYRIGHT|LICENSE/) {
            print OUT "##$appln\n";
            while (@appmd && $appmd[0] !~ /^# /) {
              $appln = shift @appmd;
              print OUT "$appln\n";
            }
          }

        }
      }
    }

  } else {
    print OUT "$topln\n";
  }

}
close OUT;



# for my $app (@apps) {

#   # parse Markdown lines
#   my @lines = split /\n/, $markdown_output;
#   while (@lines) {
#     $_ = shift @lines;

#     # extract NAME for application header
#     if ($_ =~ /^# NAME/) {
#       $_ = shift @lines;
#       while ($_ =~ /^\s*$/) {
#         $_ = shift @lines;
#       }
#       $_ =~ s/\.$//;
#       print OUT "### $_\n";
#     }

#     # extract DESCRIPTION for application description
#     if ($_ =~ /^# DESCRIPTION/) {
#       $_ = shift @lines;
#       while ($_ !~ /^#/) {
#         print OUT "$_\n";
#         $_ = shift @lines;
#       }
#     }

#   }

# }

# close OUT;
