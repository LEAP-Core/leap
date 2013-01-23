//
// Copyright (C) 2011 Intel Corporation
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
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"
    
    
// ===================================================================
//
// STATISTICS INTERFACE
//
// mkCentralCacheStats --
//     Statistics callbacks from central cache class.
//
// ===================================================================


module [CONNECTED_MODULE] mkCentralCacheStats#(RL_CACHE_STATS cacheStats)
    // interface:
    ();

    // Disambiguate central caches on multiple platforms    
    String platform <- getSynthesisBoundaryPlatform();

    STAT_ID statIDs[9];

    statIDs[0] = statName("CENTRAL_CACHE_LOAD_HIT_" + platform,
                          "Central Cache: Load hits");
    let statLoadHit = 0;

    statIDs[1] = statName("CENTRAL_CACHE_LOAD_MISS_" + platform,
                          "Central Cache: Load misses");
    let statLoadMiss = 1;

    statIDs[2] = statName("CENTRAL_CACHE_STORE_HIT_" + platform,
                          "Central Cache: Store hits");
    let statStoreHit  = 2;

    statIDs[3] = statName("CENTRAL_CACHE_STORE_MISS_" + platform,
                          "Central Cache: Store misses");
    let statStoreMiss = 3;

    statIDs[4] = statName("CENTRAL_CACHE_INVAL_LINE_" + platform,
                          "Central Cache: Lines invalidated due to capacity");
    let statInvalEntry = 4;

    statIDs[5] = statName("CENTRAL_CACHE_DIRTY_LINE_FLUSH_" + platform,
                          "Central Cache: Dirty lines flushed to memory");
    let statDirtyEntryFlush = 5;

    statIDs[6] = statName("CENTRAL_CACHE_FORCE_INVAL_LINE_" + platform,
                          "Central Cache: Lines forcibly invalidated (not due to capacity)");
    let statForceInvalLine = 6;

    statIDs[7] = statName("CENTRAL_CACHE_LOAD_RECENT_LINE_HIT_" + platform,
                          "Central Cache: Load recent line cache hits");
    let statLoadRecentLineHit = 7;

    statIDs[8] = statName("CENTRAL_CACHE_LOAD_NEW_MRU_" + platform,
                          "Central Cache: Reference changed MRU way for valid entry (hit)");
    let statNewMRU = 8;

    STAT_VECTOR#(9) stats <- mkStatCounter_Vector(statIDs);

    rule readHit (cacheStats.readHit());
        stats.incr(statLoadHit);
    endrule

    rule readMiss (cacheStats.readMiss());
        stats.incr(statLoadMiss);
    endrule

    rule writeHit (cacheStats.writeHit());
        stats.incr(statStoreHit);
    endrule

    rule writeMiss (cacheStats.writeMiss());
        stats.incr(statStoreMiss);
    endrule

    rule invalEntry (cacheStats.invalEntry());
        stats.incr(statInvalEntry);
    endrule

    rule dirtyEntryFlush (cacheStats.dirtyEntryFlush());
        stats.incr(statDirtyEntryFlush);
    endrule

    rule forceInvalLine (cacheStats.forceInvalLine());
        stats.incr(statForceInvalLine);
    endrule

    rule recentLineReadHit (cacheStats.readRecentLineHit());
        stats.incr(statLoadRecentLineHit);
    endrule

    rule newMRU (cacheStats.newMRU());
        stats.incr(statNewMRU);
    endrule

endmodule
