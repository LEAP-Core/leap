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

//
// Cache prefetcher.
// The prefetcher instance is sent as a module argument of the 
// higher level cache
//

// Library imports.

import FIFO::*;
import SpecialFIFOs::*;
import FIFOLevel::*;
// Project foundation imports.

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/fpga_components.bsh"

// ===================================================================
//
// PUBLIC DATA STRUCTURES
//
// ===================================================================

//
// Prefetch request priority
//
typedef enum
{
    PREFETCH_PRIO_LOW     = 0,
    PREFETCH_PRIO_HIGH    = 1
}
PREFETCH_PRIO
    deriving (Eq, Bits);

typedef struct
{
    Bool            defaultOverride;
    PREFETCH_PRIO   prio;
}
PREFETCH_PRIO_SPEC
    deriving (Eq,Bits);

//
// Prefetch mode
//
typedef enum
{
    PREFETCH_BASIC_TAGGED = 0,                   //prefetch on miss/prefetch hit, stride fixed
    PREFETCH_STRIDE_LEARN_ON_MISS = 1,           //learn only on read miss, prefetch on miss
    PREFETCH_STRIDE_LEARN_ON_ORIGINAL_MISS = 2,  //learn on original cache read miss (it can be read miss/prefetch hit/blocked req), prefetch on miss/prefetch hit/blocked req
    PREFETCH_STRIDE_HYBRID = 3                   //learn on read miss/hit and prefetch on miss/prefetch hit
}
PREFETCH_MODE
    deriving (Eq, Bits);

   
//    
// Number of prefetch learners (in log) 
// (used in dynamic parameter settings)
//
typedef UInt#(4) PREFETCH_LEARNER_SIZE_LOG;

// Prefetch lookahead distance
typedef UInt#(4) PREFETCH_DIST;
typedef Bit#(4)  PREFETCH_DIST_PARAM;

// Prefetch stats type
// typedef STAT_VALUE PREFETCH_STAT_VALUE
// typedef STAT_VECTOR_INDEX PREFETCH_STAT_IDX
typedef Bit#(9)  PREFETCH_STAT_IDX;
typedef Bit#(16) PREFETCH_STAT_VALUE;

//
// Prefetch request
//
typedef struct
{
    t_CACHE_ADDR addr;
    t_CACHE_READ_META readMeta;
    PREFETCH_PRIO prio;
}
PREFETCH_REQ#(type t_CACHE_ADDR,
              type t_CACHE_READ_META)
    deriving (Eq, Bits);

//
// Prefetch learner stats
//
typedef struct
{
    PREFETCH_STAT_IDX    idx;   
    Bool                 isActive;
    PREFETCH_STAT_VALUE  stride;
    PREFETCH_STAT_VALUE  laDist;
}
PREFETCH_LEARNER_STATS
    deriving (Eq, Bits);

//
// Prefetcher interface.
//
interface CACHE_PREFETCHER#(type t_CACHE_IDX,
                            type t_CACHE_ADDR,
                            type t_CACHE_READ_META);
    
    method Action setPrefetchMode(Tuple2#(PREFETCH_MODE, PREFETCH_DIST_PARAM) mode, PREFETCH_LEARNER_SIZE_LOG size, PREFETCH_PRIO_SPEC prioSpec);
    
    // Return true if the prefetch request queue is not empty
    method Bool hasReq();
    
    // Return a read request to prefetch a word (from the prefetch request queue)
    method ActionValue#(PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_READ_META)) getReq();
    method PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_READ_META) peekReq();
   
    // Allow external user to remove stale prefetches if the prefetcher gets full. 
    method Bool prefetcherNearlyFull();
    
    //
    // Learn the prefetch mechanism 
    //
    // Cache provides hit/miss information
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr);
    method Action readMiss(t_CACHE_IDX idx,
                           t_CACHE_ADDR addr,
                           Bool isPrefetch,
                           t_CACHE_READ_META readMeta);
    // Prefetch status reset by write/invalid reqeust
    method Action prefetchInval(t_CACHE_IDX idx);
    // Cache request is blocked by the busy cache line (may due to prefetch request)
    method Action shuntNewCacheReq(t_CACHE_IDX idx, t_CACHE_ADDR addr);
    // Fill response received
    method Action fillResp(t_CACHE_IDX idx,
                           t_CACHE_ADDR addr,
                           Bool isPrefetch,
                           t_CACHE_READ_META readMeta);

    //
    // Collect prefetch stats and update prefetch tag/busy bits
    //
    method Action prefetchDroppedByBusy(t_CACHE_ADDR addr);
    method Action prefetchDroppedByHit();
    method Action prefetchIllegalReq();

    interface RL_PREFETCH_STATS stats;
    
endinterface: CACHE_PREFETCHER

// ===================================================================
//
// Internal types
//
// ===================================================================

// Prefetch size (# prefetch requests)
typedef UInt#(2) PREFETCH_SIZE;

// Size of prefetch buffer.  Has some impact on Low-priority performance
typedef 4 PREFETCH_BUF_SIZE;

typedef 2 PREFETCH_BUF_NEARLY_FULL;

// Prefetch learner index
typedef UInt#(n_IDX_BITS) PREFETCH_LEARNER_IDX#(numeric type n_IDX_BITS);

// Prefetch Stride
typedef Int#(n_STRIDE_BITS) PREFETCH_STRIDE#(numeric type n_STRIDE_BITS);

//
// Prefetch request source (from leaner)
//
typedef struct
{
    t_CACHE_ADDR addr;
    PREFETCH_STRIDE#(SizeOf#(t_CACHE_ADDR)) stride;
    PREFETCH_DIST laDist;
}
PREFETCH_REQ_SOURCE#(type t_CACHE_ADDR)
    deriving (Eq, Bits);    

//
// Prefetch status for each cache line
//
// 1: the cache line is (going to be) filled by the prefetch 
//    request and has not been accessed yet
// 0: otherwise
typedef Bit#(1) PREFETCH_STATUS;    

//
// For stream prefetcher
//
// Stream prefetcher state
typedef enum
{
    STREAMER_INIT,
    STREAMER_TRANSIENT,
    STREAMER_STEADY,
    STREAMER_NO_PREDICT
}
PREFETCH_STREAMER_STATE
    deriving (Eq, Bits);

// Prefetch streamer    
typedef struct
{
    t_STREAMER_TAG          tag;
    t_STREAMER_ADDR         preAddr;
    t_STREAMER_STRIDE       stride;
    PREFETCH_STREAMER_STATE state;
    PREFETCH_DIST           laDist;
}
PREFETCH_STREAMER#(type t_STREAMER_TAG,
                   type t_STREAMER_ADDR,
                   type t_STREAMER_STRIDE)
    deriving (Eq, Bits);
   
// Prefetch learner request
typedef enum
{
    PREFETCH_ACT_LEARN        = 0, // update learner 
    PREFETCH_ACT_HALF_LEARN   = 1, // update learner on correct prediction
    PREFETCH_ACT_UPDATE_DIST  = 2  // update look ahead distance
}
PREFETCH_LEARNER_ACTION
    deriving (Eq, Bits);

typedef struct
{
    t_LEARNER_IDX            idx;
    t_LEARNER_TAG            tag;
    t_LEARNER_ADDR           curAddr;
    t_CACHE_ADDR             cacheAddr;
    PREFETCH_LEARNER_ACTION  act;
    Bool                     reqGen;
}
PREFETCH_LEARNER_REQ#(type t_LEARNER_IDX, 
                      type t_LEARNER_TAG,
                      type t_LEARNER_ADDR,
                      type t_CACHE_ADDR)
    deriving (Eq, Bits);

// ===================================================================
//
// Default Values
//
// ===================================================================

// Prefetch default size (-1)
`define PREFETCH_DEFAULT_SIZE 0
// Prefetch default stride
`define PREFETCH_DEFAULT_STRIDE 1
// Prefetch default distance
`define PREFETCH_DEFAULT_DIST 1
// Prefetch default priority
`define PREFETCH_DEFAULT_PRIO PREFETCH_PRIO_LOW

// ===================================================================
//
// Prefetcher implementation
//
// ===================================================================

