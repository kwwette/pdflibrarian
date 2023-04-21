bin_SCRIPTS = \
	pre-inst/pdf-lbr-edit-bib \
	pre-inst/pdf-lbr-import-pdf \
	pre-inst/pdf-lbr-output-bib \
	pre-inst/pdf-lbr-output-key \
	pre-inst/pdf-lbr-query-ads \
	pre-inst/pdf-lbr-rebuild-links \
	pre-inst/pdf-lbr-remove-pdf \
	pre-inst/pdf-lbr-replace-pdf \
	$(END_OF_LINE)

pkgperllib_DATA = \
	pre-inst/config.pm \
	src/bibtex.pm \
	src/library.pm \
	src/query_dialog.pm \
	src/title_abbr.pm \
	src/util.pm \
	$(END_OF_LINE)

pkgdata_DATA = \
	src/bibtex.xsl \
	src/dublincore.xsl \
	src/title_abbr_aas.csv \
	src/title_abbr_iso4.csv \
	$(END_OF_LINE)

man1_MANS = $(bin_SCRIPTS:%=%.man)

%.man: %
	$(AM_V_GEN)$(POD2MAN) $* > $@

EXTRA_DIST = \
	$(DATA) \
	$(END_OF_LINE)
