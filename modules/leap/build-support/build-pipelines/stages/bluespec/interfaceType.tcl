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
    puts "Usage: import.tcl"
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
Bluetcl::flags set -wait-for-license
Bluetcl::flags set -verilog
Bluetcl::flags set -p $OPT(-p):[join $libs ":"]

# set path to whatever we were given on the command line
set moduleTarget $OPT(--m)
module load $moduleTarget

set outStr ""    


###
### Various methods for extracting fields from the bluetcl data structures
###
proc getMembers {ft} {
    foreach elem $ft {
        if {[lindex $elem 0] == "members" } {
            return [lindex $elem 1]
        }
    }
    return ""
}

proc getWireNamed {ft name} {
    foreach elem $ft {
        if {[lindex $elem 0] == $name } {
            return [lindex $elem 1]
        }
    }
    return ""
}

proc getInterface {ft} {
    foreach elem $ft {
        if {[lindex $elem 0] == "interface" } {
            return [lindex $elem 1]
        }
    }
    return ""
}

proc getInterfaceNamed {ft name} {
    foreach elem $ft {
        #puts stderr "\n\nCheckign $ft against $name\n\n"
        if {[lindex $elem 1] == $name } {
            #puts stderr "GOT A MATCH on $name"    
            return $elem
        }
    }
    return ""
}

###
### The following functions recursively analyze a bluespec 
### interface definition and build a python representation of that
### interface.  This requires a simulatneous recursion over three
### different data structures: interface type, interface ports, and
### interface method. This recursion is required because each structure
### includes (or omits, unfortunately) information about the interface 
### and its physical representation in the bluespec object. 
###

#
# Switch for handling recursive interface type cases.  
#
proc analyzeSwitch { elem ports methods } {
    #puts stderr "ELEM: $elem \n\n\n\n\nemacs -n"
    set type [type full $elem]     
    set key [lindex $type 0]
    #puts "procfulltype $name $ft"                                              
    switch -exact $key {
        "Primary" { set retVal [analyzePrimary $elem $type $ports $methods]  } 
        "Alias"   { set retVal [analyzeAlias $elem $type $ports $methods]  }
        "Struct"  { set retVal [analyzeStruct $elem $type $ports $methods]  }
        "Enum"    { set retVal [analyzeEnum $elem $type $ports $methods]  }
        "TaggedUnion"    { set retVal [analyzeTaggedUnion $elem $type $ports $methods]  }
        "Vector"  { set retVal [analyzeVector $elem $type $ports $methods]  }
        "Interface" { set retVal [analyzeInterface $elem $type $ports $methods]  }
        }

    ##puts stderr "Switch Return: $retVal"
    return $retVal
}

#
# Handles bluespec primative types
#
proc analyzePrimary { elem prim ports methods } {
    # maybe need cases here?
    set key [lindex $prim 0]
    set primType [lindex $prim 1]
    set methodsMembers [lindex $methods 1]
    set methodsName [lindex $methods 0]

    # get clock wires
    set osc  [getWireNamed $ports "osc"]
    set gate  [getWireNamed $ports "gate"]    
    
    # get reset wires
    set port  [getWireNamed $ports "port"]
    set clock  [getWireNamed $ports "clock"]    

    #puts stderr "Analyzing Primary: $primType \n PORTS $ports METHODS $methods" 
    switch -regexp $primType {
        "Inout" { return [list "Interface" "Interface('$elem','$methodsName',{})"] }
        "Clock"  { return [list "Primary" "Prim_Clock('$methodsName','$osc', '$gate')"] }
        "Reset"  { return [list "Primary" "Prim_Reset('$methodsName','$port', '$clock')"] }
    }
    puts "ERROR unhandled primary type"
}

#
# Handles enums.  Our platform code doesn't use enums, so this is unimplemented
#
proc analyzeEnum { elem enum ports methods} {
   # maybe need cases here?
   return [list "Enum" enum]
}

#
# Handles tagged unions.  Our platform code doesn't use tagged unions, so this is unimplemented
#
proc analyzeTaggedUnion { elem tUnion ports methods} {
   # maybe need cases here?
   return [list "TaggedUnion" tUnion]
}


