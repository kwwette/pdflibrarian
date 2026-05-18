#!/usr/bin/env perl

use strict;

use File::Spec;
use IO::Scalar;
use Pod::Markdown::Github;
use Pod::Select;

# document applications in this order
my @apps = qw(
               pdf-lbr-import-pdf
               pdf-lbr-edit-bib
               pdf-lbr-output-bib
               pdf-lbr-output-key
               pdf-lbr-replace-pdf
               pdf-lbr-remove-pdf
               pdf-lbr-rebuild-links
               pdf-lbr-iso4-abbr
            );

# open README
open OUT, ">README.md" or die "$!";

# print header
print OUT <<EOF;
# App::PDFLibrarian

App::PDFLibrarian manages a library of academic papers in PDF format with embedded BibTeX metadata.

## Installation

Requires the following packages:

* Debian, Ubuntu:
  ```
  apt install cpanminus ghostscript libwx-perl libxml2-dev libxslt1-dev perl-base poppler-utils xdg-utils zlib1g-dev
  ```

Then install from CPAN:
```
cpanm App::PDFLibrarian
```

## Applications

EOF

for my $app (@apps) {

  # extract POD from application
  my $pod_content = '';
  my $pod_fh = IO::Scalar->new(\$pod_content);
  podselect({ -output => $pod_fh }, File::Spec->catfile("bin", $app));
  close $pod_fh;

  # convert POD to Github-flavoured Markdown
  my $markdown_output = '';
  my $parser = Pod::Markdown::Github->new;
  $parser->output_string(\$markdown_output);
  $parser->parse_string_document($pod_content);

  # parse Markdown lines
  my @lines = split /\n/, $markdown_output;
  while (@lines) {
    $_ = shift @lines;

    # extract NAME for application header
    if ($_ =~ /^# NAME/) {
      $_ = shift @lines;
      while ($_ =~ /^\s*$/) {
        $_ = shift @lines;
      }
      $_ =~ s/\.$//;
      print OUT "### $_\n";
    }

    # extract DESCRIPTION for application description
    if ($_ =~ /^# DESCRIPTION/) {
      $_ = shift @lines;
      while ($_ !~ /^#/) {
        print OUT "$_\n";
        $_ = shift @lines;
      }
    }

  }

}

close OUT;
