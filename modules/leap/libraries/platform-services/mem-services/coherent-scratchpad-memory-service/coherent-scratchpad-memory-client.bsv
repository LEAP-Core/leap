///
// Copyright (C) 2013 MIT
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
// Interfaces to coherent scratchpad memory.
//

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import DefaultValue::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/scratchpad_memory_service.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/dict/PARAMS_COHERENT_SCRATCHPAD_MEMORY_SERVICE.bsh"

// Number of slots in a read port's reorder buffer.  The coherent scratchpad 
// subsystem does not guarantee to return results in order, so all clients 
// need a ROB. The ROB size limits the number of read requests in flight 
// for a given port.

typedef SCRATCHPAD_PORT_ROB_SLOTS COH_SCRATCH_PORT_ROB_SLOTS;

// ========================================================================
//
// Modules that instantiate a coherent scratchpad client.
//
// ========================================================================
    
//
// mkCoherentScratchpadClient --
//     This is the typical coherent scratchpad client module.
//
//     Build a coherent scratchpad client of an arbitrary data type with 
// marshalling to the global scratchpad base memory size.
//
module [CONNECTED_MODULE] mkCoherentScratchpadClient#(Integer scratchpadID, COH_SCRATCH_CONFIG conf)
    // interface:
    (MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    //
    // The coherent scratchpad implementation is all in the multi-reader interface.
    // Allocate a multi-reader coherent scratchpad client with a single reader 
    // and convert it to MEMORY_WITH_FENCE_IFC.
    //
    MEMORY_MULTI_READ_WITH_FENCE_IFC#(1, t_ADDR, t_DATA) m_scratch <- mkMultiReadCoherentScratchpadClient(scratchpadID, conf);
    MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) scratch <- mkMultiMemFenceIfcToMemFenceIfc(m_scratch);
    return scratch;
endmodule

//
// mkDebugCoherentScratchpadClient --
//     This is the typical coherent scratchpad client module used for debugging. 
// Debug file and statsID are passed in as arguments for simplicity. statsID for
// each coherent scratchpad client needs to be unique.
//
module [CONNECTED_MODULE] mkDebugCoherentScratchpadClient#(Integer scratchpadID, 
                                                           Integer statsID, 
                                                           COH_SCRATCH_CONFIG conf,
                                                           DEBUG_FILE debugLog)
    // interface:
    (MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    //
    // The coherent scratchpad implementation is all in the multi-reader interface.
    // Allocate a multi-reader coherent scratchpad client with a single reader 
    // and convert it to MEMORY_WITH_FENCE_IFC.
    //
    MEMORY_MULTI_READ_WITH_FENCE_IFC#(1, t_ADDR, t_DATA) m_scratch <- mkMultiReadDebugCoherentScratchpadClient(scratchpadID, statsID, conf, debugLog);
    MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) scratch <- mkMultiMemFenceIfcToMemFenceIfc(m_scratch);
    return scratch;
endmodule

