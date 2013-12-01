///
// Copyright (C) 2010 Intel Corporation
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/stats_service.bsh"
`include "awb/provides/soft_connections.bsh"


// COH_SCRATCH_STATS_CONSTRUCTOR

// A function to instantiate a stat tracker. Passed to the multi-cached-memory
// modules below.

typedef function CONNECTED_MODULE#(Empty) f(RL_COH_CACHE_STATS stats) COH_SCRATCH_STATS_CONSTRUCTOR;

//
// mkBasicCoherentScratchpadCacheStats --
//     Shim between an RL_COH_CACHE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicCoherentScratchpadCacheStats#(String tagPrefix,
                                                               String descPrefix,
                                                               RL_COH_CACHE_STATS stats)
    // interface:
    ();

    String tag_prefix = "LEAP_" + tagPrefix;

    STAT_ID statIDs[9] = {
        statName(tag_prefix + "COH_SCRATCH_LOAD_HIT",
                 descPrefix + "Coherent scratchpad load hits"),
        statName(tag_prefix + "COH_SCRATCH_LOAD_MISS",
                 descPrefix + "Coherent scratchpad load misses"),
        statName(tag_prefix + "COH_SCRATCH_STORE_HIT",
                 descPrefix + "Coherent scratchpad store hits"),
        statName(tag_prefix + "COH_SCRATCH_STORE_CACHELINE_MISS",
                 descPrefix + "Coherent scratchpad store cache-line misses"),
        statName(tag_prefix + "COH_SCRATCH_STORE_PERMISSION_MISS",
                 descPrefix + "Coherent scratchpad store permission misses"),
        statName(tag_prefix + "COH_SCRATCH_SELF_INVAL",
                 descPrefix + "Coherent scratchpad self invalidate"),
        statName(tag_prefix + "COH_SCRATCH_SELF_FLUSH",
                 descPrefix + "Coherent scratchpad self flush"),
        statName(tag_prefix + "COH_SCRATCH_COH_INVAL",
                 descPrefix + "Coherent scratchpad invalidate due to coherence"),
        statName(tag_prefix + "COH_SCRATCH_COH_FLUSH",
                 descPrefix + "Coherent scratchpad flush due to coherence")

    };
    STAT_VECTOR#(9) sv <- mkStatCounter_Vector(statIDs);
    
    rule readHit (stats.readHit());
        sv.incr(0);
    endrule

    rule readMiss (stats.readMiss());
        sv.incr(1);
    endrule

    rule writeHit (stats.writeHit());
        sv.incr(2);
    endrule

    rule writeCacheMiss (stats.writeCacheMiss());
        sv.incr(3);
    endrule

    rule writePermissionMiss (stats.writePermissionMiss());
        sv.incr(4);
    endrule

    rule invalEntry (stats.invalEntry());
        sv.incr(5);
    endrule

    rule dirtyEntryFlush (stats.dirtyEntryFlush());
        sv.incr(6);
    endrule

    rule coherenceInval (stats.coherenceInval());
        sv.incr(7);
    endrule

    rule coherenceFlush (stats.coherenceFlush());
        sv.incr(8);
    endrule

endmodule


module [CONNECTED_MODULE] mkNullCoherentScratchpadCacheStats#(RL_COH_CACHE_STATS stats)
    // interface:
    ();
endmodule

