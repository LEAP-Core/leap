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
`include "awb/provides/shared_scratchpad_memory_common.bsh"
`include "awb/provides/uncached_shared_scratchpad_memory_service.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/coherent_cache.bsh"
`include "awb/dict/PARAMS_COHERENT_SCRATCHPAD_MEMORY_SERVICE.bsh"

// Number of slots in a read port's reorder buffer.  The coherent scratchpad 
// subsystem does not guarantee to return results in order, so all clients 
// need a ROB. The ROB size limits the number of read requests in flight 
// for a given port.

typedef SCRATCHPAD_PORT_ROB_SLOTS COH_SCRATCH_PORT_ROB_SLOTS;
typedef SCRATCHPAD_PORT_ROB_SLOTS COH_SCRATCH_TEST_SET_ROB_SLOTS;

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
module [CONNECTED_MODULE] mkCoherentScratchpadClient#(Integer scratchpadID, COH_SCRATCH_CLIENT_CONFIG conf)
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
    MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) scratch <- mkMultiReadMemFenceIfcToMemFenceIfc(m_scratch);
    return scratch;
endmodule

//
// mkMultiReadCoherentScratchpadClient --
//     The same as a normal mkCoherentScratchpadClient but with multiple read ports.
//     Requests are processed in order, with reads being scheduled before
//     a write requested in the same cycle.
//
module [CONNECTED_MODULE] mkMultiReadCoherentScratchpadClient#(Integer scratchpadID, COH_SCRATCH_CLIENT_CONFIG conf)
    // interface:
    (MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    let statsConstructor = mkNullCoherentScratchpadCacheStats;
    let prefetchStatsConstructor = mkNullScratchpadPrefetchStats;
    let reqRingStatsConstructor = mkNullCoherentScratchpadRingNodeStats;
    let respRingStatsConstructor = mkNullCoherentScratchpadRingNodeStats;
    let debugScanNodeConstructor = mkNullCohScratchClientDebugScanNode;
    
    String debugFileName = "";
    if (conf.debugLogPath matches tagged Valid .log_name)
    begin
        debugFileName = log_name;
    end
    DEBUG_FILE debugLog <- (isValid(conf.debugLogPath))? mkDebugFile(debugFileName) : mkDebugFileNull(debugFileName); 

    if(conf.enableStatistics matches tagged Valid .stats_name)
    begin
        // stats_name example: String stats_name = "Coherent_scratchpad_" + integerToString(scratchpadID) + "_client_" + integerToString(statsID) + "_";
        statsConstructor = mkBasicCoherentScratchpadCacheStats(stats_name, "");

        NumTypeParam#(`SHARED_SCRATCHPAD_PVT_CACHE_PREFETCH_LEARNER_NUM) n_prefetch_learners = ?;
        prefetchStatsConstructor = (`SHARED_SCRATCHPAD_PVT_CACHE_PREFETCH_ENABLE == 1)?
                                   mkBasicScratchpadPrefetchStats(stats_name, "", n_prefetch_learners):
                                   mkNullScratchpadPrefetchStats;
        
        reqRingStatsConstructor = (`ADDR_RING_DEBUG_ENABLE == 1)? 
                                  mkBasicCoherentScratchpadRingNodeStats(stats_name + "req_", ""):
                                  mkNullCoherentScratchpadRingNodeStats;

        respRingStatsConstructor = (`ADDR_RING_DEBUG_ENABLE == 1)?
                                   mkBasicCoherentScratchpadRingNodeStats(stats_name + "resp_", ""):
                                   mkNullCoherentScratchpadRingNodeStats; 
    end
    
    if(conf.enableDebugScan matches tagged Valid .debug_scan_name)
    begin
        debugScanNodeConstructor = mkCohScratchClientDebugScanNode(debug_scan_name);
    end
    else if (`SHARED_SCRATCHPAD_DEBUG_ENABLE == 1)
    begin
        debugScanNodeConstructor = mkCohScratchClientDebugScanNode("Coherent Scratchpad Client " + integerToString(scratchpadID));
    end

    let m <- mkMultiReadStatsCoherentScratchpadClient(scratchpadID,
                                                      conf,
                                                      statsConstructor, 
                                                      prefetchStatsConstructor,
                                                      reqRingStatsConstructor,
                                                      respRingStatsConstructor,
                                                      debugScanNodeConstructor,
                                                      debugLog);
    return m;
endmodule

//
// mkMultiReadStatsCoherentScratchpadClient
//     Instantiate different coherent scratchpad client wrappers (marshallers) 
// based on user's requested data size.
//
module [CONNECTED_MODULE] mkMultiReadStatsCoherentScratchpadClient#(Integer scratchpadID,
                                                                    COH_SCRATCH_CLIENT_CONFIG conf,
                                                                    COH_SCRATCH_CACHE_STATS_CONSTRUCTOR statsConstructor,
                                                                    SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR prefetchStatsConstructor,
                                                                    COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR reqStatsConstructor,
                                                                    COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR respStatsConstructor,
                                                                    COH_SCRATCH_CLIENT_DEBUG_SCAN_NODE_CONSTRUCTOR debugScanNodeConstructor,
                                                                    DEBUG_FILE debugLog)
    // interface:
    (MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Compute the natural size in bits. The natural size is rounded up to
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
        mem <- mkUncachedSharedScratchpadClient(scratchpadID, debugLog);
    end
    else if (valueOf(t_NATURAL_SZ) <= valueOf(t_COH_SCRATCH_MEM_VALUE_SZ)/2)
    begin
        mem <- mkSmallMultiReadStatsCoherentScratchpadClient(scratchpadID, 
                                                             conf,
                                                             statsConstructor, 
                                                             prefetchStatsConstructor, 
                                                             reqStatsConstructor,
                                                             respStatsConstructor,
                                                             debugScanNodeConstructor,
                                                             debugLog);
    end
    else
    begin
        mem <- mkMediumMultiReadStatsCoherentScratchpadClient(scratchpadID, 
                                                              conf,
                                                              statsConstructor, 
                                                              prefetchStatsConstructor,
                                                              reqStatsConstructor,
                                                              respStatsConstructor,
                                                              debugScanNodeConstructor,
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
                                                                         COH_SCRATCH_CLIENT_CONFIG conf, 
                                                                         COH_SCRATCH_CACHE_STATS_CONSTRUCTOR cacheStats,
                                                                         SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR pfStats,
                                                                         COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR reqStats,
                                                                         COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR respStats,
                                                                         COH_SCRATCH_CLIENT_DEBUG_SCAN_NODE_CONSTRUCTOR debugScanNode,
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

    NumTypeParam#(t_ADDR_SZ) userAddrWidth = ?;

    NumTypeParam#(`SHARED_SCRATCHPAD_PVT_CACHE_PREFETCH_LEARNER_NUM) n_learners = ?;
    let mode = `PARAMS_COHERENT_SCRATCHPAD_MEMORY_SERVICE_COHERENT_SCRATCHPAD_PVT_CACHE_MODE;
    let e = conf.cacheEntries;
    let id = scratchpadID;

    // Instantiate the underlying memory.
    MEMORY_MULTI_READ_MASKED_WRITE_WITH_FENCE_IFC#(n_READERS, t_CONTAINER_ADDR, COH_SCRATCH_MEM_VALUE, t_CONTAINER_MASK) mem = ?; 

    // Require brute-force conversion because Integer cannot be converted to a type
    
    if      (e <= 8)      begin NumTypeParam#(8)      n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 16)     begin NumTypeParam#(16)     n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 32)     begin NumTypeParam#(32)     n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 64)     begin NumTypeParam#(64)     n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 128)    begin NumTypeParam#(128)    n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 256)    begin NumTypeParam#(256)    n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 512)    begin NumTypeParam#(512)    n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 1024)   begin NumTypeParam#(1024)   n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 2048)   begin NumTypeParam#(2048)   n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 4096)   begin NumTypeParam#(4096)   n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 8192)   begin NumTypeParam#(8192)   n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    
    // Below here, we size the coherent scratchpads to take advantage of non-power-of-two
    // caches.  We could do this for the smaller caches, but the impact would be 
    // limited. Synplify can only do non-power of two caches if they are larger 
    // than 16K. Vivado unfortunately doesn't support this yet. 
    
    else if (e <= 16384)  begin NumTypeParam#(16384)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 20480)  begin NumTypeParam#(20480)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 24576)  begin NumTypeParam#(24576)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 28672)  begin NumTypeParam#(28672)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 32768)  begin NumTypeParam#(32768)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 40960)  begin NumTypeParam#(40960)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 49152)  begin NumTypeParam#(49152)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 57344)  begin NumTypeParam#(57344)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 65536)  begin NumTypeParam#(65536)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 81920)  begin NumTypeParam#(81920)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 98304)  begin NumTypeParam#(98304)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 114688) begin NumTypeParam#(114688) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 131072) begin NumTypeParam#(131072) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 163840) begin NumTypeParam#(163840) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 196608) begin NumTypeParam#(196608) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 229376) begin NumTypeParam#(229376) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else                  begin NumTypeParam#(262144) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 

    
    // Read request info holds the address of the requested data within the container.
    Vector#(n_READERS, FIFO#(t_OBJ_IDX)) readReqInfoQ <- replicateM(mkSizedFIFO(valueOf(COH_SCRATCH_PORT_ROB_SLOTS)));

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    FIFO#(t_OBJ_IDX) testAndSetReqInfoQ <- mkSizedFIFO(valueOf(COH_SCRATCH_TEST_SET_ROB_SLOTS));
`endif

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
                    debugLog.record($format("wrapper: read port %0d: req addr=0x%x, obj idx=%0d, scratchpad addr=0x%x", 
                                    p, addr, o_idx, c_addr));
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let o_idx = readReqInfoQ[p].first();
                    readReqInfoQ[p].deq();
                    // Receive the data and return the desired object from the container.
                    let d <- mem.readPorts[p].readRsp();
                    t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
                    debugLog.record($format("wrapper: read port %0d: obj idx=%0d, resp val=0x%x", p, o_idx, pack_data[o_idx]));
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
        debugLog.record($format("wrapper: write req addr=0x%x, obj idx=%0d, val=0x%x, scratchpad addr=0x%x, scratchpad data=0x%x", 
                        addr, o_idx, val, c_addr, pack(pack_data)));
    endmethod

    method Bool writeNotFull() = mem.writeNotFull();
   
   
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_ADDR addr, t_DATA val);
        match {.c_addr, .o_idx} = addrSplit(addr);
        // Put the data at the right place in the container
        t_PACKED_CONTAINER pack_data = unpack(0);
        pack_data[o_idx] = zeroExtendNP(pack(val));
        testAndSetReqInfoQ.enq(o_idx);
        mem.testAndSetReq(c_addr, unpack(zeroExtendNP(pack(pack_data))), computeByteMask(o_idx));
    endmethod

    method ActionValue#(t_DATA) testAndSetRsp();
        let o_idx = testAndSetReqInfoQ.first();
        testAndSetReqInfoQ.deq();
        // Receive the data and return the desired object from the container.
        let d <- mem.testAndSetRsp();
        t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
        return unpack(truncateNP(pack_data[o_idx]));
    endmethod
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence() = mem.fence();
    method Action writeFence() = mem.writeFence();
    method Action readFence() = mem.readFence();
`endif

    method Bool writePending() = mem.writePending();
    method Bool readPending() = mem.readPending();

endmodule


//
// mkMediumMultiReadStatsCoherentScratchpadClient --
//     Only one data object is stored in one coherent scratchpad container. 
//
module [CONNECTED_MODULE] mkMediumMultiReadStatsCoherentScratchpadClient#(Integer scratchpadID,
                                                                          COH_SCRATCH_CLIENT_CONFIG conf, 
                                                                          COH_SCRATCH_CACHE_STATS_CONSTRUCTOR cacheStats,
                                                                          SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR pfStats,
                                                                          COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR reqStats,
                                                                          COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR respStats,
                                                                          COH_SCRATCH_CLIENT_DEBUG_SCAN_NODE_CONSTRUCTOR debugScanNode,
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

    NumTypeParam#(t_ADDR_SZ) userAddrWidth = ?;

    NumTypeParam#(`SHARED_SCRATCHPAD_PVT_CACHE_PREFETCH_LEARNER_NUM) n_learners = ?;
    let mode = `PARAMS_COHERENT_SCRATCHPAD_MEMORY_SERVICE_COHERENT_SCRATCHPAD_PVT_CACHE_MODE;
    let e = conf.cacheEntries;
    let id = scratchpadID;

    // Instantiate the underlying memory.
    MEMORY_MULTI_READ_MASKED_WRITE_WITH_FENCE_IFC#(n_READERS, t_CONTAINER_ADDR, COH_SCRATCH_MEM_VALUE, t_CONTAINER_MASK) mem = ?; 

    // Require brute-force conversion because Integer cannot be converted to a type
    
    if      (e <= 8)      begin NumTypeParam#(8)      n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 16)     begin NumTypeParam#(16)     n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 32)     begin NumTypeParam#(32)     n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 64)     begin NumTypeParam#(64)     n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 128)    begin NumTypeParam#(128)    n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 256)    begin NumTypeParam#(256)    n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 512)    begin NumTypeParam#(512)    n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 1024)   begin NumTypeParam#(1024)   n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 2048)   begin NumTypeParam#(2048)   n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 4096)   begin NumTypeParam#(4096)   n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 8192)   begin NumTypeParam#(8192)   n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    
    // Below here, we size the coherent scratchpads to take advantage of non-power-of-two
    // caches.  We could do this for the smaller caches, but the impact would be 
    // limited. Synplify can only do non-power of two caches if they are larger 
    // than 16K. Vivado unfortunately doesn't support this yet. 
    
    else if (e <= 16384)  begin NumTypeParam#(16384)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 20480)  begin NumTypeParam#(20480)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 24576)  begin NumTypeParam#(24576)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 28672)  begin NumTypeParam#(28672)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 32768)  begin NumTypeParam#(32768)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 40960)  begin NumTypeParam#(40960)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 49152)  begin NumTypeParam#(49152)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 57344)  begin NumTypeParam#(57344)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 65536)  begin NumTypeParam#(65536)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 81920)  begin NumTypeParam#(81920)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 98304)  begin NumTypeParam#(98304)  n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 114688) begin NumTypeParam#(114688) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 131072) begin NumTypeParam#(131072) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 163840) begin NumTypeParam#(163840) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 196608) begin NumTypeParam#(196608) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else if (e <= 229376) begin NumTypeParam#(229376) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 
    else                  begin NumTypeParam#(262144) n = ?; mem <- mkUnmarshalledCachedCoherentScratchpadClient(id, conf, mode, n, n_learners, userAddrWidth, cacheStats, pfStats, reqStats, respStats, debugScanNode, debugLog); end 

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
    
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_ADDR addr, t_DATA val);
        mem.testAndSetReq(addr, unpack(zeroExtendNP(pack(val))), unpack(pack(replicate(True))));
    endmethod

    method ActionValue#(t_DATA) testAndSetRsp();
        let d <- mem.testAndSetRsp();
        return unpack(truncateNP(pack(d)));
    endmethod
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence() = mem.fence();
    method Action writeFence() = mem.writeFence();
    method Action readFence() = mem.readFence();
`endif

    method Bool writePending() = mem.writePending();
    method Bool readPending() = mem.readPending();