//
// mkCachePrefetcher 
//
module mkCachePrefetcher#(NumTypeParam#(n_LEARNERS) dummy, Bool hashAddresses, Bool usingBRAM, DEBUG_FILE debugLog)
    // interface:
    (CACHE_PREFETCHER#(t_CACHE_IDX, t_CACHE_ADDR, t_CACHE_READ_META))
    provisos (Bits#(t_CACHE_IDX,      t_CACHE_IDX_SZ),
              Bits#(t_CACHE_ADDR,     t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),
              Alias#(PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_READ_META), t_PREFETCH_REQ),
              Alias#(PREFETCH_STRIDE#(t_CACHE_ADDR_SZ), t_STRIDE),
              Bits#(t_PREFETCH_REQ,   t_PREFETCH_REQ_SZ),
              Bounded#(t_CACHE_IDX));
    
    // Prefetch request queue
    FIFOCountIfc#(t_PREFETCH_REQ, PREFETCH_BUF_SIZE) prefetchReqQ <- mkFIFOCount();

    // Number of words to prefetch
    Reg#(PREFETCH_SIZE) prefetchNum <- mkReg(`PREFETCH_DEFAULT_SIZE);
    
    // Prefetch stride 
    Reg#(t_STRIDE) prefetchStride <- mkReg(unpack(`PREFETCH_DEFAULT_STRIDE));
    
    // Prefetch distance
    Reg#(PREFETCH_DIST) prefetchDist <- mkReg(unpack(`PREFETCH_DEFAULT_DIST));

    // Prefetch address
    Reg#(t_CACHE_ADDR) prefetchAddr <- mkReg(unpack(0));

    // Prefetch priority
    Reg#(PREFETCH_PRIO) prefetchPriority <- mkReg(`PREFETCH_DEFAULT_PRIO);

    PulseWire startPrefetch <- mkPulseWire();
    
    // Wires for communicating stats
    PulseWire prefetchDroppedByBusyW <- mkPulseWire();
    PulseWire prefetchDroppedByHitW  <- mkPulseWire();
    PulseWire prefetchIssuedW        <- mkPulseWire();
    PulseWire prefetchIllegalReqW    <- mkPulseWire();

    // Prefetch learner
    CACHE_PREFETCH_LEARNER#(t_CACHE_IDX, t_CACHE_ADDR) learner <- mkCachePrefetchStrideLearnerDynamic(dummy, hashAddresses, usingBRAM, debugLog);
    // CACHE_PREFETCH_LEARNER#(t_CACHE_IDX, t_CACHE_ADDR) learner <- mkCachePrefetchStrideLearner(dummy, hashAddresses, usingBRAM, debugLog);
    
    rule createPrefetchReq (True);
        t_CACHE_ADDR new_addr;
        t_CACHE_ADDR diff_addr;
        if (prefetchNum == 0)
        begin
            let req_source <- learner.getReqSource();
            prefetchStride <= req_source.stride;
            prefetchDist   <= req_source.laDist;
            diff_addr = unpack(pack(req_source.stride)*zeroExtendNP(pack(req_source.laDist)));
            new_addr  = unpack(pack(req_source.addr) + pack(diff_addr));
            debugLog.record($format(" generate prefetch req: addr=0x%x (base_addr:0x%x, stride:0x%x, dist:0x%x)", new_addr, req_source.addr, req_source.stride, req_source.laDist));
        end
        else
        begin
            diff_addr = unpack(pack(prefetchStride)*zeroExtendNP(pack(prefetchDist)));
            new_addr = unpack(pack(prefetchAddr) + pack(diff_addr));
            debugLog.record($format(" generate prefetch req: addr=0x%x (base_addr:0x%x, stride:0x%x, dist:0x%x)", new_addr, prefetchAddr, prefetchStride, prefetchDist));
        end
        prefetchAddr <= new_addr;
        let req = PREFETCH_REQ { addr: new_addr, 
                                 readMeta: ?,
                                 prio: prefetchPriority };
        prefetchReqQ.enq(req);
        startPrefetch.send();
        prefetchIssuedW.send();
    endrule
    
    rule updatePrefetchNum (startPrefetch);
        prefetchNum <= ( prefetchNum == `PREFETCH_DEFAULT_SIZE ) ? 0 : prefetchNum + 1;
    endrule
        
    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action setPrefetchMode(Tuple2#(PREFETCH_MODE, PREFETCH_DIST_PARAM) mode, PREFETCH_LEARNER_SIZE_LOG size, PREFETCH_PRIO_SPEC prioSpec);
        match {.prefetch_type, .prefetch_dist} = mode; 
        learner.setLearnerLookaheadDist(prefetch_dist);
        learner.setLearnerSize(size);
        learner.setLearnerMode(prefetch_type);
        if(prioSpec.defaultOverride)
        begin
            prefetchPriority <= prioSpec.prio;
        end
    endmethod

    method Bool hasReq() = prefetchReqQ.notEmpty;

    method Bool prefetcherNearlyFull() = prefetchReqQ.count() > fromInteger(valueof(PREFETCH_BUF_SIZE) - valueof(PREFETCH_BUF_NEARLY_FULL));
 
    method ActionValue#(PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_READ_META)) getReq();
        let req = prefetchReqQ.first();
        prefetchReqQ.deq();
        return req;
    endmethod
    
    method PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_READ_META) peekReq();
        return prefetchReqQ.first();
    endmethod
        
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr) = learner.readHit(idx, addr);
    method Action readMiss(t_CACHE_IDX idx,
                           t_CACHE_ADDR addr,
                           Bool isPrefetch,
                           t_CACHE_READ_META readMeta) = learner.readMiss(idx, addr, isPrefetch);
    method Action prefetchInval(t_CACHE_IDX idx) = learner.prefetchInval(idx);
    method Action shuntNewCacheReq(t_CACHE_IDX idx, t_CACHE_ADDR addr) = learner.shuntNewCacheReq(idx, addr);
    
    method Action fillResp(t_CACHE_IDX idx,
                           t_CACHE_ADDR addr,
                           Bool isPrefetch,
                           t_CACHE_READ_META readMeta);
        noAction;
    endmethod

    //stats from the cache
    method Action prefetchDroppedByBusy(t_CACHE_ADDR addr);
        prefetchDroppedByBusyW.send();
        learner.prefetchDroppedByBusy(addr);
    endmethod
    method Action prefetchDroppedByHit();
        prefetchDroppedByHitW.send();
    endmethod
    method Action prefetchIllegalReq();
        prefetchIllegalReqW.send();
    endmethod
    
    interface RL_PREFETCH_STATS stats;
        method Bool prefetchHit() = learner.prefetchHit();
        method Bool prefetchDroppedByBusy() = prefetchDroppedByBusyW;
        method Bool prefetchDroppedByHit() = prefetchDroppedByHitW;
        method Bool prefetchLate() = learner.prefetchLate();
        method Bool prefetchUseless() = learner.prefetchUseless();
        method Bool prefetchIssued() = prefetchIssuedW;
        method Bool prefetchLearn() = learner.prefetchLearn();
        method Bool prefetchLearnerConflict() = learner.prefetchLearnerConflict();
        method Bool prefetchIllegalReq() = prefetchIllegalReqW;
        method Maybe#(PREFETCH_LEARNER_STATS) hitLearnerInfo() = learner.hitLearnerInfo();
    endinterface
    
endmodule


// ===================================================================
//
// Internal Interface and Modules
//
// ===================================================================

// Prefetch learner interface
interface CACHE_PREFETCH_LEARNER#(type t_CACHE_IDX,
                                  type t_CACHE_ADDR);
    // Set learner size
    method Action setLearnerSize(PREFETCH_LEARNER_SIZE_LOG size);
    // Set learner mode
    method Action setLearnerMode(PREFETCH_MODE mode);
    // Set learner look ahead distance
    method Action setLearnerLookaheadDist(PREFETCH_DIST_PARAM laDist);
    
    // Get source of prefetch request
    method ActionValue#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR)) getReqSource();
    
    // Methods to learn the prefetch mechanism and prefetch stats
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr);
    method Action readMiss(t_CACHE_IDX idx, t_CACHE_ADDR addr, Bool isPrefetch);
    method Action prefetchInval(t_CACHE_IDX idx);
    method Action shuntNewCacheReq(t_CACHE_IDX idx, t_CACHE_ADDR addr); 
    method Action prefetchDroppedByBusy(t_CACHE_ADDR addr);
    
    // Learner's stat methods
    method Bool prefetchHit();
    method Bool prefetchLate();
    method Bool prefetchUseless();
    method Bool prefetchLearn();
    method Bool prefetchLearnerConflict();
    method Maybe#(PREFETCH_LEARNER_STATS) hitLearnerInfo();
    
endinterface: CACHE_PREFETCH_LEARNER

//
// mkCachePrefetchTaggedLearner -- 
//     the basic learner prefetch next (few) lines (with fixed stride) 
//     when there is a cache miss or prefetch hit
//
module mkCachePrefetchTaggedLearner#(DEBUG_FILE debugLog)
    // interface:
    (CACHE_PREFETCH_LEARNER#(t_CACHE_IDX, t_CACHE_ADDR))
    provisos (Bits#(t_CACHE_IDX,  t_CACHE_IDX_SZ),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Alias#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR), t_PREFETCH_REQ_SOURCE),
              Alias#(PREFETCH_STRIDE#(t_CACHE_ADDR_SZ), t_PREFETCH_STRIDE),
              Bits#(t_PREFETCH_REQ_SOURCE, t_PREFETCH_REQ_SOURCE_SZ),
              Bounded#(t_CACHE_IDX));

    Reg#(PREFETCH_DIST)     prefetchDist           <- mkReg(unpack(`PREFETCH_DEFAULT_DIST));
    Reg#(PREFETCH_DIST)     prefetchDistMax        <- mkReg(unpack('1));
    Reg#(Bool)              learnDist              <- mkReg(False);
    
    // Store prefetch status bit per cache line (indicating whether it is first loaded from prefetch)
    LUTRAM#(t_CACHE_IDX, PREFETCH_STATUS) prefetchStatuses <- mkLUTRAM(0);
    
    // Queue of prefetch request sources
    FIFO#(t_PREFETCH_REQ_SOURCE) reqSourceQ        <- mkSizedFIFO(8);

    FIFO#(Tuple2#(t_CACHE_IDX, Bool)) blockedReqQ  <- mkFIFO();

    PulseWire             readHitW                 <- mkPulseWire();
    PulseWire             readMissW                <- mkPulseWire();
    PulseWire             prefetchInvalW           <- mkPulseWire();
    
    // Wires for communicating stats
    PulseWire             prefetchDroppedByBusyW   <- mkPulseWire();
    PulseWire             prefetchHitW             <- mkPulseWire();
    PulseWire             prefetchUselessW         <- mkPulseWire();
    PulseWire             prefetchLateW            <- mkPulseWire();
    PulseWire             prefetchLearnW           <- mkPulseWire();
    RWire#(PREFETCH_LEARNER_STATS) hitLearnerInfoW <- mkRWire();
    
    rule checkLatePrefetch (!readHitW && !readMissW && !prefetchInvalW);
        let lateReq = blockedReqQ.first();
        blockedReqQ.deq();
        match {.idx, .is_prefetch_req} = lateReq;
        if (is_prefetch_req) // prefetchDroppedByBusy
        begin
            prefetchDroppedByBusyW.send();
        end
        else if (prefetchStatuses.sub(idx) != 0) // new cache req is blocked by a prefetch req
        begin
            prefetchLateW.send();
        end
    endrule
    
    rule updatePrefetchDist (learnDist && (prefetchLateW || prefetchDroppedByBusyW));
        if (prefetchDist != prefetchDistMax)
            prefetchDist <= prefetchDist + 1;
    endrule

    rule prefetchLearnTrigger( prefetchHitW || readMissW );
        prefetchLearnW.send();
    endrule

    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action setLearnerSize(PREFETCH_LEARNER_SIZE_LOG size);
        noAction;
    endmethod
    
    method Action setLearnerMode(PREFETCH_MODE mode);
        noAction;
    endmethod
    
    method Action setLearnerLookaheadDist(PREFETCH_DIST_PARAM laDist);
        learnDist <= (laDist[3] == 0);
        if (laDist[3] == 0)
        begin
            prefetchDistMax <= (1<<laDist[2:0])-1;
        end
        else
        begin
            prefetchDist <= unpack(zeroExtend(laDist[2:0]));
        end
    endmethod    

    method ActionValue#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR)) getReqSource();
        let req_source = reqSourceQ.first();
        reqSourceQ.deq();
        return req_source;
    endmethod
    
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr);
        readHitW.send();
        // continue prefetching if it is the first hit of prefetch data
        if (prefetchStatuses.sub(idx) != 0) 
        begin
            prefetchStatuses.upd(idx, 0);
            reqSourceQ.enq(PREFETCH_REQ_SOURCE{ addr: addr, 
                                                stride: unpack(`PREFETCH_DEFAULT_STRIDE),
                                                laDist: prefetchDist });
            // stats
            prefetchHitW.send();
            hitLearnerInfoW.wset(PREFETCH_LEARNER_STATS{ idx: unpack(0),
                                                         isActive: True,
                                                         stride: unpack(`PREFETCH_DEFAULT_STRIDE),
                                                         laDist: unpack(zeroExtend(pack(prefetchDist))) });

            debugLog.record($format(" Prefetch hit: addr=0x%x", addr));
        end
    endmethod
    
    method Action readMiss(t_CACHE_IDX idx, t_CACHE_ADDR addr, Bool isPrefetch);
        readMissW.send();
        // prefetch data is replaced before being accessed
        if (prefetchStatuses.sub(idx) != 0)
        begin
            prefetchUselessW.send();
            debugLog.record($format(" Useless prefetch (evict by read miss): idx=0x%x, addr=0x%x", idx, addr));
        end
        // update prefetch status depending on request type
        if (isPrefetch)
        begin
            prefetchStatuses.upd(idx, 1);
        end
        else
        begin
            prefetchStatuses.upd(idx, 0);
            reqSourceQ.enq(PREFETCH_REQ_SOURCE{ addr: addr, 
                                                stride: unpack(`PREFETCH_DEFAULT_STRIDE),
                                                laDist: prefetchDist });
            // stats
            hitLearnerInfoW.wset(PREFETCH_LEARNER_STATS{ idx: unpack(0),
                                                         isActive: True,
                                                         stride: unpack(`PREFETCH_DEFAULT_STRIDE),
                                                         laDist: unpack(zeroExtend(pack(prefetchDist))) });
            
            debugLog.record($format(" Cache miss: addr=0x%x", addr));
        end
    endmethod

    method Action prefetchInval(t_CACHE_IDX idx);
        prefetchInvalW.send();
        if (prefetchStatuses.sub(idx) != 0)  //prefetch data is replaced before being accessed
        begin
            prefetchStatuses.upd(idx, 0); 
            prefetchUselessW.send();
            debugLog.record($format(" Useless prefetch (evict by write/inval): idx=0x%x", idx));
        end
    endmethod
    
    method Action shuntNewCacheReq(t_CACHE_IDX idx, t_CACHE_ADDR addr);
        blockedReqQ.enq(tuple2(idx, False));
    endmethod

    method Action prefetchDroppedByBusy(t_CACHE_ADDR addr);
        blockedReqQ.enq(tuple2(?, True));
    endmethod    
    
    // Learner's stat methods
    method Bool prefetchHit() = prefetchHitW;
    method Bool prefetchLate() = prefetchLateW;
    method Bool prefetchUseless() = prefetchUselessW;
    method Bool prefetchLearn() = prefetchLearnW;
    method Bool prefetchLearnerConflict() = False;
    method Maybe#(PREFETCH_LEARNER_STATS) hitLearnerInfo() = hitLearnerInfoW.wget(); 
    