//
// mkMultiReadCoherentScratchpadClient --
//     The same as mkMultiReadStatsCoherentScratchpadClient but we have null stats in this case
//
module [CONNECTED_MODULE] mkMultiReadCoherentScratchpadClient#(Integer scratchpadID, COH_SCRATCH_CONFIG conf)
    // interface:
    (MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    let statsConstructor = mkNullCoherentScratchpadCacheStats;
    let prefetchStatsConstructor = mkNullScratchpadPrefetchStats;
    let reqRingStatsConstructor = mkNullCoherentScratchpadRingNodeStats;
    let respRingStatsConstructor = mkNullCoherentScratchpadRingNodeStats;
    DEBUG_FILE debugLog <- mkDebugFileNull(""); 
    
    let m <- mkMultiReadStatsCoherentScratchpadClient(scratchpadID,
                                                      conf,
                                                      statsConstructor, 
                                                      prefetchStatsConstructor,
                                                      reqRingStatsConstructor,
                                                      respRingStatsConstructor,
                                                      debugLog);
    return m;
endmodule

//
// mkMultiReadDebugCoherentScratchpadClient --
//     The same as mkMultiReadStatsCoherentScratchpadClient with stats created by an unique statsID.
//
module [CONNECTED_MODULE] mkMultiReadDebugCoherentScratchpadClient#(Integer scratchpadID, 
                                                                    Integer statsID,
                                                                    COH_SCRATCH_CONFIG conf,
                                                                    DEBUG_FILE debugLog)
    // interface:
    (MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));
    
    String statsName = "Coherent_scratchpad_" + integerToString(scratchpadID) + "_client_" + integerToString(statsID) + "_";
    NumTypeParam#(`COHERENT_SCRATCHPAD_PVT_CACHE_PREFETCH_LEARNER_NUM) n_prefetch_learners = ?;
    
    let statsConstructor = mkBasicCoherentScratchpadCacheStats(statsName, "");
    let prefetchStatsConstructor = (`COHERENT_SCRATCHPAD_PVT_CACHE_PREFETCH_ENABLE == 1)?
                                   mkBasicScratchpadPrefetchStats(statsName, "", n_prefetch_learners):
                                   mkNullScratchpadPrefetchStats;
    
    let reqRingStatsConstructor = (`ADDR_RING_DEBUG_ENABLE == 1)? 
                                  mkBasicCoherentScratchpadRingNodeStats(statsName + "req_", ""):
                                  mkNullCoherentScratchpadRingNodeStats;

    let respRingStatsConstructor = (`ADDR_RING_DEBUG_ENABLE == 1)?
                                   mkBasicCoherentScratchpadRingNodeStats(statsName + "resp_", ""):
                                   mkNullCoherentScratchpadRingNodeStats; 
    
    let m <- mkMultiReadStatsCoherentScratchpadClient(scratchpadID, 
                                                      conf, 
                                                      statsConstructor, 
                                                      prefetchStatsConstructor, 
                                                      reqRingStatsConstructor,
                                                      respRingStatsConstructor,
                                                      debugLog);
    return m;
endmodule

//
// mkMultiReadStatsCoherentScratchpadClient --
//     The same as a normal mkCoherentScratchpadClient but with multiple read ports.
//     Requests are processed in order, with reads being scheduled before
//     a write requested in the same cycle.
//
module [CONNECTED_MODULE] mkMultiReadStatsCoherentScratchpadClient#(Integer scratchpadID,
                                                                    COH_SCRATCH_CONFIG conf,
                                                                    COH_SCRATCH_CACHE_STATS_CONSTRUCTOR statsConstructor,
                                                                    SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR prefetchStatsConstructor,
                                                                    COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR reqStatsConstructor,
                                                                    COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR respStatsConstructor,
                                                                    DEBUG_FILE debugLog)
    // interface:
    (MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Compute the natural size in bits.  The natural size is rounded up to
              // a power of 2 bits that is one byte or larger.
              Max#(8, TExp#(TLog#(t_DATA_SZ)), t_NATURAL_SZ),
              Bits#(COH_SCRATCH_MEM_VALUE, t_COH_SCRATCH_MEM_VALUE_SZ));
    
    if (valueOf(t_NATURAL_SZ) > valueOf(t_COH_SCRATCH_MEM_VALUE_SZ))
    begin
        //
        // Object size is larger than COH_SCRATCH_MEM_VALUE 
        // This requires issuing multiple reads and writes for every reference,
        // and they need to be automic.
        // This requires a locking scheme so currently is not supported. 
        //
        error("Coherent scratchpad doesn't support data larger than coherent scratchpad's base size");
    end
    
    MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA) mem;
    
    if (conf.cacheMode == COH_SCRATCH_UNCACHED)
    begin
        mem <- mkUncachedCoherentScratchpadClient(scratchpadID, debugLog);
    end
    else if (valueOf(t_NATURAL_SZ) <= valueOf(t_COH_SCRATCH_MEM_VALUE_SZ)/2)
    begin
        mem <- mkSmallMultiReadStatsCoherentScratchpadClient(scratchpadID, 
                                                             statsConstructor, 
                                                             prefetchStatsConstructor, 
                                                             reqStatsConstructor,
                                                             respStatsConstructor,
                                                             debugLog);
    end
    else
    begin
        mem <- mkMediumMultiReadStatsCoherentScratchpadClient(scratchpadID, 
                                                              statsConstructor, 
                                                              prefetchStatsConstructor,
                                                              reqStatsConstructor,
                                                              respStatsConstructor,
                                                              debugLog);
    end
    
    return mem;
endmodule



// ============================================================================
//
// Internal module
//
// ============================================================================

//
// mkSmallMultiReadStatsCoherentScratchpadClient --
//     The target data type is smaller than (or equal to) half of the global 
// coherent scratchpad base memory size.
// We store multiple objects in one coherent scratchpad container and use 
// byteMask to perform partial writes. 
//
module [CONNECTED_MODULE] mkSmallMultiReadStatsCoherentScratchpadClient#(Integer scratchpadID,
                                                                         COH_SCRATCH_CACHE_STATS_CONSTRUCTOR statsConstructor,
                                                                         SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR prefetchStatsConstructor,
                                                                         COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR reqStatsConstructor,
                                                                         COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR respStatsConstructor,
                                                                         DEBUG_FILE debugLog)
    // interface:
    (MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Compute the natural size in bits.  The natural size is rounded up to
              // a power of 2 bits that is one byte or larger.
              Max#(8, TExp#(TLog#(t_DATA_SZ)), t_NATURAL_SZ),
              Bits#(COH_SCRATCH_MEM_VALUE, t_COH_SCRATCH_MEM_VALUE_SZ),
              // Compute the object index within a container 
              NumAlias#(TLog#(TDiv#(t_COH_SCRATCH_MEM_VALUE_SZ, t_NATURAL_SZ)), t_OBJ_IDX_SZ),
              Alias#(Bit#(t_OBJ_IDX_SZ), t_OBJ_IDX),
              // Arrangement of objects packed in a container.  Objects are evenly
              // spaced to make packed values easier to read while debugging.
              Alias#(Vector#(TExp#(t_OBJ_IDX_SZ), Bit#(TDiv#(t_COH_SCRATCH_MEM_VALUE_SZ, TExp#(t_OBJ_IDX_SZ)))), t_PACKED_CONTAINER),
              // Compute the container (scratchpad) address size
              NumAlias#(TSub#(t_ADDR_SZ, t_OBJ_IDX_SZ), t_CONTAINER_ADDR_SZ),
              Alias#(Bit#(t_CONTAINER_ADDR_SZ), t_CONTAINER_ADDR),
              // Container byte mask
              NumAlias#(TDiv#(t_COH_SCRATCH_MEM_VALUE_SZ, 8), t_COH_SCRATCH_BYTES_PER_WORD),
              Alias#(Vector#(t_COH_SCRATCH_BYTES_PER_WORD, Bool), t_CONTAINER_MASK));

    NumTypeParam#(`COHERENT_SCRATCHPAD_PVT_CACHE_ENTRIES) n_cache_entries = ?;
    NumTypeParam#(`COHERENT_SCRATCHPAD_PVT_CACHE_PREFETCH_LEARNER_NUM) n_cache_prefetch_learners = ?;

    // Instantiate the underlying memory.
    MEMORY_MULTI_READ_MASKED_WRITE_WITH_FENCE_IFC#(n_READERS, t_CONTAINER_ADDR, COH_SCRATCH_MEM_VALUE, t_CONTAINER_MASK) mem <-
        mkUnmarshalledCachedCoherentScratchpadClient(scratchpadID,
                                                     `PARAMS_COHERENT_SCRATCHPAD_MEMORY_SERVICE_COHERENT_SCRATCHPAD_PVT_CACHE_MODE,
                                                     n_cache_entries,
                                                     n_cache_prefetch_learners,
                                                     statsConstructor,
                                                     prefetchStatsConstructor,
                                                     reqStatsConstructor,
                                                     respStatsConstructor,
                                                     debugLog);

    
    // Read request info holds the address of the requested data within the container.
    Vector#(n_READERS, FIFO#(t_OBJ_IDX)) readReqInfoQ <- replicateM(mkSizedFIFO(valueOf(COH_SCRATCH_PORT_ROB_SLOTS)));

    //
    // addrSplit --
    //     Split an incoming address into two components:  the container address
    //     and the index of the requested object within the container.
    //
    function Tuple2#(t_CONTAINER_ADDR, t_OBJ_IDX) addrSplit(t_ADDR addr);
        // return unpack(pack(addr));
        Bit#(t_ADDR_SZ) p_addr = pack(addr);
        return tuple2(unpack(p_addr[valueOf(t_ADDR_SZ)-1 : valueOf(t_OBJ_IDX_SZ)]), p_addr[valueOf(t_OBJ_IDX_SZ)-1 : 0]);
    endfunction
    
    //
    // computeByteMask --
    //     Compute the byte mask of an object within a container given the object index.
    //
    function t_CONTAINER_MASK computeByteMask(t_OBJ_IDX idx);
        // Build a mask of valid bytes
        Vector#(TExp#(t_OBJ_IDX_SZ), Bit#(TDiv#(t_NATURAL_SZ, 8))) b_mask = replicate(0);
        b_mask[idx] = -1;
        // Size should match.  Resize avoids a proviso.
        return unpack(resize(pack(b_mask)));
    endfunction
    
    //
    // Methods
    //
    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr);
                    match {.c_addr, .o_idx} = addrSplit(addr);
                    mem.readPorts[p].readReq(c_addr);
                    readReqInfoQ[p].enq(o_idx);
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let o_idx = readReqInfoQ[p].first();
                    readReqInfoQ[p].deq();
                    // Receive the data and return the desired object from the container.
                    let d <- mem.readPorts[p].readRsp();
                    t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
                    return unpack(truncateNP(pack_data[o_idx]));
                endmethod

                method t_DATA peek();
                    let o_idx = readReqInfoQ[p].first();
                    // Receive the data and return the desired object from the container.
                    let d = mem.readPorts[p].peek();
                    t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
                    return unpack(truncateNP(pack_data[o_idx]));
                endmethod

                method Bool notEmpty() = mem.readPorts[p].notEmpty();
                method Bool notFull() = mem.readPorts[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val);
        match {.c_addr, .o_idx} = addrSplit(addr);
        // Put the data at the right place in the container
        t_PACKED_CONTAINER pack_data = unpack(0);
        pack_data[o_idx] = zeroExtendNP(pack(val));
        mem.write(c_addr, unpack(zeroExtendNP(pack(pack_data))), computeByteMask(o_idx));
    endmethod

    method Bool writeNotFull() = mem.writeNotFull();

    method Action fence() = mem.fence();
    method Action writeFence() = mem.writeFence();
    method Action readFence() = mem.readFence();
    method Bool writePending() = mem.writePending();
    method Bool readPending() = mem.readPending();

endmodule


//
// mkMediumMultiReadStatsCoherentScratchpadClient --
//     Only one data object is stored in one coherent scratchpad container. 
//
module [CONNECTED_MODULE] mkMediumMultiReadStatsCoherentScratchpadClient#(Integer scratchpadID,
                                                                          COH_SCRATCH_CACHE_STATS_CONSTRUCTOR statsConstructor,
                                                                          SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR prefetchStatsConstructor,
                                                                          COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR reqStatsConstructor,
                                                                          COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR respStatsConstructor,
                                                                          DEBUG_FILE debugLog)
    // interface:
    (MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(COH_SCRATCH_MEM_VALUE, t_COH_SCRATCH_MEM_VALUE_SZ),
              Alias#(t_ADDR, t_CONTAINER_ADDR),
              // Container byte mask
              NumAlias#(TDiv#(t_COH_SCRATCH_MEM_VALUE_SZ, 8), t_COH_SCRATCH_BYTES_PER_WORD),
              Alias#(Vector#(t_COH_SCRATCH_BYTES_PER_WORD, Bool), t_CONTAINER_MASK));

    NumTypeParam#(`COHERENT_SCRATCHPAD_PVT_CACHE_ENTRIES) n_cache_entries = ?;
    NumTypeParam#(`COHERENT_SCRATCHPAD_PVT_CACHE_PREFETCH_LEARNER_NUM) n_cache_prefetch_learners = ?;

    // Instantiate the underlying memory.
    MEMORY_MULTI_READ_MASKED_WRITE_WITH_FENCE_IFC#(n_READERS, t_CONTAINER_ADDR, COH_SCRATCH_MEM_VALUE, t_CONTAINER_MASK) mem <-
        mkUnmarshalledCachedCoherentScratchpadClient(scratchpadID,
                                                     `PARAMS_COHERENT_SCRATCHPAD_MEMORY_SERVICE_COHERENT_SCRATCHPAD_PVT_CACHE_MODE,
                                                     n_cache_entries,
                                                     n_cache_prefetch_learners,
                                                     statsConstructor,
                                                     prefetchStatsConstructor,
                                                     reqStatsConstructor,
                                                     respStatsConstructor,
                                                     debugLog);
    //
    // Methods
    //
    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr);
                    mem.readPorts[p].readReq(addr);
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let d <- mem.readPorts[p].readRsp();
                    return unpack(truncateNP(pack(d)));
                endmethod

                method t_DATA peek();
                    let d = mem.readPorts[p].peek();
                    return unpack(truncateNP(pack(d)));
                endmethod
                method Bool notEmpty() = mem.readPorts[p].notEmpty();
                method Bool notFull() = mem.readPorts[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val);
        mem.write(addr, unpack(zeroExtendNP(pack(val))), unpack(pack(replicate(True))));
    endmethod

    method Bool writeNotFull() = mem.writeNotFull();

    method Action fence() = mem.fence();
    method Action writeFence() = mem.writeFence();
    method Action readFence() = mem.readFence();
    method Bool writePending() = mem.writePending();
    method Bool readPending() = mem.readPending();
endmodule


//
// mkUnmarshalledCachedCoherentScratchpadClient --
//     Allocate a cached connection to the coherent scratchpad rings of a 
// particular coherent scratchpad memory region.  This module does no marshalling 
// of data sizes.
//
module [CONNECTED_MODULE] mkUnmarshalledCachedCoherentScratchpadClient#(Integer scratchpadID, 
                                                                        Integer cacheModeParam,
                                                                        NumTypeParam#(n_CACHE_ENTRIES) nCacheEntries,
                                                                        NumTypeParam#(n_PREFETCH_LEARNER_SIZE) nPrefetchLearners,
                                                                        COH_SCRATCH_CACHE_STATS_CONSTRUCTOR statsConstructor,
                                                                        SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR prefetchStatsConstructor,
                                                                        COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR reqStatsConstructor,
                                                                        COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR respStatsConstructor,
                                                                        DEBUG_FILE debugLog)
    // interface:
    (MEMORY_MULTI_READ_MASKED_WRITE_WITH_FENCE_IFC#(n_READERS, t_MEM_ADDR, COH_SCRATCH_MEM_VALUE, t_MEM_MASK))
    provisos (Bits#(t_MEM_ADDR, t_MEM_ADDR_SZ),
              Bits#(t_MEM_MASK, t_MEM_MASK_SZ),
              Alias#(COH_SCRATCH_MEM_VALUE, t_MEM_DATA),
              Bits#(t_MEM_DATA, t_MEM_DATA_SZ),
              Div#(t_MEM_DATA_SZ, 8, t_MEM_MASK_SZ),
              // Index in a reorder buffer
              Alias#(SCOREBOARD_FIFO_ENTRY_ID#(COH_SCRATCH_PORT_ROB_SLOTS), t_REORDER_ID),
              // MAF for in-flight reads
              Alias#(Tuple2#(Bit#(TLog#(n_READERS)), t_REORDER_ID), t_MAF_IDX),
              Bits#(t_MAF_IDX, t_MAF_IDX_SZ));
              
    // Debug file and log for the cache prefetcher
    DEBUG_FILE debugLogForPrefetcher <- mkDebugFileNull(""); 

    // Dynamic parameters
    PARAMETER_NODE paramNode         <- mkDynamicParameterNode();
    Param#(2) cacheMode              <- mkDynamicParameter(fromInteger(cacheModeParam), paramNode);

    // Connection between private cache and the scratchpad virtual device
    let sourceData <- mkCoherentScratchpadCacheSourceData(scratchpadID, 
                                                          reqStatsConstructor,
                                                          respStatsConstructor,
                                                          debugLog);
                             
    // Cache Prefetcher
    let prefetcher <- (`COHERENT_SCRATCHPAD_PVT_CACHE_PREFETCH_ENABLE == 1) ?
                      mkCachePrefetcher(nPrefetchLearners, False, True, debugLogForPrefetcher):
                      mkNullCachePrefetcher();
    
    // Coherent private cache
    RL_COH_DM_CACHE#(t_MEM_ADDR, t_MEM_DATA, t_MEM_MASK, t_MAF_IDX) cache <- 
        mkCoherentCacheDirectMapped(sourceData, prefetcher, nCacheEntries, True, debugLog);

    // Hook up stats
    let cacheStats <- statsConstructor(cache.stats);
    let prefetchStats <- prefetchStatsConstructor(prefetcher.stats);

    // Merge FIFOF combines read, write, and fence requests in temporal order,
    // with reads from the same cycle as a write going first.  Each read port
    // gets a slot. The write port is always second from last. The port for 
    // the fence request is always last. 
    MERGE_FIFOF#(TAdd#(n_READERS, 2), Tuple2#(t_MEM_ADDR, t_REORDER_ID)) incomingReqQ <- mkMergeFIFOF();

    // Write data (and write mask) is sent in a side port to keep the incomingReqQ smaller.
    FIFO#(Tuple2#(t_MEM_DATA, t_MEM_MASK)) writeDataQ <- mkFIFO();

    // Cache responses are not ordered.  Sort them with a reorder buffer.
    Vector#(n_READERS, SCOREBOARD_FIFOF#(COH_SCRATCH_PORT_ROB_SLOTS, t_MEM_DATA)) sortResponseQ <- replicateM(mkScoreboardFIFOF());
  
    // Read and write request counter
    COUNTER#(TLog#(TAdd#(TMul#(n_READERS, COH_SCRATCH_PORT_ROB_SLOTS),1))) numPendingReads  <- mkLCounter(0);
    COUNTER#(TLog#(TAdd#(COH_SCRATCH_PORT_ROB_SLOTS,1))) numPendingWrites <- mkLCounter(0);
    Vector#(n_READERS, PulseWire) readIssuedW <- replicateM(mkPulseWire());

    // Initialization
    Reg#(Bool) initialized <- mkReg(False);
    rule doInit (! initialized);
        cache.setCacheMode(unpack(cacheMode[0]), unpack(cacheMode[1]));
        initialized <= True;
    endrule

    //
    // Update read and write request counter
    //

    rule incrNumReads (True);
        Bit#(n_READERS) reads = ?;
        for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
        begin
            reads[p] = readIssuedW[p]? 1 : 0;
        end
        numPendingReads.upBy(zeroExtendNP(pack(countOnesAlt(reads))));
    endrule
    
    rule decNumReads (cache.numReadProcessed() != 0);
        numPendingReads.downBy(zeroExtendNP(cache.numReadProcessed()));
        debugLog.record($format("%x read request being processed, numPendingReads=0x%x", 
                        cache.numReadProcessed(), numPendingReads.value()));
    endrule

    rule decNumWrites (cache.numWriteProcessed() != 0);
        numPendingWrites.downBy(zeroExtendNP(cache.numWriteProcessed()));
        debugLog.record($format("%x write request being processed, numPendingWrites=0x%x", 
                        cache.numWriteProcessed(), numPendingWrites.value()));
    endrule

    //
    // Forward merged requests to the cache.
    //

    // fence requests
    rule forwardFenceReq (initialized && incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS)+1));
        let fence_mode = pack(incomingReqQ.first());
        incomingReqQ.deq();
        cache.fence(unpack(truncate(fence_mode)));
    endrule

    // Write requests
    rule forwardWriteReq (initialized && incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS)));
        let addr = tpl_1(incomingReqQ.first());
        incomingReqQ.deq();

        match {.val, .mask} = writeDataQ.first();
        writeDataQ.deq();

        cache.write(addr, val, mask);
    endrule


    // Read requests
    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        rule forwardReadReq (initialized && incomingReqQ.firstPortID() == fromInteger(p));
            match {.addr, .idx} = incomingReqQ.first();
            incomingReqQ.deq();

            // The read UID for this request is the concatenation of the
            // port ID and the ROB index.
            t_MAF_IDX maf_idx = tuple2(fromInteger(p), idx);

            // Request data from the cache
            cache.readReq(addr, maf_idx, defaultValue());
        endrule

        //
        // receiveResp --
        //     Push read responses to the reorder buffer.  They will be returned
        //     through readRsp() in order.
        //
        rule receiveResp (tpl_1(cache.peekResp().readMeta) == fromInteger(p));
            let r <- cache.readResp();

            // The readUID field holds the concatenation of the port ID and
            // the port's reorder buffer index.
            match {.port, .maf_idx} = r.readMeta;

            sortResponseQ[p].setValue(maf_idx, r.val);
        endrule
    end

    //
    // Methods.  All requests are stored in the incomingReqQ to maintain their
    // order.
    //

    Vector#(n_READERS, MEMORY_READER_IFC#(t_MEM_ADDR, t_MEM_DATA)) portsLocal = newVector();

    for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_MEM_ADDR, t_MEM_DATA);
                method Action readReq(t_MEM_ADDR addr);
                    // Allocate a slot in the reorder buffer for the read request.  Each
                    // read port gets its own reorder buffer.
                    let idx <- sortResponseQ[p].enq();
                    incomingReqQ.ports[p].enq(tuple2(addr, idx));
                    readIssuedW[p].send();
                    debugLog.record($format("read port %0d: req addr=0x%x, rob idx=%0d, numPendingReads=0x%x", 
                                    p, addr, idx, numPendingReads.value()));
                endmethod

                method ActionValue#(t_MEM_DATA) readRsp();
                    let r = sortResponseQ[p].first();
                    sortResponseQ[p].deq();
                    debugLog.record($format("read port %0d: resp val=0x%x", p, r));
                    return r;
                endmethod

                method t_MEM_DATA peek();
                    return sortResponseQ[p].first();
                endmethod

                method Bool notEmpty() = sortResponseQ[p].notEmpty();
                method Bool notFull() = incomingReqQ.ports[p].notFull() &&
                                        sortResponseQ[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_MEM_ADDR addr, t_MEM_DATA val, t_MEM_MASK byteMask) if (numPendingWrites.value() != maxBound);
        // The write port is the second from last in the merge FIFO
        incomingReqQ.ports[valueOf(n_READERS)].enq(tuple2(addr, ?));
        writeDataQ.enq(tuple2(val, byteMask));
        numPendingWrites.up(); 
        debugLog.record($format("write addr=0x%x, val=0x%x, byteMask=0x%x, numPendingWrites=0x%x", 
                        addr, val, byteMask, numPendingWrites.value()));
    endmethod

    method Bool writeNotFull = incomingReqQ.ports[valueOf(n_READERS)].notFull();

    method Action fence();
        incomingReqQ.ports[valueOf(n_READERS)+1].enq(unpack(zeroExtend(pack(RL_COH_DM_ALL_FENCE))));
        debugLog.record($format("recive memory fence request"));
    endmethod
    
    method Action writeFence();
        incomingReqQ.ports[valueOf(n_READERS)+1].enq(unpack(zeroExtend(pack(RL_COH_DM_WRITE_FENCE))));
        debugLog.record($format("recive memory write fence request"));
    endmethod
    
    method Action readFence();
        incomingReqQ.ports[valueOf(n_READERS)+1].enq(unpack(zeroExtend(pack(RL_COH_DM_READ_FENCE))));
        debugLog.record($format("recive memory read fence request"));
    endmethod

    method Bool writePending() = (numPendingWrites.value() != 0);
    method Bool readPending() = (numPendingReads.value() != 0);
      
