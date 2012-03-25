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


// SCRATCHPAD_STATS_CONSTRUCTOR

// A function to instantiate a stat tracker. Passed to the multi-cached-memory
// modules below.

typedef function CONNECTED_MODULE#(Empty) f(RL_CACHE_STATS stats) SCRATCHPAD_STATS_CONSTRUCTOR;

//
// mkBasicScratchpadCacheStats --
//     Shim between an RL_CACHE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicScratchpadCacheStats#(String tagPrefix,
                                                       String descPrefix,
                                                       RL_CACHE_STATS stats)
    // interface:
    ();

    STAT_ID statIDs[4] = {
        statName(tagPrefix + "SCRATCH_LOAD_HIT",
                 descPrefix + "Scratchpad load hits"),
        statName(tagPrefix + "SCRATCH_LOAD_MISS",
                 descPrefix + "Scratchpad load misses"),
        statName(tagPrefix + "SCRATCH_STORE_HIT",
                 descPrefix + "Scratchpad store hits"),
        statName(tagPrefix + "SCRATCH_STORE_MISS",
                 descPrefix + "Scratchpad store misses")
    };
    STAT_VECTOR#(4) sv <- mkStatCounter_Vector(statIDs);
    
    rule readHit (stats.readHit());
        sv.incr(0);
    endrule

    rule readMiss (stats.readMiss());
        sv.incr(1);
    endrule

    rule writeHit (stats.writeHit());
        sv.incr(2);
    endrule

    rule writeMiss (stats.writeMiss());
        sv.incr(3);
    endrule
endmodule


module [CONNECTED_MODULE] mkNullScratchpadCacheStats#(RL_CACHE_STATS stats)
    // interface:
    ();
endmodule