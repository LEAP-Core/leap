##
## LEAP Vivado Area Library
##
##                            * * * * * * * * * *
## 
##  This library contains functions for obtaining information about design area utilization. 
## 
##                            * * * * * * * * * *


proc dumpPBlockUtilization {prefix} {
    set pblocks [get_pblocks]
    foreach pblock $pblocks {
        report_utilization -file "$prefix.$pblock" -pblock $pblock
    }
}

