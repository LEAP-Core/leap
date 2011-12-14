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

`include "awb/dict/STATS_CENTRAL_CACHE.bsh"
    
    
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
    
    Vector#(8, STATS_DICT_TYPE) statIDs = newVector();

    statIDs[0] = `STATS_CENTRAL_CACHE_CACHE_LOAD_HIT;
    let statLoadHit = 0;

    statIDs[1] = `STATS_CENTRAL_CACHE_CACHE_LOAD_MISS;
    let statLoadMiss = 1;

    statIDs[2] = `STATS_CENTRAL_CACHE_CACHE_STORE_HIT;
    let statStoreHit  = 2;

    statIDs[3] = `STATS_CENTRAL_CACHE_CACHE_STORE_MISS;
    let statStoreMiss = 3;

    statIDs[4] = `STATS_CENTRAL_CACHE_CACHE_INVAL_LINE;
    let statInvalEntry = 4;

    statIDs[5] = `STATS_CENTRAL_CACHE_CACHE_DIRTY_LINE_FLUSH;
    let statDirtyEntryFlush = 5;

    statIDs[6] = `STATS_CENTRAL_CACHE_CACHE_FORCE_INVAL_LINE;
    let statForceInvalLine = 6;

    statIDs[7] = `STATS_CENTRAL_CACHE_CACHE_LOAD_RECENT_LINE_HIT;
    let statLoadRecentLineHit = 7;

    let stats <- mkStatCounter_Vector(statIDs);

    //
    // fire_when_enabled and no_implicit_conditions pragmas confirm that
    // the statistics counting code is ready to fire whenever an incoming
    // statistics wire requests an update.
    //

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule readHit (cacheStats.readHit());
        stats.incr(statLoadHit);
    endrule

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule readMiss (cacheStats.readMiss());
        stats.incr(statLoadMiss);
    endrule

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule writeHit (cacheStats.writeHit());
        stats.incr(statStoreHit);
    endrule

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule writeMiss (cacheStats.writeMiss());
        stats.incr(statStoreMiss);
    endrule

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule invalEntry (cacheStats.invalEntry());
        stats.incr(statInvalEntry);
    endrule

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule dirtyEntryFlush (cacheStats.dirtyEntryFlush());
        stats.incr(statDirtyEntryFlush);
    endrule

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule forceInvalLine (cacheStats.forceInvalLine());
        stats.incr(statForceInvalLine);
    endrule

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule recentLineReadHit (cacheStats.readRecentLineHit());
        stats.incr(statLoadRecentLineHit);
    endrule

endmodule