endmodule

// number of entries in the merge table
typedef 32 COH_SCRATCH_MERGE_TABLE_ENTRIES;

typedef struct
{
    t_MERGE_TAG               tag;
    Vector#(n_ENTRIES, Bool)  mergeMeta;
}
COH_SCRATCH_MERGE_TABLE_ENTRY#(type t_MERGE_TAG, 
                               numeric type n_ENTRIES)
    deriving(Bits, Eq);


//
// mkUnmarshalledCachedCoherentScratchpadClient --
//     Allocate a cached connection to the coherent scratchpad rings of a 
// particular coherent scratchpad memory region.  This module does no marshalling 
// of data sizes.
//
module [CONNECTED_MODULE] mkUnmarshalledCachedCoherentScratchpadClient#(Integer scratchpadID, 
                                                                        COH_SCRATCH_CLIENT_CONFIG conf, 
                                                                        Integer cacheModeParam,
                                                                        NumTypeParam#(n_CACHE_ENTRIES) nCacheEntries,
                                                                        NumTypeParam#(n_PREFETCH_LEARNER_SIZE) nPrefetchLearners,
                                                                        NumTypeParam#(t_ADDR_SZ) userAddrWidth,
                                                                        COH_SCRATCH_CACHE_STATS_CONSTRUCTOR statsConstructor,
                                                                        SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR prefetchStatsConstructor,
                                                                        COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR reqStatsConstructor,
                                                                        COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR respStatsConstructor,
                                                                        COH_SCRATCH_CLIENT_DEBUG_SCAN_NODE_CONSTRUCTOR debugScanNodeConstructor,
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
              Alias#(SCOREBOARD_FIFO_ENTRY_ID#(TMin#(COH_SCRATCH_PORT_ROB_SLOTS, COH_SCRATCH_TEST_SET_ROB_SLOTS)), t_TS_REORDER_ID),
              // Request merge table
              NumAlias#(TMin#(t_MEM_ADDR_SZ, TLog#(COH_SCRATCH_MERGE_TABLE_ENTRIES)), t_MERGE_IDX_SZ),
              Alias#(Bit#(t_MERGE_IDX_SZ), t_MERGE_IDX),
              Alias#(Bit#(TSub#(t_MEM_ADDR_SZ, t_MERGE_IDX_SZ)), t_MERGE_TAG),
              NumAlias#(TMax#(1, TExp#(TAdd#(TLog#(n_READERS), TLog#(COH_SCRATCH_PORT_ROB_SLOTS)))), n_MERGE_META_ENTRIES),
              Alias#(COH_SCRATCH_MERGE_TABLE_ENTRY#(t_MERGE_TAG, n_MERGE_META_ENTRIES), t_MERGE_ENTRY), 
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
                                                          conf.multiController,
                                                          debugLog);
                             

    // Choose a prefetcher. The prefetcher may need to translate
    // between the user-level address, and the cache address. 
    SCRATCHPAD_PREFETCHER_IMPL prefetch_type = unpack(`SHARED_SCRATCHPAD_PVT_CACHE_PREFETCH_ENABLE);
    if (conf.enablePrefetching matches tagged Valid .pf_en)
    begin
        prefetch_type = pf_en;
    end
         

    let prefetcher_constructor = mkNullCachePrefetcher;
    if(prefetch_type == SCRATCHPAD_STRIDE_PREFETCH)
    begin
        prefetcher_constructor = mkCachePrefetcher(nPrefetchLearners, False, conf.enableAddressHashing, debugLogForPrefetcher);        
    end
    else if(prefetch_type == SCRATCHPAD_USER_PREFETCH)
    begin
        prefetcher_constructor = mkScratchpadUserPrefetcher(scratchpadID, userAddrWidth, conf.enableAddressHashing, debugLogForPrefetcher);        
    end  

    let prefetcher <- prefetcher_constructor();

    
    // Coherent private cache
    COH_DM_CACHE#(t_MEM_ADDR, t_MEM_DATA, t_MEM_MASK, t_MAF_IDX) cache = ?;
    if (conf.backingStore == SHARED_SCRATCH_CACHE_STORE_FLAT_BRAM)
    begin
        NumTypeParam#(COH_SCRATCH_CACHE_FLAT_BRAM_LATENCY) store_latency = ?;
        cache <- mkCoherentCacheDirectMapped(sourceData, prefetcher, nCacheEntries, conf.backingStore, store_latency, True, debugLog);
    end
    else
    begin
        NumTypeParam#(COH_SCRATCH_CACHE_BANKED_BRAM_LATENCY) store_latency = ?;
        cache <- mkCoherentCacheDirectMapped(sourceData, prefetcher, nCacheEntries, conf.backingStore, store_latency, True, debugLog);
    end

    // Hook up stats
    let cacheStats <- statsConstructor(cache.stats);
    let prefetchStats <- prefetchStatsConstructor(prefetcher.stats);

    // Merge FIFOF combines read, write, and fence requests in temporal order,
    // with reads from the same cycle as a write going first.  Each read port
    // gets a slot. The write port is always second from last. The port for 
    // the fence request is always last. 
`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    MERGE_FIFOF#(TAdd#(n_READERS, 2), Tuple2#(t_MEM_ADDR, Maybe#(t_REORDER_ID))) incomingReqQ <- mkMergeFIFOF();
`else
    MERGE_FIFOF#(TAdd#(n_READERS, 1), Tuple2#(t_MEM_ADDR, Maybe#(t_REORDER_ID))) incomingReqQ <- mkMergeFIFOF();
`endif

    // Write data (and write mask) is sent in a side port to keep the incomingReqQ smaller.
    FIFO#(Tuple2#(t_MEM_DATA, t_MEM_MASK)) writeDataQ <- mkFIFO();

    // Cache responses are not ordered.  Sort them with a reorder buffer.
    Vector#(n_READERS, SCOREBOARD_FIFOF#(COH_SCRATCH_PORT_ROB_SLOTS, t_MEM_DATA)) sortResponseQ <- replicateM(mkScoreboardFIFOF());

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    // Sort test&set responses in a separate reorder buffer
    SCOREBOARD_FIFOF#(COH_SCRATCH_TEST_SET_ROB_SLOTS, t_MEM_DATA) sortTestAndSetRespQ <- mkScoreboardFIFOF();
`endif

    //
    // Request merging
    //
    // Merge multiple read requests accessing the same scratchpad address.
    // Only issue the fist read request to the memory, and let subsequent 
    // read requests wait in the request merging table (reqMergeTable).
    //
    Reg#(Bool) multiRespFwd <- mkReg(False);
    PulseWire fwdRespW <- mkPulseWire();

    LUTRAM#(t_MERGE_IDX, t_MERGE_ENTRY) reqMergeTable = ?;
    LUTRAM#(Bit#(t_MAF_IDX_SZ), Maybe#(t_MERGE_IDX)) reqMergeHeadInfo = ?;
    Reg#(Vector#(COH_SCRATCH_PORT_ROB_SLOTS, Bool)) reqMergeTableValidBits = ?;
    Reg#(Vector#(COH_SCRATCH_PORT_ROB_SLOTS, Bool)) reqMergeTableEndBits = ?;
    Reg#(Tuple2#(t_MERGE_IDX, t_MEM_DATA)) multiRespFwdEntry = ?;
    PulseWire mergeTableLockedW = ?;
    PulseWire forwardFenceReqW = ?;

    // allocate merge table
    if (conf.requestMerging)
    begin
        reqMergeTable <- mkLUTRAMU();
        reqMergeHeadInfo <- mkLUTRAM(tagged Invalid);
        reqMergeTableValidBits <- mkReg(replicate(False));
        reqMergeTableEndBits <- mkReg(replicate(True));
        multiRespFwdEntry <- mkRegU();
        mergeTableLockedW <- mkPulseWire();
        forwardFenceReqW <- mkPulseWire();
    end

    function Tuple2#(t_MERGE_TAG, t_MERGE_IDX) mergeEntryFromAddr(t_MEM_ADDR addr);
        return unpack(truncateNP(pack(addr)));
    endfunction
    function Action initOrResetMergeEntry(t_MERGE_IDX idx, Bool isInit);
        if (conf.requestMerging)
        begin
            return 
                action
                    let new_valid_bits = reqMergeTableValidBits;
                    new_valid_bits[idx] = isInit;
                    reqMergeTableValidBits <= new_valid_bits;
                    if (!forwardFenceReqW)
                    begin
                        let new_end_bits = reqMergeTableEndBits;
                        new_end_bits[idx] = !isInit;
                        reqMergeTableEndBits <= new_end_bits;
                    end
                endaction;
        end
        else
        begin
            return noAction;
        end
    endfunction

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

    (* fire_when_enabled *)
    rule incrNumReads (True);
        Bit#(n_READERS) reads = ?;
        for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
        begin
            reads[p] = readIssuedW[p]? 1 : 0;
        end
        numPendingReads.upBy(zeroExtendNP(pack(countOnesAlt(reads))));
    endrule
    
    (* fire_when_enabled *)
    rule decNumReads (cache.numReadProcessed() != 0 || fwdRespW);
        let num_reads = (fwdRespW)? (cache.numReadProcessed() + 1) : cache.numReadProcessed();
        numPendingReads.downBy(zeroExtendNP(num_reads));
        debugLog.record($format("%x read request being processed, numPendingReads=0x%x", 
                        num_reads, numPendingReads.value()));
    endrule

    (* fire_when_enabled *)
    rule decNumWrites (cache.numWriteProcessed() != 0);
        numPendingWrites.downBy(zeroExtendNP(cache.numWriteProcessed()));
        debugLog.record($format("%x write request being processed, numPendingWrites=0x%x", 
                        cache.numWriteProcessed(), numPendingWrites.value()));
    endrule

    //
    // Forward merged requests to the cache.
    //

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    // fence requests
    rule forwardFenceReq (initialized && incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS)+1));
        let fence_mode = pack(incomingReqQ.first());
        incomingReqQ.deq();
        cache.fence(unpack(truncate(fence_mode)));
        if (conf.requestMerging)
        begin
            forwardFenceReqW.send();
            reqMergeTableEndBits <= replicate(True);
            debugLog.record($format("forwardFenceReq: set reqMergeTableEndBits to True"));
        end
    endrule
`endif

    // Write requests and test&set requests
    rule forwardWriteReq (initialized && !multiRespFwd && incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS)));
        match {.addr, .idx} = incomingReqQ.first();
        incomingReqQ.deq();
        match {.val, .mask} = writeDataQ.first();
        writeDataQ.deq();
        // test&set requests
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
        if (idx matches tagged Valid .d)
        begin
            t_MAF_IDX maf_idx = tuple2(?, d);
            cache.testAndSetReq(addr, val, mask, maf_idx, defaultValue());
        end
        else
        begin
            cache.write(addr, val, mask);
        end
