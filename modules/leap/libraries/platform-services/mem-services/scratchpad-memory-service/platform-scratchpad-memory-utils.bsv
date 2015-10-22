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
`include "awb/provides/stats_service.bsh"
`include "awb/provides/soft_connections.bsh"

//
// A type class which allows us to extract the ID of a datatype. 
// Although this is general, we currently only use it to extract 
// the port ID of scratchpad read metadata. 
//
typeclass ID#(type t_DATA, type t_ID)
    dependencies (t_DATA determines t_ID);

    function t_ID getID(t_DATA data);

endtypeclass

// SCRATCHPAD_STATS_CONSTRUCTOR

// A function to instantiate a stat tracker. Passed to the multi-cached-memory
// modules below.

typedef function CONNECTED_MODULE#(Empty) f(RL_CACHE_STATS#(t_READ_META) stats) SCRATCHPAD_STATS_CONSTRUCTOR#(type t_READ_META);
typedef function CONNECTED_MODULE#(Empty) f(RL_PREFETCH_STATS stats) SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR;

//
// mkBasicScratchpadCacheStats --
//     Shim between an RL_CACHE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicScratchpadCacheStats#(String tagPrefix,
                                                       String descPrefix,
                                                       RL_CACHE_STATS#(t_READ_META) stats)
    // interface:
    ();

    String tag_prefix = "LEAP_" + tagPrefix;

    STAT_ID statIDs[4] = {
        statName(tag_prefix + "SCRATCH_LOAD_HIT",
                 descPrefix + "Scratchpad load hits"),
        statName(tag_prefix + "SCRATCH_LOAD_MISS",
                 descPrefix + "Scratchpad load misses"),
        statName(tag_prefix + "SCRATCH_STORE_HIT",
                 descPrefix + "Scratchpad store hits"),
        statName(tag_prefix + "SCRATCH_STORE_MISS",
                 descPrefix + "Scratchpad store misses")
    };
    STAT_VECTOR#(4) sv <- mkStatCounter_Vector(statIDs);
    
    rule readHit (stats.readHit() matches tagged Valid .readMeta);
        sv.incr(0);
    endrule

    rule readMiss (stats.readMiss() matches tagged Valid .readMeta);
        sv.incr(1);
    endrule

    rule writeHit (stats.writeHit() matches tagged Valid .readMeta);
        sv.incr(2);
    endrule

    rule writeMiss (stats.writeMiss() matches tagged Valid .readMeta);
        sv.incr(3);
    endrule
endmodule