endmodule

//
// mkWriteValidatedReg --
//     This module provides a register that can be seen as a read-only register
// using write method to intialize its value. This register can only be read
// after initialization. 
//
module mkWriteValidatedReg
    // interface:
    (Reg#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));
    
    Reg#(t_DATA) data <- mkRegU();
    Reg#(Bool) initialized <- mkReg(False);

    method t_DATA _read() if (initialized);
        return data;
    endmethod

    method Action _write(t_DATA val) if (!initialized);
        initialized <= True;
        data <= val;
    endmethod
endmodule

typedef struct
{
    COH_SCRATCH_PORT_NUM       requester;
    COH_SCRATCH_MEM_VALUE      val;
    Bool                       ownership;
    Bool                       isCacheable;
    Bool                       retry;
    COH_SCRATCH_META           meta;
    RL_CACHE_GLOBAL_READ_META  globalReadMeta;
}
RL_COH_DM_CACHE_SNOOPED_REQ_TABLE_ENTRY
    deriving(Bits, Eq);


//
// Statistics wires for coherent scratchpad ring nodes.
// When a line becomes true the coresponding statistic should be incremented.
//
interface COH_SCRATCH_RING_NODE_STATS;
    method Bool localMsgSent();  // send local message on to the ring
    method Bool fwdMsgSent();    // forward message on the ring
    method Bool msgReceived();   // receive message from the ring
endinterface: COH_SCRATCH_RING_NODE_STATS

//
// mkCoherentScratchpadCacheSourceData --
//     Connection between a private cache for a coherent scratchpad client and 
// the coherence rings that connect all coherent scratchpad clients and the 
// coherent scratchpad controller for this coherence memory region.  Requests 
// arrive here when the cache either misses or needs to flush dirty data.  
// Requests will be forwarded to the coherent scratchpad controller.
//
module [CONNECTED_MODULE] mkCoherentScratchpadCacheSourceData#(Integer scratchpadID, 
                                                               COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR reqStatsConstructor,
                                                               COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR respStatsConstructor,
                                                               DEBUG_FILE debugLog)
    // interface:
    (RL_COH_DM_CACHE_SOURCE_DATA#(t_CACHE_ADDR, COH_SCRATCH_MEM_VALUE, t_CACHE_META, t_REQ_IDX))
    provisos (Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_META, t_CACHE_META_SZ),
              Bits#(t_REQ_IDX, t_REQ_IDX_SZ),
              NumAlias#(TExp#(t_REQ_IDX_SZ), n_REQ_TABLE_ENTRIES),
              Alias#(COH_SCRATCH_MEM_VALUE, t_CACHE_WORD),
              // Coherence messages
              Alias#(COH_SCRATCH_MEM_REQ#(t_CACHE_ADDR), t_UNACTIVATED_REQ),
              Alias#(COH_SCRATCH_ACTIVATED_REQ#(t_CACHE_ADDR), t_ACTIVATED_REQ),
              Alias#(RL_COH_DM_CACHE_FILL_RESP#(t_CACHE_WORD, t_CACHE_META), t_COH_CACHE_FILL_RESP),
              Alias#(RL_COH_DM_CACHE_NETWORK_REQ#(t_CACHE_ADDR, t_REQ_IDX), t_CACHE_NW_REQ),
              Alias#(RL_COH_DM_CACHE_SNOOPED_REQ_TABLE_ENTRY, t_REQ_INFO_ENTRY),
              Bounded#(t_REQ_IDX));

    if (valueOf(t_CACHE_META_SZ) > valueOf(COH_SCRATCH_CLIENT_META_SZ))
    begin
        error("Scratchpad ID " + integerToString(scratchpadID) + " client meta size is too large: " + integerToString(valueOf(t_CACHE_META_SZ)) + " bits");
    end

    Reg#(COH_SCRATCH_PORT_NUM) myPort <- mkWriteValidatedReg();

    // =======================================================================
    //
    // Coherent scratchpad clients and the coherent scratchpad controller are 
    // connected via rings.
    //
    // Three rings are required to avoid deadlocks: one for requests, 
    // one for responses, and one for activated requests.
    //
    // =======================================================================

    // Addressable ring (self-enumeration)
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_UNACTIVATED_REQ) link_mem_req <-
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingDynNode("Coherent_Scratchpad_" + integerToString(scratchpadID) + "_Req"):
        mkConnectionTokenRingDynNode("Coherent_Scratchpad_" + integerToString(scratchpadID) + "_Req");
        
    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP) link_mem_resp <-
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode("Coherent_Scratchpad_" + integerToString(scratchpadID) + "_Resp", myPort._read()):
        mkConnectionTokenRingNode("Coherent_Scratchpad_" + integerToString(scratchpadID) + "_Resp", myPort._read());

    // Broadcast ring
    CONNECTION_CHAIN#(t_ACTIVATED_REQ) link_mem_activatedReq <- 
        mkConnectionChain("Coherent_Scratchpad_" + integerToString(scratchpadID) + "_ActivatedReq");
   

    // =======================================================================
    //
    // Ring stats
    //
    // =======================================================================
    let req_stats = ?;
    let resp_stats = ?;

