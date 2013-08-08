#
# Copyright (C) 2012 Intel Corporation
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
# 
#

EXTRA_DIST = doxygen.config
#-----------------------------------------------------------------------------
# Generate documentation with Doxygen
#-----------------------------------------------------------------------------
.PHONY: dox

all: doxygen.config dox-gen html-gen search-gen index-gen
	@echo "Doxygen output is at `pwd`/dox/html/index.html"

dox-gen:
	doxygen doxygen.config

html-gen: dox/html/index.html

dox/html/index.html: dox/xml/index.xml
	ls dox/xml/*.xml | xargs -I {} basename {} .xml | xargs -I {} xsltproc -o dox/html/{}.html doxyhtmlgen.xsl dox/xml/{}.xml
	@cp title.png dox/html/
	@cp search/search.html dox/html/
	@cp --parent search/* dox/html/
	
search-gen:
	@xsltproc -o dox/searchdata.xml doxyhtmlgen.xsl dox/searchdata.xml

index-gen:
	@doxyindexer -o dox/ dox/searchdata.xml

install:
	rm -rf $(htmldir)
	test -d "$(htmldir)" || mkdir -p "$(htmldir)" && cp -r dox/html/* $(htmldir)

clean-local:
	rm -rf dox/xml
	rm -rf dox/html
	rm -rf dox/searchdata.xml
	rm -rf dox/doxysearch.db


