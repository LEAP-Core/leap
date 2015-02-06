##
## LEAP Vivado Timing Library
##
##                            * * * * * * * * * *
##
##  This library contains functions for annotating LEAP clock constructs with timing constraints.
##
##                            * * * * * * * * * *


## This function annotates pairs of sets of cells with a maximum
## timing delay equal to the miminimum clock period among the sets.
proc annotateClockCrossing {src_cells dst_cells} {

    # check inputs -- sometimes things may have been optimized away.

    if { [llength $src_cells] && [llength $dst_cells] } {

        set dst_clock          [get_clocks -of_objects $dst_cells]

        set src_clock          [get_clocks -of_objects $src_cells]

        set dst_period         [get_property -min PERIOD $dst_clock]

        set src_period         [get_property -min PERIOD $src_clock]

        set min_clock          [::tcl::mathfunc::min $src_period $dst_period ]

        set_max_delay -from $src_clock -to $dst_cells -datapath_only $min_clock
        set_max_delay -from $dst_clock -to $src_cells -datapath_only $min_clock
    }
}

## Annotates the timing of a bluespec SyncFIFO.  This object correctly
## synchronizes communications between two clock domains.

proc annotateSyncFIFO {sync_object} {
    set sync_cell [get_cells -hier -filter "NAME =~ $sync_object"]

    set path               [get_property NAME $sync_cell]
    set src_cells          [get_cells -hier -filter "NAME =~ $sync_cell/sGEnqPtr*"]
    lappend src_cells      [get_cells -hier -filter "NAME =~ $sync_cell/*fifoMem*"]
    lappend src_cells      [get_cells -hier -filter "NAME =~ $sync_cell/sSyncReg*"]
    lappend src_cells      [get_cells -hier -filter "NAME =~ $sync_cell/sNotFullReg*"]
    lappend src_cells      [get_cells -hier -filter "NAME =~ $sync_cell/sDeqPtr*"]

    set dst_cells          [get_cells -hier -filter "NAME =~ $sync_cell/dDoutReg*"]
    lappend dst_cells      [get_cells -hier -filter "NAME =~ $sync_cell/dGDeqPtr*"]
    lappend dst_cells      [get_cells -hier -filter "NAME =~ $sync_cell/dNotEmpty*"]
    lappend dst_cells      [get_cells -hier -filter "NAME =~ $sync_cell/dEnqPtr*"]
    lappend dst_cells      [get_cells -hier -filter "NAME =~ $sync_cell/dSyncReg*"]

    annotateClockCrossing $src_cells $dst_cells

#   The following syntax searches for SyncFIFOs, but does not work with synplify
#   if {[get_property ORIG_REF_NAME $sync_cell] == "SyncFIFO"} {
#   }

}
