############################################################################
############################################################################
##
## Utility functions used in this module and in submodules
##
############################################################################
############################################################################

import os
import re
import sys
import string
import subprocess

##
## clean_split --
##     Split a string into a list using specified separator (default ':'),
##     dropping empty entries.
##
def clean_split(list, sep=':'):
    return [x for x in list.split(sep) if x != '' ]

##
## rebase_directory --
##     Rebase directory (d) that is a reference relative to the root build
##     directory, returning a result relative to cwd.  cwd must also be
##     relative to the root build directory.
##
def rebase_directory(d, cwd):
    d = clean_split(d, sep='/')
    cwd = clean_split(cwd, sep='/')

    for x in cwd:
        if (len(d) == 0 or d[0] != x):
            d.insert(0, '..')
        else:
            d.pop(0)

    if (len(d) == 0): d = [ '.' ]
    return '/'.join(d)

##
## transform_string_list --
##     Interpret incoming string (str) as a list of substrings separated by (sep).
##     Add (prefix) and (suffix) to each substring and return a modified string.
##
def transform_string_list(str, sep, prefix, suffix):
    if (sep == None):
        sep = ' '
    t = [ prefix + a + suffix for a in clean_split(str, sep) ]
    return string.join(t, sep)
    
##
## one_line_cmd --
##     Issue a shell command and return the first line of output
##
def one_line_cmd(cmd):
    p = os.popen(cmd)
    r = p.read().rstrip()
    p.close()
    return r

def execute(cmd):
    p = subprocess.Popen(cmd, shell=True)
    sts = os.waitpid(p.pid, 0)[1]
    return sts

##
## awb_resolver --
##     Ask awb-resolver for some info.  Return the first line.
##
def awb_resolver(arg):
    return one_line_cmd("awb-resolver " + arg)


##
## getGccVersion()
##

def getGccVersion():
    # What is the Gcc compiler version in the form XXYYZZ?

    gcc_version = 0

    # Parsing expression for version number

    ver_regexp = re.compile('^gcc.* \(.*\) ([0-9]+)\.([0-9]+)\.([0-9]+)')

    # Read through output of 'gcc --version'

    gcc_ostream = os.popen('gcc --version')

    for ln in gcc_ostream.readlines():
        m = ver_regexp.match(ln)
        if (m):
           gcc_version = int(m.group(1))*10000 + int(m.group(2))*100 + int(m.group(3))

    gcc_ostream.close()

    # Fail if we didn't find anything

    if gcc_version == 0:
        print "Failed to get Gcc compiler version"
        sys.exit(1)

#    print "Gcc version = %d"%(gcc_version)

    return gcc_version



##
## get_bluespec_verilog --
##     Return a list of Verilog files from the Bluespec compiler release.
##
def get_bluespec_verilog(env):
    resultArray = []
    bluespecdir = env['ENV']['BLUESPECDIR']
    
    fileProc = subprocess.Popen(["ls", "-1", bluespecdir + '/Verilog/'], stdout = subprocess.PIPE)
    fileList = fileProc.stdout.read()
    fileArray = clean_split(fileList, sep = '\n')
    for file in fileArray:
        if ((file[-2:] == '.v') and
            (file != 'main.v') and
            (file != 'ConstrainedRandom.v') and
            # For now we exclud the Vivado versions.  Need to fix this.
            (file[-9:] != '.vivado.v')):
            resultArray.append(bluespecdir + '/Verilog/' + file)

    fileProc = subprocess.Popen(["ls", "-1", bluespecdir + '/Libraries/'], stdout = subprocess.PIPE)
    fileList = fileProc.stdout.read()
    fileArray = clean_split(fileList, sep = '\n')
    for file in fileArray:
        if ((file[-2:] == '.v') and
            (file[:6] != 'xilinx') and
            # For now we exclud the Vivado versions.  Need to fix this.
            (file[-9:] != '.vivado.v')):
            resultArray.append(bluespecdir + '/Libraries/' + file)

    return resultArray


##
## get_bluespec_xcf --
##     Return a list of XCF files associated with Bluespec provided libraries.
##
def get_bluespec_xcf(env):
    bluespecdir = env['ENV']['BLUESPECDIR']

    # Bluespec only provides board-specific XCF files, but for now they are
    # all the same.  Find one.
    xcf = bluespecdir + '/board_support/xilinx/XUPV5/default.xcf.template'
    if os.path.exists(xcf):
        return [ xcf ];
    else:
        return [];


##
## What is the Bluespec compiler version?
##
def getBluespecVersion():
    if not hasattr(getBluespecVersion, 'version'):
        bsc_ostream = os.popen('bsc -verbose')
        ver_regexp = re.compile('^Bluespec Compiler, version.*\(build ([0-9]+),')
        for ln in bsc_ostream.readlines():
            m = ver_regexp.match(ln)
            if (m):
                getBluespecVersion.version = int(m.group(1))
        bsc_ostream.close()

        if getBluespecVersion.version == 0:
            print "Failed to get Bluespec compiler version"
            sys.exit(1)

        ## Generate an include file as a side-effect of calling this function
        ## that describes the compiler's capabilities.
        bsv_cap = open('hw/include/awb/provides/bsv_version_capabilities.bsh', 'w')
        bsv_cap.write('//\n')
        bsv_cap.write('// Bluespec compiler version\'s capabilities.\n')
        bsv_cap.write('// Generated at build time by Utils.py.\n\n')
        bsv_cap.write('//\n')
        bsv_cap.write('// Compiler version: ' + str(getBluespecVersion.version) + '\n')
        bsv_cap.write('//\n\n')

        bsv_cap.write('`ifndef INCLUDED_bsv_version_capabilities\n');
        bsv_cap.write('`define INCLUDED_bsv_version_capabilities\n\n');

        bsv_cap.write('// Char type implemented?\n')
        if (getBluespecVersion.version < 31201):
            bsv_cap.write('// ')
        bsv_cap.write('`define BSV_VER_CAP_CHAR 1\n')

        bsv_cap.write('\n`endif // INCLUDED_bsv_version_capabilities\n');
        bsv_cap.close()

    return getBluespecVersion.version


# useful for reconstructing synthesis boundary dependencies
# returns a list of elements with exactly the argument filepath 
def checkFilePath(prefix, path):
   (filepath,filname) = os.path.split(path)
   return prefix == path


##
## relpath --
##     Available as os.path.relpath starting in Python 2.6.  Can remove once
##     all sites have upgraded.  This code comes from James Gardner's
##     BareNecessities Python library.
##

import posixpath

def relpath(path, start=posixpath.curdir):
    """Return a relative version of a path"""
    if not path:
        raise ValueError("no path specified")
    start_list = posixpath.abspath(start).split(posixpath.sep)
    path_list = posixpath.abspath(path).split(posixpath.sep)
    # Work out how much of the filepath is shared by start and path.
    i = len(posixpath.commonprefix([start_list, path_list]))
    rel_list = [posixpath.pardir] * (len(start_list)-i) + path_list[i:]
    if not rel_list:
        return posixpath.curdir
    return posixpath.join(*rel_list)