//
// mkBasicScratchpadCacheStats --
//     Shim between an RL_CACHE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkMultiportedScratchpadCacheStats#(NumTypeParam#(n_PORTS) ports,
                                                             String tagPrefix,
                                                             String descPrefix,
                                                             RL_CACHE_STATS#(t_READ_META) stats)
    // interface:
    ()

    provisos(ID#(t_READ_META, t_PORT_ID),
             Bits#(t_PORT_ID, t_PORT_ID_SZ));

    for(Integer i = 0; i < valueof(n_PORTS); i = i + 1)
    begin
        String tag_prefix = "LEAP_" + tagPrefix + "_port_" + integerToString(i) + "_";

        STAT_ID statIDs[4] = {
            statName(tag_prefix + "SCRATCH_LOAD_HIT",
                     descPrefix + "Scratchpad load hits"),
            statName(tag_prefix + "SCRATCH_LOAD_MISS",
                     descPrefix + "Scratchpad load misses"),
            statName(tag_prefix + "SCRATCH_STORE_HIT",
                     descPrefix + "Scratchpad store hits"),
            statName(tag_prefix + "SCRATCH_STORE_MISS",
                     descPrefix + "Scratchpad store misses")
        };
        STAT_VECTOR#(4) sv <- mkStatCounter_Vector(statIDs);
        
        rule readHit (stats.readHit() matches tagged Valid .readMeta &&& pack(getID(readMeta)) == fromInteger(i));
            sv.incr(0);
        endrule

        rule readMiss (stats.readMiss() matches tagged Valid .readMeta &&& pack(getID(readMeta)) == fromInteger(i));
            sv.incr(1);
        endrule

        rule writeHit (stats.writeHit() matches tagged Valid .readMeta &&& pack(getID(readMeta)) == fromInteger(i));
            sv.incr(2);
        endrule

        rule writeMiss (stats.writeMiss() matches tagged Valid .readMeta &&& pack(getID(readMeta)) == fromInteger(i));
            sv.incr(3);
        endrule
    end        
endmodule


module [CONNECTED_MODULE] mkNullScratchpadCacheStats#(RL_CACHE_STATS#(t_READ_META) stats)
    // interface:
    ();
endmodule


//
// mkBasicScratchpadPrefetchStats --
//     Shim between an RL_CACHE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicScratchpadPrefetchStats#(String tagPrefix,
                                                          String descPrefix,
                                                          NumTypeParam#(n_LEARNERS) dummy,
                                                          RL_PREFETCH_STATS stats)
    // interface:
    ()
    provisos( NumAlias#(TMul#(n_LEARNERS, 4), n_STATS),
              Add#(TMax#(TLog#(n_STATS),1), extraBits, TLog#(`STATS_MAX_VECTOR_LEN)));
    
    STAT_ID prefetchStatIDs[9];
    STAT_ID learnerStatIDs[ valueOf(n_STATS) ];

    String tag_prefix = "LEAP_" + tagPrefix;

    prefetchStatIDs[0] = statName(tag_prefix  + "SCRATCH_PREFETCH_HIT", 
                         descPrefix + "Scratchpad prefetch hits");
    prefetchStatIDs[1] = statName(tag_prefix  + "SCRATCH_PREFETCH_DROP_BUSY", 
                         descPrefix + "Scratchpad prefetch reqs dropped by busy");
    prefetchStatIDs[2] = statName(tag_prefix  + "SCRATCH_PREFETCH_DROP_HIT", 
                         descPrefix + "Scratchpad prefetch reqs dropped by hit");
    prefetchStatIDs[3] = statName(tag_prefix  + "SCRATCH_PREFETCH_LATE", 
                         descPrefix + "Scratchpad late prefetch reqs");
    prefetchStatIDs[4] = statName(tag_prefix  + "SCRATCH_PREFETCH_USELESS", 
                         descPrefix + "Scratchpad useless prefetch reqs");
    prefetchStatIDs[5] = statName(tag_prefix  + "SCRATCH_PREFETCH_ISSUE", 
                         descPrefix + "Scratchpad prefetch reqs issued");
    prefetchStatIDs[6] = statName(tag_prefix  + "SCRATCH_PREFETCH_LEARN", 
                         descPrefix + "Scratchpad prefetcher learns");
    prefetchStatIDs[7] = statName(tag_prefix  + "SCRATCH_PREFETCH_CONFLICT", 
                         descPrefix + "Scratchpad prefetch learner conflicts");
    prefetchStatIDs[8] = statName(tag_prefix  + "SCRATCH_PREFETCH_ILLEGAL", 
                         descPrefix + "Scratchpad uncacheable prefetch reqs");
    
    for (Integer i = 0; i < valueOf(n_LEARNERS); i = i+1)
    begin
        learnerStatIDs[0+4*i] = statName(tag_prefix  + "SCRATCH_PREFETCH_L"+integerToString(i)+"_HIT",
                                descPrefix + "Scratchpad prefetch learner "+integerToString(i)+" hits");
        learnerStatIDs[1+4*i] = statName(tag_prefix  + "SCRATCH_PREFETCH_L"+integerToString(i)+"_ISSUE", 
                                descPrefix + "Scratchpad prefetch reqs from learner "+integerToString(i));
        learnerStatIDs[2+4*i] = statName(tag_prefix  + "SCRATCH_PREFETCH_L"+integerToString(i)+"_STRIDE", 
                                descPrefix + "Scratchpad prefetch stride from learner "+integerToString(i));
        learnerStatIDs[3+4*i] = statName(tag_prefix  + "SCRATCH_PREFETCH_L"+integerToString(i)+"_LA_DIST", 
                                descPrefix + "Scratchpad prefetch lookahead dist from learner "+integerToString(i));
    end

    STAT_VECTOR#(9)       prefetchSv <- mkStatCounter_Vector(prefetchStatIDs);
    STAT_VECTOR#(n_STATS) learnerSv  <- mkStatCounter_Vector(learnerStatIDs);
    
    Reg#(Bool) prefetchHitR              <- mkReg(False);
    Reg#(Bool) prefetchDroppedByBusyR    <- mkReg(False);
    Reg#(Bool) prefetchDroppedByHitR     <- mkReg(False);
    Reg#(Bool) prefetchLateR             <- mkReg(False);
    Reg#(Bool) prefetchUselessR          <- mkReg(False);
    Reg#(Bool) prefetchIssuedR           <- mkReg(False);
    Reg#(Bool) prefetchLearnR            <- mkReg(False);
    Reg#(Bool) prefetchLearnerConflictR  <- mkReg(False);
    Reg#(Bool) prefetchIllegalReqR       <- mkReg(False);
    Reg#(Maybe#(PREFETCH_LEARNER_STATS)) hitLearnerInfoR <- mkReg(tagged Invalid);
    
    rule addPipeline (True);
        prefetchHitR              <= stats.prefetchHit();
        prefetchDroppedByHitR     <= stats.prefetchDroppedByHit();
        prefetchDroppedByBusyR    <= stats.prefetchDroppedByBusy();
        prefetchLateR             <= stats.prefetchLate();
        prefetchUselessR          <= stats.prefetchUseless();
        prefetchIssuedR           <= stats.prefetchIssued();
        prefetchLearnR            <= stats.prefetchLearn();
        prefetchLearnerConflictR  <= stats.prefetchLearnerConflict();
        prefetchIllegalReqR       <= stats.prefetchIllegalReq();
        hitLearnerInfoR           <= stats.hitLearnerInfo();
    endrule
   
    rule prefetchHit (prefetchHitR);
        prefetchSv.incr(0);
    endrule

    rule prefetchDroppedByBusy (prefetchDroppedByBusyR);
        prefetchSv.incr(1);
    endrule

    rule prefetchDroppedByHit (prefetchDroppedByHitR);
        prefetchSv.incr(2);
    endrule

    rule prefetchLate (prefetchLateR);
        prefetchSv.incr(3);
    endrule

    rule prefetchUseless (prefetchUselessR);
        prefetchSv.incr(4);
    endrule
    
    rule prefetchIssued (prefetchIssuedR);
        prefetchSv.incr(5);
    endrule
    
    rule prefetchLearn (prefetchLearnR);
        prefetchSv.incr(6);
    endrule
    
    rule prefetchLearnerConflict (prefetchLearnerConflictR);
        prefetchSv.incr(7);
    endrule

    rule prefetchIllegalReq (prefetchIllegalReqR);
        prefetchSv.incr(8);
    endrule

    rule hitLearnerUpdate (hitLearnerInfoR matches tagged Valid .s);
        learnerSv.incr(0+resize(s.idx)*4); //hitLeanerIdx
        if (s.isActive)                    //the learner is issuing prefetch request
        begin
            learnerSv.incr(1+resize(s.idx)*4);                         //activeLearnerIdx
            learnerSv.incrBy(2+resize(s.idx)*4, signExtend(s.stride)); //activeLearnerStride
            learnerSv.incrBy(3+resize(s.idx)*4, zeroExtend(s.laDist)); //activeLearnerLaDist
        end
    endrule

endmodule

module [CONNECTED_MODULE] mkNullScratchpadPrefetchStats#(RL_PREFETCH_STATS stats)
    // interface:
    ();
endmodule


//
// mkScratchpadHistogramStats --
//     Generate histogram stats for a given counter.
//
typedef 64 HISTOGRAM_STATS_NUM;

module [CONNECTED_MODULE] mkScratchpadHistogramStats#(String statTag,
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
// mkScratchpadQueueingDelayStats --
//     Generate queueing delay histogram stats for a given FIFO. 
//
// Maximum queueing delay
typedef 256 SCRATCHPAD_QUEUE_MAX_LATENCY;

module [CONNECTED_MODULE] mkScratchpadQueueingDelayStats#(String statTag,
                                                          String statDesc,
                                                          Maybe#(Integer) fifoSz, 
                                                          Bool enqEn, 
                                                          Bool deqEn)
    // interface:
    ()
    provisos(NumAlias#(TLog#(HISTOGRAM_STATS_NUM), n_STATS_LOG),
             Alias#(Bit#(TAdd#(TLog#(SCRATCHPAD_QUEUE_MAX_LATENCY), 1)), t_LATENCY));
    
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

