tool_PROGRAMS= leap-front-panel

leap_front_panel_SOURCES = leap_front_panel_header.pl \
	leap_front_panel.ui leap_front_panel.ui.h

leap-front-panel$(EXEEXT): leap_front_panel_header.pl leap_front_panel.ui.pm
	cat leap_front_panel_header.pl leap_front_panel.ui.pm >$@
	chmod +x $@

leap_front_panel.ui.pm: leap_front_panel.ui leap_front_panel.ui.h

%.ui.pm: %.ui
	puic -x -o $@ $<

CLEANFILES = *.ui.pm

