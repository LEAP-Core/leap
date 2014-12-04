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

##
## dictionary_list_create_append -- Checks dictionary to see if key
##     exists. If so, appends value to list.  Else creates a new key
##     entry in the dictionary and sets to value.
##
def dictionary_list_create_append(dictionary, key, value):
    if(key in dictionary):
        dictionary[key].append(value)
    else:
        dictionary[key] = value

##
## modify_path_hw -- Modifies a file path for AWB's 'hw' directory
## path.  
##
def modify_path_hw(path):
    return 'hw/' + path 