`else
        cache.write(addr, val, mask);
`endif
        if (conf.requestMerging)
        begin
            match {.m_tag, .m_idx} = mergeEntryFromAddr(addr);
            if (reqMergeTableValidBits[m_idx] == True && reqMergeTableEndBits[m_idx] == False)
            begin
                let e = reqMergeTable.sub(m_idx);
                if (e.tag == m_tag) // hit
                begin
                    let new_end_bits = reqMergeTableEndBits;
                    new_end_bits[m_idx] = True;
                    reqMergeTableEndBits <= new_end_bits;
                    debugLog.record($format("forwardWriteReq: update reqMergeTableEndBits, addr=0x%x, idx=0x%x, tag=0x%x, mergeMeta=0x%x, endMerge=True",
                                    addr, m_idx, e.tag, e.mergeMeta));
                end
            end
        end
    endrule

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    //
    // recvTestAndSetResp --
    //     Push test&set responses to the reorder buffer.  They will be returned
    //     through testAndSetRsp() in order.
    //
    rule recvTestAndSetResp (True);
        let r <- cache.testAndSetResp();
        t_REORDER_ID idx = tpl_2(r.readMeta);
        sortTestAndSetRespQ.setValue(unpack(truncate(pack(idx))), r.val);
    endrule
`endif

    // Read requests
    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        rule forwardReadReq (initialized && incomingReqQ.firstPortID() == fromInteger(p));
            match {.addr, .idx} = incomingReqQ.first();
            incomingReqQ.deq();
            if (idx matches tagged Valid .d)
            begin
                // The read UID for this request is the concatenation of the
                // port ID and the ROB index.
                t_MAF_IDX maf_idx = tuple2(fromInteger(p), d);
                
                Bool issue_req = True;
               
                if (conf.requestMerging)
                begin
                    debugLog.record($format("forwardReadReq: port %0d: addr=0x%x, rob_idx=%0d, maf_idx=0x%x",
                                    p, addr, d, pack(maf_idx)));
                    if (!mergeTableLockedW)
                    begin
                        match {.m_tag, .m_idx} = mergeEntryFromAddr(addr);
                        if (reqMergeTableValidBits[m_idx] == True)
                        begin
                            let e = reqMergeTable.sub(m_idx);
                            if (e.tag == m_tag && !reqMergeTableEndBits[m_idx]) // hit
                            begin
                                issue_req = False;
                                let new_entry = e;
                                new_entry.mergeMeta[pack(tuple2(fromInteger(p),d))] = True;
                                reqMergeTable.upd(m_idx, new_entry); 
                                debugLog.record($format("forwardReadReq: port %0d: update reqMergeTable, idx=0x%x, tag=0x%x, mergeMeta=0x%x",
                                                p, m_idx, m_tag, pack(new_entry.mergeMeta)));
                            end
                        end
                        else // initialize merge table
                        begin
                            reqMergeTable.upd(m_idx, COH_SCRATCH_MERGE_TABLE_ENTRY { tag: m_tag,
                                                                                     mergeMeta: replicate(False) });
                            reqMergeHeadInfo.upd(pack(maf_idx), tagged Valid m_idx);
                            initOrResetMergeEntry(m_idx, True);
                            debugLog.record($format("forwardReadReq: port %0d: initialize reqMergeTable, idx=0x%x, tag=0x%x", 
                                            p, m_idx, m_tag));
                            debugLog.record($format("forwardReadReq: port %0d: set reqMergeHeadInfo, idx=0x%x", p, pack(maf_idx)));
                        end
                    end
                end
                
                if (issue_req)
                begin
                    // Request data from the cache
                    cache.readReq(addr, maf_idx, defaultValue());
                    debugLog.record($format("forwardReadReq: port %0d: issue request to cache, addr=0x%x, idx=0x%x",
                                    p, addr, maf_idx));
                end
            end
        endrule
        
        //
        // receiveResp --
        //     Push read responses to the reorder buffer.  They will be returned
        //     through readRsp() in order.
        //
`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
        (* descending_urgency = "receiveResp, forwardFenceReq, forwardWriteReq" *)
`else
        (* descending_urgency = "receiveResp, forwardWriteReq" *)
`endif
        rule receiveResp (tpl_1(cache.peekResp().readMeta) == fromInteger(p) && !multiRespFwd);
            let r <- cache.readResp();

            // The readUID field holds the concatenation of the port ID and
            // the port's reorder buffer index.
            match {.port, .maf_idx} = r.readMeta;

            sortResponseQ[p].setValue(maf_idx, r.val);
            debugLog.record($format("receiveResp: port %0d: resp val=0x%x, rob idx=%0d", p, r.val, maf_idx));

            if (conf.requestMerging)
            begin
                mergeTableLockedW.send();
                let merge_head_info = reqMergeHeadInfo.sub(pack(r.readMeta));
                if (merge_head_info matches tagged Valid .m_idx)
                begin
                    let e = reqMergeTable.sub(m_idx);
                    if (fold(\|| , e.mergeMeta))
                    begin
                        multiRespFwd <= True;
                        multiRespFwdEntry <= tuple2(m_idx, r.val);
                        debugLog.record($format("receiveResp: port %0d: need to forward resp, merge table idx=0x%x", p, m_idx));
                    end
                    else //release merge table entry
                    begin
                        initOrResetMergeEntry(m_idx, False);
                        debugLog.record($format("receiveResp: port %0d: no need to forward resp, reset merge table idx=0x%x", p, m_idx));
                    end
                    // reset reqMergeHeadInfo
                    reqMergeHeadInfo.upd(pack(r.readMeta), tagged Invalid);
                    debugLog.record($format("receiveResp: port %0d: reset reqMergeHeadInfo, idx=0x%x", p, pack(r.readMeta)));
                end
            end
        endrule
    end
    
    if (conf.requestMerging)
    begin
