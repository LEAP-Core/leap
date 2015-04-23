##
## LEAP Vivado Reset Library
##
##                            * * * * * * * * * *
## 
##  This library contains functions for annotation of resets. 
## 
##                            * * * * * * * * * *


##
## Keep all the resets in the design.  Vivado seems to try to merge resets
## that seem equivalent, even removing stages in a chain!
##
proc annotateAllAsyncResets {} {
    set resetCells [get_cells -hierarchical -filter "NAME =~ */asyncResetStage/reset_hold*"]
    if {[llength $resetCells] != 0} { 
        set_property DONT_TOUCH true $resetCells
        puts "Tagging AsyncReset ${resetCells}"

        # Don't enforce timing.  We will manage timing of the output of this reset
        # by chaining it with a synchronous reset.
        set_false_path -to $resetCells
    }
}

annotateAllAsyncResets
