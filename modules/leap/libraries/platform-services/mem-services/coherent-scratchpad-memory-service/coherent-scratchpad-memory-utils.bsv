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


// coherent scratchpad stats constructor

// A function to instantiate a stat tracker. Passed to the multi-cached-memory
// modules below.

typedef function CONNECTED_MODULE#(Empty) f(RL_COH_CACHE_STATS stats) COH_SCRATCH_CACHE_STATS_CONSTRUCTOR;
typedef function CONNECTED_MODULE#(Empty) f(COH_SCRATCH_CONTROLLER_STATS stats) COH_SCRATCH_CONTROLLER_STATS_CONSTRUCTOR;
typedef function CONNECTED_MODULE#(Empty) f(COH_SCRATCH_RING_NODE_STATS stats) COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR;

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

    STAT_ID statIDs[13] = {
        statName(tag_prefix + "COH_SCRATCH_LOAD_HIT",
                 descPrefix + "Coherent scratchpad load hits"),
        statName(tag_prefix + "COH_SCRATCH_LOAD_MISS",
                 descPrefix + "Coherent scratchpad load misses"),
        statName(tag_prefix + "COH_SCRATCH_STORE_HIT",
                 descPrefix + "Coherent scratchpad store hits"),
        statName(tag_prefix + "COH_SCRATCH_STORE_CACHELINE_MISS",
                 descPrefix + "Coherent scratchpad store cache-line misses"),
        statName(tag_prefix + "COH_SCRATCH_STORE_PERMISSION_MISS_S",
                 descPrefix + "Coherent scratchpad store permission misses from S state"),
        statName(tag_prefix + "COH_SCRATCH_STORE_PERMISSION_MISS_O",
                 descPrefix + "Coherent scratchpad store permission misses from O state"),
        statName(tag_prefix + "COH_SCRATCH_SELF_INVAL",
                 descPrefix + "Coherent scratchpad self invalidate"),
        statName(tag_prefix + "COH_SCRATCH_SELF_DIRTY_FLUSH",
                 descPrefix + "Coherent scratchpad self dirty flush due to capacity"),
        statName(tag_prefix + "COH_SCRATCH_SELF_CLEAN_FLUSH",
                 descPrefix + "Coherent scratchpad self clean flush due to capacity"),
        statName(tag_prefix + "COH_SCRATCH_COH_INVAL",
                 descPrefix + "Coherent scratchpad invalidate due to coherence"),
        statName(tag_prefix + "COH_SCRATCH_COH_FLUSH",
                 descPrefix + "Coherent scratchpad flush due to coherence"),
        statName(tag_prefix + "COH_SCRATCH_MSHR_RETRY",
                 descPrefix + "Coherent scratchpad cache retry due to unavailable mshr entry"),
        statName(tag_prefix + "COH_SCRATCH_GETX_RETRY",
                 descPrefix + "Coherent scratchpad resend GETX forced by other caches")

    };
    STAT_VECTOR#(13) sv <- mkStatCounter_Vector(statIDs);
    
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

    rule writePermissionMissS (stats.writePermissionMissS());
        sv.incr(4);
    endrule

    rule writePermissionMissO (stats.writePermissionMissO());
        sv.incr(5);
    endrule
    
    rule invalEntry (stats.invalEntry());
        sv.incr(6);
    endrule

    rule dirtyEntryFlush (stats.dirtyEntryFlush());
        sv.incr(7);
    endrule
    
    rule cleanEntryFlush (stats.cleanEntryFlush());
        sv.incr(8);
    endrule

    rule coherenceInval (stats.coherenceInval());
        sv.incr(9);
    endrule

    rule coherenceFlush (stats.coherenceFlush());
        sv.incr(10);
    endrule
    
    rule mshrRetry (stats.mshrRetry());
        sv.incr(11);
    endrule

    rule getxRetry (stats.getxRetry());
        sv.incr(12);
    endrule

endmodule

module [CONNECTED_MODULE] mkNullCoherentScratchpadCacheStats#(RL_COH_CACHE_STATS stats)
    // interface:
    ();
endmodule

