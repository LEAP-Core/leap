##
## LEAP Vivado Reset Library
##
##                            * * * * * * * * * *
## 
##  This library contains functions for annotation of resets. 
## 
##                            * * * * * * * * * *


# This function is necessary to meet timing in low-fanout designs with device drivers.  The driver timing paths are 
# impossible to meet otherwise.

proc annotateAsyncReset {} {

    set resetCells [get_cells -hier -regexp -filter "ORIG_REF_NAME =~ mkUnoptimizableAsyncReset"]
    lappend resetCells [get_cells -hier -regexp -filter "REF_NAME =~ mkUnoptimizableAsyncReset"]
    if { [llength $resetCells] != 0 } { 
        set_property DONT_TOUCH true $resetCells
    }

}

puts "Included reset library \n"
annotateAsyncReset