`ifndef ADDR_RING_DEBUG_ENABLE_Z
    req_stats = interface COH_SCRATCH_RING_NODE_STATS;
                    method Bool localMsgSent() = link_mem_req.localMsgSent();  
                    method Bool fwdMsgSent()   = link_mem_req.fwdMsgSent();  
                    method Bool msgReceived()  = link_mem_req.msgReceived();  
                endinterface;
    
    resp_stats = interface COH_SCRATCH_RING_NODE_STATS;
                     method Bool localMsgSent() = link_mem_resp.localMsgSent();  
                     method Bool fwdMsgSent()   = link_mem_resp.fwdMsgSent();  
                     method Bool msgReceived()  = link_mem_resp.msgReceived();  
                 endinterface;
`endif
    
    reqStatsConstructor(req_stats);
    respStatsConstructor(resp_stats);
    
    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================


    Reg#(Bool) initialized <- mkReg(False);
    
    // Assign the port number got from request ring's self-enumeration to the response ring
    rule doInit (!initialized);
        initialized <= True;
        let port_num = link_mem_req.nodeID();
        myPort <= port_num;
        debugLog.record($format("    sourceData: assigned port ID = %0d", port_num));
    endrule


    // =======================================================================
    //
    // Forward unactivated requests
    //
    // =======================================================================

    FIFOF#(t_UNACTIVATED_REQ) unactivatedReqQ <- mkSizedFIFOF(valueOf(RL_COH_DM_CACHE_NW_REQ_BUF_SIZE));
    PulseWire unactivatedReqSentW <- mkPulseWire();
    COUNTER#(4) numBufferedReq <- mkLCounter(0);

    (* fire_when_enabled *)
    rule sendReqToNetwork (True);
        let r = unactivatedReqQ.first();
        unactivatedReqQ.deq();
        link_mem_req.enq(0, r);
        numBufferedReq.downBy(1);
        unactivatedReqSentW.send();
        debugLog.record($format("    sourceData: sendReqToNetwork: numBufferedReq=%x", numBufferedReq.value()));
    endrule

    // =======================================================================
    //
    // Snoop activated requests
    //
    // =======================================================================
    
    // The request info of activated GETS/GETX from other clients and the 
    // cache's own activated PUTX is kept in a memory heap and waiting for 
    // the cache's responses (write back data is seen as the response for PUTX). 
    //
    // The heap size limits the number of in-flight activated requests to be 
    // processed in the cache. 
    MEMORY_HEAP_IMM#(t_REQ_IDX, t_REQ_INFO_ENTRY) snoopedReqTable <- mkMemoryHeapUnionLUTRAM();
    FIFO#(t_CACHE_NW_REQ) activatedReqQ <- mkSizedFIFO(valueOf(n_REQ_TABLE_ENTRIES));

    //
    // snoopActivatedReq --
    //      Snoop activated requests on the activated request ring and 
    // forward them on the same ring. 
    //
    rule snoopActivatedReq (True);
        let req <- link_mem_activatedReq.recvFromPrev();
        t_REQ_INFO_ENTRY new_entry = ?;
        t_CACHE_NW_REQ cache_req = ?;
        Bool need_snoop = False;
        debugLog.record($format("    sourceData: check activated request from the ring..."));
        
        case (req) matches
            tagged COH_SCRATCH_ACTIVATED_GETS .gets_req:
            begin
                cache_req.ownReq          = (gets_req.requester == myPort);
                cache_req.addr            = gets_req.addr;
                cache_req.reqType         = COH_CACHE_GETS;
                need_snoop                = !cache_req.ownReq;
                new_entry.requester       = gets_req.requester;
                new_entry.ownership       = False; 
                new_entry.isCacheable     = True;
                new_entry.meta            = zeroExtendNP(gets_req.clientMeta); 
                new_entry.globalReadMeta  = gets_req.globalReadMeta;
                debugLog.record($format("    sourceData: check activated %s GETS request: addr=0x%x", (cache_req.ownReq)? "own" : "other", cache_req.addr));
            end
            tagged COH_SCRATCH_ACTIVATED_GETX .getx_req:
            begin
                cache_req.ownReq          = (getx_req.requester == myPort);
                cache_req.addr            = getx_req.addr;
                cache_req.reqType         = COH_CACHE_GETX;
                need_snoop                = !cache_req.ownReq;
                new_entry.requester       = getx_req.requester;
                new_entry.ownership       = True;
                new_entry.isCacheable     = True;
                new_entry.meta            = zeroExtendNP(getx_req.clientMeta); 
                new_entry.globalReadMeta  = getx_req.globalReadMeta;
                debugLog.record($format("    sourceData: check activated %s GETX request: addr=0x%x", (cache_req.ownReq)? "own" : "other", cache_req.addr));
            end
            tagged COH_SCRATCH_ACTIVATED_PUTX .putx_req:
            begin
                cache_req.ownReq          = (putx_req.requester == myPort);
                cache_req.addr            = putx_req.addr;
                cache_req.reqType         = COH_CACHE_PUTX;
                need_snoop                = cache_req.ownReq && !putx_req.isCleanWB;
                new_entry.requester       = 0;
                new_entry.ownership       = True;
                new_entry.isCacheable     = True;
                new_entry.meta            = zeroExtendNP(putx_req.controllerMeta); 
                debugLog.record($format("    sourceData: check activated %s PUTX request: addr=0x%x", (cache_req.ownReq)? "own" : "other", cache_req.addr));
            end
        endcase
       
        // allocate an entry in the snoopedReqTable if the activated request needs 
        // to be snooped (own activated PUTX that is not clean write-back also needs
        // to be included because the controller is waiting for the write back data)
        if (need_snoop)
        begin
            let idx <- snoopedReqTable.malloc();
            snoopedReqTable.upd(idx, new_entry);
            cache_req.reqIdx = idx;
            debugLog.record($format("    sourceData: allocate snoopedReqTable entry (idx=0x%x)", idx));
        end
        
        // request to be sent to the cache
        if (cache_req.ownReq || need_snoop)
        begin
            activatedReqQ.enq(cache_req);
        end

        // forward activated request on the ring
        link_mem_activatedReq.sendToNext(req);
    endrule

    // =======================================================================
    //
    // Send responses
    //
    // =======================================================================

    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP)) respToNetworkQ  <- mkBypassFIFOF();
    FIFOF#(t_REQ_IDX) respReadyEntryQ <- mkSizedFIFOF(valueOf(n_REQ_TABLE_ENTRIES));
    FIFOF#(Tuple4#(t_REQ_IDX, t_CACHE_WORD, Bool, Bool)) respFromCacheQ <- mkBypassFIFOF();

    //
    // recvRespFromCache --
    //     Generate the response to the ring and free the entry in the completion
    // table (snoopedReqTable) if respToNetworkQ is not full. Otherwise, store
    // the response info back to snoopedReqTable.
    //
    (* fire_when_enabled *)
    rule recvRespFromCache (respFromCacheQ.notEmpty());
        match {.idx, .val, .retry, .nullResp} = respFromCacheQ.first();
        respFromCacheQ.deq();
        let e = snoopedReqTable.sub(idx);
        
        if (respToNetworkQ.notFull() && !nullResp)
        begin
            respToNetworkQ.enq(tuple2(e.requester, COH_SCRATCH_RESP { val: val,
                                                                      ownership: e.ownership,
                                                                      meta: e.meta, 
                                                                      globalReadMeta: e.globalReadMeta,
                                                                      isCacheable: e.isCacheable,
                                                                      retry: retry }));
            
            debugLog.record($format("    sourceData: recvRespFromCache: send response: dest=%d, val=0x%x, ownership=%s, %s", 
                            e.requester, val, (e.ownership)? "True" : "False", (retry)? "RETRY!!!" : " "));
        end

        if (respToNetworkQ.notFull() || nullResp)
        begin
            snoopedReqTable.free(idx); 
            debugLog.record($format("    sourceData: recvRespFromCache: free snoopedReqTable (entry=0x%x)", idx));
        end
        else
        begin
            // update snoopedReqTable if not able to send response
            let new_entry = e;
            new_entry.val = val;
            new_entry.retry = retry;
            snoopedReqTable.upd(idx, new_entry);
            respReadyEntryQ.enq(idx);
            debugLog.record($format("    sourceData: recvRespFromCache: resp queue is full! table entry=0x%x, wait in the respReadyEntryQ...", idx));
        end
    endrule

    //
    // sendRespFromSnoopTable --
    //     Second time trying to send response to the ring. 
    //
    //(* descending_urgency = "sendRespFromCache, storeRespFromCache, recvNullRespFromCache, sendRespFromSnoopTable, snoopActivatedReq" *)
    (* descending_urgency = "recvRespFromCache, sendRespFromSnoopTable, snoopActivatedReq" *)
    rule sendRespFromSnoopTable (respReadyEntryQ.notEmpty() && respToNetworkQ.notFull());
        let idx = respReadyEntryQ.first();
        respReadyEntryQ.deq();
        let e = snoopedReqTable.sub(idx);
        // send response
        respToNetworkQ.enq(tuple2(e.requester, COH_SCRATCH_RESP { val: e.val,
                                                                  ownership: e.ownership,
                                                                  meta: e.meta, 
                                                                  globalReadMeta: e.globalReadMeta,
                                                                  isCacheable: e.isCacheable,
                                                                  retry: e.retry }));
        
        debugLog.record($format("    sourceData: send response from snoopedReqTable: dest=%d, val=0x%x, ownership=%s, %s", 
                        e.requester, e.val, (e.ownership)? "True" : "False", (e.retry)? "RETRY!!!" : " "));
        // free the entry in snoopedReqTable
        snoopedReqTable.free(idx); 
        debugLog.record($format("    sourceData: sendRespFromSnoopTable: free snoopedReqTable (entry=0x%x)", idx));
    endrule

    (* fire_when_enabled *)
    rule sendRespToNetwork (True);
        let resp = respToNetworkQ.first();
        respToNetworkQ.deq();
        link_mem_resp.enq(tpl_1(resp), tpl_2(resp));
        debugLog.record($format("    sourceData: sendRespToNetwork: val=0x%x ", tpl_2(resp).val));
    endrule

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================

    // Request for share data
    method Action getShare(t_CACHE_ADDR addr,
                           t_CACHE_META meta,
                           RL_CACHE_GLOBAL_READ_META globalReadMeta) if (initialized);
    
        let req = COH_SCRATCH_GET_REQ { requester: myPort,
                                        addr: addr,
                                        clientMeta: unpack(zeroExtendNP(pack(meta))),
                                        globalReadMeta: globalReadMeta };

        // Forward the request to the coherent scratchpad controller that orders
        // all coherent scratchpad clients' requests
        unactivatedReqQ.enq(tagged COH_SCRATCH_GETS req);

        debugLog.record($format("    sourceData: send GETS REQ ID %0d: addr 0x%x", myPort, addr));
        
        numBufferedReq.upBy(1);
        debugLog.record($format("    sourceData: getShare: numBufferedReq=%x", numBufferedReq.value()));
    endmethod
    
    
    // Request for data and exlusive ownership
    method Action getExclusive(t_CACHE_ADDR addr,
                               t_CACHE_META meta,
                               RL_CACHE_GLOBAL_READ_META globalReadMeta) if (initialized);

        let req = COH_SCRATCH_GET_REQ { requester: myPort,
                                        addr: addr,
                                        clientMeta: unpack(zeroExtendNP(pack(meta))),
                                        globalReadMeta: globalReadMeta };

        // Forward the request to the coherent scratchpad controller that orders
        // all coherent scratchpad clients' requests
        unactivatedReqQ.enq(tagged COH_SCRATCH_GETX req);

        debugLog.record($format("    sourceData: send GETX REQ ID %0d: addr 0x%x", myPort, addr));

        numBufferedReq.upBy(1);
        debugLog.record($format("    sourceData: getExclusive: numBufferedReq=%x", numBufferedReq.value()));
    endmethod                           

    // Response received from other coherent scratchpad clients or the controller (memory)
    method ActionValue#(t_COH_CACHE_FILL_RESP) getResp();
        let s = link_mem_resp.first();
        link_mem_resp.deq();

        t_COH_CACHE_FILL_RESP r;
        r.val = s.val;
        r.meta = unpack(truncateNP(s.meta));
        r.ownership = s.ownership;
        r.isCacheable = s.isCacheable;
        r.retry = s.retry;
        r.globalReadMeta = s.globalReadMeta;
        
        debugLog.record($format("    sourceData: read RESP: val=0x%x, meta=0x%x", s.val, r.meta));

        return r;
    endmethod
    
    method t_COH_CACHE_FILL_RESP peekResp();
        let s = link_mem_resp.first();

        t_COH_CACHE_FILL_RESP r;
        r.val = s.val;
        r.meta = unpack(truncateNP(s.meta));
        r.ownership = s.ownership;
        r.isCacheable = s.isCacheable;
        r.retry = s.retry;
        r.globalReadMeta = s.globalReadMeta;
        
        return r;
    endmethod                                  
    
    // Request for writing back data and giving up ownership 
    method Action putExclusive(t_CACHE_ADDR addr, Bool isCleanWB) if (initialized);

        let req = COH_SCRATCH_PUT_REQ { requester: myPort,
                                        addr: addr,
                                        isCleanWB: isCleanWB };

        // Forward the request to the coherent scratchpad controller that orders
        // all coherent scratchpad clients' requests
        unactivatedReqQ.enq(tagged COH_SCRATCH_PUTX req);

        debugLog.record($format("    sourceData: send PUTX REQ ID %0d: addr 0x%x, isCleanWB=%s", 
                        myPort, addr, isCleanWB? "True" : "False"));
        
        numBufferedReq.upBy(1);
        debugLog.record($format("    sourceData: putExclusive: numBufferedReq=%x", numBufferedReq.value()));
    endmethod                           
   
    // Signal indicating an unactivated request is sent to the network
    // (One slot in the request buffer is released)
    method Bool unactivatedReqSent() = unactivatedReqSentW;
       
    // Data owner sends responses to serve other caches
    // If it is not the owner, null response is sent to clear the entry in the 
    // completion table 
    method Action sendResp(t_REQ_IDX reqIdx,
                           t_CACHE_WORD val,
                           Bool retry,
                           Bool nullResp) if (initialized);
        
        respFromCacheQ.enq(tuple4(reqIdx, val, retry, nullResp));
        debugLog.record($format("    sourceData: receive response from cache: entry=0x%x, val=0x%x, retry=%s, nullResp=%s", 
                        reqIdx, val, retry? "True" : "False", nullResp? "True" : "False"));
    
    endmethod                       

    //
    // Activated requests from the network
    // In a snoopy-based protocol, the requests may be the cache's own requests or
    // from other caches or next level in the hierarchy
    //
    method ActionValue#(t_CACHE_NW_REQ) activatedReq();
        let r = activatedReqQ.first();
        activatedReqQ.deq();
        return r;
    endmethod

    method t_CACHE_NW_REQ peekActivatedReq();
        let r = activatedReqQ.first();
        return r;
    endmethod

    // Pass invalidate and flush requests down the hierarchy.
    // invalOrFlushWait must block until the operation is complete.
    //
    // In the current version, these two requests are not implemented.
    //
    method Action invalReq(t_CACHE_ADDR addr);
        noAction;
    endmethod

    method Action flushReq(t_CACHE_ADDR addr);
        noAction;
    endmethod
    
    method Action invalOrFlushWait();
        noAction;
    endmethod

