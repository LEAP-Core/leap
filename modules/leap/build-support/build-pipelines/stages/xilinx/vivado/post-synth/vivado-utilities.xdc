##
## LEAP Vivado Utilites Library
##
##                            * * * * * * * * * *
## 
##  This library contains functions useful in synthesis and place and route. 
## 
##                            * * * * * * * * * *


# This function is necessary to meet timing in low-fanout designs with device drivers.  The driver timing paths are 
# impossible to meet otherwise.

proc annotateBlackBox { cellName } {

    set cells [get_cells -hier -regexp -filter "NAME =~ $cellName"]
    if { [llength $cells] != 0 } { 
        set_property IS_BLACKBOX 1 $cells
    }

}

proc executePARConstraints { constraintsFunction objectName} {
    global IS_AREA_GROUP_BUILD 
    global IS_TOP_BUILD 
    global AG_OBJECT
   
    puts "Executing $constraintsFunction"

    if {[getAWBParams {"area_group_tool" "AREA_GROUPS_PAR_DEVICE_AG"}] == "1"} {
        if {$IS_AREA_GROUP_BUILD} {
            if {$AG_OBJECT == $objectName} {
                puts "Executing area group build"
                $constraintsFunction
            }
        }
        puts "Area group enabled, but not applying constraints"
    } 

    if {$IS_TOP_BUILD} {
        puts "Applying normal constraints function $constraintsFunction"
        # Just a normal build.  
        $constraintsFunction
    }
    

}


proc executeSynthConstraints { constraintsFunction objectName} {
    global SYNTH_OBJECT
    if {$SYNTH_OBJECT == $objectName} {
        $constraintsFunction
    }
}

# This is just an estimate used for the early stages of synthesis and place and
# route.  For the final place and route, it cannot be used.
proc annotateModelClockHelper { clk } {
    # get an estimate of the model clock frequency
    if { [llength [get_ports $clk]] } {
        set model_clock_freq [getAWBParams {"clocks_device" "MODEL_CLOCK_FREQ"}]
        set model_clock_period [expr double(1)/$model_clock_freq*1000]
        create_clock -name model_clock -period $model_clock_period [get_ports $clk]
        puts "Calling create clock.\n" 
    }
}

proc annotateModelClock {} {
    annotateModelClockHelper CLK
}

proc annotateCLK_SRC {} {

    global MODEL_CLK_BUFG

    # The -quiet below is something of a hack.  Some physical devices
    #  may already have CLK_SRC set.
    set_property -quiet HD.CLK_SRC $MODEL_CLK_BUFG [get_ports CLK]
    
}

##
## Function to find clock pins.
##
proc bindClockPin {clock_pin clock_wire} {
    set_property VCCAUX_IO DONTCARE $clock_wire
    #set_property IOSTANDARD DIFF_SSTL15 $clock_wire
    set_property PACKAGE_PIN $clock_pin $clock_wire
}
