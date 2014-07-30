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
    puts "Usage: mcd.tcl"
    puts ""
    puts "   switches from compile (see bsc help for more detail):"
    puts "      -p <path>       - path, if suppled to bsc command (i.e. -p obj:+)"
    exit
}

set valOptions [list -p]
set boolOptions [list -verilog]

if { [catch [list ::utils::scanOptions $boolOptions $valOptions true OPT "$argv"] opts] } {
    puts stderr $opts
    usage
    exit 1
}

set bsdir $::env(BLUESPECDIR)
set libs [list [file join $bsdir "Prelude"] [file join $bsdir "Libraries"]]

portUtil::processSwitches [list {p "+"}]
Bluetcl::flags set -wait-for-license
Bluetcl::flags set -verilog
Bluetcl::flags set -p $OPT(-p):[join $libs ":"]

# set path to whatever 
module load mk_model_Wrapper

set clk 0
# recursive function to do things

proc printPaths { v_path module } {
  #upvar #0 clk clknum
  set submodules [lindex $module 1]
  set kind [lindex $module 0]

  set len [llength $submodules]

  #puts "has length $len"
  #puts "$module"

  for {set i 0} {$i < $len} {incr i} { 
    set submodule [lindex $submodules $i] 
    set type [lindex $submodule 1]
    set name [lindex $submodule 0]
    # handle top level 
    if {$v_path == ""} {
       set prefix ""
    } else  {
       set prefix "$v_path/"
    }

    set compare [string compare $kind "user"]
    if {$compare == 0} {
      # traverse to children
      #puts "traversing submodule $type : $name"
      set submod_struct [module submods $type]
      set newpath "${prefix}${name}"
      #puts "$newpath"
      printPaths $newpath $submod_struct
    }    
  
    set compare [string compare $type "mkUserClock_Ratio_PLL"]
    if {$compare == 0} {
     # the pll uses CLK OUT
     #_CLK_OUT
      puts "$prefix${name}/x/CLKOUT0_BUF"
      set portlist [module ports $type]
      set submod_struct [module submods $type]
      #puts stderr "$submod_struct"
      #puts stderr "ports of $type: $portlist"
    }

    set compare [string compare $type "mkUserClock_Ratio"]
    if {$compare == 0} {
     # the pll uses CLK OUT
     #_CLK_OUT
      puts "$prefix${name}/x/CLKFX_BUF"
      set portlist [module ports $type]
      set submod_struct [module submods $type]
      #puts stderr "$submod_struct"
      #puts stderr "ports: $portlist"
    }


    set compare [string compare $type "ClockDiv"]
    if {$compare == 0} {
     # the pll uses CLK OUT
     #_CLK_OUT
      puts "$prefix${name}/cntr_0_01"
      set portlist [module ports $type]
    }
    
  
  }
  #puts "return"
}

set submod_struct [module submods mk_model_Wrapper]
printPaths [] $submod_struct
