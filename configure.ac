AC_PREREQ([2.69])
AC_INIT([PDFLibrarian],[4.3.11])
AC_CONFIG_SRCDIR([Makefile.am])
AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([1.14 foreign])
AM_SILENT_RULES([yes])

# check for standard programs
AC_PROG_INSTALL
AC_PROG_SED

# check for Perl
AC_SUBST([PERLVERSION],[5.18.0])
AC_CACHE_CHECK([for perl version >= ${PERLVERSION}],[ac_cv_path_PERL],[
  AC_PATH_PROGS_FEATURE_CHECK([PERL],[perl],[
    AS_IF([${ac_path_PERL} -e "require ${PERLVERSION}" >/dev/null 2>&1],[
      ac_cv_path_PERL=${ac_path_PERL}
      ac_path_PERL_found=:
    ])
  ],[
    AC_MSG_ERROR([could not find perl version >= ${PERLVERSION}])
  ])
])
AC_SUBST([PERL],[${ac_cv_path_PERL}])
AC_PATH_PROGS([POD2MAN],[pod2man],[])
AS_IF([test "x${POD2MAN}" = x],[
  AC_MSG_ERROR([could not find 'pod2man' in PATH])
])

# determine Perl installation directories
AC_MSG_CHECKING([for ${PERL} install prefix])
for perlconfigvar in prefix installprefix vendorprefix; do
  eval perlconfigprefix=`eval ${PERL} -V::${perlconfigvar} 2>/dev/null`
  AS_CASE(["${perlconfigprefix}"],
    [''|'UNKNOWN'],[continue],
  )
  break
done
AC_MSG_RESULT([${perlconfigprefix}])
AS_CASE(["${perlconfigprefix}"],
  [''|'UNKNOWN'],[AC_MSG_ERROR([could not determine ${PERL} install prefix])],
)
AC_MSG_CHECKING([for ${PERL} install location])
for perlconfigvar in installvendorlib vendorlib installsitelib sitelib; do
  eval perlconfiglib=`eval ${PERL} -V::${perlconfigvar} 2>/dev/null`
  AS_CASE(["${perlconfiglib}"],
    [''|'UNKNOWN'],[continue],
  )
  break
done
AC_MSG_RESULT([${perlconfiglib}])
AS_CASE(["${perlconfiglib}"],
  [''|'UNKNOWN'],[AC_MSG_ERROR([could not determine ${PERL} install location])],
)
AC_CONFIG_COMMANDS_PRE([
  AC_SUBST([perllibdir],[`echo ${perlconfiglib} | ${SED} "s|^${perlconfigprefix}/|${prefix}/|"`])
  AC_SUBST([pkgperllibdir],['$(perllibdir)/$(PACKAGE)'])
  AC_SUBST([perl_use_lib],['1'])
  AM_SUBST_NOTMAKE([perl_use_lib])
  AS_IF([test "x${prefix}" != "x${installprefix}"],[
    perl_use_lib="use lib '${perllibdir}'"
  ])
])

# check for Perl modules
AC_SUBST([DEPENDS],["perl-base"])
AC_DEFUN([PDFLBR_CHECK_PERL_MODULE],[
  AC_MSG_CHECKING([for Perl module $1])
  echo "${PERL} -e 'm4_default([$3],[use $1])'" >&AS_MESSAGE_LOG_FD
  AS_IF([( unset DISPLAY; ${PERL} -e 'm4_default([$3],[use $1])' >&AS_MESSAGE_LOG_FD 2>&AS_MESSAGE_LOG_FD )],[
    AC_MSG_RESULT([yes])
  ],[
    AC_MSG_RESULT([no])
    AC_MSG_ERROR([could not find Perl module $1])
  ])
  DEPENDS="${DEPENDS}, $2"
])
PDFLBR_CHECK_PERL_MODULE([Capture::Tiny],[libcapture-tiny-perl])
PDFLBR_CHECK_PERL_MODULE([Carp::Assert],[libcarp-assert-perl])
PDFLBR_CHECK_PERL_MODULE([Config::Simple],[libconfig-simple-perl])
PDFLBR_CHECK_PERL_MODULE([Clipboard],[libclipboard-perl])
PDFLBR_CHECK_PERL_MODULE([File::BaseDir],[libfile-basedir-perl])
PDFLBR_CHECK_PERL_MODULE([File::MimeInfo],[libfile-mimeinfo-perl])
PDFLBR_CHECK_PERL_MODULE([JSON],[libjson-perl])
PDFLBR_CHECK_PERL_MODULE([LWP],[libwww-perl, libhttp-message-perl],[use LWP; use LWP::UserAgent; use HTTP::Request])
PDFLBR_CHECK_PERL_MODULE([PDF::API2],[libpdf-api2-perl])
PDFLBR_CHECK_PERL_MODULE([Parallel::Iterator],[libparallel-iterator-perl])
PDFLBR_CHECK_PERL_MODULE([Sys::CPU],[libsys-cpu-perl])
PDFLBR_CHECK_PERL_MODULE([Text::BibTeX],[libtext-bibtex-perl],[use Text::BibTeX; Text::BibTeX::Entry->new("file", undef)])
PDFLBR_CHECK_PERL_MODULE([Text::Unidecode],[libtext-unidecode-perl])
PDFLBR_CHECK_PERL_MODULE([Text::CSV::Encoded],[libtext-csv-encoded-perl])
PDFLBR_CHECK_PERL_MODULE([URI],[liburi-perl])
PDFLBR_CHECK_PERL_MODULE([URI::Encode],[liburi-encode-perl])
PDFLBR_CHECK_PERL_MODULE([Wx],[libwx-perl],[use Wx::App])
PDFLBR_CHECK_PERL_MODULE([XML::LibXML],[libxml-libxslt-perl])
PDFLBR_CHECK_PERL_MODULE([XML::LibXSLT],[libxml-libxslt-perl])

# check for fallback editor
AC_PATH_PROGS([fallback_editor],[editor emacs gedit nano vim],[editor])

# check for external PDF viewer
AC_PATH_PROGS([external_pdf_viewer],[xdg-open evince okular xpdf],[xdg-open])

# check for ghostscript
AC_PATH_PROGS([ghostscript],[gs],[])
AS_IF([test "x${ghostscript}" = x],[
  AC_MSG_ERROR([could not find 'gs' in PATH])
])

# check for pdftotext
AC_PATH_PROGS([pdftotext],[pdftotext],[])
AS_IF([test "x${pdftotext}" = x],[
  AC_MSG_ERROR([could not find 'pdftotext' in PATH])
])

# set data installation directory
AC_SUBST([pkgdatadir],['${datadir}/'"${PACKAGE}"])

# output files
AC_CONFIG_FILES([
  Makefile
  debian/control
  pre-inst/config.pm:src/config.pm
  pre-inst/pdf-lbr-edit-bib:src/pdf-lbr-edit-bib.pl
  pre-inst/pdf-lbr-import-pdf:src/pdf-lbr-import-pdf.pl
  pre-inst/pdf-lbr-output-bib:src/pdf-lbr-output-bib.pl
  pre-inst/pdf-lbr-output-key:src/pdf-lbr-output-key.pl
  pre-inst/pdf-lbr-query-ads:src/pdf-lbr-query-ads.pl
  pre-inst/pdf-lbr-rebuild-links:src/pdf-lbr-rebuild-links.pl
  pre-inst/pdf-lbr-remove-pdf:src/pdf-lbr-remove-pdf.pl
  pre-inst/pdf-lbr-replace-pdf:src/pdf-lbr-replace-pdf.pl
])
AC_OUTPUT