endmodule


//
// mkUncachedCoherentScratchpadClient --
//     Allocate an uncached connection to the coherent scratchpad rings of a 
// particular coherent scratchpad memory region. 
//
module [CONNECTED_MODULE] mkUncachedCoherentScratchpadClient#(Integer scratchpadID, 
                                                              DEBUG_FILE debugLog)
    // interface:
    (MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // coherence message
              Alias#(COH_SCRATCH_REMOTE_REQ#(Bit#(t_ADDR_SZ), Bit#(t_DATA_SZ)), t_COH_SCRATCH_REQ),
              Alias#(COH_SCRATCH_REMOTE_RESP#(Bit#(t_DATA_SZ)), t_COH_SCRATCH_RESP),
              // Index in a reorder buffer
              Alias#(SCOREBOARD_FIFO_ENTRY_ID#(COH_SCRATCH_PORT_ROB_SLOTS), t_REORDER_ID),
              // MAF for in-flight reads
              Alias#(Tuple2#(Bit#(TLog#(n_READERS)), t_REORDER_ID), t_MAF_IDX),
              Bits#(t_MAF_IDX, t_MAF_IDX_SZ));

    // ===============================================================================
    //
    // Coherent scratchpad clients and this controller are connected via rings.
    //
    // Two rings are required to avoid deadlocks: one for requests, one for responses.
    //
    // ===============================================================================

    Reg#(COH_SCRATCH_PORT_NUM) myPort <- mkWriteValidatedReg();
   
    // Addressable ring (self-enumeration)
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_REQ) link_mem_req <- 
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingDynNode("Coherent_Scratchpad_" + integerToString(scratchpadID) + "_Req"):
        mkConnectionTokenRingDynNode("Coherent_Scratchpad_" + integerToString(scratchpadID) + "_Req");

    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_COH_SCRATCH_RESP) link_mem_resp <-
        (`COHERENT_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode("Coherent_Scratchpad_" + integerToString(scratchpadID) + "_Resp", myPort._read()):
        mkConnectionTokenRingNode("Coherent_Scratchpad_" + integerToString(scratchpadID) + "_Resp", myPort._read());
   
    // =======================================================================
    //
    // Initialization
    //
    // =======================================================================

    Reg#(Bool) initialized <- mkReg(False);
    
    // Assign the port number got from request ring's self-enumeration to the response ring
    rule doInit (!initialized);
        initialized <= True;
        let port_num = link_mem_req.nodeID();
        myPort <= port_num;
        debugLog.record($format("assigned port ID = %0d", port_num));
    endrule

    // =======================================================================
    //
    // Request / response forwarding
    //
    // =======================================================================

    // Merge FIFOF combines read, write requests in temporal order, with reads 
    // from the same cycle as a write going first.  Each read port gets a slot. 
    // The write port is always last.
    MERGE_FIFOF#(TAdd#(n_READERS, 1), Tuple2#(t_ADDR, t_REORDER_ID)) incomingReqQ <- mkMergeFIFOF();
    
    // Write data is sent in a side port to keep the incomingReqQ smaller.
    FIFO#(t_DATA) writeDataQ <- mkFIFO();
    
    // Cache responses are not ordered.  Sort them with a reorder buffer.
    Vector#(n_READERS, SCOREBOARD_FIFOF#(COH_SCRATCH_PORT_ROB_SLOTS, t_DATA)) sortResponseQ <- replicateM(mkScoreboardFIFOF());
    
    // Read and write request counter
    COUNTER#(TLog#(TAdd#(TMul#(n_READERS, COH_SCRATCH_PORT_ROB_SLOTS),1))) numPendingReads  <- mkLCounter(0);
    COUNTER#(TLog#(TAdd#(COH_SCRATCH_PORT_ROB_SLOTS,1))) numPendingWrites <- mkLCounter(0);
    Vector#(n_READERS, PulseWire) readIssuedW <- replicateM(mkPulseWire());

    //
    // Update read request counter
    //
    rule incrNumReads (True);
        Bit#(n_READERS) reads = ?;
        for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
        begin
            reads[p] = readIssuedW[p]? 1 : 0;
        end
        numPendingReads.upBy(zeroExtendNP(pack(countOnesAlt(reads))));
    endrule
    
    // Read requests
    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        rule forwardReadReq (initialized && incomingReqQ.firstPortID() == fromInteger(p));
            match {.addr, .idx} = incomingReqQ.first();
            incomingReqQ.deq();

            t_MAF_IDX maf_idx = tuple2(fromInteger(p), idx);

            // Send read request on the ring
            let req = COH_SCRATCH_REMOTE_READ_REQ { requester: myPort,
                                                    addr: pack(addr),
                                                    clientMeta: unpack(zeroExtendNP(pack(maf_idx))),
                                                    globalReadMeta: defaultValue() };
                                                    
            link_mem_req.enq(0, tagged COH_SCRATCH_REMOTE_READ req);
        endrule
    end

    //
    // recvDataResp --
    //     Push read responses to the reorder buffer.  They will be returned
    //     through readRsp() in order.
    //
    rule recvDataResp (link_mem_resp.first() matches tagged COH_SCRATCH_REMOTE_READ .resp);
        link_mem_resp.deq();
        t_MAF_IDX maf_idx = unpack(truncateNP(pack(resp.clientMeta)));
        match {.port_num, .req_idx} = maf_idx;
        sortResponseQ[pack(port_num)].setValue(req_idx, unpack(resp.val));
        numPendingReads.down();
        debugLog.record($format("1 read request being processed, numPendingReads=0x%x", numPendingReads.value()));
    endrule

    // Write requests
    rule forwardWriteReq (initialized && incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS)));
        let addr = tpl_1(incomingReqQ.first());
        incomingReqQ.deq();
        let w_data = writeDataQ.first();
        writeDataQ.deq();
        // Send read request on the ring
        let req = COH_SCRATCH_REMOTE_WRITE_REQ { requester: myPort,
                                                 addr: pack(addr),
                                                 data: pack(w_data) };
        link_mem_req.enq(0, tagged COH_SCRATCH_REMOTE_WRITE req);
    endrule
   
    // Write ack
    rule recvWriteAck (link_mem_resp.first() matches tagged COH_SCRATCH_REMOTE_WRITE);
        link_mem_resp.deq();
        numPendingWrites.down();
        debugLog.record($format("1 write request being processed, numPendingWrites=0x%x", numPendingWrites.value()));
    endrule

    // =======================================================================
    //
    // Methods.  All requests are stored in the incomingReqQ to maintain their
    // order.
    //
    // =======================================================================

    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr);
                    // Allocate a slot in the reorder buffer for the read request.  Each
                    // read port gets its own reorder buffer.
                    let idx <- sortResponseQ[p].enq();
                    incomingReqQ.ports[p].enq(tuple2(addr, idx));
                    readIssuedW[p].send();
                    debugLog.record($format("read port %0d: req addr=0x%x, rob idx=%0d, numPendingReads=0x%x", 
                                    p, addr, idx, numPendingReads.value()));
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let r = sortResponseQ[p].first();
                    sortResponseQ[p].deq();
                    debugLog.record($format("read port %0d: resp val=0x%x", p, r));
                    return r;
                endmethod

                method t_DATA peek();
                    return sortResponseQ[p].first();
                endmethod
                method Bool notEmpty() = sortResponseQ[p].notEmpty();
                method Bool notFull() = incomingReqQ.ports[p].notFull() &&
                                        sortResponseQ[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val) if (numPendingWrites.value() != maxBound);
        // The write port is the second from last in the merge FIFO
        incomingReqQ.ports[valueOf(n_READERS)].enq(tuple2(addr, ?));
        writeDataQ.enq(val);
        numPendingWrites.up(); 
        debugLog.record($format("write addr=0x%x, val=0x%x, numPendingWrites=0x%x", 
                        addr, val, numPendingWrites.value()));
    endmethod

    method Bool writeNotFull = incomingReqQ.ports[valueOf(n_READERS)].notFull();

    method Action fence();
        noAction;
    endmethod
    
    method Action writeFence();
        noAction;
    endmethod
    
    method Action readFence();
        noAction;
    endmethod

    method Bool writePending() = (numPendingWrites.value() != 0);
    method Bool readPending() = (numPendingReads.value() != 0);
      
endmodule
