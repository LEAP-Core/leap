#! /usr/bin/env python
#
# Copyright (C) 2013 Intel Corporation
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
# Author: Mohit Gambhir (mohit.gambhir@intel.com)
#


#Python script to convert source files into html files for doxygen documentation 

import os
htmlheader = """
<html>
<body>
<Pre>
             """
htmlfooter= """
</Pre>
</body>
</html>
             """
for dirpath, dirnames, filenames in os.walk("../"):
    for filename in filenames:
        if filename.endswith(".bsv") or filename.endswith(".cpp") or filename.endswith(".h"):
            basename = os.path.splitext(filename)[0]
            ext =  os.path.splitext(filename)[1][1:].strip()
            htmlfilename = "dox/html/" + os.path.splitext(filename)[0] + "_8" + ext + "_source.html"
            sourcefilepath = os.path.join(dirpath, filename)
            outputfd = open (htmlfilename, 'w')
            outputfd.write(htmlheader)
            inputfd  = open (sourcefilepath, 'r')
            lineno = 1
            for line in inputfd.readlines():
                htmlline = "<div class=\"line\"><a name=\"l" + str(lineno).zfill(5) + "\"/>" + str(lineno) + "</span>&#160;<span class=\"comment\">" + line.rstrip() + "</span></div>"
                outputfd.write(htmlline)
                lineno = lineno+1
            outputfd.write(htmlfooter)

            


