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
proc annotateAsyncReset {} {
    set resetCells [get_cells -hierarchical -filter "NAME =~ */asyncResetStage/reset_hold*"]

    if {[llength $resetCells] != 0} { 
        set_property DONT_TOUCH true $resetCells
    }
}

puts "Included reset library \n"
annotateAsyncReset
