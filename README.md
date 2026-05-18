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

### **pdf-lbr-import-pdf** - Import PDF files into the PDF library

**pdf-lbr-import-pdf** imports PDF _files_ and/or any PDF files in _directories_ into the PDF library. If **--no-pdf-bib** is specified, any BibTeX metadata embedded in the PDF files will be ignored. If _files_|_directories_ are not given on the command line, they are read from standard input, one per line.

The user will be asked to select an online query database and supply a query value which uniquely identifies the paper(s), in order for App::PDFLibrarian to retrieve a BibTeX record for the paper(s). By default App::PDFLibrarian tries to extract a Digital Object Identifier from the PDF paper(s) for use in the query. If the query is successful, the user will have an opportunity to edit the BibTeX record(s) before the PDF _files_ are added to the library.

The user may also enter the BibTeX record manually. The _type_ of the manual BibTeX entry defaults to _article_, unless the **--manual-entry** option specifies a different _type_. Additional manual BibTeX _field_s may be set using the **--manual-field** option.

Note that the editor will open the BibTeX entries of all PDF files passed to the command line, even if they are already in the library. In this way, the user may call up relevant existing BibTeX entries as a guide to filling out a new BibTeX entry; for example: entries of the same type (e.g. book, techreport), entries that appear in the same journal/conference series, etc.

### **pdf-lbr-edit-bib** - Edit BibTeX bibliographic metadata in PDF files

**pdf-lbr-edit-bib** reads BibTeX bibliographic metadata embedded in PDF files given by _links_ and/or within _link-directories_ in the PDF links directory. If _links_|_link-directories_ are not given on the command line, they are read from standard input, one per line.

The BibTeX metadata is written to a temporary file, which is then opened in an editing program, given either by the **$VISUAL** or **$EDITOR** environment variables, or else the program **editor**. The **macros** section of the configuration file is parsed for custom BibTeX macros to define.

Any modifications are then written back to the PDF files given by the _file_ field in each BibTeX entry, and the PDF library links rebuilt as needed.

### **pdf-lbr-output-bib** - Output BibTeX bibliographic metadata from PDF files

**pdf-lbr-output-bib** reads BibTeX bibliographic metadata embedded in PDF _files_ and/or any PDF files in _directories_. If _files_|_directories_ are not given on the command line, they are read from standard input, one per line.

The BibTeX metadata is then printed to standard output; if **--clipboard** is given, it is instead copied to the clipboard.

### **pdf-lbr-output-key** - Output BibTeX bibliographic keys from PDF files

**pdf-lbr-output-key** reads BibTeX bibliographic keys for PDF _files_ and/or any PDF files in _directories_. If _files_|_directories_ are not given on the command line, they are read from standard input, one per line.

The BibTeX keys are then printed to standard output, separated by commas; if **--clipboard** is given, they are instead copied to the clipboard.

### **pdf-lbr-replace-pdf** - Replace a PDF file in the PDF library with a new PDF file

**pdf-lbr-replace-pdf** replaces a PDF file, given by a _old-link_ in the PDF links directory, with a new PDF _file_.

The replaced PDF file is moved to the directory _output-directory_, or else to the user's home directory.

### **pdf-lbr-remove-pdf** - Remove a PDF file from the PDF library

**pdf-lbr-remove-pdf** removes a PDF file, given by a _link_ in the PDF links directory, from the PDF library.

The PDF file is moved to the directory _output-directory_, or else to the user's home directory.

### **pdf-lbr-rebuild-links** - Rebuild the PDF links directory

**pdf-lbr-rebuild-links** rebuilds the PDF links directory.

All BibTeX metadata is written to a temporary file, which is then opened in an editing program to check for errors. The editing program is given either by the **$VISUAL** or **$EDITOR** environment variables, or else the program **editor**.

PDF files for any BibTeX entries removing during editing are moved to the directory _output-directory_, or else to the user's home directory.

### **pdf-lbr-iso4-abbr** - Output ISO4 abbreviations

**pdf-lbr-iso4-abbr** outputs the ISO4 abbreviation of _words_ using the ISSN List of Title Word Abbreviations. The abbreviation is also copied to the clipboard.