endmodule

//
// mkCachePrefetchStrideLearnerDynamic -- 
//     set up stride learners (called streamers) (one for each pre-defined memory space) 
//     to learn stride patterns of memory accesses. (adopting the concepts of stream 
//     prefetchers in processor's L2 cache but simplifying the fully associative 
//     cache of streamers to direct-mapped cache of streamers)
//
// This is the learner designed for testing prefetch parameters dynamically 
//
module mkCachePrefetchStrideLearnerDynamic#(NumTypeParam#(n_LEARNERS) dummy, Bool hashAddresses, Bool usingBRAM, DEBUG_FILE debugLog)
    // interface:
    (CACHE_PREFETCH_LEARNER#(t_CACHE_IDX, t_CACHE_ADDR))
    provisos (Bits#(t_CACHE_IDX,  t_CACHE_IDX_SZ),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Log#(n_LEARNERS, t_STREAMER_IDX_SZ),
              // Add#(t_STREAMER_IDX_SZ, extraStreamerBits, t_CACHE_ADDR_SZ),
              Alias#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR), t_PREFETCH_REQ_SOURCE),
              Alias#(t_CACHE_IDX, t_STREAMER_ADDR),             
              Alias#(Bit#(TSub#(t_CACHE_ADDR_SZ, t_CACHE_IDX_SZ)), t_STREAMER_TAG),
              Bits#(t_STREAMER_TAG, t_STREAMER_TAG_SZ),
              Alias#(PREFETCH_LEARNER_IDX#(TMin#(t_STREAMER_IDX_SZ, t_STREAMER_TAG_SZ)), t_STREAMER_IDX),
              Alias#(PREFETCH_STRIDE#(t_CACHE_IDX_SZ), t_STREAMER_STRIDE),
              Alias#(Maybe#(PREFETCH_STREAMER#(t_STREAMER_TAG, t_STREAMER_ADDR, t_STREAMER_STRIDE)), t_STREAMER),
              Alias#(PREFETCH_LEARNER_REQ#(t_STREAMER_IDX, t_STREAMER_TAG, t_STREAMER_ADDR, t_CACHE_ADDR), t_LEARNER_REQ),
              Bits#(t_PREFETCH_REQ_SOURCE, t_PREFETCH_REQ_SOURCE_SZ),
              Bounded#(t_CACHE_IDX),
              Bounded#(t_STREAMER_IDX));
    
    // Queue of prefetch request sources
    FIFO#(t_PREFETCH_REQ_SOURCE) reqSourceQ                       <- mkSizedFIFO(8);
    FIFO#(Tuple3#(t_CACHE_IDX, t_CACHE_ADDR, Bool)) blockedReqQ   <- mkFIFO();
              
    Reg#(PREFETCH_MODE) learnerMode                <- mkReg(PREFETCH_STRIDE_HYBRID);
    Reg#(Bool)          learnDist                  <- mkReg(False);
    Reg#(PREFETCH_DIST) prefetchDistDefault        <- mkReg(unpack(`PREFETCH_DEFAULT_DIST));
    Reg#(PREFETCH_DIST) prefetchDistBasic          <- mkReg(unpack(`PREFETCH_DEFAULT_DIST));     // for PREFETCH_BASIC_TAGGED
    Reg#(PREFETCH_DIST) prefetchDistMax            <- mkReg(unpack('1));

    // A direct-mapped cache of streamers
    BRAM#(t_STREAMER_IDX, t_STREAMER) streamers    <- mkCachePrefetchLearnerMemory(tagged Invalid, usingBRAM);
    FIFOF#(t_LEARNER_REQ) learnerLookupQ           <- mkSizedBypassFIFOF(2);

    // Store prefetch status bit per cache line (indicating whether it is first loaded from prefetch)
    LUTRAM#(t_CACHE_IDX, PREFETCH_STATUS) prefetchStatuses <- mkLUTRAM(0);
    
    // Masks for streamer idx 
    // (for dynamically change the number of entries in the streamer cache)
    Reg#(t_STREAMER_IDX) idxMask <- mkReg(unpack('1));
    
    PulseWire           readHitW                   <- mkPulseWire();
    PulseWire           readMissW                  <- mkPulseWire();
    PulseWire           prefetchInvalW             <- mkPulseWire();
    Wire#(t_CACHE_ADDR) addrReadMiss               <- mkWire();
    Wire#(t_CACHE_ADDR) addrReadHit                <- mkWire();
    Wire#(t_CACHE_ADDR) addrLate                   <- mkWire();
    
    // Wires for communicating stats
    PulseWire             prefetchDroppedByBusyW   <- mkPulseWire();
    PulseWire             prefetchHitW             <- mkPulseWire();
    PulseWire             prefetchUselessW         <- mkPulseWire();
    PulseWire             prefetchLateW            <- mkPulseWire();
    PulseWire             prefetchLearnW           <- mkPulseWire();
    PulseWire             prefetchLearnerConflictW <- mkPulseWire();
    RWire#(PREFETCH_LEARNER_STATS) hitLearnerInfoW <- mkRWire();
    
    //
    // Convert cache address to/from streamer index, tag, and address 
    //
    function Tuple3#(t_STREAMER_IDX, t_STREAMER_TAG, t_STREAMER_ADDR) streamerEntryFromCacheAddr(t_CACHE_ADDR cache_addr);
        Tuple2#(t_STREAMER_TAG, t_STREAMER_ADDR) streamer_entry = unpack(truncateNP(pack(cache_addr)));
        match {.tag, .addr} = streamer_entry;
        let t = hashAddresses ? hashBits(pack(tag)) : pack(tag);
        t_STREAMER_IDX idx = unpack(truncateNP(t));
        return tuple3 (unpack(pack(idx) & pack(idxMask)), tag, addr);
    endfunction

    function PREFETCH_STREAMER_STATE streamerStateTransition(PREFETCH_STREAMER_STATE old_state, Bool predict_correct);
        PREFETCH_STREAMER_STATE new_state = ?;
        case (old_state)
            STREAMER_INIT:       new_state = predict_correct? STREAMER_STEADY    : STREAMER_TRANSIENT;
            STREAMER_TRANSIENT:  new_state = predict_correct? STREAMER_STEADY    : STREAMER_NO_PREDICT;
            STREAMER_STEADY:     new_state = predict_correct? STREAMER_STEADY    : STREAMER_INIT;
            STREAMER_NO_PREDICT: new_state = predict_correct? STREAMER_TRANSIENT : STREAMER_NO_PREDICT;
        endcase        
        return new_state;
    endfunction

    function Action reqSourceGen(t_CACHE_ADDR cache_addr, t_STREAMER_STRIDE stride, PREFETCH_STREAMER_STATE state, PREFETCH_DIST la_dist, t_STREAMER_IDX idx);
        return
            action
                PREFETCH_STAT_IDX stat_idx = unpack(zeroExtendNP(pack(idx)));
                if (stride != 0 && (state == STREAMER_STEADY || state == STREAMER_TRANSIENT))
                begin
                    hitLearnerInfoW.wset(PREFETCH_LEARNER_STATS{ idx: stat_idx,
                                                                 isActive: True,
                                                                 stride: unpack(signExtendNP(pack(stride))),
                                                                 laDist: unpack(zeroExtend(pack(la_dist))) });
                    reqSourceQ.enq(PREFETCH_REQ_SOURCE{ addr: cache_addr, stride: signExtendNP(stride), laDist: la_dist });
                    debugLog.record($format(" Prefetch req source: addr=0x%x, stride=0x%x, lookahead distance=%d", cache_addr, stride, la_dist));
                end
                else
                begin
                    hitLearnerInfoW.wset(PREFETCH_LEARNER_STATS{ idx: stat_idx,
                                                                 isActive: False,
                                                                 stride: ?,
                                                                 laDist: ? });
                end
            endaction;
    endfunction

    function Action strideLearn(t_CACHE_ADDR cache_addr, Bool update_learner, Bool req_gen);
        return 
            action
                prefetchLearnW.send();
                let streamer_entry = streamerEntryFromCacheAddr(cache_addr);
                match {.idx, .tag, .cur_addr} = streamer_entry;
                debugLog.record($format(" Streamer: idx=0x%x, tag=0x%x, addr=0x%x", idx, tag, cur_addr));
                streamers.readReq(idx);
                learnerLookupQ.enq(PREFETCH_LEARNER_REQ{ idx:       idx, 
                                                         tag:       tag, 
                                                         curAddr:   cur_addr, 
                                                         cacheAddr: cache_addr, 
                                                         act:       (update_learner)? PREFETCH_ACT_LEARN : PREFETCH_ACT_HALF_LEARN,
                                                         reqGen:    req_gen });
            endaction;
    endfunction
  
    function Action basicReqSourceGen(t_CACHE_ADDR cache_addr);
        return 
            action
                reqSourceQ.enq(PREFETCH_REQ_SOURCE{ addr:   cache_addr, 
                                                    stride: unpack(`PREFETCH_DEFAULT_STRIDE),
                                                    laDist: prefetchDistBasic });
            endaction;
    endfunction

    function Action basicStatsGen();
        return
            action
                hitLearnerInfoW.wset(PREFETCH_LEARNER_STATS{ idx: unpack(0),
                                                             isActive: True,
                                                             stride: unpack(`PREFETCH_DEFAULT_STRIDE),
                                                             laDist: unpack(zeroExtend(pack(prefetchDistBasic))) });
            endaction;
    endfunction    
  
    (* mutually_exclusive = "learnOnHit, learnOnMiss, basicPrefetchOnHit, basicPrefetchOnMiss" *)
    rule learnOnHit (readHitW && (learnerMode == PREFETCH_STRIDE_LEARN_ON_ORIGINAL_MISS || learnerMode == PREFETCH_STRIDE_HYBRID));
        if (prefetchHitW)
            strideLearn(addrReadHit, (learnerMode == PREFETCH_STRIDE_HYBRID), True);
        else if (learnerMode == PREFETCH_STRIDE_HYBRID)
            strideLearn(addrReadHit, True, False);
    endrule

    rule learnOnMiss (readMissW && (learnerMode != PREFETCH_BASIC_TAGGED));
        strideLearn(addrReadMiss, True, True);
    endrule
    
    rule basicPrefetchOnMiss (learnerMode == PREFETCH_BASIC_TAGGED);
        basicReqSourceGen(addrReadMiss);
        basicStatsGen();
    endrule

    rule basicPrefetchOnHit (prefetchHitW && learnerMode == PREFETCH_BASIC_TAGGED);
        basicReqSourceGen(addrReadHit);
        basicStatsGen();
    endrule
    
    rule checkLatePrefetch (!readHitW && !readMissW && !prefetchInvalW);
        let req = blockedReqQ.first();
        blockedReqQ.deq();
        match {.idx, .addr, .is_prefetch_req} = req;
        if (is_prefetch_req) // prefetchDroppedByBusy
        begin
            prefetchDroppedByBusyW.send();
            addrLate <= addr;
            debugLog.record($format(" prefetchDroppedByBusy: addr=0x%x", addr));
        end
        else  // new cache request is blocked
        begin
            if (prefetchStatuses.sub(idx) != 0) // blocked by prefetch request
            begin
                prefetchLateW.send();
                addrLate <= addr;
                debugLog.record($format(" newReqBlocked: addr=0x%x", addr));
            end
        end
    endrule
    
    rule updatePrefetchDist (learnDist && (prefetchLateW || prefetchDroppedByBusyW));
        if (learnerMode == PREFETCH_BASIC_TAGGED)
        begin
            if (prefetchDistBasic != prefetchDistMax)
                prefetchDistBasic <= prefetchDistBasic + 1;
        end
        else
        begin
            let streamer_entry = streamerEntryFromCacheAddr(addrLate);
            match {.idx, .tag, .cur_addr} = streamer_entry;
            streamers.readReq(idx);
            learnerLookupQ.enq(PREFETCH_LEARNER_REQ{ idx:       idx, 
                                                     tag:       tag, 
                                                     curAddr:   cur_addr,
                                                     cacheAddr: addrLate,
                                                     act:       PREFETCH_ACT_UPDATE_DIST,
                                                     reqGen:    (prefetchLateW && learnerMode == PREFETCH_STRIDE_LEARN_ON_ORIGINAL_MISS) });
        end
    endrule

    (* conservative_implicit_conditions *)
    rule lookupLearnerDistUpdate (learnerLookupQ.first().act == PREFETCH_ACT_UPDATE_DIST);
        let streamer_req  = learnerLookupQ.first();
        learnerLookupQ.deq();
        let cur_streamer <- streamers.readRsp(); 
        if (cur_streamer matches tagged Valid .s &&& s.tag == streamer_req.tag) // streamer hit!
        begin
            t_STREAMER_ADDR   new_addr        = s.preAddr;
            t_STREAMER_STRIDE new_stride      = s.stride;
            PREFETCH_STREAMER_STATE new_state = s.state;
            let new_dist = (s.laDist != prefetchDistMax) ? (s.laDist + 1) : s.laDist;
            debugLog.record($format(" Update look-ahead distance: tag=0x%x, addr=0x%x, stride=0x%x, state=%d", s.tag, s.preAddr, s.stride, s.state));
            
            if (streamer_req.reqGen) // learn & generate prefetch request on blocked new requests
            begin
                t_STREAMER_STRIDE stride =  unpack( pack(streamer_req.curAddr) - pack(s.preAddr) );
                let predict_correct = ( stride == s.stride );
                if ( (stride != 0) && (predict_correct || s.state == STREAMER_INIT) )
                begin
                    new_state  = streamerStateTransition(s.state, predict_correct);
                    new_stride = stride;
                    new_addr   = streamer_req.curAddr;
                    reqSourceGen(streamer_req.cacheAddr, stride, new_state, new_dist, streamer_req.idx);
                end
                debugLog.record($format(" Streamer update: tag=0x%x, addr=0x%x, stride=0x%x, state=%d, laDist=%d", streamer_req.tag, new_addr, new_stride, new_state, new_dist));
            end

            streamers.write(streamer_req.idx, tagged Valid PREFETCH_STREAMER{ tag:     s.tag,
                                                                              preAddr: new_addr,
                                                                              stride:  new_stride,
                                                                              state:   new_state,
                                                                              laDist:  new_dist});
        end            
    endrule

    (* descending_urgency = "learnOnHit, learnOnMiss, basicPrefetchOnMiss, basicPrefetchOnHit, lookupLearnerDistUpdate, lookupLearnerUpdate, checkLatePrefetch, updatePrefetchDist" *)
    (* conservative_implicit_conditions *)
    rule lookupLearnerUpdate (learnerLookupQ.first().act != PREFETCH_ACT_UPDATE_DIST);
        let streamer_req  = learnerLookupQ.first();
        learnerLookupQ.deq();
        let cur_streamer <- streamers.readRsp(); 
        Bool predict_correct = False;
        Bool prefetch_hit_update = False;
        t_STREAMER_STRIDE new_stride = 0;
        PREFETCH_STREAMER_STATE new_state = STREAMER_INIT; 
        PREFETCH_DIST new_dist = prefetchDistDefault;
        
        if (cur_streamer matches tagged Valid .s &&& s.tag == streamer_req.tag) // streamer hit!
        begin
            debugLog.record($format(" Streamer hit: tag=0x%x, addr=0x%x, stride=0x%x, state=%d, laDist=%d", s.tag, s.preAddr, s.stride, s.state, s.laDist));
            t_STREAMER_STRIDE stride =  unpack( pack(streamer_req.curAddr) - pack(s.preAddr) );
            predict_correct = ( stride == s.stride );
            prefetch_hit_update = predict_correct || (s.state == STREAMER_INIT);
            new_state  = (stride != 0)? streamerStateTransition(s.state, predict_correct) : s.state;
            new_stride = (stride != 0)? ((s.state == STREAMER_STEADY && !predict_correct)? 0 : stride) : s.stride;
            new_dist   = s.laDist;
            if (streamer_req.reqGen)
                reqSourceGen(streamer_req.cacheAddr, stride, new_state, new_dist, streamer_req.idx);
        end
        else
        begin
           prefetchLearnerConflictW.send();
        end
        
        if (streamer_req.act == PREFETCH_ACT_LEARN || prefetch_hit_update)
        begin
            streamers.write(streamer_req.idx, tagged Valid PREFETCH_STREAMER{ tag:     streamer_req.tag,
                                                                              preAddr: streamer_req.curAddr,
                                                                              stride:  new_stride,
                                                                              state:   new_state,
                                                                              laDist:  new_dist});
            debugLog.record($format(" Streamer update: tag=0x%x, addr=0x%x, stride=0x%x, state=%d, laDist=%d", streamer_req.tag, streamer_req.curAddr, new_stride, new_state, new_dist));
        end
    endrule


    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action setLearnerSize(PREFETCH_LEARNER_SIZE_LOG size);
        UInt#(t_STREAMER_IDX_SZ) mask = (1<<size)-1;
        idxMask <= truncateNP(mask);
        debugLog.record($format(" Streamer idx mask: 0x%x", mask));
    endmethod

    method Action setLearnerMode(PREFETCH_MODE mode);
        learnerMode <= mode;
    endmethod

    method Action setLearnerLookaheadDist(PREFETCH_DIST_PARAM laDist);
        learnDist <= (laDist[3] == 0);
        if (laDist[3] == 0)
        begin
            prefetchDistMax <= (1<<laDist[2:0])-1;
        end
        else
        begin
            prefetchDistDefault <= unpack(zeroExtend(laDist[2:0]));
            prefetchDistBasic   <= unpack(zeroExtend(laDist[2:0]));
        end
    endmethod
    
    method ActionValue#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR)) getReqSource();
        let req_source = reqSourceQ.first();
        reqSourceQ.deq();
        return req_source;
    endmethod
    
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR cache_addr);
        readHitW.send();
        addrReadHit <= cache_addr;
        debugLog.record($format(" Cache hit: addr=0x%x", cache_addr));
        // continue prefetching if it is the first hit of prefetch data
        if (prefetchStatuses.sub(idx) != 0) 
        begin
            prefetchStatuses.upd(idx, 0);
            prefetchHitW.send();
            debugLog.record($format(" Prefetch hit: addr=0x%x", cache_addr));
        end
    endmethod
    
    method Action readMiss(t_CACHE_IDX idx, t_CACHE_ADDR cache_addr, Bool isPrefetch);
        readMissW.send();
        // prefetch data is replaced before being accessed
        if (prefetchStatuses.sub(idx) != 0)
        begin
            prefetchUselessW.send();
            debugLog.record($format(" Useless prefetch (evict by read miss): idx=0x%x, addr=0x%x", idx, cache_addr));
        end
        // update prefetch status depending on request type
        if (isPrefetch)
        begin
            prefetchStatuses.upd(idx, 1);
        end
        else
        begin
            prefetchStatuses.upd(idx, 0);
            addrReadMiss <= cache_addr;
            debugLog.record($format(" Cache miss: addr=0x%x", cache_addr));
        end
    endmethod    

    method Action prefetchInval(t_CACHE_IDX idx);
        prefetchInvalW.send();
        //prefetch data is replaced before being accessed
        if (prefetchStatuses.sub(idx) != 0)
        begin
            prefetchStatuses.upd(idx, 0);
            prefetchUselessW.send();
            debugLog.record($format(" Useless prefetch (evict by write/inval): idx=0x%x", idx));
        end
    endmethod
    
    method Action shuntNewCacheReq(t_CACHE_IDX idx, t_CACHE_ADDR cache_addr);
        blockedReqQ.enq(tuple3(idx, cache_addr, False));
    endmethod

    method Action prefetchDroppedByBusy(t_CACHE_ADDR cache_addr);
        blockedReqQ.enq(tuple3(?, cache_addr, True));
    endmethod
    
    // Learner's stat methods
    method Bool prefetchHit() = prefetchHitW;
    method Bool prefetchLate() = prefetchLateW;
    method Bool prefetchUseless() = prefetchUselessW;
    method Bool prefetchLearn() = prefetchLearnW;
    method Bool prefetchLearnerConflict() = prefetchLearnerConflictW;
    method Maybe#(PREFETCH_LEARNER_STATS) hitLearnerInfo() = hitLearnerInfoW.wget(); 
    
endmodule

//
// mkCachePrefetchLearnerMemory -- 
//     Memory module with bypassing writes (a read request coming 
//     in the same cycle as a write request can see the write data).
//
//     The memory may be allocated either as BRAM or LUTRAM.
//
module mkCachePrefetchLearnerMemory#(t_DATA initVal, Bool usingBRAM)
    // interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bounded#(t_ADDR));
    
    MEMORY_IFC#(t_ADDR, t_DATA) ram;
    if (usingBRAM)
    begin
        ram <- mkBRAMInitialized(initVal);
    end
    else
    begin
        LUTRAM#(t_ADDR, t_DATA) lutram <- mkLUTRAM(initVal);
        ram <- mkLUTRAMIfcToMemIfc(lutram);
    end

    let wbr <- mkWriteBeforeReadMemory(ram);
    return wbr;
endmodule

//
// mkCachePrefetchStrideLearner -- 
//     set up stride learners to learn stride patterns of memory accesses
//
// This is the final learner implementation with only static parameters 
//
module mkCachePrefetchStrideLearner#(NumTypeParam#(n_LEARNERS) dummy, Bool hashAddresses, Bool usingBRAM, DEBUG_FILE debugLog)
    // interface:
    (CACHE_PREFETCH_LEARNER#(t_CACHE_IDX, t_CACHE_ADDR))
    provisos (Bits#(t_CACHE_IDX,  t_CACHE_IDX_SZ),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Log#(n_LEARNERS, t_STREAMER_IDX_SZ),
              Alias#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR), t_PREFETCH_REQ_SOURCE),
              Alias#(t_CACHE_IDX, t_STREAMER_ADDR),             
              Alias#(Bit#(TSub#(t_CACHE_ADDR_SZ, t_CACHE_IDX_SZ)), t_STREAMER_TAG),
              Bits#(t_STREAMER_TAG, t_STREAMER_TAG_SZ),
              Alias#(PREFETCH_LEARNER_IDX#(TMin#(t_STREAMER_IDX_SZ, t_STREAMER_TAG_SZ)), t_STREAMER_IDX),
              Alias#(PREFETCH_STRIDE#(t_CACHE_IDX_SZ), t_STREAMER_STRIDE),
              Alias#(Maybe#(PREFETCH_STREAMER#(t_STREAMER_TAG, t_STREAMER_ADDR, t_STREAMER_STRIDE)), t_STREAMER),
              Alias#(PREFETCH_LEARNER_REQ#(t_STREAMER_IDX, t_STREAMER_TAG, t_STREAMER_ADDR, t_CACHE_ADDR), t_LEARNER_REQ),
              Bits#(t_PREFETCH_REQ_SOURCE, t_PREFETCH_REQ_SOURCE_SZ),
              Bounded#(t_CACHE_IDX),
              Bounded#(t_STREAMER_IDX));
    
    // Queue of prefetch request sources
    FIFO#(t_PREFETCH_REQ_SOURCE) reqSourceQ                       <- mkSizedFIFO(8);
    FIFO#(Tuple3#(t_CACHE_IDX, t_CACHE_ADDR, Bool)) blockedReqQ   <- mkFIFO();
            
    // Prefetch look ahead distance
    Reg#(PREFETCH_DIST) prefetchDistDefault        <- mkReg(unpack(`PREFETCH_DEFAULT_DIST));
    Reg#(PREFETCH_DIST) prefetchDistMax            <- mkReg(unpack('1));

    // A direct-mapped cache of streamers
    BRAM#(t_STREAMER_IDX, t_STREAMER) streamers    <- mkCachePrefetchLearnerMemory(tagged Invalid, usingBRAM);
    FIFOF#(t_LEARNER_REQ) learnerLookupQ           <- mkSizedBypassFIFOF(2);

    // Store prefetch status bit per cache line (indicating whether it is first loaded from prefetch)
    LUTRAM#(t_CACHE_IDX, PREFETCH_STATUS) prefetchStatuses <- mkLUTRAM(0);
    
    PulseWire           readHitW                   <- mkPulseWire();
    PulseWire           readMissW                  <- mkPulseWire();
    PulseWire           prefetchInvalW             <- mkPulseWire();
    Wire#(t_CACHE_ADDR) addrReadMiss               <- mkWire();
    Wire#(t_CACHE_ADDR) addrReadHit                <- mkWire();
    Wire#(t_CACHE_ADDR) addrLate                   <- mkWire();
    
    // Wires for communicating stats
    PulseWire             prefetchDroppedByBusyW   <- mkPulseWire();
    PulseWire             prefetchHitW             <- mkPulseWire();
    PulseWire             prefetchUselessW         <- mkPulseWire();
    PulseWire             prefetchLateW            <- mkPulseWire();
    PulseWire             prefetchLearnW           <- mkPulseWire();
    PulseWire             prefetchLearnerConflictW <- mkPulseWire();
    RWire#(PREFETCH_LEARNER_STATS) hitLearnerInfoW <- mkRWire();
    
    //
    // Convert cache address to/from streamer index, tag, and address 
    //
    function Tuple3#(t_STREAMER_IDX, t_STREAMER_TAG, t_STREAMER_ADDR) streamerEntryFromCacheAddr(t_CACHE_ADDR cache_addr);
        Tuple2#(t_STREAMER_TAG, t_STREAMER_ADDR) streamer_entry = unpack(truncateNP(pack(cache_addr)));
        match {.tag, .addr} = streamer_entry;
        let t = hashAddresses ? hashBits(pack(tag)) : pack(tag);
        t_STREAMER_IDX idx = unpack(truncateNP(t));
        return tuple3 (idx, tag, addr);
    endfunction

    function PREFETCH_STREAMER_STATE streamerStateTransition(PREFETCH_STREAMER_STATE old_state, Bool predict_correct);
        PREFETCH_STREAMER_STATE new_state = ?;
        case (old_state)
            STREAMER_INIT:       new_state = predict_correct? STREAMER_STEADY    : STREAMER_TRANSIENT;
            STREAMER_TRANSIENT:  new_state = predict_correct? STREAMER_STEADY    : STREAMER_NO_PREDICT;
            STREAMER_STEADY:     new_state = predict_correct? STREAMER_STEADY    : STREAMER_INIT;
            STREAMER_NO_PREDICT: new_state = predict_correct? STREAMER_TRANSIENT : STREAMER_NO_PREDICT;
        endcase        
        return new_state;
    endfunction

    function Action reqSourceGen(t_CACHE_ADDR cache_addr, t_STREAMER_STRIDE stride, PREFETCH_STREAMER_STATE state, PREFETCH_DIST la_dist, t_STREAMER_IDX idx);
        return
            action
                PREFETCH_STAT_IDX stat_idx = unpack(zeroExtendNP(pack(idx)));
                if (stride != 0 && (state == STREAMER_STEADY || state == STREAMER_TRANSIENT))
                begin
                    hitLearnerInfoW.wset(PREFETCH_LEARNER_STATS{ idx: stat_idx,
                                                                 isActive: True,
                                                                 stride: unpack(signExtendNP(pack(stride))),
                                                                 laDist: unpack(zeroExtend(pack(la_dist))) });
                    reqSourceQ.enq(PREFETCH_REQ_SOURCE{ addr: cache_addr, stride: signExtendNP(stride), laDist: la_dist });
                    debugLog.record($format(" Prefetch req source: addr=0x%x, stride=0x%x, lookahead distance=%d", cache_addr, stride, la_dist));
                end
                else
                begin
                    hitLearnerInfoW.wset(PREFETCH_LEARNER_STATS{ idx: stat_idx,
                                                                 isActive: False,
                                                                 stride: ?,
                                                                 laDist: ? });
                end
            endaction;
    endfunction

    function Action strideLearn(t_CACHE_ADDR cache_addr, Bool update_learner, Bool req_gen);
        return 
            action
                prefetchLearnW.send();
                let streamer_entry = streamerEntryFromCacheAddr(cache_addr);
                match {.idx, .tag, .cur_addr} = streamer_entry;
                debugLog.record($format(" Streamer: idx=0x%x, tag=0x%x, addr=0x%x", idx, tag, cur_addr));
                streamers.readReq(idx);
                learnerLookupQ.enq(PREFETCH_LEARNER_REQ{ idx:       idx, 
                                                         tag:       tag, 
                                                         curAddr:   cur_addr, 
                                                         cacheAddr: cache_addr, 
                                                         act:       (update_learner)? PREFETCH_ACT_LEARN : PREFETCH_ACT_HALF_LEARN,
                                                         reqGen:    req_gen });
            endaction;
    endfunction
  
    (* mutually_exclusive = "learnOnHit, learnOnMiss" *)
    rule learnOnHit (prefetchHitW);
        strideLearn(addrReadHit, False, True);
    endrule

    rule learnOnMiss (readMissW);
        strideLearn(addrReadMiss, True, True);
    endrule
    
    rule checkLatePrefetch (!readHitW && !readMissW && !prefetchInvalW);
        let req = blockedReqQ.first();
        blockedReqQ.deq();
        match {.idx, .addr, .is_prefetch_req} = req;
        if (is_prefetch_req) // prefetchDroppedByBusy
        begin
            prefetchDroppedByBusyW.send();
            addrLate <= addr;
            debugLog.record($format(" prefetchDroppedByBusy: addr=0x%x", addr));
        end
        else  // new cache request is blocked
        begin
            if (prefetchStatuses.sub(idx) != 0) // blocked by prefetch request
            begin
                prefetchLateW.send();
                addrLate <= addr;
                debugLog.record($format(" newReqBlocked: addr=0x%x", addr));
            end
        end
    endrule
    
    (* descending_urgency = "learnOnHit, learnOnMiss, checkLatePrefetch, updatePrefetchDist" *)
    rule updatePrefetchDist (prefetchLateW || prefetchDroppedByBusyW);
        let streamer_entry = streamerEntryFromCacheAddr(addrLate);
        match {.idx, .tag, .cur_addr} = streamer_entry;
        streamers.readReq(idx);
        learnerLookupQ.enq(PREFETCH_LEARNER_REQ{ idx:       idx, 
                                                 tag:       tag, 
                                                 curAddr:   cur_addr,
                                                 cacheAddr: addrLate,
                                                 act:       PREFETCH_ACT_UPDATE_DIST,
                                                 reqGen:    prefetchLateW });
    endrule

    (* conservative_implicit_conditions *)
    rule lookupLearnerDistUpdate (learnerLookupQ.first().act == PREFETCH_ACT_UPDATE_DIST);
        let streamer_req  = learnerLookupQ.first();
        learnerLookupQ.deq();
        let cur_streamer <- streamers.readRsp(); 
        if (cur_streamer matches tagged Valid .s &&& s.tag == streamer_req.tag) // streamer hit!
        begin
            t_STREAMER_ADDR   new_addr        = s.preAddr;
            t_STREAMER_STRIDE new_stride      = s.stride;
            PREFETCH_STREAMER_STATE new_state = s.state;
            let new_dist = (s.laDist != prefetchDistMax) ? (s.laDist + 1) : s.laDist;
            debugLog.record($format(" Update look-ahead distance: tag=0x%x, addr=0x%x, stride=0x%x, state=%d", s.tag, s.preAddr, s.stride, s.state));
            
            if (streamer_req.reqGen) // learn & generate prefetch request on blocked new requests
            begin
                t_STREAMER_STRIDE stride =  unpack( pack(streamer_req.curAddr) - pack(s.preAddr) );
                let predict_correct = ( stride == s.stride );
                if ( (stride != 0) && (predict_correct || s.state == STREAMER_INIT) )
                begin
                    new_state  = streamerStateTransition(s.state, predict_correct);
                    new_stride = stride;
                    new_addr   = streamer_req.curAddr;
                    reqSourceGen(streamer_req.cacheAddr, stride, new_state, new_dist, streamer_req.idx);
                end
                debugLog.record($format(" Streamer update: tag=0x%x, addr=0x%x, stride=0x%x, state=%d, laDist=%d", streamer_req.tag, new_addr, new_stride, new_state, new_dist));
            end

            streamers.write(streamer_req.idx, tagged Valid PREFETCH_STREAMER{ tag:     s.tag,
                                                                              preAddr: new_addr,
                                                                              stride:  new_stride,
                                                                              state:   new_state,
                                                                              laDist:  new_dist});
        end            
    endrule

    rule lookupLearnerUpdate (learnerLookupQ.first().act != PREFETCH_ACT_UPDATE_DIST);
        let streamer_req  = learnerLookupQ.first();
        learnerLookupQ.deq();
        let cur_streamer <- streamers.readRsp(); 
        Bool predict_correct = False;
        Bool prefetch_hit_update = False;
        t_STREAMER_STRIDE new_stride = 0;
        PREFETCH_STREAMER_STATE new_state = STREAMER_INIT; 
        PREFETCH_DIST new_dist = prefetchDistDefault;
        
        if (cur_streamer matches tagged Valid .s &&& s.tag == streamer_req.tag) // streamer hit!
        begin
            debugLog.record($format(" Streamer hit: tag=0x%x, addr=0x%x, stride=0x%x, state=%d, laDist=%d", s.tag, s.preAddr, s.stride, s.state, s.laDist));
            t_STREAMER_STRIDE stride =  unpack( pack(streamer_req.curAddr) - pack(s.preAddr) );
            predict_correct = ( stride == s.stride );
            prefetch_hit_update = predict_correct || (s.state == STREAMER_INIT);
            new_state  = (stride != 0)? streamerStateTransition(s.state, predict_correct) : s.state;
            new_stride = (stride != 0)? ((s.state == STREAMER_STEADY && !predict_correct)? 0 : stride) : s.stride;
            new_dist   = s.laDist;
            if (streamer_req.reqGen)
                reqSourceGen(streamer_req.cacheAddr, stride, new_state, new_dist, streamer_req.idx);
        end
        else
        begin
           prefetchLearnerConflictW.send();
        end
        
        if (streamer_req.act == PREFETCH_ACT_LEARN || prefetch_hit_update)
        begin
            streamers.write(streamer_req.idx, tagged Valid PREFETCH_STREAMER{ tag:     streamer_req.tag,
                                                                              preAddr: streamer_req.curAddr,
                                                                              stride:  new_stride,
                                                                              state:   new_state,
                                                                              laDist:  new_dist});
            debugLog.record($format(" Streamer update: tag=0x%x, addr=0x%x, stride=0x%x, state=%d, laDist=%d", streamer_req.tag, streamer_req.curAddr, new_stride, new_state, new_dist));
        end
    endrule


    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action setLearnerSize(PREFETCH_LEARNER_SIZE_LOG size);
        noAction;
    endmethod

    method Action setLearnerMode(PREFETCH_MODE mode);
        noAction;
    endmethod

    method Action setLearnerLookaheadDist(PREFETCH_DIST_PARAM laDist);
        noAction;
    endmethod
    
    method ActionValue#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR)) getReqSource();
        let req_source = reqSourceQ.first();
        reqSourceQ.deq();
        return req_source;
    endmethod
    
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR cache_addr);
        readHitW.send();
        addrReadHit <= cache_addr;
        debugLog.record($format(" Cache hit: addr=0x%x", cache_addr));
        // continue prefetching if it is the first hit of prefetch data
        if (prefetchStatuses.sub(idx) != 0) 
        begin
            prefetchStatuses.upd(idx, 0);
            prefetchHitW.send();
            debugLog.record($format(" Prefetch hit: addr=0x%x", cache_addr));
        end
    endmethod
    
    method Action readMiss(t_CACHE_IDX idx, t_CACHE_ADDR cache_addr, Bool isPrefetch);
        readMissW.send();
        // prefetch data is replaced before being accessed
        if (prefetchStatuses.sub(idx) != 0)
        begin
            prefetchUselessW.send();
            debugLog.record($format(" Useless prefetch (evict by read miss): idx=0x%x, addr=0x%x", idx, cache_addr));
        end
        // update prefetch status depending on request type
        if (isPrefetch)
        begin
            prefetchStatuses.upd(idx, 1);
        end
        else
        begin
            prefetchStatuses.upd(idx, 0);
            addrReadMiss <= cache_addr;
            debugLog.record($format(" Cache miss: addr=0x%x", cache_addr));
        end
    endmethod    

    method Action prefetchInval(t_CACHE_IDX idx);
        prefetchInvalW.send();
        //prefetch data is replaced before being accessed
        if (prefetchStatuses.sub(idx) != 0)
        begin
            prefetchStatuses.upd(idx, 0);
            prefetchUselessW.send();
            debugLog.record($format(" Useless prefetch (evict by write/inval): idx=0x%x", idx));
        end
    endmethod
    
    method Action shuntNewCacheReq(t_CACHE_IDX idx, t_CACHE_ADDR cache_addr);
        blockedReqQ.enq(tuple3(idx, cache_addr, False));
    endmethod

    method Action prefetchDroppedByBusy(t_CACHE_ADDR cache_addr);
        blockedReqQ.enq(tuple3(?, cache_addr, True));
    endmethod
    
    // Learner's stat methods
    method Bool prefetchHit() = prefetchHitW;
    method Bool prefetchLate() = prefetchLateW;
    method Bool prefetchUseless() = prefetchUselessW;
    method Bool prefetchLearn() = prefetchLearnW;
    method Bool prefetchLearnerConflict() = prefetchLearnerConflictW;
    method Maybe#(PREFETCH_LEARNER_STATS) hitLearnerInfo() = hitLearnerInfoW.wget(); 
    
    
endmodule


// ===================================================================
//
// Null cache prefetcher implementation.
//
// ===================================================================

//
// mkNullCachePrefetcher --
//     never generates prefetch requests
//
module mkNullCachePrefetcher
    // interface:
    (CACHE_PREFETCHER#(t_CACHE_IDX, t_CACHE_ADDR, t_CACHE_READ_META))
    provisos (Bits#(t_CACHE_IDX,      t_CACHE_IDX_SZ),
              Bits#(t_CACHE_ADDR,     t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ));
    
    method Action setPrefetchMode(Tuple2#(PREFETCH_MODE, PREFETCH_DIST_PARAM) mode, PREFETCH_LEARNER_SIZE_LOG size, PREFETCH_PRIO_SPEC prioSpec);
        noAction;
    endmethod
   
    method Bool hasReq() = False;
    
    method Bool prefetcherNearlyFull() = False;

    method ActionValue#(PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_READ_META)) getReq();
        return ?;
    endmethod
    
    method PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_READ_META) peekReq();
        return ?;
    endmethod
    
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr);
        noAction;
    endmethod
    
    method Action readMiss(t_CACHE_IDX idx,
                           t_CACHE_ADDR addr,
                           Bool isPrefetch,
                           t_CACHE_READ_META readMeta);
        noAction;
    endmethod

    method Action prefetchInval(t_CACHE_IDX idx);
        noAction;
    endmethod
    
    method Action shuntNewCacheReq(t_CACHE_IDX idx, t_CACHE_ADDR addr);
        noAction;
    endmethod
    
    method Action fillResp(t_CACHE_IDX idx,
                           t_CACHE_ADDR addr,
                           Bool isPrefetch,
                           t_CACHE_READ_META readMeta);
        noAction;
    endmethod

    method Action prefetchDroppedByBusy(t_CACHE_ADDR addr);
        noAction;
    endmethod

    method Action prefetchDroppedByHit();
        noAction;
    endmethod
    
    method Action prefetchIllegalReq();
        noAction;
    endmethod
    
    interface RL_PREFETCH_STATS stats;
        method Bool prefetchHit() = False;
        method Bool prefetchDroppedByBusy() = False;
        method Bool prefetchDroppedByHit() = False;
        method Bool prefetchLate() = False;
        method Bool prefetchUseless() = False;
        method Bool prefetchIssued() = False;
        method Bool prefetchLearn() = False;
        method Bool prefetchLearnerConflict() = False;
        method Bool prefetchIllegalReq() = False;
        method Maybe#(PREFETCH_LEARNER_STATS) hitLearnerInfo() = tagged Invalid; 
    endinterface

endmodule
