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
Bluetcl::flags set -verilog
Bluetcl::flags set -p $OPT(-p):[join $libs ":"]

# set path to whatever 
module load mk_model_Wrapper

set clk 0

proc extractClocks {interfaceIn} {

  set typeL [lindex $interfaceIn 0] 
  set name [lindex $interfaceIn 1]
   
  set comp [string compare $typeL "interface"]
  set compC [string equal $typeL "interface"]
  #puts stderr "In extract $typeL $name $comp $compC" 

  if { $comp == 0 } {
    # process subinterfaces 
    set subifcs [lindex $interfaceIn 2]
    set len [llength $subifcs]
    
    set clockList {}    

    #puts stderr "exploring $len subifcs"

    # need to agglomerate return values 
    for {set i 0} {$i < $len} {incr i} { 
       set subifc [lindex $subifcs $i]
       set clockListNew [extractClocks $subifc]
       # append to list
       set clockList [concat $clockList $clockListNew]
       set clockLen [llength $clockList]
       #puts stderr "subifc got $clockListNew: $clockLen $clockList"
    }

    return $clockList
  }

  set comp [string compare $typeL "clock"]
  if {$comp == 0} {
    set oscStruct [lindex $interfaceIn 3]
    set oscName [lindex $oscStruct 1]
    #puts stderr "XXX $interfaceIn $oscName";
    return [list $oscName]
  }

  # for non matches we just return an empty list
  return {}
}

# recursive function to do things
# we don't really need to drill through the path here
# synthesis constraints are locally generated
proc printPaths { name module } {
  #upvar #0 clk clknum
  set submodules [lindex $module 1]
  set kind [lindex $module 0]

  set len [llength $submodules]

  #puts "has length $len"
  #puts stderr "module is $module"

  set comp [string compare $kind "user"]    
  if {$comp != 0} {
    #if we aren't a user module, go home
    return
  }

  # before recursing we must emit the appropriate code for _this_ module
  puts "BEGIN MODEL \"$name\""

  # we should first handle _this_ modules incoming port/outgoing list, 
  # and then those of all its children

  for {set i 0} {$i < $len} {incr i} { 
    set submodule [lindex $submodules $i] 
    set type [lindex $submodule 1]
    set name [lindex $submodule 0]

  
    # we want to look at user module interfaces 
    set comp [string compare $kind "user"]    
    if {$comp == 0} {
      # traverse to children
      #puts stderr "traversing submodule $type : $name"
      set submod_struct [module submods $type]
      set portlist [module ports $type]
    
      # check for a null portlist
      set portlistlen [llength $portlist]
      if {$portlistlen > 0} {
        #puts stderr "portlist is $portlist"
        # second component should be an interface list
        set interface [lindex $portlist 0]
        set ifc [lindex $interface 0]
        set subinterfaces [lindex $interface 1]
        set magic_arg [list $ifc "foo" $subinterfaces]
        #puts stderr "subinterfaces is $subinterfaces"
        set clock_xcf [extractClocks $magic_arg]
        set clock_len [llength $clock_xcf]
        for {set j 0} {$j < $clock_len} {incr j} { 
          set wire [lindex $clock_xcf $j]
          puts "\tNET \"${name}_${wire}\" buffer_type = none;"
        }
      }     
    }    
  
  }

  puts "END;"

  # now we can recurse

  for {set i 0} {$i < $len} {incr i} { 
    set submodule [lindex $submodules $i] 
    set type [lindex $submodule 1]
    set name [lindex $submodule 0]

    set comp [string compare $kind "user"]    
    if {$comp == 0} {
      # traverse to children
      #puts stderr "traversing submodule $type : $name"
      set submod_struct [module submods $type]
      set portlist [module ports $type]
      ##puts stderr "$submod_struct"
      #puts "$newpath"
      printPaths $type $submod_struct
    }    
  
    # we want to look at user module interfaces 
  }


  #puts "return"
}

set submod_struct [module submods mk_model_Wrapper]
printPaths "mk_model_Wrapper" $submod_struct
