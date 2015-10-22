//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

import FIFO::*;
import DReg::*;

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


module [CONNECTED_MODULE] mkCentralCacheStats#(RL_CACHE_STATS#(t_READ_META) cacheStats, Integer bankIdx)
    // interface:
    ();

    // Disambiguate central caches on multiple platforms    
    String platform <- getSynthesisBoundaryPlatform();

    String statsHeader = "LEAP_CENTRAL_CACHE_PLATFORM_" + platform + "_BANK_" + integerToString(bankIdx) + "_";

    STAT_ID statIDs[9];

    statIDs[0] = statName(statsHeader + "LOAD_HIT",
                          "Central Cache: Load hits");
    let statLoadHit = 0;

    statIDs[1] = statName(statsHeader + "LOAD_MISS",
                          "Central Cache: Load misses");
    let statLoadMiss = 1;

    statIDs[2] = statName(statsHeader + "STORE_HIT",
                          "Central Cache: Store hits");
    let statStoreHit  = 2;

    statIDs[3] = statName(statsHeader + "STORE_MISS",
                          "Central Cache: Store misses");
    let statStoreMiss = 3;

    statIDs[4] = statName(statsHeader + "INVAL_LINE",
                          "Central Cache: Lines invalidated due to capacity");
    let statInvalEntry = 4;

    statIDs[5] = statName(statsHeader + "DIRTY_LINE_FLUSH",
                          "Central Cache: Dirty lines flushed to memory");
    let statDirtyEntryFlush = 5;

    statIDs[6] = statName(statsHeader + "FORCE_INVAL_LINE",
                          "Central Cache: Lines forcibly invalidated (not due to capacity)");
    let statForceInvalLine = 6;

    statIDs[7] = statName(statsHeader + "LOAD_RECENT_LINE_HIT",
                          "Central Cache: Load recent line cache hits");
    let statLoadRecentLineHit = 7;

    statIDs[8] = statName(statsHeader + "LOAD_NEW_MRU",
                          "Central Cache: Reference changed MRU way for valid entry (hit)");
    let statNewMRU = 8;

    STAT_VECTOR#(9) stats <- mkStatCounter_Vector(statIDs);

    rule readHit (cacheStats.readHit() matches tagged Valid .meta);
        stats.incr(statLoadHit);
    endrule

    rule readMiss (cacheStats.readMiss() matches tagged Valid .meta);
        stats.incr(statLoadMiss);
    endrule

    rule writeHit (cacheStats.writeHit() matches tagged Valid .meta);
        stats.incr(statStoreHit);
    endrule

    rule writeMiss (cacheStats.writeMiss() matches tagged Valid .meta);
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

//
// mkCentralCacheHistogramStats --
//     Generate histogram stats for a given counter.
//
typedef 64 HISTOGRAM_STATS_NUM;

module [CONNECTED_MODULE] mkCentralCacheHistogramStats#(String statTag,
                                                        String statDesc,
                                                        Bit#(t_COUNTER_SZ) counter,
                                                        Bool counterEn)
    // interface:
    ()
    provisos(NumAlias#(TLog#(HISTOGRAM_STATS_NUM), n_STATS_LOG),
             NumAlias#(TMax#(t_COUNTER_SZ, n_STATS_LOG), t_MAX_COUNTER_SZ));
    
    STAT_ID statID = statName(statTag, statDesc);
    STAT_VECTOR#(HISTOGRAM_STATS_NUM) counterSv  <- mkStatCounter_RAM(statID);
    
    UInt#(n_STATS_LOG) maxStatIdx = maxBound;
    Reg#(Bit#(n_STATS_LOG)) statIdx <- mkRegU;
    Reg#(Bool) statEn  <- mkReg(False);
    
    function Bit#(n_STATS_LOG) getStatIdx(UInt#(t_MAX_COUNTER_SZ) val);
        return (val >= unpack(zeroExtend(pack(maxStatIdx))))? pack(maxStatIdx) : truncate(pack(val));
    endfunction

    rule addPipeline (True);
        statIdx <= getStatIdx(unpack(zeroExtend(counter)));
        statEn  <= counterEn;
    endrule

    rule counterIncr (statEn);
        counterSv.incr(statIdx);
    endrule

endmodule

//
// mkCentralCacheQueueingDelayStats --
//     Generate queueing delay histogram stats for a given FIFO. 
//
// Maximum queueing delay
typedef 256 CENTRAL_CACHE_QUEUE_MAX_LATENCY;

module [CONNECTED_MODULE] mkCentralCacheQueueingDelayStats#(String statTag,
                                                            String statDesc,
                                                            Maybe#(Integer) fifoSz, 
                                                            Bool enqEn, 
                                                            Bool deqEn)
    // interface:
    ()
    provisos(NumAlias#(TLog#(HISTOGRAM_STATS_NUM), n_STATS_LOG),
             Alias#(Bit#(TAdd#(TLog#(CENTRAL_CACHE_QUEUE_MAX_LATENCY), 1)), t_LATENCY));
    
    Reg#(t_LATENCY) current <- mkReg(0);
    Reg#(t_LATENCY) latencyReg <- mkDReg(0);
    
    STAT_ID statID = statName(statTag, statDesc);
    STAT_VECTOR#(HISTOGRAM_STATS_NUM) latencySv  <- mkStatCounter_RAM(statID);
    
    UInt#(n_STATS_LOG) maxStatIdx = maxBound;
    Reg#(Bit#(n_STATS_LOG)) statIdx <- mkRegU;
    Reg#(Bool) statEn  <- mkReg(False);
    
    function Bit#(n_STATS_LOG) getStatIdx(t_LATENCY val);
        return (val >= zeroExtend(pack(maxStatIdx)))? pack(maxStatIdx) : truncate(val);
    endfunction

    FIFO#(t_LATENCY) queue = ?;
    
    if (fifoSz matches tagged Valid .s)
    begin
        queue <- mkSizedFIFO(s);
    end
    else
    begin
        queue <- mkFIFO();
    end

    (* fire_when_enabled *)
    rule tickCurrent;
        current <= current + 1;
    endrule

    (* fire_when_enabled *)
    rule enqueueTimeStamp(enqEn);
        queue.enq(current); 
    endrule

    (* fire_when_enabled *)
    rule dequeueTimeStamp(deqEn);
        let stamp = queue.first();
        queue.deq();
        if (current > stamp)
        begin
            latencyReg <= (current - stamp);
        end
        else
        begin
            latencyReg <= (maxBound - stamp + current);
        end
    endrule
    
    (* fire_when_enabled *)
    rule addPipeline (True);
        statIdx <= getStatIdx(latencyReg>>2);
        statEn  <= (latencyReg != 0);
    endrule

    rule statsIncr (statEn);
        latencySv.incr(statIdx);
    endrule

endmodule
