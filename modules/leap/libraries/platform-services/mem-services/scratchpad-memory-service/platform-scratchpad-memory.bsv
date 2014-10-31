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
// Interfaces to scratchpad memory.
//

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import DefaultValue::*;


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
`include "awb/dict/VDEV.bsh"

`ifndef VDEV_SCRATCH__BASE
`define VDEV_SCRATCH__BASE 0
`endif


//
// Data structures flowing through soft connections between scratchpad clients
// and the platform interface.
//

typedef struct
{
    SCRATCHPAD_PORT_NUM port;
    SCRATCHPAD_MEM_ADDRESS allocLastWordIdx;
    Bool cached;
    Maybe#(GLOBAL_STRING_UID) initFilePath;
}
SCRATCHPAD_INIT_REQ
    deriving (Eq, Bits);

typedef struct
{
    SCRATCHPAD_PORT_NUM port;
    SCRATCHPAD_MEM_ADDRESS addr;
    SCRATCHPAD_MEM_MASK byteReadMask;
    SCRATCHPAD_CLIENT_READ_UID readUID;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
SCRATCHPAD_READ_REQ
    deriving (Eq, Bits);

typedef struct
{
    SCRATCHPAD_PORT_NUM port;
    SCRATCHPAD_MEM_ADDRESS addr;
    SCRATCHPAD_MEM_VALUE val;
}
SCRATCHPAD_WRITE_REQ
    deriving (Eq, Bits);

typedef struct
{
    SCRATCHPAD_PORT_NUM port;
    SCRATCHPAD_MEM_ADDRESS addr;
    SCRATCHPAD_MEM_VALUE val;
    SCRATCHPAD_MEM_MASK byteWriteMask;
}
SCRATCHPAD_WRITE_MASKED_REQ
    deriving (Eq, Bits);


//
// Scratchpad requests (either a load or a store) from the client to the
// server.
//
typedef union tagged 
{
    SCRATCHPAD_INIT_REQ           SCRATCHPAD_MEM_INIT;

    SCRATCHPAD_READ_REQ           SCRATCHPAD_MEM_READ;
    SCRATCHPAD_WRITE_REQ          SCRATCHPAD_MEM_WRITE;
    SCRATCHPAD_WRITE_MASKED_REQ   SCRATCHPAD_MEM_WRITE_MASKED;
}
SCRATCHPAD_MEM_REQ
    deriving (Eq, Bits);


//
// Scratchpad read response.
//
typedef struct
{
    SCRATCHPAD_MEM_VALUE val;
    SCRATCHPAD_MEM_ADDRESS addr;
    SCRATCHPAD_CLIENT_READ_UID readUID;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
    Bool isCacheable;
}
SCRATCHPAD_READ_RSP
    deriving (Eq, Bits);


// Number of slots in a read port's reorder buffer.  The scratchpad subsystem
// does not guarantee to return results in order, so all clients need a ROB.
// The ROB size limits the number of read requests in flight for a given port.
typedef 32 SCRATCHPAD_PORT_ROB_SLOTS;

// The uncached scratchpad will have more references outstanding due to latency.
// Allow more references to be in flight.
typedef 128 SCRATCHPAD_UNCACHED_PORT_ROB_SLOTS;

//
// Scratchpad ports must be unique and non-zero.  Port 0 is the server.
//
function Integer scratchpadIntPortId(Integer n);
    return fromInteger(n - `VDEV_SCRATCH__BASE + 1);
endfunction

function SCRATCHPAD_PORT_NUM scratchpadPortId(Integer n);
    return fromInteger(scratchpadIntPortId(n));
endfunction


// ========================================================================
//
// Modules that instantiate a scratchpad memory.
//
// ========================================================================
    
//
// mkScratchpad --
//     This is the typical scratchpad module.
//
//     Build a scratchpad of an arbitrary data type with marshalling to the
//     global scratchpad base memory size.
//
module [CONNECTED_MODULE] mkScratchpad#(Integer scratchpadID,
                                        SCRATCHPAD_CONFIG conf)
    // interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    //
    // The scratchpad implementation is all in the multi-reader interface.
    // Allocate a multi-reader scratchpad with a single reader and convert
    // it to MEMORY_IFC.
    //
    MEMORY_MULTI_READ_IFC#(1, t_ADDR, t_DATA) m_scratch <-
        mkMultiReadScratchpad(scratchpadID, conf);
    MEMORY_IFC#(t_ADDR, t_DATA) scratch <- mkMultiMemIfcToMemIfc(m_scratch);
    return scratch;
endmodule

//
// mkMultiReadScratchpad --
//     The same as mkMultiReadStatScratchpad but we have null stats in this case
//
module [CONNECTED_MODULE] mkMultiReadScratchpad#(Integer scratchpadID,
                                                 SCRATCHPAD_CONFIG conf)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    let statsConstructor = mkNullScratchpadCacheStats;
    let prefetchStatsConstructor = mkNullScratchpadPrefetchStats;

    NumTypeParam#(`SCRATCHPAD_STD_PVT_CACHE_PREFETCH_LEARNER_NUM) n_prefetch_learners = ?;

    if(conf.enableStatistics matches tagged Valid .prefix)
    begin
        statsConstructor = mkBasicScratchpadCacheStats(prefix, "");
        if (`SCRATCHPAD_STD_PVT_CACHE_PREFETCH_ENABLE == 1)
        begin
            prefetchStatsConstructor = mkBasicScratchpadPrefetchStats(prefix, "", n_prefetch_learners);
        end
    end
    else if(`PLATFORM_SCRATCHPAD_STATS_ENABLE != 0)
    begin
        let prefix = "Scratchpad_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_";
        statsConstructor = mkBasicScratchpadCacheStats(prefix, "");
        if (`SCRATCHPAD_STD_PVT_CACHE_PREFETCH_ENABLE == 1)
        begin
            prefetchStatsConstructor = mkBasicScratchpadPrefetchStats(prefix, "", n_prefetch_learners);
        end
    end

    let m <- mkMultiReadStatsScratchpad(scratchpadID, conf,
                                        statsConstructor,
                                        prefetchStatsConstructor);
    return m;

endmodule

//
// mkMultiReadStatsScratchpad --
//     The same as a normal mkScratchpad but with multiple read ports.
//     Requests are processed in order, with reads being scheduled before
//     a write requested in the same cycle.
//
module [CONNECTED_MODULE] mkMultiReadStatsScratchpad#(
    Integer scratchpadID,
    SCRATCHPAD_CONFIG conf,
    SCRATCHPAD_STATS_CONSTRUCTOR statsConstructor,
    SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR prefetchStatsConstructor)
    // Interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),

              // Compute container index type (size)
              Bits#(SCRATCHPAD_MEM_ADDRESS, t_SCRATCHPAD_MEM_ADDRESS_SZ),
              Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ),
              Alias#(MEM_PACK_CONTAINER_ADDR#(t_ADDR_SZ, t_DATA_SZ, t_SCRATCHPAD_MEM_VALUE_SZ), t_CONTAINER_ADDR),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ));

    MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) memory;
    Bool need_init_wrapper = False;

    //
    // Initialized scratchpads must have object sizes that are a power of 2.
    // We require this so that initialization files can simply be read right
    // into memory, without regard to the local memory word size.
    //
    if (isValid(conf.initFilePath) &&
        (valueOf(TExp#(TLog#(t_DATA_SZ))) != valueOf(t_DATA_SZ)))
    begin
        error("Scratchpad ID " + integerToString(scratchpadIntPortId(scratchpadID)) + ": Initialized scratchpads must have power of 2 data sizes.");
    end


    if (conf.cacheMode == SCRATCHPAD_UNCACHED)
    begin
        // No caches at any level.  This access pattern uses masked writes to
        // avoid read-modify-write loops when accessing objects smaller than
        // a scratchpad base data size.
        memory <- mkUncachedScratchpad(scratchpadID, conf);
    end
    else if ((conf.cacheMode == SCRATCHPAD_CACHED) &&
             (valueOf(TExp#(t_CONTAINER_ADDR_SZ)) <= `SCRATCHPAD_STD_PVT_CACHE_ENTRIES))
    begin
        // A special case:  cached scratchpad requested but the container
        // is smaller than the cache would have been.  Just allocate a BRAM.
        memory <- mkBRAMBufferedPseudoMultiReadInitialized(True, unpack(0));
        need_init_wrapper = True;
    end
    else
    begin
        // Container maps requested data size to the platform's scratchpad
        // word size.
        NumTypeParam#(`SCRATCHPAD_STD_PVT_CACHE_ENTRIES) n_cache_entries = ?;
        NumTypeParam#(t_SCRATCHPAD_MEM_VALUE_SZ) scratchpad_data_sz = ?;
        NumTypeParam#(`SCRATCHPAD_STD_PVT_CACHE_PREFETCH_LEARNER_NUM) n_cache_prefetch_learners = ?;

        if (conf.cacheMode == SCRATCHPAD_CACHED)
        begin
            memory <- mkMemPackMultiRead(scratchpad_data_sz,
                                         mkUnmarshalledCachedScratchpad(scratchpadID,
                                                                        conf,
                                                                        `PARAMS_SCRATCHPAD_MEMORY_SERVICE_SCRATCHPAD_PVT_CACHE_MODE,
                                                                        `PARAMS_SCRATCHPAD_MEMORY_SERVICE_SCRATCHPAD_PREFETCHER_MECHANISM,
                                                                        `PARAMS_SCRATCHPAD_MEMORY_SERVICE_SCRATCHPAD_PREFETCHER_LEARNER_SIZE_LOG,
                                                                        n_cache_entries,
                                                                        n_cache_prefetch_learners,
                                                                        statsConstructor,
                                                                        prefetchStatsConstructor));
        end
        else
        begin
            memory <- mkMemPackMultiRead(scratchpad_data_sz,
                                         mkUnmarshalledScratchpad(scratchpadID, conf));
        end
    end

    //
    // Is this scratchpad initialized with a file?  If so, it might need to
    // have the initialization streamed in.  The hybrid scratchpad code
    // handles initialization with mmap on the host, allowing us to initialize
    // very large spaces efficiently.  Local memory scratchpads without host-side
    // homes require initialization wrappers.
    //
    if (((`SCRATCHPAD_SUPPORTS_INIT == 0) || need_init_wrapper) &&&
        conf.initFilePath matches tagged Valid .init_path)
    begin
        // Get-based stream from the initialization file
        let init_stream <- mkStdIO_GetFile(True, init_path);
        // Put-based memory initialization wrapper
        let init_memory <- mkMultiMemInitializedWithGet(memory, init_stream);

        memory = init_memory;
    end

    return memory;