//
// mkBasicCoherentScratchpadControllerStats --
//     Shim between an COH_SCRATCH_CONTROLLER_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicCoherentScratchpadControllerStats#(String tagPrefix,
                                                                    String descPrefix,
                                                                    COH_SCRATCH_CONTROLLER_STATS stats)
    // interface:
    ();

    String tag_prefix = "LEAP_" + tagPrefix;

    STAT_ID statIDs[10] = {
        statName(tag_prefix + "COH_SCRATCH_CTRLR_CLEAN_PUTX",
                 descPrefix + "Coherence controller clean putX received"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_DIRTY_PUTX",
                 descPrefix + "Coherence controller dirty putX received"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_GETS",
                 descPrefix + "Coherence controller getS received"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_GETX",
                 descPrefix + "Coherence controller getX received"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_WRITEBACK",
                 descPrefix + "Coherence controller write-back data received"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_OWNERBIT",
                 descPrefix + "Coherence controller ownerbit checkout"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_MEM_DATA",
                 descPrefix + "Coherence controller data received from memory"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_RESP_SENT",
                 descPrefix + "Coherence controller response sent"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_RETRY_PUT",
                 descPrefix + "Coherence controller retry put request"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_RETRY_GET",
                 descPrefix + "Coherence controller retry get request")
    };
    STAT_VECTOR#(10) sv <- mkStatCounter_Vector(statIDs);
    
    rule cleanPutxReceived (stats.cleanPutxReceived());
        sv.incr(0);
    endrule

    rule dirtyPutxReceived (stats.dirtyPutxReceived());
        sv.incr(1);
    endrule

    rule getsReceived (stats.getsReceived());
        sv.incr(2);
    endrule

    rule getxReceived (stats.getxReceived());
        sv.incr(3);
    endrule

    rule writebackReceived (stats.writebackReceived());
        sv.incr(4);
    endrule

    rule ownerbitCheckout (stats.ownerbitCheckout());
        sv.incr(5);
    endrule

    rule dataReceived (stats.dataReceived());
        sv.incr(6);
    endrule
    
    rule respSent (stats.respSent());
        sv.incr(7);
    endrule

    rule putRetry (stats.putRetry());
        sv.incr(8);
    endrule

    rule getRetry (stats.getRetry());
        sv.incr(9);
    endrule
    
endmodule

module [CONNECTED_MODULE] mkNullCoherentScratchpadControllerStats#(COH_SCRATCH_CONTROLLER_STATS stats)
    // interface:
    ();
endmodule

//
// mkBasicCoherentScratchpadRingNodeStats --
//     Shim between an COH_SCRATCH_RING_NODE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicCoherentScratchpadRingNodeStats#(String tagPrefix,
                                                                  String descPrefix,
                                                                  COH_SCRATCH_RING_NODE_STATS stats)
    // interface:
    ();

    String tag_prefix = "LEAP_" + tagPrefix;

    STAT_ID statIDs[3] = {
        statName(tag_prefix + "COH_SCRATCH_RING_NODE_LOCAL_SENT",
                 descPrefix + "Coherence scratchpad ring node local message sent"),
        statName(tag_prefix + "COH_SCRATCH_RING_NODE_FORWARD",
                 descPrefix + "Coherence scratchpad ring node forward message"),
        statName(tag_prefix + "COH_SCRATCH_RING_NODE_RECEIVED",
                 descPrefix + "Coherence scratchpad ring node message received")
    };
    STAT_VECTOR#(3) sv <- mkStatCounter_Vector(statIDs);
    
    rule localMsgSent (stats.localMsgSent());
        sv.incr(0);
    endrule

    rule fwdMsgSent (stats.fwdMsgSent() != 0);
        sv.incrBy(1, zeroExtend(stats.fwdMsgSent()));
    endrule

    rule msgReceived (stats.msgReceived());
        sv.incr(2);
    endrule
endmodule

module [CONNECTED_MODULE] mkNullCoherentScratchpadRingNodeStats#(COH_SCRATCH_RING_NODE_STATS stats)
    // interface:
    ();
endmodule

