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
    if {[llength $src_cells] && [llength $dst_cells]} {
        set dst_clock          [get_clocks -of_objects $dst_cells]
        set src_clock          [get_clocks -of_objects $src_cells]

        set dst_period         [get_property -min PERIOD $dst_clock]
        set src_period         [get_property -min PERIOD $src_clock]

        set min_clock          [::tcl::mathfunc::min $src_period $dst_period ]

        set_max_delay -from $src_clock -to $dst_cells -datapath_only $min_clock
        set_max_delay -from $dst_clock -to $src_cells -datapath_only $min_clock
    }
}


## This function annotates pairs of sets of cells as a safe (managed)
## clock crossing.
proc annotateSafeClockCrossing {src_cells dst_cells} {
    # check inputs -- sometimes things may have been optimized away.
    if {[llength $src_cells] && [llength $dst_cells]} {
        set dst_clock [get_clocks -of_objects $dst_cells]
        set src_clock [get_clocks -of_objects $src_cells]

        puts "Separating clocks ${src_clock} and ${dst_clock}"
        set_clock_groups -asynchronous -group $src_clock -group $dst_clock
    }
}


## Annotates the timing of a bluespec SyncFIFO.  This object correctly
## synchronizes communications between two clock domains.
proc annotateSyncFIFO {sync_object} {
    set sync_cell [get_cells -hier -filter "NAME =~ $sync_object"]

    # Find the source and destination clocks.  We use a few names in case any
    # names are changed during optimization.
    set src_cells     [get_cells -hier -filter "NAME =~ $sync_cell/sGEnqPtr*"]
    lappend src_cells [get_cells -hier -filter "NAME =~ $sync_cell/sSyncReg*"]

    set dst_cells     [get_cells -hier -filter "NAME =~ $sync_cell/dGDeqPtr*"]
    lappend dst_cells [get_cells -hier -filter "NAME =~ $sync_cell/dSyncReg*"]

    # Separate the clocks
    if {[llength $src_cells] && [llength $dst_cells]} {
        set src_clock [get_clocks -of_objects $src_cells]
        set dst_clock [get_clocks -of_objects $dst_cells]

        if {[llength $src_clock] && [llength $dst_clock]} {
            puts "Separating clocks ${src_clock} and ${dst_clock} for SyncFIFO ${sync_object}"
            set_clock_groups -asynchronous -group $src_clock -group $dst_clock
        }
    }
}


##
## Discover and then annotate all SyncFIFOs.
##
proc findAndAnnotateAllSyncFIFOs {} {
    # Loop over all SyncFIFOs, using a well-known register name in the source
    # clock domain.
    foreach fifo_src [get_cells sGEnqPtr1[0]* -hierarchical] {
        # Get the path to the SyncFIFO
        set fifo [regsub \[^/\]*$ $fifo_src ""]
        set fifo [string trimright $fifo /]

        annotateSyncFIFO $fifo
    }

    # The same for SyncFIFOLevel.
    foreach fifo_src [get_cells sGEnqPtr[0]* -hierarchical] {
        # Get the path to the SyncFIFO
        set fifo [regsub \[^/\]*$ $fifo_src ""]
        set fifo [string trimright $fifo /]

        annotateSyncFIFO $fifo
    }
}

####
##
## Discover and annotate all LEAP clock-crossing objects.
##
####

proc annotateLEAPCrossingRegister {crossing_object} {
    set crossing_cell [get_cells -hier -filter "NAME =~ $crossing_object"]

    # Find the source and destination clocks.  We use a few names in case any
    # names are changed during optimization.
    set src_cells     [get_cells -hier -filter "NAME =~ $crossing_cell/crossingRegSrc*"]
    set dst_cells     [get_cells -hier -filter "NAME =~ $crossing_cell/crossingRegDst*"]

    if {[llength $src_cells] && [llength $dst_cells]} {
        set src_clock [get_clocks -of_objects $src_cells]
        set dst_clock [get_clocks -of_objects $dst_cells]

        if {[llength $src_clock] && [llength $dst_clock]} {
            set_clock_groups -asynchronous -group $src_clock -group $dst_clock
        }
    }

    # During the synthesis pass, this prevents the tool chain from doing 
    # renaming on the object.
    set_property DONT_TOUCH true [get_cells "$crossing_object"] 

}

proc annotateLEAPCrossingRegisters {} {
    set clocks [get_cells -hier -regexp -filter "REF_NAME =~ leap_crossing_reg"]
    lappend clocks [get_cells -hier -regexp -filter "ORIG_REF_NAME =~ leap_crossing_reg"]
    foreach clock $clocks {
        annotateLEAPCrossingRegister $clock 
    }
}

annotateLEAPCrossingRegisters