#
# Handles vectors.  Vecrtors are interfaces of the same type, wherein the 
# subinterface names are constrained to be integers.
#
# We need context here to promote underlying interfaces above the Vector type. 
proc analyzeVector { elem vec ports methods} {

    set lengthStm [lindex $vec 2]
    set typeStm [lindex $vec 3]
    set vLength [lindex $lengthStm 1]
    set vType [lindex $typeStm 1]

    set portsType [lindex $ports 0]
    set portsName [lindex $ports 1]
    set portsMembers [lindex $ports 2]

    set methodsMembers [lindex $methods 1]
    set methodsName [lindex $methods 0]

    #puts stderr "Vector: $vec"
    #puts stderr "Length: $vLength"
    #puts stderr "Ports: $ports"
    #puts stderr "Type: $vType"

    # each of the vectors has a submember. 
    # need to analyze....
    set memberList [list]
    for {set mem 0} {$mem < $vLength} {incr mem} {
        #check for optimized interface.
        set memberMethods [lindex $methodsMembers $mem]
        set memberMethodsName [lindex $memberMethods 0]

        set memberPorts [getInterfaceNamed $portsMembers $memberMethodsName]
        set compareExists [string compare $memberPorts ""]
        if {$memberPorts == ""} {
            # this member has been optimized. Skip
            #puts stderr "WARNING: anyalzeStruct $memberMethods of $methodsName has been optimized away?"
            continue
        }

        set obj [analyzeSwitch  $vType $memberPorts $memberMethods]

        # did we get an interface?
        set key [lindex $obj 0]
        set memberRep [lindex $obj 1]

        lappend memberList "$mem: $memberRep"
    }

    set memberDict [join $memberList ","]
     return [list "Interface" "Vector('Vector#($vLength, $vType)', '$portsName', {$memberDict})"]
}


#
# Handles structs.  Structs are interfaces different types, wherein the 
# subinterface names are strings. Structs are really just an unnecessary sugar
# on top of the basic interface.
#
proc analyzeStruct { elem struct ports methods } {
    #puts stderr "ELEM: $elem STRUCT: $struct \n\n PORTS: $ports \n\n METHODS: $methods" 

    set portsType [lindex $ports 0]
    set portsName [lindex $ports 1]
    set portsMembers [lindex $ports 2]

    set members [getMembers $struct]
    set memberList [list]

    set methodsMembers [lindex $methods 1]
    set methodsName [lindex $methods 0]

    for {set idx 0} {$idx < [llength $members]} {incr idx} { 
        set member [lindex $members $idx]
        set memberMethods [lindex $methodsMembers $idx]
        set memberMethodsName [lindex $memberMethods 0]

        # check for optimized away interfaces.
        set memberPorts [getInterfaceNamed $portsMembers $memberMethodsName]
        set compareExists [string compare $memberPorts ""]
        if {$compareExists == 0} {
            # this member has been optimized. Skip
            #puts stderr "WARNING: anyalzeStruct $memberMethodsName of $methodsName has been optimized away?"
            continue
        }

        set memType [lindex $member 0]
        set memName [lindex $member 1]
        set obj [analyzeSwitch  $memType $memberPorts $memberMethods]
        set memberRep [lindex $obj 1]
        lappend memberList "'$memName': $memberRep"
    }

    set memberDict [join $memberList ","]

    return [list "Struct" "Struct('$elem', '$portsName',{$memberDict})"]
}


#
# Handles methods.  Records information about method clocking and port names.
# Eventually, we need to know about port widths also. 
#
proc analyzeMethod { method ports methods } {
    #puts stderr "\n\n METHOD: $method Ports: $ports methods: $methods"    
    set methodRep [lindex $method 1]
    # We need to analyze methodRet due to Bluespecs failure to
    # use interfaces for vectors (and other stuff?)
    set methodRet [lindex $methodRep 0]
    set methodName [lindex $methodRep 1]
    #puts stderr "MethodRep: $methodRep"    
    # Probably not correct....
    set methodArgsList [lindex $methodRep 2]
    set methodArgsStrs [list]
    set argsWires [getWireNamed $ports "args"]

    for {set idx 0} {$idx < [llength $methodArgsList]} {incr idx} {
        set argType [lindex $methodArgsList $idx]
        set argWireStruct [lindex $argsWires $idx]
        set wireName [getWireNamed $argWireStruct "port"]
        lappend methodArgsStrs "\['$argType', '$wireName'\]"
    }

    # get clock/reset information from ports
    set reset  [getWireNamed $ports "reset"]
    set clock  [getWireNamed $ports "clock"]    
    set ready  [getWireNamed $ports "ready"]
    set enable [getWireNamed $ports "enable"]
    set result [getWireNamed $ports "result"]


    # need to convert arg list to a string representation. 

    set methodArgsStr [join $methodArgsStrs ","]

    set methodRep "'$methodName': Method('$methodName', '$methodRet', {'reset': '$reset', 'clock': '$clock', 'ready': '$ready', 'enable': '$enable', 'result': '$result',  'args': \[$methodArgsStr\]})"
    #puts stderr "METHOD REP: $methodRep"
    return $methodRep
}