endmodule


// ========================================================================
//
// Heaps layered on scratchpad memory
//
// ========================================================================


//
// mkMemoryHeapUnionScratchpad --
//     Data and free list share same storage in a scratchpad memory.
//
module [CONNECTED_MODULE] mkMemoryHeapUnionScratchpad#(Integer scratchpadID,
                                                       SCRATCHPAD_CONFIG conf)
    // interface:
    (MEMORY_HEAP#(t_INDEX, t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_INDEX, t_INDEX_SZ));

    let heap <- mkMemoryHeapUnionMem(mkMultiReadScratchpad(scratchpadID, conf));
    return heap;
endmodule
    
    
// ========================================================================
//
// Internal modules
//
// ========================================================================
    
// number of entries in the merge table
typedef TMax#(128, TMul#(32, n_PORTS)) SCRATCHPAD_MERGE_TABLE_ENTRIES#(numeric type n_PORTS);

typedef struct
{
    t_MERGE_TAG               tag;
    Vector#(n_ENTRIES, Bool)  mergeMeta;
}
SCRATCHPAD_MERGE_TABLE_ENTRY#(type t_MERGE_TAG, 
                              numeric type n_ENTRIES)
    deriving(Bits, Eq);
    
//
// mkUnmarshalledScratchpad --
//     Allocate a connection to the platform's scratchpad interface for
//     a single scratchpad region.  This module does no marshalling of
//     data sizes or caching.  BEWARE: the word size of the virtual
//     platform's scratchpad is platform dependent.
//
module [CONNECTED_MODULE] mkUnmarshalledScratchpad#(Integer scratchpadID,
                                                    SCRATCHPAD_CONFIG conf)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE))
    provisos (Bits#(t_MEM_ADDRESS, t_MEM_ADDRESS_SZ),
              Bits#(SCRATCHPAD_MEM_ADDRESS, t_SCRATCHPAD_MEM_ADDRESS_SZ),

              // Index in a reorder buffer
              Alias#(SCOREBOARD_FIFO_ENTRY_ID#(SCRATCHPAD_PORT_ROB_SLOTS), t_REORDER_ID),

              // Request merge table
              NumAlias#(TMin#(t_MEM_ADDRESS_SZ, TLog#(SCRATCHPAD_MERGE_TABLE_ENTRIES#(n_READERS))), t_MERGE_IDX_SZ),
              Alias#(Bit#(t_MERGE_IDX_SZ), t_MERGE_IDX),
              Alias#(Bit#(TSub#(t_MEM_ADDRESS_SZ, t_MERGE_IDX_SZ)), t_MERGE_TAG),
              NumAlias#(TMax#(1, TExp#(TAdd#(TLog#(n_READERS), TLog#(SCRATCHPAD_PORT_ROB_SLOTS)))), n_MERGE_META_ENTRIES),
              Alias#(SCRATCHPAD_MERGE_TABLE_ENTRY#(t_MERGE_TAG, n_MERGE_META_ENTRIES), t_MERGE_ENTRY), 
              
              // MAF for in-flight reads
              Alias#(Tuple2#(Bit#(TLog#(n_READERS)), t_REORDER_ID), t_MAF_IDX),
              Bits#(t_MAF_IDX, t_MAF_IDX_SZ));
    
    if (valueOf(t_MEM_ADDRESS_SZ) > valueOf(t_SCRATCHPAD_MEM_ADDRESS_SZ))
    begin
        error("Scratchpad ID " + integerToString(scratchpadIntPortId(scratchpadID)) + " address is too large: " + integerToString(valueOf(t_MEM_ADDRESS_SZ)) + " bits");
    end

    DEBUG_FILE debugLog;
    if(conf.debugLogPath matches tagged Valid .debugLogPath)
    begin 
        debugLog <- mkDebugFile(debugLogPath);
    end
    else if(`PLATFORM_SCRATCHPAD_DEBUG_ENABLE == 1)
    begin
        String debugLogFilename = "platform_scratchpad_" + integerToString(scratchpadIntPortId(scratchpadID)) + ".out";
        debugLog <- mkDebugFile(debugLogFilename);   
    end
    else
    begin
        debugLog <- mkDebugFileNull(""); 
    end

    let my_port = scratchpadPortId(scratchpadID);
    let platformID <- getSynthesisBoundaryPlatformID();
    
    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_MEM_REQ) link_mem_req <-
        mkConnectionTokenRingNode("Scratchpad_Platform_" + integerToString(platformID) + "_Req", my_port);

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_READ_RSP) link_mem_rsp <-
        mkConnectionTokenRingNode("Scratchpad_Platform_" + integerToString(platformID) + "_Resp", my_port);

    messageM("Scratchpad Ring Name: "+ "Scratchpad_Platform_" + integerToString(platformID) + "_Req, Port: " + integerToString(scratchpadIntPortId(scratchpadID)));
    messageM("Scratchpad Ring Name: "+ "Scratchpad_Platform_" + integerToString(platformID) + "_Resp, Port: " + integerToString(scratchpadIntPortId(scratchpadID)));

    // Scratchpad responses are not ordered.  Sort them with a reorder buffer.
    // Each read port gets its own reorder buffer so that each port returns data
    // when available, independent of the latency of requests on other ports.
    Vector#(n_READERS, SCOREBOARD_FIFOF#(SCRATCHPAD_PORT_ROB_SLOTS, SCRATCHPAD_MEM_VALUE)) sortResponseQ <- replicateM(mkScoreboardFIFOF());

    // Merge FIFOF combines read and write requests in temporal order,
    // with reads from the same cycle as a write going first.  Each read port
    // gets a slot.  The write port is always last.
    MERGE_FIFOF#(TAdd#(n_READERS, 1),
                 Tuple2#(t_MEM_ADDRESS, SCOREBOARD_FIFO_ENTRY_ID#(SCRATCHPAD_PORT_ROB_SLOTS))) incomingReqQ <- mkMergeBypassFIFOF();

    // Write data is sent in a side port to keep the incomingReqQ smaller.
    FIFO#(SCRATCHPAD_MEM_VALUE) writeDataQ <- mkBypassFIFO();

    Reg#(Bool) initialized <- mkReg(False);
    
    //
    // Allocate memory for this scratchpad region
    //
    rule doInit (! initialized);
        initialized <= True;

        Bit#(t_MEM_ADDRESS_SZ) alloc = maxBound;
        SCRATCHPAD_INIT_REQ r;
        r.allocLastWordIdx = zeroExtendNP(alloc);
        r.port = my_port;
        r.cached = True;
        r.initFilePath = conf.initFilePath;
        link_mem_req.enq(0, tagged SCRATCHPAD_MEM_INIT r);
    endrule

    //
    // Request merging
    //
    // Merge multiple read requests accessing the same scratchpad address.
    // Only issue the fist read request to the remote memory, and let
    // subsequent read requests wait in the request merging table (reqMergeTable).
    //
    LUTRAM#(t_MERGE_IDX, t_MERGE_ENTRY) reqMergeTable = ?;
    LUTRAM#(Bit#(t_MAF_IDX_SZ), Maybe#(t_MERGE_IDX)) reqMergeHeadInfo = ?;
    Reg#(Vector#(SCRATCHPAD_PORT_ROB_SLOTS, Bool)) reqMergeTableValidBits = ?;
    Reg#(Vector#(SCRATCHPAD_PORT_ROB_SLOTS, Bool)) reqMergeTableEndBits = ?;
    Reg#(Tuple2#(t_MERGE_IDX, SCRATCHPAD_MEM_VALUE)) multiRespFwdEntry =?;
    PulseWire mergeTableLockedW = ?;
    Reg#(Bool) multiRespFwd <- mkReg(False);

    // allocate merge table
    if (conf.requestMerging)
    begin
        reqMergeTable <- mkLUTRAMU();
        reqMergeHeadInfo <- mkLUTRAM(tagged Invalid);
        reqMergeTableValidBits <- mkReg(replicate(False));
        reqMergeTableEndBits <- mkReg(replicate(True));
        multiRespFwdEntry <- mkRegU();
        mergeTableLockedW <- mkPulseWire();
    end

    function Tuple2#(t_MERGE_TAG, t_MERGE_IDX) mergeEntryFromAddr(t_MEM_ADDRESS addr);
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
                    let new_end_bits = reqMergeTableEndBits;
                    new_end_bits[idx] = !isInit;
                    reqMergeTableEndBits <= new_end_bits;
                endaction;
        end
        else
        begin
            return noAction;
        end
    endfunction

    //
    // Forward merged requests to the memory.
    //
    
    // Read requests
    rule forwardReadReq (initialized && (incomingReqQ.firstPortID() < fromInteger(valueOf(n_READERS))));
        let port = incomingReqQ.firstPortID();
        match {.addr, .rob_idx} = incomingReqQ.first();
        incomingReqQ.deq();

        // The read UID for this request is the concatenation of the
        // port ID and the ROB index.
        t_MAF_IDX maf_idx = tuple2(truncateNP(port), rob_idx);

        Bool issue_req = True;
        
        if (conf.requestMerging)
        begin
            debugLog.record($format("forwardReadReq: port %0d: addr=0x%x, rob_idx=%0d, maf_idx=0x%x",
                            port, addr, rob_idx, pack(maf_idx)));
            if (!mergeTableLockedW)
            begin
                match {.m_tag, .m_idx} = mergeEntryFromAddr(addr);
                Bit#(TLog#(n_READERS)) p = truncateNP(port);
                if (reqMergeTableValidBits[m_idx] == True)
                begin
                    let e = reqMergeTable.sub(m_idx);
                    if (e.tag == m_tag && !reqMergeTableEndBits[m_idx]) // hit
                    begin
                        issue_req = False;
                        let new_entry = e;
                        new_entry.mergeMeta[pack(tuple2(p,rob_idx))] = True;
                        reqMergeTable.upd(m_idx, new_entry); 
                        debugLog.record($format("forwardReadReq: port %0d: update reqMergeTable, idx=0x%x, tag=0x%x, mergeMeta=0x%x",
                                        port, m_idx, m_tag, pack(new_entry.mergeMeta)));
                    end
                end
                else // initialize merge table
                begin
                    reqMergeTable.upd(m_idx, SCRATCHPAD_MERGE_TABLE_ENTRY { tag: m_tag,
                                                                            mergeMeta: replicate(False) });
                    reqMergeHeadInfo.upd(pack(maf_idx), tagged Valid m_idx);
                    initOrResetMergeEntry(m_idx, True);
                    debugLog.record($format("forwardReadReq: port %0d: initialize reqMergeTable, idx=0x%x, tag=0x%x", 
                                    port, m_idx, m_tag));
                    debugLog.record($format("forwardReadReq: port %0d: set reqMergeHeadInfo, idx=0x%x", port, pack(maf_idx)));
                end
            end
        end
        
        if (issue_req)
        begin
            let req = SCRATCHPAD_READ_REQ { port: my_port,
                                            addr: zeroExtendNP(pack(addr)),
                                            byteReadMask: replicate(True),
                                            readUID: zeroExtendNP(pack(maf_idx)),
                                            globalReadMeta: defaultValue() };
            link_mem_req.enq(0, tagged SCRATCHPAD_MEM_READ req);
        end
    endrule

    // Write requests
    rule forwardWriteReq (initialized && !multiRespFwd && (incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS))));
        let addr = tpl_1(incomingReqQ.first());
        incomingReqQ.deq();
        
        let val = writeDataQ.first();
        writeDataQ.deq();

        let req = SCRATCHPAD_WRITE_REQ { port: my_port,
                                         addr: zeroExtendNP(pack(addr)),
                                         val: val };

        link_mem_req.enq(0, tagged SCRATCHPAD_MEM_WRITE req);
        
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

    //
    // receiveResp --
    //     Push unordered read responses to the reorder buffers.  Responses will
    //     be returned through readRsp() in order.
    //
    (* descending_urgency = "receiveResp, forwardWriteReq" *)
    rule receiveResp (True);
        let s = link_mem_rsp.first();
        link_mem_rsp.deq();

        // The read UID field holds the concatenation of the port ID and
        // the port's reorder buffer index.
        t_MAF_IDX maf_idx = unpack(truncateNP(s.readUID));
        match {.port, .rob_idx} = maf_idx;

        sortResponseQ[port].setValue(rob_idx, s.val);
            
        if (conf.requestMerging)
        begin
            debugLog.record($format("receiveResp: port %0d: resp val=0x%x, rob idx=%0d", port, s.val, rob_idx));
            mergeTableLockedW.send();
            let merge_head_info = reqMergeHeadInfo.sub(pack(maf_idx));
            if (merge_head_info matches tagged Valid .m_idx)
            begin
                let e = reqMergeTable.sub(m_idx);
                if (fold(\|| , e.mergeMeta))
                begin
                    multiRespFwd <= True;
                    multiRespFwdEntry <= tuple2(m_idx, s.val);
                    debugLog.record($format("receiveResp: port %0d: need to forward resp, merge table idx=0x%x", port, m_idx));
                end
                else //release merge table entry
                begin
                    initOrResetMergeEntry(m_idx, False);
                    debugLog.record($format("receiveResp: port %0d: no need to forward resp, reset merge table idx=0x%x", port, m_idx));
                end
                // reset reqMergeHeadInfo
                reqMergeHeadInfo.upd(pack(maf_idx), tagged Invalid);
                debugLog.record($format("receiveResp: port %0d: reset reqMergeHeadInfo, idx=0x%x", port, pack(maf_idx)));
            end
        end
    endrule

    if (conf.requestMerging)
    begin
        rule fwdMultiResp (multiRespFwd);
            mergeTableLockedW.send();
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

    //
    // Methods.  All requests are stored in the incomingReqQ to maintain their
    // order.
    //

    Vector#(n_READERS, MEMORY_READER_IFC#(t_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE)) portsLocal = newVector();

    for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_MEM_ADDRESS addr);
                    // Allocate a slot in the reorder buffer for the read request.  Each
                    // read port gets its own reorder buffer.
                    let idx <- sortResponseQ[p].enq();
                    incomingReqQ.ports[p].enq(tuple2(addr, idx));
        
                    debugLog.record($format("read port %0d: req addr=0x%x, rob idx=%0d", p, addr, idx));
                endmethod

                method ActionValue#(SCRATCHPAD_MEM_VALUE) readRsp();
                    let r = sortResponseQ[p].first();
                    sortResponseQ[p].deq();

                    debugLog.record($format("read port %0d: resp val=0x%x, rob_idx=%0d", p, r, sortResponseQ[p].deqEntryId()));
                    return r;
                endmethod

                method SCRATCHPAD_MEM_VALUE peek();
                    return sortResponseQ[p].first();
                endmethod

                method Bool notEmpty() = sortResponseQ[p].notEmpty();
                method Bool notFull() = incomingReqQ.ports[p].notFull() &&
                                        sortResponseQ[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_MEM_ADDRESS addr, SCRATCHPAD_MEM_VALUE val);
        // The write port is last in the merge FIFO
        incomingReqQ.ports[valueOf(n_READERS)].enq(tuple2(addr, ?));
        writeDataQ.enq(val);
        debugLog.record($format("write addr=0x%x, val=0x%x", addr, val));
    endmethod

    method Bool writeNotFull = incomingReqQ.ports[valueOf(n_READERS)].notFull();
endmodule
    
    
//
// mkUnmarshalledCachedScratchpad --
//     Allocate a cached connection to the platform's scratchpad interface for
//     a single scratchpad region.  This module does no marshalling of
//     data sizes.
//
module [CONNECTED_MODULE] mkUnmarshalledCachedScratchpad#(Integer scratchpadID, 
                                                          SCRATCHPAD_CONFIG conf,
                                                          Integer cacheModeParam,
                                                          Integer prefetchMechanismParam,
                                                          Integer prefetchLearnerSizeLogParam,
                                                          NumTypeParam#(n_CACHE_ENTRIES) nCacheEntries,
                                                          NumTypeParam#(n_PREFETCH_LEARNER_SIZE) nPrefetchLearners,
                                                          SCRATCHPAD_STATS_CONSTRUCTOR statsConstructor,
                                                          SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR prefetchStatsConstructor)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE))
    provisos (Bits#(t_MEM_ADDRESS, t_MEM_ADDRESS_SZ),
              Bits#(SCRATCHPAD_MEM_ADDRESS, t_SCRATCHPAD_MEM_ADDRESS_SZ),

              // Index in a reorder buffer
              Alias#(SCOREBOARD_FIFO_ENTRY_ID#(SCRATCHPAD_PORT_ROB_SLOTS), t_REORDER_ID),
              
              // Request merge table
              NumAlias#(TMin#(t_MEM_ADDRESS_SZ, TLog#(SCRATCHPAD_MERGE_TABLE_ENTRIES#(n_READERS))), t_MERGE_IDX_SZ),
              Alias#(Bit#(t_MERGE_IDX_SZ), t_MERGE_IDX),
              Alias#(Bit#(TSub#(t_MEM_ADDRESS_SZ, t_MERGE_IDX_SZ)), t_MERGE_TAG),
              NumAlias#(TMax#(1, TExp#(TAdd#(TLog#(n_READERS), TLog#(SCRATCHPAD_PORT_ROB_SLOTS)))), n_MERGE_META_ENTRIES),
              Alias#(SCRATCHPAD_MERGE_TABLE_ENTRY#(t_MERGE_TAG, n_MERGE_META_ENTRIES), t_MERGE_ENTRY), 

              // MAF for in-flight reads
              Alias#(Tuple2#(Bit#(TLog#(n_READERS)), t_REORDER_ID), t_MAF_IDX),
              Bits#(t_MAF_IDX, t_MAF_IDX_SZ));
              

    DEBUG_FILE debugLog;
    DEBUG_FILE debugLogForPrefetcher;

    if(conf.debugLogPath matches tagged Valid .debugLogPath)
    begin 
        debugLog              <- mkDebugFile(debugLogPath);
        debugLogForPrefetcher <- mkDebugFile("prefetcher_" + debugLogPath);
    end
    else if(`PLATFORM_SCRATCHPAD_DEBUG_ENABLE == 1)
    begin
        String debugLogFilename = "platform_scratchpad_" + integerToString(scratchpadIntPortId(scratchpadID)) + ".out";
        debugLog <- mkDebugFile(debugLogFilename);   

        String debugLogPrefetcherFilename = "platform_scratchpad_" + integerToString(scratchpadIntPortId(scratchpadID)) + "_prefetcher.out";
        debugLogForPrefetcher <- mkDebugFile(debugLogPrefetcherFilename);   
    end
    else
    begin
        debugLog <- mkDebugFileNull(""); 
        debugLogForPrefetcher <- mkDebugFileNull("");
    end

    // Dynamic parameters
    PARAMETER_NODE paramNode         <- mkDynamicParameterNode();
    Param#(3) cacheMode              <- mkDynamicParameter(fromInteger(cacheModeParam), paramNode);
    Param#(6) prefetchMechanism      <- mkDynamicParameter(fromInteger(prefetchMechanismParam), paramNode);
    Param#(4) prefetchLearnerSizeLog <- mkDynamicParameter(fromInteger(prefetchLearnerSizeLogParam), paramNode);

    // Connection between private cache and the scratchpad virtual device
    let sourceData <- mkScratchpadCacheSourceData(scratchpadID, conf, debugLog);
                             
    // Cache Prefetcher
    let prefetcher <- (`SCRATCHPAD_STD_PVT_CACHE_PREFETCH_ENABLE == 1) ?
                          mkCachePrefetcher(nPrefetchLearners, False, True, debugLogForPrefetcher):
                          mkNullCachePrefetcher();
    
    // Private cache
    RL_DM_CACHE#(Bit#(t_MEM_ADDRESS_SZ),
                       SCRATCHPAD_MEM_VALUE,
                       t_MAF_IDX) cache <- mkCacheDirectMapped(sourceData,
                                                               prefetcher, 
                                                               nCacheEntries,
                                                               True,
                                                               debugLog);

    // Hook up stats
    let cacheStats <- statsConstructor(cache.stats);
    let prefetchStats <- prefetchStatsConstructor(prefetcher.stats);

    // Merge FIFOF combines read and write requests in temporal order,
    // with reads from the same cycle as a write going first.  Each read port
    // gets a slot.  The write port is always last.
    MERGE_FIFOF#(TAdd#(n_READERS, 1),
                 Tuple2#(t_MEM_ADDRESS, SCOREBOARD_FIFO_ENTRY_ID#(SCRATCHPAD_PORT_ROB_SLOTS))) incomingReqQ <- mkMergeFIFOF();

    // Write data is sent in a side port to keep the incomingReqQ smaller.
    FIFO#(SCRATCHPAD_MEM_VALUE) writeDataQ <- mkFIFO();

    // Cache responses are not ordered.  Sort them with a reorder buffer.
    Vector#(n_READERS, SCOREBOARD_FIFOF#(SCRATCHPAD_PORT_ROB_SLOTS, SCRATCHPAD_MEM_VALUE)) sortResponseQ <- replicateM(mkScoreboardFIFOF());
    
    // Initialization
    Reg#(Bool) initialized <- mkReg(False);
    rule doInit (! initialized);
        cache.setCacheMode(unpack(cacheMode[1:0]), unpack(cacheMode[2]));
        prefetcher.setPrefetchMode(unpack(prefetchMechanism),unpack(prefetchLearnerSizeLog));
        initialized <= True;
    endrule

    //
    // Request merging
    //
    // Merge multiple read requests accessing the same scratchpad address.
    // Only issue the fist read request to the memory, and let subsequent 
    // read requests wait in the request merging table (reqMergeTable).
    //
    LUTRAM#(t_MERGE_IDX, t_MERGE_ENTRY) reqMergeTable = ?;
    LUTRAM#(Bit#(t_MAF_IDX_SZ), Maybe#(t_MERGE_IDX)) reqMergeHeadInfo = ?;
    Reg#(Vector#(SCRATCHPAD_PORT_ROB_SLOTS, Bool)) reqMergeTableValidBits = ?;
    Reg#(Vector#(SCRATCHPAD_PORT_ROB_SLOTS, Bool)) reqMergeTableEndBits = ?;
    Reg#(Tuple2#(t_MERGE_IDX, SCRATCHPAD_MEM_VALUE)) multiRespFwdEntry = ?;
    PulseWire mergeTableLockedW = ?;
    Reg#(Bool) multiRespFwd <- mkReg(False);

    // allocate merge table
    if (conf.requestMerging)
    begin
        reqMergeTable <- mkLUTRAMU();
        reqMergeHeadInfo <- mkLUTRAM(tagged Invalid);
        reqMergeTableValidBits <- mkReg(replicate(False));
        reqMergeTableEndBits <- mkReg(replicate(True));
        multiRespFwdEntry <- mkRegU();
        mergeTableLockedW <- mkPulseWire();
    end

    function Tuple2#(t_MERGE_TAG, t_MERGE_IDX) mergeEntryFromAddr(t_MEM_ADDRESS addr);
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
                    let new_end_bits = reqMergeTableEndBits;
                    new_end_bits[idx] = !isInit;
                    reqMergeTableEndBits <= new_end_bits;
                endaction;
        end
        else
        begin
            return noAction;
        end
    endfunction

    //
    // Forward merged requests to the cache.
    //

    // Write requests
    rule forwardWriteReq (initialized && !multiRespFwd && (incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS))));
        let addr = tpl_1(incomingReqQ.first());
        incomingReqQ.deq();

        let val = writeDataQ.first();
        writeDataQ.deq();

        cache.write(pack(addr), val);
        
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


    // Read requests
    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        rule forwardReadReq (initialized && (incomingReqQ.firstPortID() == fromInteger(p)));
            match {.addr, .idx} = incomingReqQ.first();
            incomingReqQ.deq();

            // The read UID for this request is the concatenation of the
            // port ID and the ROB index.
            t_MAF_IDX maf_idx = tuple2(fromInteger(p), idx);

            Bool issue_req = True;
            
            if (conf.requestMerging)
            begin
                let port = incomingReqQ.firstPortID();
                debugLog.record($format("forwardReadReq: port %0d: addr=0x%x, rob_idx=%0d, maf_idx=0x%x",
                                port, addr, idx, pack(maf_idx)));
                if (!mergeTableLockedW)
                begin
                    match {.m_tag, .m_idx} = mergeEntryFromAddr(addr);
                    Bit#(TLog#(n_READERS)) p = truncateNP(port);
                    if (reqMergeTableValidBits[m_idx] == True)
                    begin
                        let e = reqMergeTable.sub(m_idx);
                        if (e.tag == m_tag && !reqMergeTableEndBits[m_idx]) // hit
                        begin
                            issue_req = False;
                            let new_entry = e;
                            new_entry.mergeMeta[pack(tuple2(p,idx))] = True;
                            reqMergeTable.upd(m_idx, new_entry); 
                            debugLog.record($format("forwardReadReq: port %0d: update reqMergeTable, idx=0x%x, tag=0x%x, mergeMeta=0x%x",
                                            port, m_idx, m_tag, pack(new_entry.mergeMeta)));
                        end
                    end
                    else // initialize merge table
                    begin
                        reqMergeTable.upd(m_idx, SCRATCHPAD_MERGE_TABLE_ENTRY { tag: m_tag,
                                                                                mergeMeta: replicate(False) });
                        reqMergeHeadInfo.upd(pack(maf_idx), tagged Valid m_idx);
                        initOrResetMergeEntry(m_idx, True);
                        debugLog.record($format("forwardReadReq: port %0d: initialize reqMergeTable, idx=0x%x, tag=0x%x", 
                                        port, m_idx, m_tag));
                        debugLog.record($format("forwardReadReq: port %0d: set reqMergeHeadInfo, idx=0x%x", port, pack(maf_idx)));
                    end
                end
            end

            if (issue_req)
            begin
                // Request data from the cache
                cache.readReq(pack(addr), maf_idx, defaultValue());
            end

        endrule

        //
        // receiveResp --
        //     Push read responses to the reorder buffer.  They will be returned
        //     through readRsp() in order.
        //
        (* descending_urgency = "receiveResp, forwardWriteReq" *)
        rule receiveResp (tpl_1(cache.peekResp().readMeta) == fromInteger(p) && !multiRespFwd);
            let r <- cache.readResp();

            // The readUID field holds the concatenation of the port ID and
            // the port's reorder buffer index.
            match {.port, .maf_idx} = r.readMeta;

            sortResponseQ[p].setValue(maf_idx, r.val);
        
            if (conf.requestMerging)
            begin
                debugLog.record($format("receiveResp: port %0d: resp val=0x%x, rob idx=%0d", p, r.val, maf_idx));
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
        rule fwdMultiResp (multiRespFwd);
            mergeTableLockedW.send();
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

    //
    // Methods.  All requests are stored in the incomingReqQ to maintain their
    // order.
    //

    Vector#(n_READERS, MEMORY_READER_IFC#(t_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE)) portsLocal = newVector();

    for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_MEM_ADDRESS addr);
                    // Allocate a slot in the reorder buffer for the read request.  Each
                    // read port gets its own reorder buffer.
                    let idx <- sortResponseQ[p].enq();
                    incomingReqQ.ports[p].enq(tuple2(addr, idx));

                    debugLog.record($format("read port %0d: req addr=0x%x, rob idx=%0d", p, addr, idx));
                endmethod

                method ActionValue#(SCRATCHPAD_MEM_VALUE) readRsp();
                    let r = sortResponseQ[p].first();
                    sortResponseQ[p].deq();

                    debugLog.record($format("read port %0d: resp val=0x%x, rob_idx=%0d", p, r, sortResponseQ[p].deqEntryId()));
                    return r;
                endmethod

                method SCRATCHPAD_MEM_VALUE peek();
                    return sortResponseQ[p].first();
                endmethod

                method Bool notEmpty() = sortResponseQ[p].notEmpty();
                method Bool notFull() = incomingReqQ.ports[p].notFull() &&
                                        sortResponseQ[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_MEM_ADDRESS addr, SCRATCHPAD_MEM_VALUE val);
        // The write port is last in the merge FIFO
        incomingReqQ.ports[valueOf(n_READERS)].enq(tuple2(addr, ?));
        writeDataQ.enq(val);
        debugLog.record($format("write addr=0x%x, val=0x%x", addr, val));
    endmethod

    method Bool writeNotFull = incomingReqQ.ports[valueOf(n_READERS)].notFull();
endmodule


//
// mkScratchpadCacheSourceData --
//     Connection between a private cache for a scratchpad and the platform's
//     scratchpad virtual device.  Requests arrive here when the cache either
//     misses or needs to flush dirty data.  Requests will be forwarded to
//     the main scratchpad controller.
//
module [CONNECTED_MODULE] mkScratchpadCacheSourceData#(Integer scratchpadID,
                                                       SCRATCHPAD_CONFIG conf,
                                                       DEBUG_FILE debugLog)
    // interface:
    (RL_DM_CACHE_SOURCE_DATA#(t_CACHE_ADDR, SCRATCHPAD_MEM_VALUE, t_MAF_IDX))
    provisos (Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Bits#(t_MAF_IDX, t_MAF_IDX_SZ),
              Bits#(SCRATCHPAD_MEM_ADDRESS, t_SCRATCHPAD_MEM_ADDRESS_SZ),
              Alias#(RL_DM_CACHE_FILL_RESP#(t_CACHE_ADDR, SCRATCHPAD_MEM_VALUE, t_MAF_IDX), t_CACHE_FILL_RESP));

    if (valueOf(t_CACHE_ADDR_SZ) > valueOf(t_SCRATCHPAD_MEM_ADDRESS_SZ))
    begin
        error("Scratchpad ID " + integerToString(scratchpadIntPortId(scratchpadID)) + " address is too large: " + integerToString(valueOf(t_CACHE_ADDR_SZ)) + " bits");
    end

    if (valueOf(t_MAF_IDX_SZ) > valueOf(SCRATCHPAD_CLIENT_READ_UID_SZ))
    begin
        error("Scratchpad ID " + integerToString(scratchpadIntPortId(scratchpadID)) + " read UID is too large: " + integerToString(valueOf(t_MAF_IDX_SZ)) + " bits");
    end

    let my_port = scratchpadPortId(scratchpadID);
    let platformID <- getSynthesisBoundaryPlatformID();

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_MEM_REQ) link_mem_req <-
        mkConnectionTokenRingNode("Scratchpad_Platform_" + integerToString(platformID) + "_Req", my_port);

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_READ_RSP) link_mem_rsp <-
        mkConnectionTokenRingNode("Scratchpad_Platform_" + integerToString(platformID) + "_Resp", my_port);

    messageM("Scratchpad Ring Name: "+ "Scratchpad_Platform_" + integerToString(platformID) + "_Req, Port: " + integerToString(scratchpadIntPortId(scratchpadID)));
    messageM("Scratchpad Ring Name: "+ "Scratchpad_Platform_" + integerToString(platformID) + "_Resp, Port: " + integerToString(scratchpadIntPortId(scratchpadID)));

    Reg#(Bool) initialized <- mkReg(False);

    //
    // Allocate memory for this scratchpad region
    //
    rule doInit (! initialized);
        initialized <= True;

        Bit#(t_CACHE_ADDR_SZ) alloc = maxBound;
        SCRATCHPAD_INIT_REQ r;
        r.port = my_port;
        r.allocLastWordIdx = zeroExtendNP(alloc);
        r.cached = True;
        r.initFilePath = conf.initFilePath;
        link_mem_req.enq(0, tagged SCRATCHPAD_MEM_INIT r);

        debugLog.record($format("sourceData: init ID %0d: last word idx 0x%x", my_port, r.allocLastWordIdx));
    endrule

    //
    // readReq --
    //     Read miss from the private cache.  Request a fill from the scratchpad
    //     controller's backing storage.
    //
    method Action readReq(t_CACHE_ADDR addr,
                          t_MAF_IDX readUID,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta) if (initialized);
        //
        // Construct a generic scratchpad device request by padding the
        // requesting scratchpad's UID (port number) to the request.
        //
        let req = SCRATCHPAD_READ_REQ { port: my_port,
                                        addr: zeroExtendNP(pack(addr)),
                                        byteReadMask: replicate(True),
                                        readUID: zeroExtendNP(pack(readUID)),
                                        globalReadMeta: globalReadMeta };

        // Forward the request to the scratchpad virtual device that handles
        // all scratchpad backing storage I/O.
        link_mem_req.enq(0, tagged SCRATCHPAD_MEM_READ req);

        debugLog.record($format("sourceData: read REQ ID %0d: addr 0x%x", my_port, req.addr));
    endmethod

    //
    // readResp --
    //     Fill response from scratchpad controller backing storage.
    //
    method ActionValue#(t_CACHE_FILL_RESP) readResp();
        let s = link_mem_rsp.first();
        link_mem_rsp.deq();

        t_CACHE_FILL_RESP r;
        r.addr = unpack(truncateNP(s.addr));
        r.val = s.val;
        r.isCacheable = s.isCacheable;
        // Restore local read metadata.  The generic response is large enough for    
        // any client's metadata and extra bits can simply be truncated.
        r.readMeta = unpack(truncateNP(s.readUID));
        r.globalReadMeta = s.globalReadMeta;

        debugLog.record($format("sourceData: read RESP: addr=0x%x, val=0x%x", s.addr, s.val));

        return r;
    endmethod

    method t_CACHE_FILL_RESP peekResp();
        let s = link_mem_rsp.first();

        t_CACHE_FILL_RESP r;
        r.addr = unpack(truncateNP(s.addr));
        r.val = s.val;
        r.isCacheable = s.isCacheable;
        r.readMeta = unpack(truncateNP(s.readUID));
        r.globalReadMeta = s.globalReadMeta;

        return r;
    endmethod

    // Asynchronous write (no response)
    method Action write(t_CACHE_ADDR addr,
                        SCRATCHPAD_MEM_VALUE val) if (initialized);
        let req = SCRATCHPAD_WRITE_REQ { port: my_port,
                                         addr: zeroExtendNP(pack(addr)),
                                         val: val };
        link_mem_req.enq(0, tagged SCRATCHPAD_MEM_WRITE req);

        debugLog.record($format("sourceData: write ID %0d: addr=0x%x, val=0x%x", my_port, addr, val));
    endmethod

    //
    // Invalidate / flush not required for scratchpad memory.
    //
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
        noAction;
    endmethod

    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
        noAction;
    endmethod

    method Action invalOrFlushWait();
        noAction;
    endmethod
endmodule



//
// mkUncachedScratchpad --
//     The uncached scratchpad is connected directly to the scratchpad memory
//     and uses neither a private nor the central cache.  To avoid read-modify-
//     write operations on data smaller than a SCRATCHPAD_MEM_VALUE, data
//     is tiled in containers that are one byte or larger and a size that is
//     a power of 2.  A byte write mask is passed to the memory along with
//     write data, thus eliminating the need to read partial values.
//
module [CONNECTED_MODULE] mkUncachedScratchpad#(Integer scratchpadID,
                                                SCRATCHPAD_CONFIG conf)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_IN_ADDR, t_DATA))
    provisos (Bits#(t_IN_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),

              Alias#(Bit#(t_ADDR_SZ), t_ADDR),    

              // Compute the natural size in bits.  The natural size must be
              // a power of 2 bits that is one byte or larger.
              Max#(8, TExp#(TLog#(t_DATA_SZ)), t_NATURAL_SZ),
              NumAlias#(TDiv#(t_NATURAL_SZ, 8), t_NATURAL_BYTES),

              // Compute scratchpad container index type (size)
              Bits#(SCRATCHPAD_MEM_ADDRESS, t_SCRATCHPAD_MEM_ADDRESS_SZ),
              Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ),

              // Index a naturally sized t_DATA within a SCRATCHPAD_MEM_VALUE
              Alias#(Bit#(TLog#(TDiv#(t_SCRATCHPAD_MEM_VALUE_SZ, t_NATURAL_SZ))),
                     t_NATURAL_IDX),

              // Compute a non-zero size for the read port index
              Alias#(Bit#(TMax#(1, TLog#(n_READERS))), t_PORT_IDX),

              // Index in a reorder buffer
              Alias#(SCOREBOARD_FIFO_ENTRY_ID#(SCRATCHPAD_UNCACHED_PORT_ROB_SLOTS), t_REORDER_ID),

              // MAF for in-flight reads
              Alias#(Tuple2#(Bit#(TLog#(n_READERS)), t_REORDER_ID), t_MAF_IDX),
              Bits#(t_MAF_IDX, t_MAF_IDX_SZ),
              Alias#(t_NATURAL_IDX, t_MAF_DATA));

    DEBUG_FILE debugLog;
    if(conf.debugLogPath matches tagged Valid .debugLogPath)
    begin 
        debugLog <- mkDebugFile(debugLogPath);
    end
    else if(`PLATFORM_SCRATCHPAD_DEBUG_ENABLE == 1)
    begin
        String debugLogFilename = "platform_scratchpad_" + integerToString(scratchpadIntPortId(scratchpadID)) + ".out";
        debugLog <- mkDebugFile(debugLogFilename);   
    end
    else
    begin
        debugLog <- mkDebugFileNull(""); 
    end


    //
    // Elaboration time checks
    //
    if (valueOf(t_NATURAL_SZ) > valueOf(t_SCRATCHPAD_MEM_VALUE_SZ))
    begin
        //
        // Object size is larger than SCRATCHPAD_MEM_VALUE.  The code here could
        // support this case by issuing multiple reads and writes for every
        // reference.  For now it does not.
        //
        error("Uncached scratchpad doesn't support data larger than scratchpad's base size");
    end

    if (valueOf(TDiv#(t_ADDR_SZ, TDiv#(t_SCRATCHPAD_MEM_VALUE_SZ, t_NATURAL_SZ))) >
        valueOf(t_SCRATCHPAD_MEM_ADDRESS_SZ))
    begin
        //
        // Requested address space is larger than the maximum scratchpad size.
        //
        error("Address space too large.");
    end

    // MAF must fit in the readUID field
    if (valueOf(t_MAF_IDX_SZ) > valueOf(SCRATCHPAD_CLIENT_READ_UID_SZ))
    begin
        error("MAF index size (" + integerToString(valueOf(t_MAF_IDX_SZ)) +
              ") doesn't fit in scratchpad's read UID");
    end


    let my_port = scratchpadPortId(scratchpadID);

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_MEM_REQ) link_mem_req <-
        mkConnectionTokenRingNode("Scratchpad_" + `SCRATCHPAD_PLATFORM + "_Req", my_port);

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_READ_RSP) link_mem_rsp <-
        mkConnectionTokenRingNode("Scratchpad_" + `SCRATCHPAD_PLATFORM + "_Resp", my_port);


    // Scratchpad responses are not ordered.  Sort them with a reorder buffer.
    // Each read port gets its own reorder buffer so that each port returns data
    // when available, independent of the latency of requests on other ports.
    Vector#(n_READERS,
            SCOREBOARD_FIFOF#(SCRATCHPAD_UNCACHED_PORT_ROB_SLOTS,
                              t_DATA)) sortResponseQ <- replicateM(mkBRAMScoreboardFIFOF());

    // MAF to hold properties of outstanding reads
    LUTRAM#(t_MAF_IDX, t_MAF_DATA) maf <- mkLUTRAMU();

    // Buffer between reorder buffer (sortResponseQ) and output methods to
    // reduce timing pressure.
    Vector#(n_READERS, FIFOF#(t_DATA)) responseQ <- replicateM(mkFIFOF());

    // Merge FIFOF combines read and write requests in temporal order,
    // with reads from the same cycle as a write going first.  Each read port
    // gets a slot.  The write port is always last.
    MERGE_FIFOF#(TAdd#(n_READERS, 1),
                 Tuple2#(Bit#(t_ADDR_SZ),
                         SCOREBOARD_FIFO_ENTRY_ID#(SCRATCHPAD_UNCACHED_PORT_ROB_SLOTS))) incomingReqQ <- mkMergeBypassFIFOF();

    // Write data is sent in a side port to keep the incomingReqQ smaller.
    FIFO#(t_DATA) writeDataQ <- mkBypassFIFO();

    // Most recent writes are collected in a buffer in order to group
    // streaming writes sharing a container into a single transaction.
    Reg#(Maybe#(SCRATCHPAD_MEM_ADDRESS)) lastWriteAddr <- mkReg(tagged Invalid);
    Reg#(SCRATCHPAD_MEM_VALUE) lastWriteVal <- mkRegU();
    Reg#(SCRATCHPAD_MEM_MASK) lastWriteMask <- mkRegU();

    // The most recent read address is recorded.  Multiple read requests
    // to the same address are collapsed into a single request from the backing
    // storage.
    Reg#(Maybe#(SCRATCHPAD_MEM_ADDRESS)) lastReadAddr <- mkReg(tagged Invalid);
    Reg#(SCRATCHPAD_MEM_VALUE) lastReadVal <- mkRegU();

    // Record the source of the next read response (either backing storage
    // or a repeat of the last read's location.
    FIFO#(Tuple4#(Bool,
                  t_PORT_IDX,
                  t_NATURAL_IDX,
                  t_REORDER_ID))
        readRspSourceQ <- mkSizedFIFO(valueOf(SCRATCHPAD_UNCACHED_PORT_ROB_SLOTS));


    //
    // scratchpadAddr --
    //     Compute scratchpad address given an object address.  Multiple objects
    //     may be stored in a single scratchpad entry.
    //
    function SCRATCHPAD_MEM_ADDRESS scratchpadAddr(t_ADDR addr);
        return zeroExtendNP(unpack(addr) /
                            fromInteger(valueOf(TDiv#(t_SCRATCHPAD_MEM_VALUE_SZ,
                                                      t_NATURAL_SZ))));
    endfunction

    //
    // scratchpadAddrIdx --
    //     Compute the index of a naturally sized object within a scratchpad's
    //     base container size.  This is the remainder of the scratchpadAddr
    //     computation above when multiple objects are stored in each
    //     scratchpad container.
    //
    function t_NATURAL_IDX scratchpadAddrIdx(t_ADDR addr);
        return truncateNP(unpack(addr) % fromInteger(valueOf(TDiv#(t_SCRATCHPAD_MEM_VALUE_SZ,
                                                                   t_NATURAL_SZ))));
    endfunction


    //
    // scratchpadByteMask --
    //     Compute the byte mask of an object within a scratchpad word.
    //
    function SCRATCHPAD_MEM_MASK scratchpadByteMask(t_ADDR addr);
        t_NATURAL_IDX addr_idx = scratchpadAddrIdx(addr);

        // Build a mask of valid bytes
        Vector#(TDiv#(t_SCRATCHPAD_MEM_VALUE_SZ,
                      t_NATURAL_SZ),
                Bit#(TDiv#(t_NATURAL_SZ, 8))) b_mask = replicate(0);
        b_mask[addr_idx] = -1;

        // Size should match.  Resize avoids a proviso.
        return unpack(resize(pack(b_mask)));
    endfunction


    //
    // Allocate memory for this scratchpad region
    //
    Reg#(Bool) initialized <- mkReg(False);
    
    rule doInit (! initialized);
        initialized <= True;

        Bit#(t_ADDR_SZ) alloc = maxBound;
        SCRATCHPAD_INIT_REQ r;
        r.port = my_port;
        r.allocLastWordIdx = scratchpadAddr(alloc);
        r.cached = False;
        r.initFilePath = conf.initFilePath;
        link_mem_req.enq(0, tagged SCRATCHPAD_MEM_INIT r);
    endrule


    //
    // Forward merged requests to the memory.
    //

    // Read requests
    rule forwardReadReq (initialized && (incomingReqQ.firstPortID() < fromInteger(valueOf(n_READERS))));
        let port = incomingReqQ.firstPortID();
        match {.addr, .rob_idx} = incomingReqQ.first();

        let s_addr = scratchpadAddr(addr);

        if (lastWriteAddr matches tagged Valid .lw_addr &&&
            s_addr == lw_addr)
        begin
            //
            // Conflict with last write.  Flush the last write first.  The
            // read will be retried next cycle.
            //
            let req = SCRATCHPAD_WRITE_MASKED_REQ { port: my_port,
                                                    addr: lw_addr,
                                                    val: lastWriteVal,
                                                    byteWriteMask: lastWriteMask };
            link_mem_req.enq(0, tagged SCRATCHPAD_MEM_WRITE_MASKED req);

            lastWriteAddr <= tagged Invalid;

            debugLog.record($format("port %0d: flush write for read conflict s_addr=0x%x", port, s_addr));
        end
        else
        begin
            //
            // Do the read...
            //
            incomingReqQ.deq();

            t_NATURAL_IDX addr_idx = scratchpadAddrIdx(addr);

            // Update the MAF with details of the read
            t_MAF_IDX maf_idx = tuple2(truncateNP(port), rob_idx);
            maf.upd(maf_idx, addr_idx);

            if (lastReadAddr matches tagged Valid .lr_addr &&&
                s_addr == lr_addr)
            begin
                // Reading the same address as the last request.  Reuse the response.
                readRspSourceQ.enq(tuple4(True, truncateNP(port), addr_idx, rob_idx));

                debugLog.record($format("read port %0d: reuse addr=0x%x, s_addr=0x%x, s_idx=%0d", port, addr, s_addr, addr_idx));
            end
            else
            begin
                let req = SCRATCHPAD_READ_REQ { port: my_port,
                                                addr: s_addr,
                                                byteReadMask: scratchpadByteMask(addr),
                                                readUID: zeroExtendNP(pack(maf_idx)),
                                                globalReadMeta: defaultValue() };

                link_mem_req.enq(0, tagged SCRATCHPAD_MEM_READ req);

                // Record the source of the read value (scratchpad)
                lastReadAddr <= tagged Valid s_addr;
                readRspSourceQ.enq(tuple4(False, ?, ?, ?));

                debugLog.record($format("read port %0d: req addr=0x%x, s_addr=0x%x, s_idx=%0d", port, addr, s_addr, addr_idx));
            end
        end
    endrule


    // Write requests
    rule forwardWriteReq (initialized && (incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS))));
        let addr = tpl_1(incomingReqQ.first());
        incomingReqQ.deq();
        
        let w_data = writeDataQ.first();
        writeDataQ.deq();

        // Put the data at the right place in the scratchpad word
        Vector#(TDiv#(t_SCRATCHPAD_MEM_VALUE_SZ, t_NATURAL_SZ), Bit#(t_NATURAL_SZ)) d = unpack(0);
        d[scratchpadAddrIdx(addr)] = zeroExtendNP(pack(w_data));

        let s_addr = scratchpadAddr(addr);
        let b_mask = scratchpadByteMask(addr);

        if (lastWriteAddr matches tagged Valid .lw_addr &&&
            s_addr == lw_addr)
        begin
            // Write to same address as previous write.  Merge writes.
            // Resizing is to avoid tautological provisos.  Sizes are actually
            // identical.
            lastWriteVal <= lastWriteVal | resize(pack(d));
            lastWriteMask <= unpack(pack(lastWriteMask) | pack(b_mask));
        end
        else
        begin
            // Write to a new address.  Flush the previous write buffer.
            if (lastWriteAddr matches tagged Valid .lw_addr)
            begin
                let req = SCRATCHPAD_WRITE_MASKED_REQ { port: my_port,
                                                        addr: lw_addr,
                                                        val: lastWriteVal,
                                                        byteWriteMask: lastWriteMask };
                link_mem_req.enq(0, tagged SCRATCHPAD_MEM_WRITE_MASKED req);
            end

            // Record the latest write in the buffer.
            lastWriteAddr <= tagged Valid s_addr;
            lastWriteVal <= resize(pack(d));
            lastWriteMask <= b_mask;

            // Need to invalidate the read history due to conflicting address?
        end

        if (validValue(lastReadAddr) == s_addr)
        begin
            lastReadAddr <= tagged Invalid;
        end

        debugLog.record($format("write addr=0x%x, val=0x%x, s_addr=0x%x, s_val=0x%x, s_bmask=%b", addr, w_data, scratchpadAddr(addr), pack(d), pack(b_mask)));
    endrule


    //
    // receiveResp --
    //     Push unordered read responses to the reorder buffers.  Responses will
    //     be returned through readRsp() in order.
    //
    rule receiveResp (! tpl_1(readRspSourceQ.first()));
        readRspSourceQ.deq();

        let s = link_mem_rsp.first();
        link_mem_rsp.deq();

        // The read UID field holds the concatenation of the port ID and
        // the port's reorder buffer index.
        t_MAF_IDX maf_idx = unpack(truncateNP(s.readUID));
        match {.port, .rob_idx} = maf_idx;
        let addr_idx = maf.sub(maf_idx);

        Vector#(TDiv#(t_SCRATCHPAD_MEM_VALUE_SZ, t_NATURAL_SZ), Bit#(t_NATURAL_SZ)) d;
        // The resize here is required only to avoid a proviso asserting the
        // tautology that Mul#() is equivalent to TMul#().
        d = unpack(resize(s.val));

        t_DATA v = unpack(truncateNP(d[addr_idx]));
        sortResponseQ[port].setValue(rob_idx, v);

        // Record the value in case it is used by reuseResp
        lastReadVal <= s.val;

        debugLog.record($format("read port %0d: resp val=0x%x, s_idx=%0d", port, v, addr_idx));
    endrule


    //
    // reuseResp --
    //     Re-use the same word as the response for the next read request.    
    //
    rule reuseResp (tpl_1(readRspSourceQ.first()));
        match {.reuse, .port, .addr_idx, .rob_idx} = readRspSourceQ.first();
        readRspSourceQ.deq();

        Vector#(TDiv#(t_SCRATCHPAD_MEM_VALUE_SZ, t_NATURAL_SZ), Bit#(t_NATURAL_SZ)) d;
        // The resize here is required only to avoid a proviso asserting the
        // tautology that Mul#() is equivalent to TMul#().
        d = unpack(resize(lastReadVal));

        t_DATA v = unpack(truncateNP(d[addr_idx]));
        sortResponseQ[port].setValue(rob_idx, v);

        debugLog.record($format("read port %0d: reuse val=0x%x, s_idx=%0d", port, v, addr_idx));
    endrule


    //
    // forwardResp --
    //     Forward the next response to the output FIFO.  This stage exists
    //     solely to reduce FPGA timing pressure.
    //
    for (Integer r = 0; r < valueOf(n_READERS); r = r + 1)
    begin
        rule forwardResp (True);
            let d = sortResponseQ[r].first();
            sortResponseQ[r].deq();
            
            responseQ[r].enq(d);
        endrule
    end


    //
    // Methods.  All requests are stored in the incomingReqQ to maintain their
    // order.
    //

    Vector#(n_READERS, MEMORY_READER_IFC#(t_IN_ADDR, t_DATA)) portsLocal = newVector();

    for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_IN_ADDR, t_DATA);
                method Action readReq(t_IN_ADDR addr);
                    // Allocate a slot in the reorder buffer for the read request.  Each
                    // read port gets its own reorder buffer.
                    let rob_idx <- sortResponseQ[p].enq();
                    incomingReqQ.ports[p].enq(tuple2(pack(addr), rob_idx));
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let r = responseQ[p].first();
                    responseQ[p].deq();

                    return r;
                endmethod

                method t_DATA peek();
                    return responseQ[p].first();
                endmethod

                method Bool notEmpty() = responseQ[p].notEmpty();
                method Bool notFull() = incomingReqQ.ports[p].notFull() &&
                                        sortResponseQ[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_IN_ADDR addr, t_DATA val);
        // The write port is last in the merge FIFO
        incomingReqQ.ports[valueOf(n_READERS)].enq(tuple2(pack(addr), ?));
        writeDataQ.enq(val);
    endmethod

    method Bool writeNotFull = incomingReqQ.ports[valueOf(n_READERS)].notFull();
endmodule