`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
        (* descending_urgency = "fwdMultiResp, forwardFenceReq" *)
`endif
        rule fwdMultiResp (multiRespFwd);
            mergeTableLockedW.send();
            fwdRespW.send();
            match {.idx, .val} = multiRespFwdEntry;
            let e = reqMergeTable.sub(idx);
            Tuple2#(Bit#(TLog#(n_READERS)), t_REORDER_ID) fwd_id = unpack(resize(pack(fromMaybe(?, findElem(True, e.mergeMeta)))));
            let p = (valueOf(n_READERS) == 1) ? 0 : tpl_1(fwd_id);
            sortResponseQ[p].setValue(tpl_2(fwd_id), val);
            debugLog.record($format("fwdMultiResp: port %0d: resp val=0x%x, rob_idx=%0d", p, val, tpl_2(fwd_id)));
            let new_entry = e;
            new_entry.mergeMeta[pack(fwd_id)] = False;
            reqMergeTable.upd(idx, new_entry); 
            debugLog.record($format("fwdMultiResp: port %0d: update reqMergeTable, idx=0x%x, mergeMeta=0x%x",
                            p, idx, pack(new_entry.mergeMeta)));
            if (!fold(\|| , new_entry.mergeMeta))
            begin
                multiRespFwd <= False;
                initOrResetMergeEntry(idx, False);
                debugLog.record($format("fwdMultiResp: port %0d: done with forwarding, reset merge table idx=0x%x", p, idx));
            end
        endrule
    end

    // ====================================================================
    //
    // Coherent scratchpad client debug scan for deadlock debugging.
    //
    // ====================================================================
    
    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
    dbg_list <- addDebugScanField(dbg_list, "Pending Reads", numPendingReads.value());
    dbg_list <- addDebugScanField(dbg_list, "Pending Writes", numPendingWrites.value());
    dbg_list <- addDebugScanField(dbg_list, "Request Queue notEmpty", incomingReqQ.notEmpty());
    
    for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        dbg_list <- addDebugScanField(dbg_list, "Read request: incomingReqQ port " + integerToString(p) + " notFull", incomingReqQ.ports[p].notFull());
        dbg_list <- addDebugScanField(dbg_list, "Read request: sortResponseQ port " + integerToString(p) + " notEmpty", sortResponseQ[p].notEmpty());
        dbg_list <- addDebugScanField(dbg_list, "Read request: sortResponseQ port " + integerToString(p) + " notFull", sortResponseQ[p].notFull());
    end

    dbg_list <- addDebugScanField(dbg_list, "Write Request Queue notFull ", incomingReqQ.ports[valueOf(n_READERS)].notFull());

    // Append coherent cache state and sourceData state
    List#(Tuple2#(String, Bool)) debug_scan_state = List::append(cache.debugScanState(), sourceData.debugScanState());
    while (debug_scan_state matches tagged Nil ? False : True)
    begin
        let fld = List::head(debug_scan_state);
        dbg_list <- addDebugScanField(dbg_list, tpl_1(fld), tpl_2(fld));

        debug_scan_state = List::tail(debug_scan_state);
    end
    debugScanNodeConstructor(dbg_list);

    // =======================================================================
    //
    // Methods.  All requests are stored in the incomingReqQ to maintain their
    // order.
    //
    // =======================================================================

    Vector#(n_READERS, MEMORY_READER_IFC#(t_MEM_ADDR, t_MEM_DATA)) portsLocal = newVector();

    for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_MEM_ADDR, t_MEM_DATA);
                method Action readReq(t_MEM_ADDR addr);
                    // Allocate a slot in the reorder buffer for the read request.  Each
                    // read port gets its own reorder buffer.
                    let idx <- sortResponseQ[p].enq();
                    incomingReqQ.ports[p].enq(tuple2(addr, tagged Valid idx));
                    readIssuedW[p].send();
                    debugLog.record($format("read port %0d: req addr=0x%x, rob_idx=%0d, numPendingReads=0x%x", 
                                    p, addr, idx, numPendingReads.value()));
                endmethod

                method ActionValue#(t_MEM_DATA) readRsp();
                    let r = sortResponseQ[p].first();
                    sortResponseQ[p].deq();
                    debugLog.record($format("read port %0d: resp val=0x%x, rob_idx=%0d", p, r, sortResponseQ[p].deqEntryId()));
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
        incomingReqQ.ports[valueOf(n_READERS)].enq(tuple2(addr, tagged Invalid));
        writeDataQ.enq(tuple2(val, byteMask));
        numPendingWrites.up(); 
        debugLog.record($format("write addr=0x%x, val=0x%x, byteMask=0x%x, numPendingWrites=0x%x", 
                        addr, val, byteMask, numPendingWrites.value()));
    endmethod

    method Bool writeNotFull = incomingReqQ.ports[valueOf(n_READERS)].notFull();

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_MEM_ADDR addr, t_MEM_DATA val, t_MEM_MASK byteMask) if (numPendingWrites.value() != maxBound);
        // The write port is the second from last in the merge FIFO
        let idx <- sortTestAndSetRespQ.enq();
        t_REORDER_ID d = zeroExtend(idx);
        incomingReqQ.ports[valueOf(n_READERS)].enq(tuple2(addr, tagged Valid d));
        writeDataQ.enq(tuple2(val, byteMask));
        numPendingWrites.up(); 
        debugLog.record($format("test&set addr=0x%x, val=0x%x, byteMask=0x%x, numPendingWrites=0x%x", 
                        addr, val, byteMask, numPendingWrites.value()));
    endmethod
    
    method ActionValue#(t_MEM_DATA) testAndSetRsp();
        let r = sortTestAndSetRespQ.first();
        sortTestAndSetRespQ.deq();
        debugLog.record($format("test&set: resp val=0x%x", r));
        return r;
    endmethod
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence();
        incomingReqQ.ports[valueOf(n_READERS)+1].enq(unpack(zeroExtend(pack(COH_DM_ALL_FENCE))));
        debugLog.record($format("recive memory fence request"));
    endmethod

    method Action writeFence();
        incomingReqQ.ports[valueOf(n_READERS)+1].enq(unpack(zeroExtend(pack(COH_DM_WRITE_FENCE))));
        debugLog.record($format("recive memory write fence request"));
    endmethod
    
    method Action readFence();
        incomingReqQ.ports[valueOf(n_READERS)+1].enq(unpack(zeroExtend(pack(COH_DM_READ_FENCE))));
        debugLog.record($format("recive memory read fence request"));
    endmethod
`endif
    
    method Bool writePending() = (numPendingWrites.value() != 0);
    method Bool readPending() = (numPendingReads.value() != 0);
      
endmodule

typedef struct
{
    COH_SCRATCH_PORT_NUM       requester;
    COH_SCRATCH_CTRLR_PORT_NUM reqControllerId;
    COH_SCRATCH_MEM_VALUE      val;
    Bool                       ownership;
    Bool                       retry;
    Bool                       isCacheable;
    Bool                       isExclusive;
    COH_SCRATCH_META           meta;
    RL_CACHE_GLOBAL_READ_META  globalReadMeta;
}
COH_DM_CACHE_SNOOPED_REQ_TABLE_ENTRY
    deriving(Bits, Eq);


`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z

typedef struct
{
    COH_SCRATCH_PORT_NUM        clientId;
    COH_SCRATCH_CTRLR_PORT_NUM  controllerId;
    Bool                        isGetx;
    COH_SCRATCH_CLIENT_META     clientMeta;
    RL_CACHE_GLOBAL_READ_META   globalReadMeta;
    Bool                        multiFwd;
    COH_SCRATCH_PORT_NUM        lastClientId;
    COH_SCRATCH_CTRLR_PORT_NUM  lastControllerId;
    Bool                        getsFwd;
}
COH_DM_CACHE_FWD_TABLE_ENTRY
    deriving(Bits, Eq);

`else

typedef struct
{
    Vector#(n_ENTRIES, Bool)    forwardMeta;
    Bool                        hasGetx;
    COH_SCRATCH_PORT_NUM        getxRequester;
    COH_SCRATCH_CTRLR_PORT_NUM  getxReqControllerId;
}
COH_DM_CACHE_FWD_TABLE_ENTRY#(numeric type n_ENTRIES)
    deriving(Bits, Eq);

`endif

