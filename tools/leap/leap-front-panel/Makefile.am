tool_PROGRAMS= leap-front-panel

leap_front_panel_SOURCES = leap_front_panel_header.pl \
	leap_front_panel.ui \
    leap_front_panel.pm \
    leap_front_panel.qrc

leap-front-panel$(EXEEXT): leap_front_panel_header.pl leap_front_panel.ui.pm leap_front_panel_images.pm leap_front_panel.pm 
	cat leap_front_panel_header.pl leap_front_panel.ui.pm leap_front_panel_images.pm leap_front_panel.pm  >$@
	chmod +x $@

leap_front_panel.ui.pm: leap_front_panel.ui

%.ui.pm: %.ui
	puic4 -o $@ $<

leap_front_panel_images.pm: leap_front_panel.qrc
	prcc4_bin -o leap_front_panel_images.pm $<

CLEANFILES = *.ui.pm leap_front_panel_images.pm

