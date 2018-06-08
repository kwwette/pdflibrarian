AC_PREREQ([2.69])
AC_INIT([PDFLibrarian],[0.1])
AC_CONFIG_SRCDIR([Makefile.am])
AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([1.14 foreign])
AM_SILENT_RULES([yes])

# check for standard programs
AC_PROG_INSTALL
AC_PROG_SED
AC_PATH_PROG([MAN],[man])
AS_IF([test "x${MAN}" = x],[
  AC_MSG_ERROR([could not find man])
])

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
dnl PDFLBR_CHECK_PERL_MODULE([Capture::Tiny])   dnl libcapture-tiny-perl
dnl PDFLBR_CHECK_PERL_MODULE([Config::Simple])   dnl libconfig-simple-perl
dnl PDFLBR_CHECK_PERL_MODULE([File::chmod])   dnl libfile-chmod-perl
dnl PDFLBR_CHECK_PERL_MODULE([JSON])   dnl libjson-perl
dnl PDFLBR_CHECK_PERL_MODULE([LWP],[use LWP::UserAgent; use HTTP::Request])
dnl PDFLBR_CHECK_PERL_MODULE([PDF::API2])   dnl libpdf-api2-perl
dnl PDFLBR_CHECK_PERL_MODULE([Parallel::Iterator])   dnl libparallel-iterator-perl
dnl PDFLBR_CHECK_PERL_MODULE([Sys::CPU])   dnl libsys-cpu-perl
dnl PDFLBR_CHECK_PERL_MODULE([Term::ReadLine])
dnl PDFLBR_CHECK_PERL_MODULE([Text::BibTeX],[Text::BibTeX::Entry->new("file", undef)])   dnl libtext-bibtex-perl
dnl PDFLBR_CHECK_PERL_MODULE([Text::Unidecode])
dnl PDFLBR_CHECK_PERL_MODULE([URI])
dnl PDFLBR_CHECK_PERL_MODULE([XML::LibXML])
dnl PDFLBR_CHECK_PERL_MODULE([XML::LibXSLT])   dnl libxml-libxslt-perl

# check for fallback editor
fallback_editor=
AC_CHECK_PROGS([fallback_editor],[editor emacs gedit nano vim])
AS_IF([test "x${fallback_editor}" = x],[
  AC_MSG_ERROR([could not find an editing program])
])

# check for optional programs
ghostscript=
AC_CHECK_PROGS([ghostscript],[gs])

# output files
AC_CONFIG_FILES([
  Makefile
])
  dnl pre-inst/fmdt.1:src/fmdt.man
  dnl pre-inst/fmdt:src/fmdt.pl
  dnl pre-inst/fmdtools.pm:src/fmdtools.pm
AC_OUTPUT
