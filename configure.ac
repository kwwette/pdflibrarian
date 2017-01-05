AC_PREREQ([2.69])
AC_INIT([fmdtools],[0.1])
AC_CONFIG_SRCDIR([Makefile.am])
AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([1.14 foreign])
AM_SILENT_RULES([yes])
AC_SUBST([DATE],[`date +'%Y-%m-%d'`])

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
modules=m4_normalize("
  Capture::Tiny
  File::chmod
  PDF::API2
  Parallel::Iterator
  Sys::CPU
  Text::BibTeX
  Text::Unidecode
  XML::LibXML
  XML::LibXSLT
")
module_check_fail=
for module in ${modules}; do
  AC_MSG_CHECKING([for Perl module '${module}'])
  AS_IF([${PERL} -M${module} -e '0' >/dev/null 2>&1],[
    AC_MSG_RESULT([yes])
  ],[
    AC_MSG_RESULT([no])
    module_check_fail=yes
  ])
done
AS_IF([test "x${module_check_fail}" != x],[
  AC_MSG_ERROR([could not find all required Perl modules (see above)])
])

# check for fallback editor
AC_SUBST([fallback_editor],[''])
AM_SUBST_NOTMAKE([fallback_editor])
AC_CHECK_PROGS([fallback_editor],[emacs nano vim ed])
AS_IF([test "x${fallback_editor}" = x],[
  AC_MSG_ERROR([could not find an editing program])
])

# output files
AC_CONFIG_FILES([
  Makefile
  pre-inst/fmdt.1:src/fmdt.man
  pre-inst/fmdt:src/fmdt.pl
  pre-inst/fmdtools.pm:src/fmdtools.pm
])
AC_OUTPUT