//
// Statistics wires for coherent scratchpad ring nodes.
// When a line becomes true the coresponding statistic should be incremented.
//
interface COH_SCRATCH_RING_NODE_STATS;
    method Bool localMsgSent();   // send local message on to the ring
    method Bool msgReceived();    // receive message from the ring
    method Bit#(2) fwdMsgSent();  // number of forwarding messages on the ring
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
                                                               Bool hasMultiController,
                                                               DEBUG_FILE debugLog)
    // interface:
    (COH_DM_CACHE_SOURCE_DATA#(t_CACHE_ADDR, COH_SCRATCH_MEM_VALUE, t_CACHE_META, t_REQ_IDX))
    provisos (Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_META, t_CACHE_META_SZ),
              Bits#(t_REQ_IDX, t_REQ_IDX_SZ),
              NumAlias#(TExp#(t_REQ_IDX_SZ), n_REQ_TABLE_ENTRIES),
              NumAlias#(TExp#(t_CACHE_META_SZ), n_FWD_TABLE_ENTRIES),
              Alias#(COH_SCRATCH_MEM_VALUE, t_CACHE_WORD),
              NumAlias#(TMul#(SHARED_SCRATCH_N_CONTROLLERS, SHARED_SCRATCH_N_CLIENTS), n_FWD_ENTRIES),
              NumAlias#(TMax#(1, TLog#(SHARED_SCRATCH_N_CLIENTS)), n_CLIENT_IDX_SZ),
              Bits#(COH_SCRATCH_CTRLR_PORT_NUM, n_CONTROLLER_IDX_SZ),
              NumAlias#(TAdd#(n_CONTROLLER_IDX_SZ, n_CLIENT_IDX_SZ), n_TOTAL_NODE_IDX_SZ),
              Alias#(Bit#(n_TOTAL_NODE_IDX_SZ), t_TOTAL_NODE_IDX), 
              Alias#(Bit#(TAdd#(t_CACHE_META_SZ, n_TOTAL_NODE_IDX_SZ)), t_FWD_INFO_TABLE_IDX),
              // Coherence messages
              Alias#(COH_SCRATCH_MEM_REQ#(t_CACHE_ADDR), t_UNACTIVATED_REQ),
              Alias#(COH_SCRATCH_ACTIVATED_REQ#(t_CACHE_ADDR), t_ACTIVATED_REQ),
              Alias#(COH_DM_CACHE_FILL_RESP#(t_CACHE_WORD, t_CACHE_META), t_COH_CACHE_FILL_RESP),
              Alias#(COH_DM_CACHE_NETWORK_REQ#(t_CACHE_ADDR, t_REQ_IDX), t_CACHE_NW_REQ),
              Alias#(COH_DM_CACHE_MSHR_ROUTER_RESP#(t_REQ_IDX, t_CACHE_WORD, t_CACHE_META, t_CACHE_ADDR), t_ROUTER_RESP),
              Alias#(COH_DM_CACHE_SNOOPED_REQ_TABLE_ENTRY, t_REQ_INFO_ENTRY),
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
              Alias#(COH_DM_CACHE_FWD_TABLE_ENTRY, t_FWD_TABLE_ENTRY),
`else
              Alias#(COH_DM_CACHE_FWD_TABLE_ENTRY#(n_FWD_ENTRIES), t_FWD_TABLE_ENTRY),
`endif
              Bounded#(t_FWD_INFO_TABLE_IDX),
              Bounded#(t_CACHE_META),
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

    String clientControllerRingName = "Coherent_Scratchpad_" + integerToString(scratchpadID); 
    
    // Addressable ring (self-enumeration)
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, t_UNACTIVATED_REQ) link_mem_req <-
        mkConnectionAddrRingDynNode(clientControllerRingName + "_Req");
        
    // Addressable ring
    CONNECTION_ADDR_RING#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP) link_mem_resp <-
        (`ADDR_RING_DEBUG_ENABLE == 1)?
        mkDebugConnectionAddrRingNodeNtoN(clientControllerRingName + "_Resp", myPort._read(), debugLog):
        mkConnectionAddrRingNodeNtoN(clientControllerRingName + "_Resp", myPort._read());

    // Broadcast ring
    Vector#(2, CONNECTION_CHAIN#(t_ACTIVATED_REQ)) links_mem_activatedReq = newVector();
    CONNECTION_CHAIN#(t_ACTIVATED_REQ) link_mem_activatedReq = ?;

    if (hasMultiController)
    begin
        links_mem_activatedReq[0] <- mkConnectionChain(clientControllerRingName + "_ActivatedReq_0");
        links_mem_activatedReq[1] <- mkConnectionChain(clientControllerRingName + "_ActivatedReq_1");
    end
    else
    begin
        link_mem_activatedReq <- mkConnectionChain(clientControllerRingName + "_ActivatedReq");
    end

    // =======================================================================
    //
    // Ring stats
    //
    // =======================================================================
    let req_stats = ?;
    let resp_stats = ?;

`ifndef ADDR_RING_DEBUG_ENABLE_Z
    req_stats = interface COH_SCRATCH_RING_NODE_STATS;
                    method Bool localMsgSent()  = link_mem_req.localMsgSent();  
                    method Bool msgReceived()   = link_mem_req.msgReceived();  
                    method Bit#(2) fwdMsgSent() = link_mem_req.fwdMsgSent();  
                endinterface;
    
    resp_stats = interface COH_SCRATCH_RING_NODE_STATS;
                     method Bool localMsgSent()  = link_mem_resp.localMsgSent();  
                     method Bool msgReceived()   = link_mem_resp.msgReceived();  
                     method Bit#(2) fwdMsgSent() = link_mem_resp.fwdMsgSent();  
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
    Reg#(COH_SCRATCH_CTRLR_PORT_NUM) controllerPort <- mkReg(0);
   
    if (hasMultiController)
    begin
        // Assign the port number got from request ring's self-enumeration to the response ring
        // Receive the controller broadcast port number
        rule doInit (!initialized);
            initialized <= True;
            let port_num = link_mem_req.nodeID();
            myPort <= port_num;
            let req <- links_mem_activatedReq[0].recvFromPrev();
            controllerPort <= req.reqControllerId;
            links_mem_activatedReq[0].sendToNext(req);
            debugLog.record($format("    sourceData: assigned port ID = %03d", port_num));
            debugLog.record($format("    sourceData: receive controller port ID = %02d", req.reqControllerId));
        endrule
    end
    else
    begin
        // Assign the port number got from request ring's self-enumeration to the response ring
        rule doInit (!initialized);
            initialized <= True;
            let port_num = link_mem_req.nodeID();
            myPort <= port_num;
            debugLog.record($format("    sourceData: assigned port ID = %03d", port_num));
        endrule
    end

    // =======================================================================
    //
    // Forward unactivated requests
    //
    // =======================================================================

    FIFOF#(t_UNACTIVATED_REQ) unactivatedReqQ <- mkSizedFIFOF(valueOf(COH_DM_CACHE_NW_REQ_BUF_SIZE));
    PulseWire unactivatedReqSentW <- mkPulseWire();
    COUNTER#(TLog#(TAdd#(COH_DM_CACHE_NW_REQ_BUF_SIZE,1))) numBufferedReq <- mkLCounter(0);

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
    
    MEMORY_HEAP_IMM#(t_REQ_IDX, t_REQ_INFO_ENTRY) snoopedReqTable <- mkMemoryHeapLUTRAM();
    FIFOF#(t_CACHE_NW_REQ) activatedReqQ <- mkSizedFIFOF(valueOf(n_REQ_TABLE_ENTRIES));
    Reg#(Bool) activatedReqArb <- mkReg(True);
    
    function Tuple2#(Bit#(1), Maybe#(t_ACTIVATED_REQ)) getActivatedReq();
        if (hasMultiController)
        begin
            if (links_mem_activatedReq[0].recvNotEmpty() && links_mem_activatedReq[0].sendNotFull() && (activatedReqArb || !links_mem_activatedReq[1].recvNotEmpty() || !links_mem_activatedReq[1].sendNotFull()))
            begin
                return tuple2(0, tagged Valid links_mem_activatedReq[0].peekFromPrev());
            end
            else if (links_mem_activatedReq[1].recvNotEmpty() && links_mem_activatedReq[1].sendNotFull())
            begin
                return tuple2(1, tagged Valid links_mem_activatedReq[1].peekFromPrev());
            end
            else
            begin
                return tuple2(?, tagged Invalid);
            end
        end
        else
        begin
            if (link_mem_activatedReq.recvNotEmpty())
            begin
                return tuple2(?, tagged Valid link_mem_activatedReq.peekFromPrev());
            end
            else
            begin
                return tuple2(?, tagged Invalid);
            end
        end
    endfunction
    function Action fwdActivatedReq(Bit#(1) channel_id);
        return 
            action
                if (hasMultiController)
                begin
                    let req <- links_mem_activatedReq[channel_id].recvFromPrev();
                    links_mem_activatedReq[channel_id].sendToNext(req);
                    activatedReqArb <= !activatedReqArb;
                end
                else
                begin
                    let req <- link_mem_activatedReq.recvFromPrev();
                    link_mem_activatedReq.sendToNext(req);
                end
            endaction;
    endfunction
    function Bool isOwnReq(COH_SCRATCH_PORT_NUM clientId, COH_SCRATCH_CTRLR_PORT_NUM controllerId);
        if (hasMultiController)
        begin
            return (clientId == myPort) && (controllerId == controllerPort);
        end
        else
        begin
            return (clientId == myPort);
        end
    endfunction

    //
    // snoopActivatedReq --
    //      Snoop activated requests on the activated request ring and 
    // forward them on the same ring. 
    //
    rule snoopActivatedReq (True);
        match {.channel_id, .r} = getActivatedReq();
        if (r matches tagged Valid .req)
        begin
            t_REQ_INFO_ENTRY new_entry = ?;
            t_CACHE_NW_REQ cache_req = ?;
            Bool need_snoop = False;
            if (hasMultiController)
            begin
                debugLog.record($format("    sourceData: check activated request from ring %01d...", channel_id));
            end
            else
            begin
                debugLog.record($format("    sourceData: check activated request from the ring..."));
            end

            cache_req.ownReq = isOwnReq(req.requester, req.reqControllerId);
            cache_req.addr = req.addr;

            case (req.reqInfo) matches
                tagged COH_SCRATCH_ACTIVATED_GETS .gets_req:
                begin
                    cache_req.reqType         = COH_CACHE_GETS;
                    need_snoop                = !cache_req.ownReq;
                    new_entry.requester       = req.requester;
                    new_entry.reqControllerId = req.reqControllerId;
                    new_entry.ownership       = False; 
                    new_entry.isExclusive     = False;
                    new_entry.meta            = zeroExtendNP(gets_req.clientMeta); 
                    new_entry.globalReadMeta  = gets_req.globalReadMeta;
                    debugLog.record($format("    sourceData: check activated %s GETS request: addr=0x%x, requester=%03d, reqControllerId=%02d, meta=0x%x", 
                                    (cache_req.ownReq)? "own" : "other", cache_req.addr, new_entry.requester, new_entry.reqControllerId, new_entry.meta));
                end
                tagged COH_SCRATCH_ACTIVATED_GETX .getx_req:
                begin
                    cache_req.reqType         = COH_CACHE_GETX;
                    need_snoop                = !cache_req.ownReq;
                    new_entry.requester       = req.requester;
                    new_entry.reqControllerId = req.reqControllerId;
                    new_entry.ownership       = True;
                    new_entry.isExclusive     = True;
                    new_entry.meta            = zeroExtendNP(getx_req.clientMeta); 
                    new_entry.globalReadMeta  = getx_req.globalReadMeta;
                    debugLog.record($format("    sourceData: check activated %s GETX request: addr=0x%x, requester=%03d, reqControllerId=%02d, meta=0x%x", 
                                    (cache_req.ownReq)? "own" : "other", cache_req.addr, new_entry.requester, new_entry.reqControllerId, new_entry.meta));
                end
                tagged COH_SCRATCH_ACTIVATED_PUTX .putx_req:
                begin
                    cache_req.reqType         = COH_CACHE_PUTX;
                    need_snoop                = cache_req.ownReq && !putx_req.isCleanWB;
                    new_entry.requester       = 0;
                    new_entry.reqControllerId = req.homeControllerId;
                    new_entry.ownership       = True;
                    new_entry.isExclusive     = False;
                    new_entry.meta            = zeroExtendNP(putx_req.controllerMeta); 
                    debugLog.record($format("    sourceData: check activated %s PUTX request: addr=0x%x, requester=%03d, reqControllerId=%02d, meta=0x%x", 
                                   (cache_req.ownReq)? "own" : "other", cache_req.addr, new_entry.requester, new_entry.reqControllerId, new_entry.meta));
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
            fwdActivatedReq(channel_id);
        end
    endrule

    // =======================================================================
    //
    // Send responses
    //
    // =======================================================================

    // Forwarding table
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
    LUTRAM#(t_CACHE_META, Maybe#(t_CACHE_ADDR)) lastGetReqTable <- mkLUTRAM(tagged Invalid);
    LUTRAM#(t_CACHE_META, t_FWD_TABLE_ENTRY) forwardingTable <- mkLUTRAMU();
    Bool fwdBusy = False;
    FIFOF#(Bool) pendingFwdGetsQ <- mkSizedFIFOF(valueOf(n_FWD_TABLE_ENTRIES));
`else
    LUTRAM#(t_CACHE_META, t_FWD_TABLE_ENTRY) forwardingTable <- mkLUTRAM( COH_DM_CACHE_FWD_TABLE_ENTRY{ forwardMeta: replicate(False),
                                                                                                        hasGetx: False,
                                                                                                        getxRequester: ?,
                                                                                                        getxReqControllerId: ? });
    LUTRAM#(t_FWD_INFO_TABLE_IDX, COH_SCRATCH_GET_REQ_INFO) forwardInfoTable <- mkLUTRAMU();
    Reg#(COH_SCRATCH_MEM_VALUE) curFwdValue <- mkRegU();
    Reg#(t_CACHE_META) curFwdIdx <- mkRegU();
    Reg#(Bool) fwdBusy <- mkReg(False);
`endif
    Wire#(Tuple2#(t_CACHE_META, COH_SCRATCH_MEM_VALUE)) curFwdEntry <- mkWire();

    FIFOF#(Tuple2#(COH_SCRATCH_PORT_NUM, COH_SCRATCH_RESP)) respToNetworkQ  <- mkBypassFIFOF();
    FIFOF#(t_REQ_IDX) respReadyEntryQ <- mkSizedFIFOF(valueOf(n_REQ_TABLE_ENTRIES));
    FIFOF#(t_ROUTER_RESP) respFromCacheQ <- mkBypassFIFOF();
    FIFOF#(t_CACHE_META) pendingFwdEntryQ <- mkSizedFIFOF(valueOf(n_FWD_TABLE_ENTRIES));
    FIFOF#(t_CACHE_META) releaseFwdEntryQ <- mkFIFOF();

    RWire#(Tuple4#(t_CACHE_META, t_CACHE_WORD, COH_SCRATCH_PORT_NUM, COH_SCRATCH_CTRLR_PORT_NUM))  getsFwdResp <- mkRWire();
    PulseWire recvGetsFwdRespW   <- mkPulseWire();
    PulseWire resendFwdRespValW  <- mkPulseWire();

    function COH_SCRATCH_PORT_NUM getRespDestination(COH_SCRATCH_CTRLR_PORT_NUM controllerId, COH_SCRATCH_PORT_NUM clientId);
         return (hasMultiController && controllerPort != controllerId)? 0 : clientId;
    endfunction
   
    function Action sendRespToNetworkQ(COH_SCRATCH_CTRLR_PORT_NUM controllerId, 
                                       COH_SCRATCH_PORT_NUM clientId, 
                                       t_CACHE_WORD val,
                                       COH_SCRATCH_META meta, 
                                       RL_CACHE_GLOBAL_READ_META globalReadMeta,
                                       Bool ownership,
                                       Bool retry,
                                       Bool isCacheable,
                                       Bool isExclusive, 
                                       Tuple3#(Bool, COH_SCRATCH_CTRLR_PORT_NUM, COH_SCRATCH_PORT_NUM) fwdInfo,
                                       String ruleName);
        return 
            action
                let dest = getRespDestination(controllerId, clientId);
                let cacheable = (`COHERENT_SCRATCHPAD_I_TO_M_ENABLE == 0)? True : isCacheable;
                respToNetworkQ.enq(tuple2(dest, COH_SCRATCH_RESP { val: val,
                                                                   ownership: ownership,
                                                                   isExclusive: isExclusive, 
`ifndef SHARED_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z
                                                                   controllerId: controllerId,
                                                                   clientId: clientId,
`endif
`ifndef SHARED_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
                                                                   needFwd: tpl_1(fwdInfo),
                                                                   lastFwdControllerId: tpl_2(fwdInfo),
                                                                   lastFwdClientId: tpl_3(fwdInfo),
`endif
                                                                   meta: meta,
                                                                   globalReadMeta: globalReadMeta,
                                                                   isCacheable: cacheable, 
                                                                   retry: retry,
                                                                   fromCache: True }));
            
                debugLog.record($format("    sourceData: %s: send response: dest=%d, val=0x%x, meta=0x%x, ownership=%s, isCacheable=%s, isExclusive=%s %s", 
                                ruleName, dest, val, meta, (ownership)? "True" : "False", cacheable? "True" : "False", 
                                isExclusive? "Ture" : "False", (retry)? "RETRY!!!" : " "));

`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
                debugLog.record($format("    sourceData: %s: send response: needFwd=%s, lastFwdClientId=%03d, lastFwdControllerId=%02d",
                                ruleName, tpl_1(fwdInfo)? "True" : "False", tpl_3(fwdInfo), tpl_2(fwdInfo)));
`endif
`ifndef SHARED_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z
                if (hasMultiController)
                begin
                    debugLog.record($format("    sourceData: %s: send response: requester=%03d, reqControllerId=%02d",
                                    ruleName, clientId, controllerId));
                end
`endif
            endaction;
    endfunction

    function Action sendRespFromSnoopTableToNetwork(t_REQ_INFO_ENTRY e, 
                                                    t_CACHE_WORD val, 
                                                    Bool retry,
                                                    Bool isCacheable,
                                                    Bool isExclusive,
                                                    Tuple3#(Bool, COH_SCRATCH_CTRLR_PORT_NUM, COH_SCRATCH_PORT_NUM) fwdInfo, 
                                                    String ruleName);
        return 
            action
                sendRespToNetworkQ(e.reqControllerId, e.requester, val, e.meta, e.globalReadMeta, 
                                   e.ownership, retry, isCacheable, (isExclusive||e.isExclusive), fwdInfo, ruleName);
            endaction;
    endfunction

`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
    
    function Action sendRespFromForwardingTableToNetwork(t_FWD_TABLE_ENTRY f, t_CACHE_WORD val, Bool needFwd, String ruleName);
        return 
            action
                sendRespToNetworkQ(f.controllerId, f.clientId, val, zeroExtendNP(f.clientMeta), f.globalReadMeta, 
                                   f.isGetx, False, True, f.isGetx, tuple3(needFwd, f.lastControllerId, f.lastClientId), ruleName); 
            endaction;
    endfunction

`else

    function t_TOTAL_NODE_IDX localIdToGlobal (COH_SCRATCH_CTRLR_PORT_NUM controllerId, COH_SCRATCH_PORT_NUM clientId);
        let idx = (hasMultiController)? tuple2(controllerId, truncateNP(clientId-1)) : tuple2(0, truncateNP(clientId-1));
        return pack(idx);
    endfunction
    
    function Tuple2#(COH_SCRATCH_CTRLR_PORT_NUM, COH_SCRATCH_PORT_NUM) globalIdToLocal (t_TOTAL_NODE_IDX nodeId);
        Tuple2#(Bit#(n_CONTROLLER_IDX_SZ), Bit#(n_CLIENT_IDX_SZ)) tuple_node_id = unpack(nodeId);
        COH_SCRATCH_CTRLR_PORT_NUM controller_id = tpl_1(tuple_node_id);
        COH_SCRATCH_PORT_NUM client_id = zeroExtendNP(tpl_2(tuple_node_id)) + 1;
        return tuple2(controller_id, client_id);
    endfunction
    
    function Action sendRespFromForwardingTableToNetwork(t_FWD_TABLE_ENTRY f, t_CACHE_META fIdx, t_CACHE_WORD val, String ruleName);
        return 
            action
                let fwd_node_id = fromMaybe(?, findElem(True, f.forwardMeta));
                match {.controller_id, .client_id} = globalIdToLocal(pack(fwd_node_id));
                let fwd_info = forwardInfoTable.sub(pack(tuple2(fIdx, pack(fwd_node_id))));
                let fwd_getx = f.hasGetx && (f.getxRequester == client_id) && ((f.getxReqControllerId == controller_id) || !hasMultiController);
                
                sendRespToNetworkQ(controller_id, client_id, val, zeroExtendNP(fwd_info.clientMeta), 
                                   fwd_info.globalReadMeta, fwd_getx, False, True, fwd_getx, ?, ruleName); 

                // update forwarding table
                let new_fwd_entry = f;
                new_fwd_entry.forwardMeta[fwd_node_id] = False;
                new_fwd_entry.hasGetx = fwd_getx? False : f.hasGetx;
                forwardingTable.upd(fIdx, new_fwd_entry);  
                debugLog.record($format("    sourceData: %s: update forwardingTable (entry=0x%x), forwardMeta=0x%x, hasGetx=%s",
                                ruleName, fIdx, pack(new_fwd_entry.forwardMeta), new_fwd_entry.hasGetx? "True" : "False"));
            endaction;
    endfunction

`endif

    //
    // recvNullRespFromCache --
    //     Consume the null response from the cache and free the entry in the 
    // completion table (snoopedReqTable).
    //
    (* fire_when_enabled *)
    rule recvNullRespFromCache (respFromCacheQ.first() matches tagged MSHR_NULL_RESP .r &&& !recvGetsFwdRespW &&& !resendFwdRespValW);
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
        // may need to forward data to the next cache on the response chain
        if (r.fwdEntryIdx matches tagged Valid .fwd_idx)
        begin
            let e = snoopedReqTable.sub(r.reqIdx);
            let f = forwardingTable.sub(fwd_idx);
            let g = lastGetReqTable.sub(fwd_idx);
            if (g matches tagged Valid .g_addr &&& pack(g_addr) == pack(r.reqAddr) &&& f.getsFwd)
            begin
                let new_fwd_entry = f;
                pendingFwdEntryQ.enq(fwd_idx);
                pendingFwdGetsQ.enq(True);
                new_fwd_entry.clientId = e.requester;
                new_fwd_entry.controllerId = e.reqControllerId;
                new_fwd_entry.isGetx = e.ownership;
                new_fwd_entry.clientMeta = truncateNP(e.meta);
                new_fwd_entry.globalReadMeta = e.globalReadMeta;
                new_fwd_entry.getsFwd = False;
                forwardingTable.upd(fwd_idx, new_fwd_entry);
                debugLog.record($format("    sourceData: recvNullRespFromCache: need to forward! wait in the pendingFwdEntryQ, entry=0x%x", fwd_idx));
            end
        end
`endif
        respFromCacheQ.deq();
        snoopedReqTable.free(r.reqIdx); 
        debugLog.record($format("    sourceData: recvNullRespFromCache: free snoopedReqTable (entry=0x%x)", r.reqIdx));
    endrule
    
    //
    // recvRealRespFromCacheToNetwork --
    //     Generate the response to the ring and free the entry in the completion
    // table (snoopedReqTable) if respToNetworkQ is not full. 
    //
    (* fire_when_enabled *)
    rule recvRealRespFromCacheToNetwork (respFromCacheQ.first() matches tagged MSHR_REMOTE_RESP .r &&& respToNetworkQ.notFull &&& !resendFwdRespValW);
        respFromCacheQ.deq();
        let e = snoopedReqTable.sub(r.reqIdx);
        sendRespFromSnoopTableToNetwork(e, r.val, r.retry, r.isCacheable, r.isExclusive, tuple3(False, ?, ?), "recvRealRespFromCacheToNetwork");
        snoopedReqTable.free(r.reqIdx); 
        debugLog.record($format("    sourceData: recvRealRespFromCacheToNetwork: free snoopedReqTable (entry=0x%x)", r.reqIdx));
    endrule
    
    //
    // recvRealRespFromCacheToTable -- 
    //     Store the response info back to snoopedReqTable if respToNetworkQ is full.
    //
    (* fire_when_enabled *)
    rule recvRealRespFromCacheToTable (respFromCacheQ.first() matches tagged MSHR_REMOTE_RESP .r &&& !respToNetworkQ.notFull);
        respFromCacheQ.deq();
        let e = snoopedReqTable.sub(r.reqIdx);
        // update snoopedReqTable if not able to send response
        let new_entry = e;
        new_entry.val = r.val;
        new_entry.retry = r.retry;
        new_entry.isCacheable = r.isCacheable;
        new_entry.isExclusive = (r.isExclusive || e.isExclusive);
        snoopedReqTable.upd(r.reqIdx, new_entry);
        respReadyEntryQ.enq(r.reqIdx);
        debugLog.record($format("    sourceData: recvRealRespFromCacheToTable: response queue is full! table entry=0x%x, wait in the respReadyEntryQ...", r.reqIdx));
    endrule
    
    //
    // sendRespFromSnoopTable --
    //     Second time trying to send response to the ring. 
    //
    rule sendRespFromSnoopTable (respReadyEntryQ.notEmpty() && respToNetworkQ.notFull() && !resendFwdRespValW);
        let idx = respReadyEntryQ.first();
        respReadyEntryQ.deq();
        let e = snoopedReqTable.sub(idx);
        // send response
        sendRespFromSnoopTableToNetwork(e, e.val, e.retry, e.isCacheable, e.isExclusive, tuple3(False, ?, ?), "sendRespFromSnoopTable");
        // free the entry in snoopedReqTable
        snoopedReqTable.free(idx); 
        debugLog.record($format("    sourceData: sendRespFromSnoopTable: free snoopedReqTable (entry=0x%x)", idx));
    endrule
    
    //
    // recvDelayRespFromCache --
    //     Receive a delayed response from cache. Record the forwarding 
    // infomation in the forwarding table and release the entry in snoopedReqTable.
    //
    (* fire_when_enabled *)
    rule recvDelayRespFromCache (respFromCacheQ.first() matches tagged MSHR_DELAY_RESP .r &&& !recvGetsFwdRespW &&& !resendFwdRespValW);
        respFromCacheQ.deq();
        let e = snoopedReqTable.sub(r.reqIdx);
        let fwd_entry = forwardingTable.sub(r.fwdEntryIdx);  
        let new_fwd_entry = fwd_entry;
        
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
        if (r.isFirstFwd)
        begin
            new_fwd_entry.clientId = e.requester;
            new_fwd_entry.controllerId = e.reqControllerId;
            new_fwd_entry.isGetx = e.ownership;
            new_fwd_entry.clientMeta = truncateNP(e.meta);
            new_fwd_entry.globalReadMeta = e.globalReadMeta;
        end
        new_fwd_entry.multiFwd = !r.isFirstFwd;
        if (!fwd_entry.getsFwd)
        begin
            new_fwd_entry.lastClientId = e.requester;
            new_fwd_entry.lastControllerId = e.reqControllerId;
        end

        debugLog.record($format("    sourceData: recvDelayRespFromCache: update forwardingTable: (entry=0x%x), isFirstFwd=%s, clientId=%03d, controllerId=%02d, isGetx=%s, meta=0x%x, lastClientId=%03d, lastControllerId=%02d",
                        r.fwdEntryIdx, r.isFirstFwd? "True" : "False", new_fwd_entry.clientId, new_fwd_entry.controllerId, 
                        new_fwd_entry.isGetx? "True" : "False", new_fwd_entry.clientMeta, new_fwd_entry.lastClientId, new_fwd_entry.lastControllerId));
`else
        let fwd_node_idx = localIdToGlobal(e.reqControllerId, e.requester); 
        new_fwd_entry.forwardMeta[fwd_node_idx] = True;
        new_fwd_entry.hasGetx = e.ownership;
        if (e.ownership)
        begin
            new_fwd_entry.getxRequester = e.requester;
            new_fwd_entry.getxReqControllerId = e.reqControllerId;
        end
        debugLog.record($format("    sourceData: recvDelayRespFromCache: update forwardingTable: (entry=0x%x), fwdMeta=0x%x, hasGetx=%s, getxRequester=%03d, getxReqControllerId=%02d, requester=%03d, reqControllerId=%02d",
                        r.fwdEntryIdx, pack(new_fwd_entry.forwardMeta), new_fwd_entry.hasGetx? "True" : "False", 
                        new_fwd_entry.getxRequester, new_fwd_entry.getxReqControllerId, e.requester, e.reqControllerId));
        
        let info_entry = COH_SCRATCH_GET_REQ_INFO { clientMeta: truncateNP(e.meta), globalReadMeta: e.globalReadMeta };
        forwardInfoTable.upd(pack(tuple2(r.fwdEntryIdx, fwd_node_idx)), info_entry);
        debugLog.record($format("    sourceData: recvDelayRespFromCache: update forwardInfoTable: (entry=0x%x), meta=0x%x",
                        pack(tuple2(r.fwdEntryIdx, fwd_node_idx)), info_entry.clientMeta));
`endif
        forwardingTable.upd(r.fwdEntryIdx, new_fwd_entry);
        snoopedReqTable.free(r.reqIdx); 
        debugLog.record($format("    sourceData: recvDelayRespFromCache: free snoopedReqTable (entry=0x%x)", r.reqIdx));
    endrule

    (* fire_when_enabled *)
    rule recvFwdResetRespFromCache (respFromCacheQ.first() matches tagged MSHR_FWD_RESP .r &&& r.resetEntry &&& !recvGetsFwdRespW &&& !resendFwdRespValW);
        respFromCacheQ.deq();
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
        // forward data to the next cache on the response chain
        let f = forwardingTable.sub(r.fwdEntryIdx);
        if (f.getsFwd)
        begin
            if (respToNetworkQ.notFull)
            begin
                sendRespFromForwardingTableToNetwork(f, r.val, True, "recvFwdResetRespFromCache");
                // release entry
                releaseFwdEntryQ.enq(r.fwdEntryIdx);
                debugLog.record($format("    sourceData: recvFwdResetRespFromCache: done with forwarding, release entry 0x%x", r.fwdEntryIdx)); 
            end
            else
            begin
                pendingFwdEntryQ.enq(r.fwdEntryIdx);
                pendingFwdGetsQ.enq(True);
                debugLog.record($format("    sourceData: recvFwdResetRespFromCache: response queue is full! wait in the pendingFwdEntryQ, entry=0x%x", r.fwdEntryIdx));
            end
            //reset forwarding table
            let new_fwd_entry = f;
            new_fwd_entry.getsFwd = False;
            forwardingTable.upd(r.fwdEntryIdx, new_fwd_entry);
        end

`else
        // reset forwarding table
        forwardingTable.upd( r.fwdEntryIdx, COH_DM_CACHE_FWD_TABLE_ENTRY{ forwardMeta: replicate(False),
                                                                          hasGetx: False,
                                                                          getxRequester: ?,
                                                                          getxReqControllerId: ? });
        debugLog.record($format("    sourceData: recvFwdResetRespFromCache: reset forwardingTable: (entry=0x%x)", r.fwdEntryIdx));
`endif
    endrule

    //
    // recvFwdRespFromCacheToNetwork --
    //     Receive a forwarding response from cache. Send response to network 
    // according to the forwarding table. 
    //
    (* fire_when_enabled *)
    rule recvFwdRespFromCacheToNetwork (respFromCacheQ.first() matches tagged MSHR_FWD_RESP .r &&& !r.resetEntry &&& respToNetworkQ.notFull &&& !resendFwdRespValW &&& !recvGetsFwdRespW);
        respFromCacheQ.deq();
        let f = forwardingTable.sub(r.fwdEntryIdx);  

`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
        sendRespFromForwardingTableToNetwork(f, r.val, f.multiFwd, "recvFwdRespFromCacheToNetwork");
        releaseFwdEntryQ.enq(r.fwdEntryIdx);
        debugLog.record($format("    sourceData: recvFwdRespFromCacheToNetwork: done with forwarding, release entry 0x%x", r.fwdEntryIdx)); 
`else
        sendRespFromForwardingTableToNetwork(f, r.fwdEntryIdx, r.val, "recvFwdRespFromCacheToNetwork");
        if (countElem(True, f.forwardMeta) > 1) // multiple forwarding
        begin
            pendingFwdEntryQ.enq(r.fwdEntryIdx);
            debugLog.record($format("    sourceData: recvFwdRespFromCacheToNetwork: multiple forwarding occurs...")); 
        end
        else
        begin
            releaseFwdEntryQ.enq(r.fwdEntryIdx);
            debugLog.record($format("    sourceData: recvFwdRespFromCacheToNetwork: done with forwarding, release entry 0x%x", r.fwdEntryIdx)); 
        end
`endif
    endrule

    //
    // recvFwdRespFromCacheToTable --
    //     Receive a forwarding response from cache but response queue is full. 
    // Record response in the forwarding table. 
    //
    (* mutually_exclusive = "recvNullRespFromCache, recvRealRespFromCacheToNetwork, recvRealRespFromCacheToTable, recvDelayRespFromCache, recvFwdResetRespFromCache, recvFwdRespFromCacheToNetwork, recvFwdRespFromCacheToTable" *)
    (* descending_urgency = "recvNullRespFromCache, recvRealRespFromCacheToNetwork, recvRealRespFromCacheToTable, recvDelayRespFromCache, recvFwdResetRespFromCache, recvFwdRespFromCacheToNetwork, recvFwdRespFromCacheToTable, sendRespFromSnoopTable, snoopActivatedReq" *)
    (* fire_when_enabled *)
    rule recvFwdRespFromCacheToTable (respFromCacheQ.first() matches tagged MSHR_FWD_RESP .r &&& !r.resetEntry &&& !respToNetworkQ.notFull);
        respFromCacheQ.deq();
        pendingFwdEntryQ.enq(r.fwdEntryIdx);
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
        pendingFwdGetsQ.enq(False);
`endif
        debugLog.record($format("    sourceData: recvFwdRespFromCacheToTable: response queue is full! wait in pendingFwdEntryQ, idx=0x%x", r.fwdEntryIdx));
    endrule

    //
    // sendRespFromFwdTable --
    //     Send response from forwarding table for pending entries in the forwarding table.
    //
    (* mutually_exclusive = "sendRespFromFwdTable, recvNullRespFromCache, recvRealRespFromCacheToNetwork, recvDelayRespFromCache, recvFwdResetRespFromCache, recvFwdRespFromCacheToNetwork" *)
    (* mutually_exclusive = "sendRespFromFwdTable, sendRespFromSnoopTable" *)
    (* fire_when_enabled *)
    rule sendRespFromFwdTable (True);
        match {.idx, .val} = curFwdEntry;
        let f = forwardingTable.sub(idx);

`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
        let is_gets_fwd = pendingFwdGetsQ.first();
        pendingFwdGetsQ.deq();
        sendRespFromForwardingTableToNetwork(f, val, f.multiFwd || is_gets_fwd, "sendRespFromFwdTable");
        releaseFwdEntryQ.enq(idx);
        debugLog.record($format("    sourceData: sendRespFromFwdTable: done with forwarding, release entry 0x%x", idx)); 
`else
        sendRespFromForwardingTableToNetwork(f, idx, val, "sendRespFromFwdTable");
        if (countElem(True, f.forwardMeta) > 1)
        begin
            curFwdValue <= val;
            curFwdIdx   <= idx;
            fwdBusy     <= True;
        end
        else
        begin
            releaseFwdEntryQ.enq(idx);
            debugLog.record($format("    sourceData: sendRespFromFwdTable: done with forwarding, release entry 0x%x", idx)); 
        end
`endif
    endrule

`ifdef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
    (* mutually_exclusive = "sendRespFromFwdTable, sendRespFromFwdTableMultiFwd" *)
    (* descending_urgency = "recvFwdResetRespFromCache, sendRespFromSnoopTable, sendRespFromFwdTableMultiFwd" *)
    rule sendRespFromFwdTableMultiFwd (fwdBusy && respToNetworkQ.notFull);
        let f = forwardingTable.sub(curFwdIdx);
        sendRespFromForwardingTableToNetwork(f, curFwdIdx, curFwdValue, "sendRespFromFwdTableMultiFwd");
        if (countElem(True, f.forwardMeta) == 1)
        begin
            fwdBusy <= False;
            releaseFwdEntryQ.enq(curFwdIdx);
            debugLog.record($format("    sourceData: sendRespFromFwdTableMultiFwd: done with forwarding, release entry 0x%x", curFwdIdx)); 
        end
    endrule
`endif

`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
    (* mutually_exclusive = "recvGetsFwdResp, recvNullRespFromCache, recvDelayRespFromCache, recvFwdResetRespFromCache, recvFwdRespFromCacheToNetwork, recvFwdRespFromCacheToTable" *)
    (* mutually_exclusive = "recvGetsFwdResp, sendRespFromFwdTable" *)
    (* fire_when_enabled *)
    rule recvGetsFwdResp (getsFwdResp.wget() matches tagged Valid .resp);
        recvGetsFwdRespW.send();
        match {.meta, .val, .client_id, .controller_id} = resp;
        let f = forwardingTable.sub(meta);
        let new_fwd_entry = f;
        new_fwd_entry.getsFwd = True;
        new_fwd_entry.lastClientId = client_id;
        new_fwd_entry.lastControllerId = controller_id;
        forwardingTable.upd(meta, new_fwd_entry);
        debugLog.record($format("    sourceData: recvGetsFwdResp: update forwardingTable (entry=0x%x), getsFwd=True, lastClientId=%03d, lastControllerId=%02d", 
                        meta, client_id, controller_id));
    endrule
`endif

    (* fire_when_enabled *)
    rule sendRespToNetwork (True);
        let resp = respToNetworkQ.first();
        respToNetworkQ.deq();
        link_mem_resp.enq(tpl_1(resp), tpl_2(resp));
        debugLog.record($format("    sourceData: sendRespToNetwork: val=0x%x, dest=%03d", tpl_2(resp).val, tpl_1(resp)));
    endrule
    
    // ====================================================================
    //
    //   Debug scan state
    //
    // ====================================================================

    List#(Tuple2#(String, Bool)) ds_data = List::nil;

    // Request or response queues
    ds_data = List::cons(tuple2("Coherent Cache Router numBufferedReq notEmpty", numBufferedReq.value()>0), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache Router numBufferedReq notFull", numBufferedReq.value()<fromInteger(valueOf(COH_DM_CACHE_NW_REQ_BUF_SIZE))), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache Router unactivatedReqQ notEmpty", unactivatedReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache Router unactivatedReqQ notFull", unactivatedReqQ.notFull), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache Router activatedReqQ notEmpty", activatedReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache Router activatedReqQ notFull", activatedReqQ.notFull), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache Router respReadyEntryQ notEmpty", respReadyEntryQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache Router respReadyEntryQ notFull", respReadyEntryQ.notFull), ds_data);
    
    // Network channels
    ds_data = List::cons(tuple2("Coherent Cache Router link_mem_req notEmpty", link_mem_req.notEmpty), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache Router link_mem_req notFull", link_mem_req.notFull), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache Router link_mem_resp notEmpty", link_mem_resp.notEmpty), ds_data);
    ds_data = List::cons(tuple2("Coherent Cache Router link_mem_resp notFull", link_mem_resp.notFull), ds_data);
    
    if (hasMultiController)
    begin
        ds_data = List::cons(tuple2("Coherent Cache Router links_mem_activatedReq0 notEmpty", links_mem_activatedReq[0].recvNotEmpty), ds_data);
        ds_data = List::cons(tuple2("Coherent Cache Router links_mem_activatedReq0 notFull", links_mem_activatedReq[0].sendNotFull), ds_data);
        ds_data = List::cons(tuple2("Coherent Cache Router links_mem_activatedReq1 notEmpty", links_mem_activatedReq[1].recvNotEmpty), ds_data);
        ds_data = List::cons(tuple2("Coherent Cache Router links_mem_activatedReq1 notFull", links_mem_activatedReq[1].sendNotFull), ds_data);
    end
    else
    begin
        ds_data = List::cons(tuple2("Coherent Cache Router link_mem_activatedReq notEmpty", link_mem_activatedReq.recvNotEmpty), ds_data);
        ds_data = List::cons(tuple2("Coherent Cache Router link_mem_activatedReq notFull", link_mem_activatedReq.sendNotFull), ds_data);
    end

    let debugScanData = ds_data;

    // =======================================================================
    // 
    // Methods
    //
    // =======================================================================

    // Request for share data
    method Action getShare(t_CACHE_ADDR addr,
                           t_CACHE_META meta,
                           RL_CACHE_GLOBAL_READ_META globalReadMeta) if (initialized);
    
        let req_info = COH_SCRATCH_GET_REQ_INFO { clientMeta: unpack(zeroExtendNP(pack(meta))),
                                                  globalReadMeta: globalReadMeta };
        let req = COH_SCRATCH_MEM_REQ { requester: myPort,
                                        reqControllerId: ?,
                                        addr: addr,
                                        reqInfo: tagged COH_SCRATCH_GETS req_info};

        // Forward the request to the coherent scratchpad controller that orders
        // all coherent scratchpad clients' requests
        unactivatedReqQ.enq(req);
        debugLog.record($format("    sourceData: send GETS REQ ID %0d: addr 0x%x", myPort, addr));
        
        numBufferedReq.upBy(1);
        debugLog.record($format("    sourceData: getShare: numBufferedReq=%x", numBufferedReq.value()));
    
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
        // record the request address in the lastGetReqTable
        lastGetReqTable.upd(meta, tagged Valid addr);
`endif    
    endmethod
    
    
    // Request for data and exlusive ownership
    method Action getExclusive(t_CACHE_ADDR addr,
                               t_CACHE_META meta,
                               RL_CACHE_GLOBAL_READ_META globalReadMeta) if (initialized);

        let req_info = COH_SCRATCH_GET_REQ_INFO { clientMeta: unpack(zeroExtendNP(pack(meta))),
                                                  globalReadMeta: globalReadMeta };

        let req = COH_SCRATCH_MEM_REQ { requester: myPort,
                                        reqControllerId: ?,
                                        addr: addr,
                                        reqInfo: tagged COH_SCRATCH_GETX req_info};

        // Forward the request to the coherent scratchpad controller that orders
        // all coherent scratchpad clients' requests
        unactivatedReqQ.enq(req);
        debugLog.record($format("    sourceData: send GETX REQ ID %0d: addr 0x%x", myPort, addr));

        numBufferedReq.upBy(1);
        debugLog.record($format("    sourceData: getExclusive: numBufferedReq=%x", numBufferedReq.value()));

`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
        // record the request address in the lastGetReqTable
        lastGetReqTable.upd(meta, tagged Valid addr);
`endif    
    endmethod                           

    // Response received from other coherent scratchpad clients or the controller (memory)
    method ActionValue#(t_COH_CACHE_FILL_RESP) getResp();
        let s = link_mem_resp.first();
        link_mem_resp.deq();

        t_COH_CACHE_FILL_RESP r;
        r.val = s.val;
        r.meta = unpack(truncateNP(s.meta));
        r.ownership = s.ownership;
        r.isExclusive = s.isExclusive;
        r.isCacheable = s.isCacheable;
        r.retry = s.retry;
        r.globalReadMeta = s.globalReadMeta;
        r.getsFwd = False;
        r.fromCache = s.fromCache;

`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
        // GETS response forwarding happens when the received response indicates 
        // that the cache needs to forward and the cache itself is not the last 
        // node of the forwarding chain
        if (!s.ownership && s.needFwd && !isOwnReq(s.lastFwdClientId, s.lastFwdControllerId))
        begin
            r.getsFwd = True;
            getsFwdResp.wset(tuple4(r.meta, s.val, s.lastFwdClientId, s.lastFwdControllerId));
        end
`endif
        debugLog.record($format("    sourceData: read RESP: val=0x%x, meta=0x%x", s.val, r.meta));
        
        return r;
    endmethod
    
    method t_COH_CACHE_FILL_RESP peekResp();
        let s = link_mem_resp.first();

        t_COH_CACHE_FILL_RESP r;
        r.val = s.val;
        r.meta = unpack(truncateNP(s.meta));
        r.ownership = s.ownership;
        r.isExclusive = s.isExclusive;
        r.isCacheable = s.isCacheable;
        r.retry = s.retry;
        r.globalReadMeta = s.globalReadMeta;
        r.getsFwd = False;
        r.fromCache = s.fromCache;

`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
        if (!s.ownership && s.needFwd && !isOwnReq(s.lastFwdClientId, s.lastFwdControllerId))
        begin
            r.getsFwd = True;
        end
`endif
        return r;
    endmethod                                  
    
    // Request for writing back data and giving up ownership 
    method Action putExclusive(t_CACHE_ADDR addr, Bool isCleanWB, Bool isExclusive) if (initialized);
        
        let req_info = COH_SCRATCH_PUT_REQ_INFO { isCleanWB: isCleanWB, isExclusive: isExclusive };

        let req = COH_SCRATCH_MEM_REQ { requester: myPort,
                                        reqControllerId: ?,
                                        addr: addr,
                                        reqInfo: tagged COH_SCRATCH_PUTX req_info};

        // Forward the request to the coherent scratchpad controller that orders
        // all coherent scratchpad clients' requests
        unactivatedReqQ.enq(req);

        debugLog.record($format("    sourceData: send PUTX REQ ID %0d: addr 0x%x, isCleanWB=%s, isExclusive=%s", 
                        myPort, addr, isCleanWB? "True" : "False", isExclusive? "True" : "False"));
        
        numBufferedReq.upBy(1);
        debugLog.record($format("    sourceData: putExclusive: numBufferedReq=%x", numBufferedReq.value()));
    endmethod                           
   
    // Signal indicating an unactivated request is sent to the network
    // (One slot in the request buffer is released)
    method Bool unactivatedReqSent() = unactivatedReqSentW;
       
    // Data owner sends responses to serve other caches
    // If it is not the owner, null response is sent to clear the entry in the 
    // completion table 
    method Action sendResp(t_ROUTER_RESP resp);
        respFromCacheQ.enq(resp);
        debugLog.record($format("    sourceData: receive a response from cache...")); 
    endmethod                       
    
    // Return the released forwarding entry index
    // Cache will pass the information to MSHR in order to release the MSHR entry
    method ActionValue#(t_CACHE_META) getReleasedFwdEntryIdx();
        let idx = releaseFwdEntryQ.first();
        releaseFwdEntryQ.deq();
        debugLog.record($format("    sourceData: return released forwarding entry idx=0x%x", idx)); 
        return idx;
    endmethod

    // Return the pending forwarding entry
    // Cache will pass the information to MSHR and ask MSHR to re-send the
    // forwarding response 
    method ActionValue#(t_CACHE_META) getPendingFwdEntryIdx();
        let idx = pendingFwdEntryQ.first();
        pendingFwdEntryQ.deq();
        debugLog.record($format("    sourceData: return pending forwarding entry idx=0x%x", idx)); 
        return idx;
    endmethod

    // Resend forward response value 
    method Action resendFwdRespVal(t_CACHE_META fwdIdx, t_CACHE_WORD val) if (respToNetworkQ.notFull && !recvGetsFwdRespW && !fwdBusy);
        curFwdEntry <= tuple2(fwdIdx, val);
        resendFwdRespValW.send();
        debugLog.record($format("    sourceData: resendFwdRespVal: entry=0x%x, val=0x%x", fwdIdx, val)); 
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
    
    //
    // debugScanState -- Return cache state for DEBUG_SCAN.
    //
    method List#(Tuple2#(String, Bool)) debugScanState();
        return debugScanData;
    endmethod

endmodule


