#!/bin/sh
# Copyright 2007--2009 Bluespec, Inc.  All rights reserved.
# $Id: expandPorts.tcl 17899 2009-09-21 13:39:55Z czeck $
# \
exec $BLUESPECDIR/bin/bluetcl "$0" -quiet -- "$@"

# 
set major_version 2
set minor_version 0
set version "$major_version.$minor_version"

# TODO: load rather than source ?
global env
namespace import ::Bluetcl::* 

package require utils
package require portUtil

# processSwitches also sets these switches (feel free to set them yourself)
# flags set "-verilog -vdir obj -bdir obj -simdir obj -p obj:.:+"

proc usage {} {
    puts "Usage: wrapper.tcl"
    puts ""
    puts "   switches from compile (see bsc help for more detail):"
    puts "      -p <path>       - path, if suppled to bsc command (i.e. -p obj:+)"
    puts "      --m module      - module to examine)"
    exit
}

set valOptions [list --m -p]
set boolOptions [list -verilog]

if { [catch [list ::utils::scanOptions $boolOptions $valOptions true OPT "$argv"] opts] } {
    puts stderr $opts
    usage
    exit 1
}

set bsdir $::env(BLUESPECDIR)
set libs [list [file join $bsdir "Prelude"] [file join $bsdir "Libraries"]]

portUtil::processSwitches [list {p "+"}]
Bluetcl::flags set -verilog
Bluetcl::flags set -p $OPT(-p):[join $libs ":"]

# set path to whatever 
set moduleTarget $OPT(--m)
module load $moduleTarget

set outStr ""    
set paths [schedule pathinfo $moduleTarget]
set lenPathStm [llength $paths]
for {set pathStm 0} {$pathStm < $lenPathStm} {incr pathStm} { 
    set sinkSet [lindex $paths $pathStm]
    set srcSet [lindex $sinkSet 0]
    set lenSrc [llength $srcSet]
    set sinkWire [lindex $sinkSet 1]
    for {set src 0} {$src < $lenSrc} {incr src} { 
        set srcWire [lindex $srcSet $src]
        set outStr "${outStr}path($srcWire,$sinkWire);\n"
    }
}
puts "$outStr"

