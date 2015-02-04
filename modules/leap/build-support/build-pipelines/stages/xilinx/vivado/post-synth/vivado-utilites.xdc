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

proc annotateBlackBox { cells } {

    if { [llength $cells] != 0 } { 
        set_property BLACK_BOX true $cells
    }

}


