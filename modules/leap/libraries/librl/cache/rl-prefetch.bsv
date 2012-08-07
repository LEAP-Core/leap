//
// Copyright (C) 2012 Intel Corporation
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

//
// Cache prefetcher.
// The prefetcher instance is sent as a module argument of the 
// higher level cache
//

// Library imports.

import FIFO::*;
import SpecialFIFOs::*;
import FIFOLevel :: * ;

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
    PREFETCH_PRIO_HIGH    = 1,
    PREFETCH_NON_BLOCKING = 2
}
PREFETCH_PRIO
    deriving (Eq, Bits);

//
// Prefetch mode
//
typedef enum
{
    PREFETCH_BASIC_TAGGED = 0,
    PREFETCH_STRIDE_LEARN_ON_MISS = 1,  //learn only when read miss
    PREFETCH_STRIDE_LEARN_ON_BOTH = 2,  //learn when read miss/hit
    PREFETCH_STRIDE_LEARN_ON_REQ  = 3   //learn when clients send read reqs
}
PREFETCH_MODE
    deriving (Eq, Bits);

   
//    
// Number of prefetch learners (in log) 
// (used in dynamic parameter settings)
//
typedef UInt#(3) PREFETCH_LEARNER_SIZE_LOG;

//
// Prefetch request
//
typedef struct
{
    t_CACHE_ADDR     addr;
    t_CACHE_REF_INFO refInfo;
    PREFETCH_PRIO    prio;
}
PREFETCH_REQ#(type t_CACHE_ADDR,
              type t_CACHE_REF_INFO)
    deriving (Eq, Bits);
    
//
// Prefetcher interface.
//
interface CACHE_PREFETCHER#(type t_CACHE_IDX,
                            type t_CACHE_ADDR,
                            type t_CACHE_REF_INFO);
    
    method Action setPrefetchMode(PREFETCH_PRIO prio, Tuple3#(PREFETCH_MODE, PREFETCH_SIZE, PREFETCH_DIST) mode, PREFETCH_LEARNER_SIZE_LOG size);
    
    // Return true if the prefetch request queue is not empty
    method Bool hasReq();
    
    // Return a read request to prefetch a word (from the prefetch request queue)
    method ActionValue#(PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_REF_INFO)) getReq();
    method PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_REF_INFO) peekReq();
    
    //
    // Learn the prefetch mechanism 
    //
    // Cache provides hit/miss information
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr);
    method Action readMiss(t_CACHE_ADDR addr);
    // Update the prefetcher's tag array (when prefetch read)
    method Action loadPrefetch(t_CACHE_IDX idx);
    // Update the prefetcher's tag array (when normal cache read (miss) or a cache write)
    method Action loadNormal(t_CACHE_IDX idx);
    // Update stride learner when there is a read request
    method Action reqLearn(t_CACHE_ADDR addr);
    
endinterface: CACHE_PREFETCHER

// ===================================================================
//
// Internal types
//
// ===================================================================

// Prefetch size
typedef UInt#(2) PREFETCH_SIZE;

// Prefetch distance
typedef UInt#(3) PREFETCH_DIST;

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
}
PREFETCH_REQ_SOURCE#(type t_CACHE_ADDR)
    deriving (Eq, Bits);    

//
// Tag bit for each cache line 
//(indicating the cache line is filled from the prefetch or cache request)
//
typedef Bit#(1)  PREFETCH_TAG;

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
}
PREFETCH_STREAMER#(type t_STREAMER_TAG,
                   type t_STREAMER_ADDR,
                   type t_STREAMER_STRIDE)
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

// ===================================================================
//
// Prefetcher implementation
//
// ===================================================================

