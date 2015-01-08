##
## LEAP Vivado Clock Divider Library
##
##                            * * * * * * * * * *
## 
##  This library contains functions for annotating LEAP clock divider constructs 
##  with timing constraints. It is run only after all clocks have been defined and 
##  will gather all LEAP clock dividers in the system. 
## 
##                            * * * * * * * * * *


## This function annotates a clock divider with a derived clock signal 
proc annotateClockDivider {cell divisor} {

    # check inputs -- sometimes things may have been optimized away. 
    # we need to look for the source clock.  It will be on one of the pins. 
    set source_pin []
    foreach pin [get_pins -of_objects [get_cell $cell]] {
        set src_clock [get_clocks -of_objects $pin]
  
        if { [llength $src_clock] } {
            lappend source_pin $pin
        }
    }

    # Bluespec produces different code for half divisors.  Handle that here
    set pin_length [llength $source_pin]

    if { [llength $source_pin] != 1 } {
        set source_pin [lindex $source_pin 0]        
    } 

    # set the output to the highest cntr_reg we can find...
    # Since we support only up to divide by 4, this would be cntr_reg[1]
    set out_pin [get_pins [subst -nocommands "$cell/divider/cntr_reg[1]/Q"]]    

    if { [llength $out_pin] == 0 } {
        set out_pin [get_pins [subst -nocommands "$cell/divider/cntr[1]/Q"]]    
    } 

    if { [llength $out_pin] == 0 } {
        set out_pin [get_pins [subst -nocommands "$cell/divider/cntr_reg[0]/Q"]]    
    } 

    if { [llength $out_pin] == 0 } {
        set out_pin [get_pins [subst -nocommands "$cell/divider/cntr[0]/Q"]]    
    } 

    create_generated_clock -name "${cell}_div_clk" -divide_by $divisor -source $source_pin $out_pin
}


proc annotateClockDividers {refName divisor} {

    set clocks [get_cells -hier -regexp -filter "REF_NAME =~ $refName"]
    lappend clocks [get_cells -hier -regexp -filter "ORIG_REF_NAME =~ $refName"]
    foreach clock $clocks {
        annotateClockDivider $clock $divisor
    }

}

# Find and process all LEAP clock dividers.

annotateClockDividers "mkUserClock_DivideByTwo" 2
annotateClockDividers "mkUserClock_DivideByThree" 3
annotateClockDividers "mkUserClock_DivideByFour" 4




