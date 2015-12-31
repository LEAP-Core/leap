############################################################################
############################################################################
##
## Sort a list of files that import other packages.  This is particularly
## important for SystemVerilog packages compiled by VCS, which depends
## on seeing packages in depth-first order on the compilation command
## line.
##
############################################################################
############################################################################

import os
import re

##
## Is seekLeaf a leaf file (without suffix) in the list files?
##
def findFileFromLeap(seekLeaf, files):
    for fn in files:
        leaf = os.path.split(fn)[1]
        base = os.path.splitext(leaf)[0]
        if (base == seekLeaf):
            return fn
    return None

##
## Generate a sorted list based on depth first sort so leaves wind up first
## in the list.
##
def genDepthSortList(fn, sorted, deps, processed):
    if (not fn in processed):
        processed[fn] = 1
        if (fn in deps):
            for d in deps[fn]:
                genDepthSortList(d, sorted, deps, processed)
        sorted += [fn]


def sortPkgList(fNames):
    ## Regular expression to find import statements
    p = re.compile(r'\s*import\s+(\w*)::.*')
    deps = {}
    processed = {}

    ## Walk through all files and record dependence on all imports
    for fn in fNames:
        f = open(fn, 'r')
        for line in f:
            m = p.match(line)
            if m:
                dep = findFileFromLeap(m.group(1), fNames)
                if dep:
                    if (fn in deps):
                        deps[fn] += [dep]
                    else:
                        deps[fn] = [dep]

        f.close()

    sorted = []
    for fn in fNames:
        genDepthSortList(fn, sorted, deps, processed)
    return sorted
