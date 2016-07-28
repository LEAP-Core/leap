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

`include "awb/dict/PARAMS_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/dict/VDEV.bsh"

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
// mkMultiportedScratchpadCacheStats --
//     Shim between an RL_CACHE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.  This version tracks accesses across the several 
//     cache ports of a multiported cache.
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


interface SCRATCHPAD_MONITOR_IFC#(type t_MAF_IDX);
    method Action enqReadReq(SCRATCHPAD_READ_REQ req);
    method Action enqWriteReq(SCRATCHPAD_WRITE_REQ req);
    method Action enqWriteMaskedReq(SCRATCHPAD_WRITE_MASKED_REQ req);
    method Action enqReadRsp(t_MAF_IDX maf, SCRATCHPAD_READ_RSP rsp);
    method Bool   reqNotEmpty();
    method SCRATCHPAD_READ_RSP peekRsp();
    method ActionValue#(SCRATCHPAD_MEM_REQ) getReq();
    method ActionValue#(SCRATCHPAD_READ_RSP) getRsp();
endinterface: SCRATCHPAD_MONITOR_IFC

typedef 2048                SCRATCHPAD_READ_MAX_LATENCY;
typedef HISTOGRAM_STATS_NUM SCRATCHPAD_HISTOGRAM_STATS_NUM;

//
// Scratchpad performance monitor 
//
module [CONNECTED_MODULE] mkScratchpadMonitor#(Integer scratchpadID,
                                               NumTypeParam#(t_COUNTER_SZ) reqCounterSz,
                                               DEBUG_FILE debugLog)
    // interface:
    (SCRATCHPAD_MONITOR_IFC#(t_MAF_IDX))
    provisos (Bits#(SCRATCHPAD_MEM_ADDRESS, t_SCRATCHPAD_MEM_ADDRESS_SZ),
              Bits#(SCRATCHPAD_MEM_REQ, t_SCRATCHPAD_MEM_REQ_SZ), 
              Bits#(SCRATCHPAD_READ_RSP, t_SCRATCHPAD_READ_RSP_SZ), 
              Bits#(t_MAF_IDX, t_MAF_IDX_SZ),
              // Read latency
              Alias#(Bit#(TAdd#(TLog#(SCRATCHPAD_READ_MAX_LATENCY), 1)), t_LATENCY),
              NumAlias#(TLog#(SCRATCHPAD_HISTOGRAM_STATS_NUM), n_STATS_LOG));
    
    let platformID <- getSynthesisBoundaryPlatformID();
    
    STAT_ID statIDs[3];
    statIDs[0] = statName("LEAP_SCRATCHPAD_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_PLATFORM_" + integerToString(platformID) + "_READ_REQUESTS",
                          "Scratchpad read requests sent to the network");
    let statReadReq = 0;
    statIDs[1] = statName("LEAP_SCRATCHPAD_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_PLATFORM_" + integerToString(platformID) + "_WRITE_REQUESTS",
                          "Scratchpad write requests sent to the network");
    let statWriteReq = 1;
    statIDs[2] = statName("LEAP_SCRATCHPAD_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_PLATFORM_" + integerToString(platformID) + "_RESPONSES",
                          "Scratchpad responses received from the network");
    let statReadResp = 2;
    STAT_VECTOR#(3) stats <- mkStatCounter_Vector(statIDs);

    COUNTER#(t_COUNTER_SZ) readReqCounter <- mkLCounter(0);
    Reg#(Bool) readReqCounterEnabled <- mkReg(False); 
    
    mkCounterHistogramStats("LEAP_SCRATCHPAD_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_PLATFORM_" + integerToString(platformID) + "_READ_REQUESTS_INFLIGHT",
                            "Scratchpad inflight read requests", 
                            readReqCounter.value(), 
                            readReqCounterEnabled._read());
    
    // Set scratchpad network latency tests
    PARAMETER_NODE paramNode                     <- mkDynamicParameterNode();
    Reg#(Bool) latencyInitialized                <- mkReg(False);
    SCFIFOF#(SCRATCHPAD_MEM_REQ) latencyReqFifo  <- mkSCSizedFIFOF(4);
    FIFOF#(SCRATCHPAD_MEM_REQ)  bypassReqFifo    <- mkSizedBypassFIFOF(4);
    Param#(6) reqLatencyParam                    <- mkDynamicParameterFromStringInitialized("LEAP_SCRATCHPAD_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_REQ_NETWORK_EXTRA_LATENCY", 6'd0, paramNode);
    let reqDelayEn = (reqLatencyParam > 0);
    let reqFifo = (reqDelayEn)? latencyReqFifo.fifo : bypassReqFifo;
    
    SCFIFOF#(Tuple2#(t_MAF_IDX, SCRATCHPAD_READ_RSP)) latencyRspFifo  <- mkSCSizedFIFOF(4);
    FIFOF#(Tuple2#(t_MAF_IDX, SCRATCHPAD_READ_RSP))  bypassRspFifo    <- mkSizedBypassFIFOF(4);
    Param#(6) rspLatencyParam                                         <- mkDynamicParameterFromStringInitialized("LEAP_SCRATCHPAD_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_RSP_NETWORK_EXTRA_LATENCY", 6'd0, paramNode);
    let rspDelayEn = (rspLatencyParam > 0);
    let rspFifo = (rspDelayEn)? latencyRspFifo.fifo : bypassRspFifo;
    
    PulseWire fifoEnqW  <- mkPulseWire;
    PulseWire fifoDeqW  <- mkPulseWire;

    mkQueueingStats("LEAP_SCRATCHPAD_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_PLATFORM_" + integerToString(platformID) + "_NETWORK_REQUEST",
                    "Scratchpad network request", 
                    tagged Valid 4,
                    fifoEnqW, 
                    fifoDeqW, 
                    True);

    Reg#(Bool) initialized <- mkReg(False);
    
    rule doInit (!initialized);
        initialized <= True;
        if (reqDelayEn && reqLatencyParam > 1)
        begin
            latencyReqFifo.control.setControl(True);
            debugLog.record($format("Profiling: doInit: enable latencyReqFIFO, scratchpadID=%0d, delay=0x%x", scratchpadIntPortId(scratchpadID), reqLatencyParam));
        end
        if (rspDelayEn && rspLatencyParam > 1)
        begin
            latencyRspFifo.control.setControl(True);
            debugLog.record($format("Profiling: doInit: enable latencyRspFIFO, scratchpadID=%0d, delay=0x%x", scratchpadIntPortId(scratchpadID), rspLatencyParam));
        end
    endrule

    rule initLatency (!latencyInitialized && initialized);
        if (reqDelayEn && reqLatencyParam > 1)
        begin
            latencyReqFifo.control.setDelay(resize(pack(reqLatencyParam)-1));
        end
        if (rspDelayEn && rspLatencyParam > 1)
        begin
            latencyRspFifo.control.setDelay(resize(pack(rspLatencyParam)-1));
        end
        latencyInitialized <= True;
    endrule
    
    //
    // Tracking read latency
    //
    STAT_ID latencyStatID = statName("LEAP_SCRATCHPAD_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_PLATFORM_" + integerToString(platformID) + "_READ_MISS_LATENCY",
                            "Scratchpad read miss latency (unit: 4 cycles)");
    STAT_VECTOR#(HISTOGRAM_STATS_NUM) latencySv  <- mkStatCounter_RAM(latencyStatID);
    
    UInt#(n_STATS_LOG) maxStatIdx = maxBound;
    
    function Bit#(n_STATS_LOG) getStatIdx(t_LATENCY val);
        return (val >= zeroExtend(pack(maxStatIdx)))? pack(maxStatIdx) : truncate(val);
    endfunction
    
    Reg#(t_LATENCY)         latencyReg     <- mkDReg(0);
    Reg#(Bit#(n_STATS_LOG)) latencyStatIdx <- mkRegU;
    Reg#(Bool)              latencyStatEn  <- mkReg(False);
    
    MEMORY_IFC#(Bit#(t_MAF_IDX_SZ), t_LATENCY) reqStartCycleTable <- mkBRAMInitialized(0);
    
    Reg#(t_LATENCY) cycleCnt <- mkReg(0);
    FIFOF#(Tuple2#(Bit#(t_MAF_IDX_SZ), t_LATENCY)) readLatencyReqQ <- mkFIFOF();

    (* fire_when_enabled, no_implicit_conditions *)
    rule tickCurrent;
        cycleCnt <= cycleCnt + 1;
    endrule
    
    rule readLatencyLookup (True);
        match {.maf, .rsp_cycle} = readLatencyReqQ.first();
        readLatencyReqQ.deq();
        let req_cycle <- reqStartCycleTable.readRsp();
        let latency = (rsp_cycle >= req_cycle)? (rsp_cycle - req_cycle) : (maxBound - req_cycle + rsp_cycle);
        debugLog.record($format("Profiling: readLatencyLookup: maf=0x%x, latency=%0d", maf, latency));
        latencyReg <= latency; 
    endrule
    
    (* fire_when_enabled *)
    rule addPipeline (True);
        latencyStatIdx  <= getStatIdx(latencyReg>>2);
        latencyStatEn   <= (latencyReg != 0);
    endrule
    
    (* fire_when_enabled *)
    rule latencyStatsIncr (latencyStatEn);
        latencySv.incr(latencyStatIdx);
        debugLog.record($format("Profiling: latencyStatsIncr: idx=%0d", latencyStatIdx));
    endrule

    // ========================================================================
    // 
    //   Methods
    //
    // ========================================================================
    
    method Action enqReadReq(SCRATCHPAD_READ_REQ req) if (initialized && latencyInitialized);
        stats.incr(statReadReq);
        readReqCounter.up();
        readReqCounterEnabled <= True;
        reqFifo.enq(tagged SCRATCHPAD_MEM_READ req);
        fifoEnqW.send();
        reqStartCycleTable.write(truncateNP(pack(req.readUID)), cycleCnt);
        debugLog.record($format("Profiling: forwardReadReq: addr=0x%x, readUID=0x%x, read_cnt=%0d", 
                        req.addr, req.readUID, readReqCounter.value()));
    endmethod
    
    method Action enqWriteReq(SCRATCHPAD_WRITE_REQ req) if (initialized && latencyInitialized);
        stats.incr(statWriteReq);
        reqFifo.enq(tagged SCRATCHPAD_MEM_WRITE req);
        debugLog.record($format("Profiling: forwardWriteReq: addr=0x%x, val=0x%x", req.addr, req.val));
        fifoEnqW.send();
    endmethod
    
    method Action enqWriteMaskedReq(SCRATCHPAD_WRITE_MASKED_REQ req) if (initialized && latencyInitialized);
        stats.incr(statWriteReq);
        reqFifo.enq(tagged SCRATCHPAD_MEM_WRITE_MASKED req);
        debugLog.record($format("Profiling: forwardWriteMaskedReq: addr=0x%x, val=0x%x", req.addr, req.val));
        fifoEnqW.send();
    endmethod

    method Action enqReadRsp(t_MAF_IDX maf, SCRATCHPAD_READ_RSP rsp);
        rspFifo.enq(tuple2(maf, rsp));
        debugLog.record($format("Profiling: enqReadRsp: maf_idx=0x%x", maf)); 
    endmethod

    method Bool reqNotEmpty() = reqFifo.notEmpty();
    
    method ActionValue#(SCRATCHPAD_MEM_REQ) getReq() if (initialized && latencyInitialized);
        let req = reqFifo.first();
        reqFifo.deq();
        fifoDeqW.send();
        let addr = ?;
        if (req matches tagged SCRATCHPAD_MEM_READ .r)
        begin
            addr = r.addr;
        end
        else if (req matches tagged SCRATCHPAD_MEM_WRITE .w)
        begin
            addr = w.addr;
        end
        else if (req matches tagged SCRATCHPAD_MEM_WRITE_MASKED .mw)
        begin
            addr = mw.addr;
        end
        debugLog.record($format("Profiling: getReq: addr=0x%x", addr));
        return req;
    endmethod
    
    method ActionValue#(SCRATCHPAD_READ_RSP) getRsp() if (initialized && latencyInitialized);
        match {.maf, .rsp} = rspFifo.first();
        rspFifo.deq();
        stats.incr(statReadResp);
        readReqCounter.down();
        readLatencyReqQ.enq(tuple2(pack(maf), cycleCnt));
        reqStartCycleTable.readReq(pack(maf));
        debugLog.record($format("Profiling: getReadRsp: maf_idx=0x%x, read_cnt=%0d",
                        maf, readReqCounter.value()));
        return rsp;
    endmethod
    
    method SCRATCHPAD_READ_RSP peekRsp() if (initialized && latencyInitialized);
        return tpl_2(rspFifo.first());
    endmethod

endmodule


interface SCRATCHPAD_SCOREBOARD_VEC_MONITOR_IFC#(numeric type n_READERS, 
                                                 type t_SCOREBOARD_ENTRY_ID);
    interface Vector#(n_READERS, SCRATCHPAD_SCOREBOARD_MONITOR_IFC#(t_SCOREBOARD_ENTRY_ID)) scoreboards;
endinterface: SCRATCHPAD_SCOREBOARD_VEC_MONITOR_IFC

interface SCRATCHPAD_SCOREBOARD_MONITOR_IFC#(type t_SCOREBOARD_ENTRY_ID);
    method Action setValue(t_SCOREBOARD_ENTRY_ID id);
    method Action deq();
    method Maybe#(STAT_VALUE) waitCycleStatInfo();
endinterface: SCRATCHPAD_SCOREBOARD_MONITOR_IFC

//
// Scratchpad scoreboard FIFO performance monitor 
//
module [CONNECTED_MODULE] mkScratchpadScoreboardVecMonitor#(Integer scratchpadID,
                                                            Vector#(n_READERS, t_SCOREBOARD_ENTRY_ID) deqEntryIds,
                                                            Vector#(n_READERS, Bool) emptySignals,
                                                            DEBUG_FILE debugLog)
    // interface:
    (SCRATCHPAD_SCOREBOARD_VEC_MONITOR_IFC#(n_READERS, t_SCOREBOARD_ENTRY_ID))
    provisos (Bits#(t_SCOREBOARD_ENTRY_ID, t_SCOREBOARD_ENTRY_ID_SZ));

    // Instantiate scoreboard monitors
    function ActionValue#(SCRATCHPAD_SCOREBOARD_MONITOR_IFC#(t_SCOREBOARD_ENTRY_ID)) doCurryDebugScoreboardMonitor(x, y, id);
        actionvalue
            let m <- mkScratchpadScoreboardMonitor(x, y, id, debugLog);
            return m;
        endactionvalue
    endfunction
    
    Vector#(n_READERS, SCRATCHPAD_SCOREBOARD_MONITOR_IFC#(t_SCOREBOARD_ENTRY_ID)) monitors <- 
        zipWith3M(doCurryDebugScoreboardMonitor, deqEntryIds, emptySignals, genVector());
    
    // Tracking waiting cycles
    
    let platformID <- getSynthesisBoundaryPlatformID();
    
    STAT_ID waitStatID = statName("LEAP_SCRATCHPAD_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_PLATFORM_" + integerToString(platformID) + "_SCOREBOARD_WAITING_TIME",
                                     "Scratchpad scoreboard waiting time when later responses are ready");
    STAT waitStat <- mkStatCounter(waitStatID); 
    Reg#(STAT_VALUE) waitStatValue <- mkDReg(unpack(0));
   
    function hasStats(SCRATCHPAD_SCOREBOARD_MONITOR_IFC#(t_SCOREBOARD_ENTRY_ID) monitor) = isValid(monitor.waitCycleStatInfo());
    Vector#(TMax#(1, n_READERS), Bool) hasStatsVec =  unpack(zeroExtendNP(pack(map(hasStats,monitors))));
  
    (* fire_when_enabled *)
    rule gatherWaitStats (fold(\|| , hasStatsVec));
        let port = fromMaybe(0,findElem(True, hasStatsVec));
        if (monitors[port].waitCycleStatInfo() matches tagged Valid .w)
        begin
            waitStatValue <= w;
        end
    endrule

    (* fire_when_enabled *)
    rule waitStatsIncr (waitStatValue > 0);
        waitStat.incrBy(waitStatValue);
        debugLog.record($format("waitStatsIncr: incr=%0d", waitStatValue));
    endrule

    Vector#(n_READERS, SCRATCHPAD_SCOREBOARD_MONITOR_IFC#(t_SCOREBOARD_ENTRY_ID)) portsLocal = newVector();

    for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface SCRATCHPAD_SCOREBOARD_MONITOR_IFC#(t_SCOREBOARD_ENTRY_ID);
                method Action setValue(t_SCOREBOARD_ENTRY_ID id);
                    monitors[p].setValue(id); 
                endmethod
                method Action deq();
                    monitors[p].deq();
                endmethod
            endinterface;
    end

    interface scoreboards = portsLocal;

endmodule

module [CONNECTED_MODULE] mkScratchpadScoreboardMonitor#(t_SCOREBOARD_ENTRY_ID deqEntryId,
                                                         Bool emptySignal,
                                                         Integer monitorId,
                                                         DEBUG_FILE debugLog)
    // interface:
    (SCRATCHPAD_SCOREBOARD_MONITOR_IFC#(t_SCOREBOARD_ENTRY_ID))
    provisos (Bits#(t_SCOREBOARD_ENTRY_ID, t_SCOREBOARD_ENTRY_ID_SZ));
    
    Reg#(Bit#(16))                      waitCycleCnt   <- mkReg(0);
    Reg#(Bool)                          isWaiting      <- mkReg(False);
    Reg#(Maybe#(t_SCOREBOARD_ENTRY_ID)) preSetEntry    <- mkReg(tagged Invalid);
    RWire#(t_SCOREBOARD_ENTRY_ID)       newValue       <- mkRWire(); 
    RWire#(STAT_VALUE)                  waitStatValue  <- mkRWire();
    PulseWire                           readerActive   <- mkPulseWire;
    PulseWire                           deqPresetEntry <- mkPulseWire;
    PulseWire                           deqW           <- mkPulseWire;
    
    (* fire_when_enabled *)
    rule updOnDelayedNewValue (newValue.wget() matches tagged Valid .v &&& pack(v) == pack(deqEntryId) &&& isWaiting);
        readerActive.send();
        waitStatValue.wset(unpack(resize(waitCycleCnt)));
        waitCycleCnt <= 0;
        isWaiting <= False;
    endrule
        
    (* fire_when_enabled *)
    rule updOnNewValue (newValue.wget() matches tagged Valid .v &&& pack(v) != pack(deqEntryId) &&& emptySignal);
        readerActive.send();
        preSetEntry <= tagged Valid v;
        if (isWaiting)
        begin
            waitCycleCnt <= waitCycleCnt + 1;
            debugLog.record($format("Profiling: scoreboard: port=%0d, setEntryId=%0d, deqEntryId=%0d, waitCycleCnt=%0d",
                            monitorId, pack(v), pack(deqEntryId), waitCycleCnt+1));
        end
        else
        begin
            isWaiting <= True;
            debugLog.record($format("Profiling: scoreboard: port=%0d, setEntryId=%0d, deqEntryId=%0d, startWaiting...", 
                            monitorId, pack(v), pack(deqEntryId)));
        end
    endrule
    
    (* fire_when_enabled *)
    rule checkDeqPresetEntry (preSetEntry matches tagged Valid .e &&& pack(e) == pack(deqEntryId));
        deqPresetEntry.send();
    endrule

    (* mutually_exclusive = "updOnNewValue, resetEntry" *)
    (* fire_when_enabled *)
    rule resetEntry (deqW && deqPresetEntry);
        preSetEntry <= tagged Invalid;
        debugLog.record($format("Profiling: scoreboard: port=%0d, reset preSetEntryId=%0d", 
                        monitorId, pack(fromMaybe(unpack(0), preSetEntry))));
    endrule

    (* mutually_exclusive = "incrWaitCnt, updOnNewValue, updOnDelayedNewValue" *)
    (* fire_when_enabled *)
    rule incrWaitCnt (!readerActive);
        if (emptySignal && isValid(preSetEntry) && !isWaiting)
        begin
            isWaiting <= True;
            debugLog.record($format("Profiling: scoreboard: port=%0d, preSetEntryId=%0d, deqEntryId=%0d, startWaiting...", 
                            monitorId, pack(fromMaybe(unpack(0),preSetEntry)), pack(deqEntryId)));
        end
        if (isWaiting)
        begin
            waitCycleCnt <= waitCycleCnt + 1;
            debugLog.record($format("Profiling: scoreboard: port=%0d, deqEntryId=%0d, waitCycleCnt=%0d",
                            monitorId, pack(deqEntryId), waitCycleCnt+1));
        end
    endrule
   
    method Action setValue(t_SCOREBOARD_ENTRY_ID id);
        newValue.wset(id);
    endmethod
    
    method Action deq();
        deqW.send();
    endmethod

    method Maybe#(STAT_VALUE) waitCycleStatInfo() = waitStatValue.wget();

endmodule

