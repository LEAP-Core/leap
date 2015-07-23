
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
import FIFOF::*;
import SpecialFIFOs::*;
import FIFOLevel::*;
import Vector::*;
import DefaultValue::*;
import ConfigReg::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/PARAMS_SCRATCHPAD_MEMORY_SERVICE.bsh"

//
//  userPrefetcherName --
//    Provides the name of the user prefetch channel.
//
function String userPrefetchName(Integer scratchpadID);
    return "PrefetchRequest_" + integerToString(scratchpadID);
endfunction

//
// mkScratchpadUserPrefetcher -- 
//   A client interface into the scratchpad, which permits the client to inject program-specific prefetches.
//

module [CONNECTED_MODULE] mkScratchpadUserPrefetcher#(Integer scratchpadID, NumTypeParam#(t_ADDR_SZ) userAddrWidth, Bool hashAddresses, DEBUG_FILE debugLog)
    // interface:
    (CACHE_PREFETCHER#(t_CACHE_IDX, t_CACHE_ADDR, t_CACHE_READ_META))
    provisos (Bits#(t_CACHE_IDX,      t_CACHE_IDX_SZ),
              Bits#(t_CACHE_ADDR,     t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),
              Alias#(Bit#(t_ADDR_SZ), t_ADDR),
              Alias#(PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_READ_META), t_PREFETCH_REQ),
              Alias#(PREFETCH_STRIDE#(t_CACHE_ADDR_SZ), t_STRIDE),
              Bits#(t_PREFETCH_REQ,   t_PREFETCH_REQ_SZ),
              Bounded#(t_CACHE_IDX));

    // Check whether or not prefetching is enabled.     
    PARAMETER_NODE paramNode         <- mkDynamicParameterNode();
    Param#(3) cacheMode              <- mkDynamicParameter(`PARAMS_SCRATCHPAD_MEMORY_SERVICE_SCRATCHPAD_PVT_CACHE_MODE, paramNode);

    // Prefetch priority
    Reg#(PREFETCH_PRIO) prefetchPriority <- mkReg(PREFETCH_PRIO_HIGH);

    // Prefetch request queue
    FIFOCountIfc#(t_PREFETCH_REQ,4) prefetchReqQ <- mkFIFOCount();

    // Wires for communicating stats
    PulseWire prefetchDroppedByBusyW <- mkPulseWire();
    PulseWire prefetchDroppedByHitW  <- mkPulseWire();
    PulseWire prefetchIssuedW        <- mkPulseWire();
    PulseWire prefetchIllegalReqW    <- mkPulseWire();
    PulseWire prefetchReadHitW       <- mkPulseWire();
    PulseWire prefetchUselessW       <- mkPulseWire();
    PulseWire prefetchLateW          <- mkPulseWire();

    CONNECTION_RECV#(t_ADDR) userPrefetchRequest <- mkConnectionRecvOptional(userPrefetchName(scratchpadID));

    rule createPrefetchReq (True);
        let new_addr = userPrefetchRequest.receive();
        userPrefetchRequest.deq();
        // Maybe we need a resizeLSB here. 
        let req = PREFETCH_REQ { addr: unpack(resizeLSB(new_addr)), 
                                 readMeta: ?,
                                 prio: prefetchPriority };

        // Use existing cache mode parameter to turn off prefetching.
        if(cacheMode[2] == 1)
        begin
            prefetchReqQ.enq(req);
            prefetchIssuedW.send();
        end

    endrule
    
        
    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action setPrefetchMode(Tuple2#(PREFETCH_MODE, PREFETCH_DIST_PARAM) mode, PREFETCH_LEARNER_SIZE_LOG size, PREFETCH_PRIO_SPEC prioSpec);
        if(prioSpec.defaultOverride)
        begin
            prefetchPriority <= prioSpec.prio;
        end
    endmethod

    method Bool hasReq() = prefetchReqQ.notEmpty;
 
    method Bool prefetcherNearlyFull() = prefetchReqQ.count() > 2;

    method ActionValue#(PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_READ_META)) getReq();
        let req = prefetchReqQ.first();
        prefetchReqQ.deq();
        return req;
    endmethod
    
    method PREFETCH_REQ#(t_CACHE_ADDR, t_CACHE_READ_META) peekReq();
        return prefetchReqQ.first();
    endmethod
        
    method Action readHit(t_CACHE_IDX idx, t_CACHE_ADDR addr);
        prefetchReadHitW.send();
    endmethod

    method Action readMiss(t_CACHE_IDX idx,
                           t_CACHE_ADDR addr,
                           Bool isPrefetch,
                           t_CACHE_READ_META readMeta) = ?;

    method Action prefetchInval(t_CACHE_IDX idx);
        prefetchUselessW.send();
    endmethod

    method Action shuntNewCacheReq(t_CACHE_IDX idx, t_CACHE_ADDR addr);
        prefetchLateW.send();
    endmethod
    
    method Action fillResp(t_CACHE_IDX idx,
                           t_CACHE_ADDR addr,
                           Bool isPrefetch,
                           t_CACHE_READ_META readMeta);
        noAction;
    endmethod

    //stats from the cache
    method Action prefetchDroppedByBusy(t_CACHE_ADDR addr);
        prefetchDroppedByBusyW.send();
    endmethod
    method Action prefetchDroppedByHit();
        prefetchDroppedByHitW.send();
    endmethod
    method Action prefetchIllegalReq();
        prefetchIllegalReqW.send();
    endmethod
    
    interface RL_PREFETCH_STATS stats;
        method Bool prefetchHit() = prefetchReadHitW;
        method Bool prefetchDroppedByBusy() = prefetchDroppedByBusyW;
        method Bool prefetchDroppedByHit() = prefetchDroppedByHitW;
        method Bool prefetchLate() = prefetchLateW;
        method Bool prefetchUseless() = prefetchUselessW;
        method Bool prefetchIssued() = prefetchIssuedW;
        method Bool prefetchLearn() = ?;
        method Bool prefetchLearnerConflict() = ?;
        method Bool prefetchIllegalReq() = prefetchIllegalReqW;
        method Maybe#(PREFETCH_LEARNER_STATS) hitLearnerInfo() = ?;
    endinterface
    
endmodule