//
// mkCachePrefetcher 
//
module mkCachePrefetcher#(NumTypeParam#(n_LEARNERS) dummy, DEBUG_FILE debugLog)
    // interface:
    (CACHE_PREFETCHER#(t_CACHE_IDX, t_CACHE_ADDR, t_CACHE_REF_INFO))
    provisos (Bits#(t_CACHE_IDX,      t_CACHE_IDX_SZ),
              Bits#(t_CACHE_ADDR,     t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_REF_INFO, t_CACHE_REF_INFO_SZ),
              Alias#(PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_REF_INFO), t_PREFETCH_REQ),
              Alias#(PREFETCH_STRIDE#(t_CACHE_ADDR_SZ), t_STRIDE),
              Bits#(t_PREFETCH_REQ,   t_PREFETCH_REQ_SZ),
              Bounded#(t_CACHE_IDX));

    Reg#(PREFETCH_PRIO) prefetchPrioDefault <- mkReg(PREFETCH_PRIO_HIGH);
    Reg#(PREFETCH_PRIO) prefetchPrio        <- mkReg(PREFETCH_PRIO_HIGH);
    Reg#(PREFETCH_MODE) prefetchMode        <- mkReg(PREFETCH_STRIDE_LEARN_ON_BOTH);
    
    // Prefetch request queue
    FIFOLevelIfc#(t_PREFETCH_REQ, 8) prefetchReqQ <- mkFIFOLevel();
    
    // Number of words to prefetch
    Reg#(PREFETCH_SIZE) prefetchNum <- mkReg(`PREFETCH_DEFAULT_SIZE);
    
    // Prefetch stride 
    Reg#(t_STRIDE) prefetchStride <- mkReg(unpack(`PREFETCH_DEFAULT_STRIDE));
    
    // Prefetch distance
    Reg#(PREFETCH_DIST) prefetchDist <- mkReg(unpack(`PREFETCH_DEFAULT_DIST));

    // Prefetch address
    Reg#(t_CACHE_ADDR) prefetchAddr <- mkReg(unpack(0));

    PulseWire startPrefetch <- mkPulseWire();

    // Prefetch learners
    CACHE_PREFETCH_LEARNER#(t_CACHE_IDX, t_CACHE_ADDR) taggedLearner <- mkCachePrefetchTaggedLearner(dummy, debugLog);
    CACHE_PREFETCH_LEARNER#(t_CACHE_IDX, t_CACHE_ADDR) strideLearner <- mkCachePrefetchStrideLearner(dummy, debugLog);
    CACHE_PREFETCH_LEARNER#(t_CACHE_IDX, t_CACHE_ADDR) learner = (prefetchMode == PREFETCH_BASIC_TAGGED)? taggedLearner : strideLearner;
    
    rule createPrefetchReq (True);
        t_CACHE_ADDR new_addr;
        t_CACHE_ADDR diff_addr;
        if (prefetchNum == 0)
        begin
            let req_source <- learner.getReqSource();
            prefetchStride <= req_source.stride;
            diff_addr = unpack(pack(req_source.stride)*zeroExtendNP(pack(prefetchDist)));
            new_addr = unpack(pack(req_source.addr) + pack(diff_addr));
            debugLog.record($format(" generate prefetch req: addr=0x%x (base_addr:0x%x, stride:0x%x)", new_addr, req_source.addr, req_source.stride));
        end
        else
        begin
            diff_addr = unpack(pack(prefetchStride)*zeroExtendNP(pack(prefetchDist)));
            new_addr = unpack(pack(prefetchAddr) + pack(diff_addr));
            debugLog.record($format(" generate prefetch req: addr=0x%x (base_addr:0x%x, stride:0x%x)", new_addr, prefetchAddr, prefetchStride));
        end
        prefetchAddr <= new_addr;
        let req = PREFETCH_REQ { addr: new_addr, 
                                 refInfo: ?, 
                                 prio: prefetchPrio };
        prefetchReqQ.enq(req);
        startPrefetch.send();
    endrule
    
    rule updatePrefetchNum (startPrefetch);
        prefetchNum <= ( prefetchNum == `PREFETCH_DEFAULT_SIZE ) ? 0 : prefetchNum + 1;
    endrule
    
    rule updatePrefetchPrio (True);
        if (prefetchReqQ.isGreaterThan(6))
        begin
            prefetchPrio <= PREFETCH_PRIO_HIGH;
        end
        else if(prefetchReqQ.isLessThan(2))
        begin
            prefetchPrio <= prefetchPrioDefault;
        end
    endrule
    
    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action setPrefetchMode(PREFETCH_PRIO prio, Tuple3#(PREFETCH_MODE, PREFETCH_SIZE, PREFETCH_DIST) mode, PREFETCH_LEARNER_SIZE_LOG size);
        prefetchPrioDefault <= prio;
        match {.prefetch_type, .prefetch_num, .prefetch_dist} = mode; 
        prefetchNum  <= prefetch_num;
        prefetchMode <= prefetch_type;
        prefetchDist <= prefetch_dist;
        strideLearner.setLearnerSize(size);
        strideLearner.setLearnerMode(prefetch_type);
    endmethod

    method Bool hasReq() = prefetchReqQ.notEmpty;
 
    method ActionValue#(PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_REF_INFO)) getReq();
        let req = prefetchReqQ.first();
        prefetchReqQ.deq();
        return req;
    endmethod
    
    method PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_REF_INFO) peekReq();
        return prefetchReqQ.first();
    endmethod
    
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr) = learner.readHit(idx, addr);
    method Action readMiss(t_CACHE_ADDR addr) = learner.readMiss(addr);
    method Action loadPrefetch(t_CACHE_IDX idx) = learner.loadPrefetch(idx);
    method Action loadNormal(t_CACHE_IDX idx) = learner.loadNormal(idx);
    method Action reqLearn(t_CACHE_ADDR addr) = learner.reqLearn(addr);

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
    // Set learner mode (for stride prefetcher sub-mode) 
    method Action setLearnerMode(PREFETCH_MODE mode);

    // Get source of prefetch request
    method ActionValue#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR)) getReqSource();
    
    // Learn the prefetch mechanism by providing hit/miss, cache filling, or request information
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr);
    method Action readMiss(t_CACHE_ADDR addr);
    method Action loadPrefetch(t_CACHE_IDX idx);
    method Action loadNormal(t_CACHE_IDX idx);
    method Action reqLearn(t_CACHE_ADDR addr);

endinterface: CACHE_PREFETCH_LEARNER

//
// mkCachePrefetchTaggedLearner -- 
//     the basic learner prefetch next (few) lines (with fixed stride) 
//     when there is a cache miss or prefetch hit
//
module mkCachePrefetchTaggedLearner#(NumTypeParam#(n_LEARNERS) dummy, DEBUG_FILE debugLog)
    // interface:
    (CACHE_PREFETCH_LEARNER#(t_CACHE_IDX, t_CACHE_ADDR))
    provisos (Bits#(t_CACHE_IDX,  t_CACHE_IDX_SZ),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Alias#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR), t_PREFETCH_REQ_SOURCE),
              Alias#(PREFETCH_STRIDE#(t_CACHE_ADDR_SZ), t_PREFETCH_STRIDE),
              Bits#(t_PREFETCH_REQ_SOURCE, t_PREFETCH_REQ_SOURCE_SZ),
              Bounded#(t_CACHE_IDX));
              
    // Store tag bit per cache line (indicating whether it is first loaded from prefetch)
    LUTRAM#(t_CACHE_IDX, PREFETCH_TAG) prefetchTags <- mkLUTRAM(0);
    // Queue of prefetch request sources
    FIFO#(t_PREFETCH_REQ_SOURCE) reqSourceQ         <- mkSizedFIFO(8);
    Reg#(t_PREFETCH_STRIDE) prefetchStride          <- mkReg(`PREFETCH_DEFAULT_STRIDE);
   
    Wire#(t_CACHE_IDX) cacheIdxPrefetchHit   <- mkWire();
    Wire#(t_CACHE_IDX) cacheIdxPrefetchFill  <- mkWire();
    Wire#(t_CACHE_IDX) cacheIdxCacheFill     <- mkWire();
    PulseWire          isPrefetchHit         <- mkPulseWire();
    PulseWire          isPrefetchFill        <- mkPulseWire();
    PulseWire          isCacheFill           <- mkPulseWire();

    rule prefetchTagUpdate (True);
        if (isCacheFill)
            prefetchTags.upd(cacheIdxCacheFill,0);
        else if (isPrefetchFill)
            prefetchTags.upd(cacheIdxPrefetchFill,1);
        else if (isPrefetchHit)
            prefetchTags.upd(cacheIdxPrefetchHit,0);
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

    method ActionValue#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR)) getReqSource();
        let req_source = reqSourceQ.first();
        reqSourceQ.deq();
        return req_source;
    endmethod
    
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr);
        // continue prefetching if it is the first hit of prefetch data
        if (prefetchTags.sub(idx) != 0) 
        begin
            // prefetchTags.upd(idx,0);
            cacheIdxPrefetchHit <= idx;
            isPrefetchHit.send();
            reqSourceQ.enq(PREFETCH_REQ_SOURCE{ addr: addr, stride: prefetchStride });
            debugLog.record($format(" Prefetch hit: addr=0x%x, entry=0x%x", addr, idx));
        end
    endmethod
    
    method Action readMiss(t_CACHE_ADDR addr);
        reqSourceQ.enq(PREFETCH_REQ_SOURCE{ addr: addr, stride: prefetchStride });
        debugLog.record($format(" Cache miss: addr=0x%x", addr));
    endmethod
    
    method Action loadPrefetch(t_CACHE_IDX idx);
        cacheIdxPrefetchFill <= idx;
        isPrefetchFill.send();
        debugLog.record($format(" Prefetch fill resp: entry=0x%x", idx));
    endmethod
    
    method Action loadNormal(t_CACHE_IDX idx);
        cacheIdxCacheFill <= idx;
        isCacheFill.send();
        debugLog.record($format(" Cache fill resp: entry=0x%x", idx));
    endmethod

    method Action reqLearn(t_CACHE_ADDR addr);
        noAction;
    endmethod

endmodule

//
// mkCachePrefetchStrideLearner -- 
//     set up stride learners (one for each pre-defined memory space) to learn 
//     stride patterns of memory accesses. (adopting the concepts of stream 
//     prefetchers in processor's L2 cache but simplifying the fully associative 
//     cache of streamers to direct-mapped cache of streamers)
//
// This is the learner designed for testing prefetch parameters dynamically 
//
module mkCachePrefetchStrideLearner#(NumTypeParam#(n_LEARNERS) dummy, DEBUG_FILE debugLog)
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
              Bits#(t_PREFETCH_REQ_SOURCE, t_PREFETCH_REQ_SOURCE_SZ));

    Reg#(PREFETCH_MODE) learnerMode        <- mkReg(PREFETCH_STRIDE_LEARN_ON_BOTH);

    // A direct-mapped cache of streamers
    LUTRAM#(t_STREAMER_IDX, t_STREAMER) streamers <- mkLUTRAM(tagged Invalid);
    // Queue of prefetch request sources
    FIFO#(t_PREFETCH_REQ_SOURCE) reqSourceQ       <- mkSizedFIFO(8);
    
    // Masks for streamer idx 
    // (for dynamically change the number of entries in the streamer cache)
    Reg#(t_STREAMER_IDX) idxMask <- mkReg(unpack('1));
    
    Reg#(t_CACHE_ADDR) learnedCacheAddr <- mkReg(unpack(0));
    Reg#(t_STREAMER_STRIDE) learnedStride <- mkReg(0);
    Reg#(PREFETCH_STREAMER_STATE) learnedState <- mkReg(STREAMER_INIT);

    Wire#(t_CACHE_ADDR) addrReadReq  <- mkWire();
    Wire#(t_CACHE_ADDR) addrReadMiss <- mkWire();
    Wire#(t_CACHE_ADDR) addrReadHit  <- mkWire();

    //
    // Convert cache address to/from streamer index, tag, and address 
    //
    function Tuple3#(t_STREAMER_IDX, t_STREAMER_TAG, t_STREAMER_ADDR) streamerEntryFromCacheAddr(t_CACHE_ADDR cache_addr);
        Tuple2#(t_STREAMER_TAG, t_STREAMER_ADDR) streamer_entry = unpack(truncateNP(pack(cache_addr)));
        match {.tag, .addr} = streamer_entry;
        t_STREAMER_IDX idx = unpack(truncateNP(pack(tag)));
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

    function Action reqSourceGen(t_CACHE_ADDR cache_addr, t_STREAMER_STRIDE stride, PREFETCH_STREAMER_STATE state);
        return
            action
                if (stride != 0 && (state == STREAMER_STEADY || state == STREAMER_TRANSIENT))
                begin
                    reqSourceQ.enq(PREFETCH_REQ_SOURCE{ addr: cache_addr, stride: signExtendNP(stride) });
                    debugLog.record($format(" Prefetch req source: addr=0x%x, stride=0x%x", cache_addr, stride));
                end
            endaction;
    endfunction

    function Action nullReqSourceGen(t_CACHE_ADDR cache_addr, t_STREAMER_STRIDE stride, PREFETCH_STREAMER_STATE state);
        return noAction;
    endfunction

    function Action storeReqSourceGen(t_CACHE_ADDR cache_addr, t_STREAMER_STRIDE stride, PREFETCH_STREAMER_STATE state);
        return
            action
                learnedCacheAddr <= cache_addr;
                learnedStride    <= stride;
                learnedState     <= state;
            endaction;
    endfunction
    
    function Action strideLearn(t_CACHE_ADDR cache_addr, function Action req_source_gen(t_CACHE_ADDR x, t_STREAMER_STRIDE y, PREFETCH_STREAMER_STATE z));
        return 
            action
                let streamer_entry = streamerEntryFromCacheAddr(cache_addr);
                match {.idx, .tag, .cur_addr} = streamer_entry;
                
                debugLog.record($format(" Streamer: idx=0x%x, tag=0x%x, addr=0x%x", idx, tag, cur_addr));

                let cur_streamer = streamers.sub(idx);
                Bool predict_correct = False;
                t_STREAMER_STRIDE new_stride = 0;
                PREFETCH_STREAMER_STATE new_state = STREAMER_INIT; 
 
                if (cur_streamer matches tagged Valid .s &&& s.tag == tag) // streamer hit!
                begin
                    debugLog.record($format(" Streamer hit: tag=0x%x, addr=0x%x, stride=0x%x, state=%d", s.tag, s.preAddr, s.stride, s.state));
                    t_STREAMER_STRIDE stride =  unpack( pack(cur_addr) - pack(s.preAddr) );
                    predict_correct = ( stride == s.stride );
                    new_state  = (stride != 0)? streamerStateTransition(s.state, predict_correct) : s.state;
                    new_stride = (stride != 0)? ((s.state == STREAMER_STEADY && !predict_correct)? 0 : stride) : s.stride;
                    // issuing prefetch request(s)
                    req_source_gen(cache_addr, stride, new_state);
                end
        
                streamers.upd(idx, tagged Valid PREFETCH_STREAMER{ tag: tag,
                                                                   preAddr: cur_addr,
                                                                   stride: new_stride,
                                                                   state: new_state });

                debugLog.record($format(" Streamer update: tag=0x%x, addr=0x%x, stride=0x%x, state=%d", tag, cur_addr, new_stride, new_state));
            endaction;
    endfunction
  
    (* mutually_exclusive = "learnOnHit, learnOnMiss" *)
    rule learnOnHit (learnerMode == PREFETCH_STRIDE_LEARN_ON_BOTH);
        strideLearn(addrReadHit, nullReqSourceGen);
    endrule

    rule learnOnMiss (learnerMode != PREFETCH_STRIDE_LEARN_ON_REQ);
        strideLearn(addrReadMiss, reqSourceGen);
    endrule

    rule learnOnReq (learnerMode == PREFETCH_STRIDE_LEARN_ON_REQ);
        strideLearn(addrReadReq, storeReqSourceGen);
    endrule

    rule prefetchReqSourceGen (learnerMode == PREFETCH_STRIDE_LEARN_ON_REQ);
        let streamer_entry = streamerEntryFromCacheAddr(addrReadMiss);
        match {.idx, .tag, .cur_addr} = streamer_entry;
        if (pack(learnedCacheAddr) == pack(addrReadMiss)) // streamer hit!
        begin
            debugLog.record($format(" Streamer hit: tag=0x%x, addr=0x%x, stride=0x%x, state=%d", tag, cur_addr, learnedStride, learnedState));
            reqSourceGen(addrReadMiss, learnedStride, learnedState);
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
        learnerMode    <= mode;
    endmethod

    method ActionValue#(PREFETCH_REQ_SOURCE#(t_CACHE_ADDR)) getReqSource();
        let req_source = reqSourceQ.first();
        reqSourceQ.deq();
        return req_source;
    endmethod
    
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR cache_addr);
        debugLog.record($format(" Cache hit: addr=0x%x", cache_addr));
        addrReadHit <= cache_addr;
    endmethod
    
    method Action readMiss(t_CACHE_ADDR cache_addr);
        debugLog.record($format(" Cache miss: addr=0x%x", cache_addr));
        addrReadMiss <= cache_addr;
    endmethod
    
    method Action loadPrefetch(t_CACHE_IDX idx);
        noAction;
    endmethod
    
    method Action loadNormal(t_CACHE_IDX idx);
        noAction;
    endmethod

    method Action reqLearn(t_CACHE_ADDR cache_addr);
        debugLog.record($format(" Read Req: addr=0x%x", cache_addr));
        addrReadReq <= cache_addr;
    endmethod

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
module mkNullCachePrefetcher#(NumTypeParam#(n_LEARNERS) dummy, DEBUG_FILE debugLog)
    // interface:
    (CACHE_PREFETCHER#(t_CACHE_IDX, t_CACHE_ADDR, t_CACHE_REF_INFO))
    provisos (Bits#(t_CACHE_IDX,      t_CACHE_IDX_SZ),
              Bits#(t_CACHE_ADDR,     t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_REF_INFO, t_CACHE_REF_INFO_SZ));
    
    method Action setPrefetchMode(PREFETCH_PRIO prio, Tuple3#(PREFETCH_MODE, PREFETCH_SIZE, PREFETCH_DIST) mode, PREFETCH_LEARNER_SIZE_LOG size);
        noAction;
    endmethod

    method Action loadPrefetch(t_CACHE_IDX idx);
        noAction;
    endmethod
    
    method Action loadNormal(t_CACHE_IDX idx);
        noAction;
    endmethod
   
    method Bool hasReq() = False;
    
    method ActionValue#(PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_REF_INFO)) getReq() if (False);
        return ?;
    endmethod
    
    method PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_REF_INFO) peekReq() if (False);
        return ?;
    endmethod
    
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr);
        noAction;
    endmethod
    
    method Action readMiss(t_CACHE_ADDR addr);
        noAction;
    endmethod

    method Action reqLearn(t_CACHE_ADDR addr);
        noAction;
    endmethod

endmodule
