AC_PREREQ([2.69])
AC_INIT([PDFLibrarian],[0.1])
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

# determine Perl installation directories
AC_MSG_CHECKING([for ${PERL} vendor install prefix])
eval vendorprefix=`eval ${PERL} -V::vendorprefix 2>/dev/null`
AC_MSG_RESULT([${vendorprefix}])
AS_CASE(["${vendorprefix}"],
  [''|'UNKNOWN'],[AC_MSG_ERROR([could not determine ${PERL} vendor install prefix])],
)
AC_MSG_CHECKING([for ${PERL} vendor install location])
eval vendorlib=`eval ${PERL} -V::vendorlib 2>/dev/null`
AC_MSG_RESULT([${vendorlib}])
AS_CASE(["${vendorlib}"],
  [''|'UNKNOWN'],[AC_MSG_ERROR([could not determine ${PERL} vendor install location])],
)
AC_CONFIG_COMMANDS_PRE([
  AC_SUBST([perllibdir],[`echo ${vendorlib} | ${SED} "s|^${vendorprefix}/|${prefix}/|"`])
  AC_SUBST([pkgperllibdir],['$(perllibdir)/$(PACKAGE)'])
  AC_SUBST([perl_use_lib],['1'])
  AM_SUBST_NOTMAKE([perl_use_lib])
  AS_IF([test "x${prefix}" != "x${vendorprefix}"],[
    perl_use_lib="use lib '${perllibdir}'"
  ])
])

# check for Perl modules
AC_DEFUN([PDFLBR_CHECK_PERL_MODULE],[
  AC_MSG_CHECKING([for Perl module $1])
  AS_IF([${PERL} -M'$1' -e '0' >/dev/null 2>&1],[
    AC_MSG_RESULT([yes])
  ],[
    AC_MSG_RESULT([no])
    AC_MSG_ERROR([could not find Perl module $1])
  ])
  m4_ifval([$2],[
    AC_MSG_CHECKING([if Perl module $1 supports '$2'])
    AS_IF([${PERL} -M'$1' -e '$2' >/dev/null 2>&1],[
      AC_MSG_RESULT([yes])
    ],[
      AC_MSG_RESULT([no])
      AC_MSG_ERROR([Perl module $1 does not support '$2'])
    ])
  ])
])
PDFLBR_CHECK_PERL_MODULE([CAM::PDF])   dnl libcam-pdf-perl
PDFLBR_CHECK_PERL_MODULE([Capture::Tiny])   dnl libcapture-tiny-perl
PDFLBR_CHECK_PERL_MODULE([Config::Simple])   dnl libconfig-simple-perl
PDFLBR_CHECK_PERL_MODULE([File::BaseDir])   dnl libfile-basedir-perl
PDFLBR_CHECK_PERL_MODULE([File::MimeInfo])   dnl libfile-mimeinfo-perl
PDFLBR_CHECK_PERL_MODULE([JSON])   dnl libjson-perl
PDFLBR_CHECK_PERL_MODULE([LWP],[use LWP::UserAgent; use HTTP::Request])
PDFLBR_CHECK_PERL_MODULE([PDF::API2])   dnl libpdf-api2-perl
PDFLBR_CHECK_PERL_MODULE([Parallel::Iterator])   dnl libparallel-iterator-perl
PDFLBR_CHECK_PERL_MODULE([Sys::CPU])   dnl libsys-cpu-perl
PDFLBR_CHECK_PERL_MODULE([Text::BibTeX],[Text::BibTeX::Entry->new("file", undef)])   dnl libtext-bibtex-perl
PDFLBR_CHECK_PERL_MODULE([Text::Unidecode])
PDFLBR_CHECK_PERL_MODULE([URI])
PDFLBR_CHECK_PERL_MODULE([Wx])   dnl libwx-perl
PDFLBR_CHECK_PERL_MODULE([XML::LibXML])
PDFLBR_CHECK_PERL_MODULE([XML::LibXSLT])   dnl libxml-libxslt-perl

# check for fallback editor
fallback_editor=
AC_PATH_PROGS([fallback_editor],[editor emacs gedit nano vim])
AS_IF([test "x${fallback_editor}" = x],[
  AC_MSG_ERROR([could not find an editing program])
])

# check for external PDF viewer
external_pdf_viewer=
AC_PATH_PROGS([external_pdf_viewer],[xdg-open evince okular xpdf])
AS_IF([test "x${external_pdf_viewer}" = x],[
  AC_MSG_ERROR([could not find an external PDF viewer])
])

# check for optional programs
ghostscript=
AC_PATH_PROGS([ghostscript],[gs])

# set data installation directories
AC_SUBST([xsltdir],['${datadir}/'"${PACKAGE}/xslt_stylesheets"])

# output files
AC_CONFIG_FILES([
  Makefile
  pre-inst/config.pm:src/config.pm
  pre-inst/pdf-lbr-edit-bib:src/pdf-lbr-edit-bib.pl
  pre-inst/pdf-lbr-import-pdf:src/pdf-lbr-import-pdf.pl
  pre-inst/pdf-lbr-query-ads:src/pdf-lbr-query-ads.pl
  pre-inst/pdf-lbr-read-bib:src/pdf-lbr-read-bib.pl
  pre-inst/pdf-lbr-rebuild:src/pdf-lbr-rebuild.pl
  pre-inst/pdf-lbr-remove-pdf:src/pdf-lbr-remove-pdf.pl
])
AC_OUTPUT