#
# Analyzes basic interfaces.  Basic interfaces have subinterface and methods, although 
# bluespec sometimes missnames interfaces as methods (Vector and inout, but possibly others)  
#
proc analyzeInterface { elem ifc ports methods} {
    #puts stderr "ELEM: $elem \n IFC: $ifc \n PORTS: $ports \n\n METHODS: $methods"
    set ifcName [lindex $ifc 0]
    set ifcType [lindex $ifc 1]
    set members [getMembers $ifc]
    
    set portsType [lindex $ports 0]
    set portsName [lindex $ports 1]
    set portsMembers [lindex $ports 2]

    set methodsMembers [lindex $methods 1]
    set methodsName [lindex $methods 0]

    #sanity check
    set compare [string compare $portsType "interface"]
    if {$compare != 0} {
        #puts stderr "WARNING: anyalzeInterface is not looking at interface port"
    }

    set memberList [list]
    # methods is analogous to type members. 
    
    for {set idx 0} {$idx < [llength $members]} {incr idx} { 
        set member [lindex $members $idx]
        set memberMethods [lindex $methodsMembers $idx]        
        set memberMethodsName [lindex $memberMethods 0]
         
        # if an interface have been optimized away, it won't be in the
        # port list. Check for this.
        set memberPorts [getInterfaceNamed $portsMembers $memberMethodsName]
        set compareExists [string compare $memberPorts ""]
        if {$compareExists == 0} {
            # this member has been optimized. Skip
            #puts stderr "WARNING: anyalzeInterface $memberMethodsName of interface $ifcName has been optimized away?"
            continue
        }

        set memberType [lindex $member 0]
        set memberPortType [lindex $memberPorts 0]

        #if either the type or the ports claim we're an interface, then we're an interface. 
        set compareType [string compare $memberType "interface"]
        set comparePort [string compare $memberPortType "interface"]
        #inouts also get handled this way.
        set compareInout [string compare $memberPortType "inout"]

        #puts stderr "\n\n HANDLING MEMBER: PARENTS PORTS: $ports \n\n MEMBER \n\nMember($memberType $compareType): $member\n MemberPorts($memberPortType $comparePort) $memberPorts"

        if {$compareInout == 0} { 
                 
            set inoutRep [lindex $member 1]
            #puts stderr "MEMBER: $member"
            #puts stderr "INOUT REP: $inoutRep"
            set memberType [lindex $member 1]
            set memberName [lindex $member 2]
            set memberPortsName  [lindex $memberPorts 1]

            set reset  [getWireNamed $memberPorts "reset"]
            set clock  [getWireNamed $memberPorts "clock"]    
            set port   [getWireNamed $memberPorts "port"]
                                    
            set memberRep "Prim_Inout('$memberType', '$memberPortsName', '$port', '$clock', '$reset')"
            #puts stderr "INOUT Returns: $memberName:$memberRep\n"
            lappend memberList "'$memberName': $memberRep"
        } else { 
            if {($compareType == 0) || ($comparePort == 0)} {
                #puts stderr "Analyzing method"
                set memberType [lindex $member 1]
                set memberName [lindex $member 2]
                #puts stderr "memberType: $memberType"
                #puts stderr "memberName: $memberName"
                # in the case that Type is method and Port is interface
                # the memberType will not be correct. Fix them here.
                if {$compareType != 0} {
                    set memberTypeNew [lindex $memberType 0]
                    set memberNameNew [lindex $memberType 1]
                    set memberType $memberTypeNew 
                    set memberName $memberNameNew 
                }
                set memberPortsName [lindex $memberPorts 1]    
                set compare [string compare $memberName  $memberPortsName]
                if {$compare != 0} {
                    #puts stderr "WARNING: $memberName and  $memberPortsName do not match"
                }     
               
                #puts stderr "memberType: $memberType"

                set obj [analyzeSwitch  $memberType $memberPorts $memberMethods]
                set memberRep [lindex $obj 1]
                lappend memberList "'$memberName': $memberRep"
            } else {
                set methodRep [lindex $member 1]

                # We need to analyze methodRet due to Bluespecs failure to 
                # use interfaces for vectors (and other stuff?)
                set methodRet [lindex $methodRep 0]
                set methodName [lindex $methodRep 1]
                lappend memberList "[analyzeMethod $member $memberPorts $memberMethods]"            
            }  

        }
    }
        
    #puts stderr "MEMBER LIST: $memberList"
    set memberDict [join $memberList ","]
    #puts stderr "MEMBER DICT: $memberDict"
    set retVal "Interface('$elem', '$portsName', {$memberDict})"
    #puts stderr "Returns: $retVal"
    return [list "Interface" $retVal]
}

###
### This is the entry point to the recursive interface analysis routine. 
### We load up the target module and then walk over its members.
### Finally we print out the interface's python representation.  
###

# Ports needs some massaging since the top level is not in a good format. 
# Methods are needed because ports seem to drop information. 
set modulePorts [module ports $moduleTarget]
#puts stderr "MODULE PORTS: $modulePorts"
set moduleMethods [module methods $moduleTarget]
set ifcMethods [list "top" $moduleMethods]
#puts stderr "MODULE METHODS: $moduleMethods"
set ifcList [getInterface $modulePorts]
set ifcPorts [list "interface" "top" $ifcList]
set ifc [module ifc $moduleTarget]

  
set finalIfc [analyzeSwitch $ifc $ifcPorts $ifcMethods]

#Print out the final python interface representation for capture.
puts [lindex $finalIfc 1]



