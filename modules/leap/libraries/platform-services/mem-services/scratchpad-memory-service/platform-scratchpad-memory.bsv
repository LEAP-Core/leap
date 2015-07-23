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
import ConfigReg::* ;


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
// For longer latency backing stores, we will use more slots. 
typedef 32 SCRATCHPAD_PORT_ROB_SLOTS_SHORT_LATENCY;
typedef 64 SCRATCHPAD_PORT_ROB_SLOTS_LONG_LATENCY;

// Provide a backwards compatible definition of ROB slots.
typedef SCRATCHPAD_PORT_ROB_SLOTS_LONG_LATENCY SCRATCHPAD_PORT_ROB_SLOTS;


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

    if (conf.enableStatistics matches tagged Valid .prefix)
    begin
        statsConstructor = mkBasicScratchpadCacheStats(prefix, "");
        if (`SCRATCHPAD_STD_PVT_CACHE_PREFETCH_ENABLE == 1)
        begin
            prefetchStatsConstructor = mkBasicScratchpadPrefetchStats(prefix, "", n_prefetch_learners);
        end
    end
    else if (`PLATFORM_SCRATCHPAD_STATS_ENABLE != 0)
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
module [CONNECTED_MODULE] mkMultiReadStatsScratchpad#(Integer scratchpadID,
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

    MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) mem;
    Bool need_init_wrapper = False;


    NumTypeParam#(t_ADDR_SZ) userAddrWidth = ?; 
    
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

    Integer entries = (conf.cacheEntries == 0) ? `SCRATCHPAD_STD_PVT_CACHE_ENTRIES : conf.cacheEntries;

    if (conf.cacheMode == SCRATCHPAD_UNCACHED)
    begin
        // No caches at any level.  This access pattern uses masked writes to
        // avoid read-modify-write loops when accessing objects smaller than
        // a scratchpad base data size.
        mem <- mkUncachedScratchpad(scratchpadID, conf);
    end
    else if ((conf.cacheMode == SCRATCHPAD_CACHED) && (valueOf(TExp#(t_CONTAINER_ADDR_SZ)) <= entries))
    begin
        messageM("Scratchpad ID: " + integerToString(scratchpadID) + " bram entries: " + integerToString(entries) + "container address size: " + integerToString(valueOf(t_CONTAINER_ADDR_SZ)) + "user address size: " + integerToString(valueOf(t_ADDR_SZ)));
        
        // A special case:  cached scratchpad requested but the container
        // is smaller than the cache would have been.  Just allocate a BRAM.
        mem <- mkBRAMBufferedPseudoMultiReadInitialized(True, unpack(0));
        need_init_wrapper = True;
    end
    else
    begin
        // Container maps requested data size to the platform's scratchpad word size.
        NumTypeParam#(t_SCRATCHPAD_MEM_VALUE_SZ) data_sz = ?;
        NumTypeParam#(TMax#(1, TExp#(MEM_PACK_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_SCRATCHPAD_MEM_VALUE_SZ)))) n_obj = ?;

        if (conf.cacheMode == SCRATCHPAD_CACHED)
        begin
            NumTypeParam#(`SCRATCHPAD_STD_PVT_CACHE_PREFETCH_LEARNER_NUM) l = ?;
            Integer id = scratchpadID;
            SCRATCHPAD_STATS_CONSTRUCTOR stats = statsConstructor;
            SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR pf_stats = prefetchStatsConstructor;
            // check whether to enable masked write in the scratchpad's cache
            Bool mask_w = (valueOf(MEM_PACK_MASKED_WRITE_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_SCRATCHPAD_MEM_VALUE_SZ)) != 0); 

            // Require brute-force conversion because Integer cannot be converted to a type
            messageM("Scratchpad ID: " + integerToString(scratchpadID) + " private cache entries: " + integerToString(entries));

            if      (entries <= 8)      begin NumTypeParam#(8)       n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 16)     begin NumTypeParam#(16)      n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 32)     begin NumTypeParam#(32)      n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 64)     begin NumTypeParam#(64)      n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 128)    begin NumTypeParam#(128)     n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 256)    begin NumTypeParam#(256)     n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 512)    begin NumTypeParam#(512)     n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 1024)   begin NumTypeParam#(1024)    n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 2048)   begin NumTypeParam#(2048)    n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 4096)   begin NumTypeParam#(4096)    n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 8192)   begin NumTypeParam#(8192)    n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            
            // Below here, we size the scratchpads to take advantage of non-power-of-two
            // caches.  We could do this for the smaller caches, but the impact would be 
            // limited. Synplify can only do non-power of two caches if they are larger 
            // than 16K. Vivado unfortunately doesn't support this yet. 

            else if (entries <= 16384)  begin NumTypeParam#(16384)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 20480)  begin NumTypeParam#(20480)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 24576)  begin NumTypeParam#(24576)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 28672)  begin NumTypeParam#(28672)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 

            else if (entries <= 32768)  begin NumTypeParam#(32768)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 40960)  begin NumTypeParam#(40960)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 49152)  begin NumTypeParam#(49152)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 57344)  begin NumTypeParam#(57344)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 

            else if (entries <= 65536)  begin NumTypeParam#(65536)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 81920)  begin NumTypeParam#(81920)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 98304)  begin NumTypeParam#(98304)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 114688)  begin NumTypeParam#(114688)   n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 

            else if (entries <= 131072) begin NumTypeParam#(131072)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 163840) begin NumTypeParam#(163840)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 196608) begin NumTypeParam#(196608)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 229376) begin NumTypeParam#(229376)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 

            else if (entries <= 262144) begin NumTypeParam#(262144)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 327680) begin NumTypeParam#(327680)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 393216) begin NumTypeParam#(393216)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 458752) begin NumTypeParam#(458762)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 

            else if (entries <= 524288) begin NumTypeParam#(524288)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 655360) begin NumTypeParam#(655360)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 786432) begin NumTypeParam#(786432)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
            else if (entries <= 917504) begin NumTypeParam#(917504)  n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 

            else                  begin NumTypeParam#(1048576) n = ?; mem <- mkMemPackMultiReadMaskWrite(data_sz, mkUnmarshalledCachedScratchpad(id, conf, n_obj, n, l, userAddrWidth, stats, pf_stats, mask_w)); end 
        end
        else
        begin
            mem <- mkMemPackMultiRead(data_sz, mkUnmarshalledScratchpad(scratchpadID, n_obj, conf));
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
        let init_memory <- mkMultiMemInitializedWithGet(mem, init_stream);

        mem = init_memory;
    end

    return mem;
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
    
//
// mkUnmarshalledScratchpad --
//     Allocate a connection to the platform's scratchpad interface for
//     a single scratchpad region.  This module does no marshalling of
//     data sizes or caching.  BEWARE: the word size of the virtual
//     platform's scratchpad is platform dependent.
//
module [CONNECTED_MODULE] mkUnmarshalledScratchpad#(
    Integer scratchpadID,
    NumTypeParam#(n_OBJECTS) nContainerObjects,
    SCRATCHPAD_CONFIG conf)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE))
    provisos (Bits#(t_MEM_ADDRESS, t_MEM_ADDRESS_SZ),
              Bits#(SCRATCHPAD_MEM_ADDRESS, t_SCRATCHPAD_MEM_ADDRESS_SZ));

    MEMORY_MULTI_READ_IFC#(n_READERS, t_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE) _scr = ?;
    Integer robSlots = ?;

    if(conf.backingStore == RL_CACHE_STORE_FLAT_BRAM)
    begin
        NumTypeParam#(SCRATCHPAD_PORT_ROB_SLOTS_SHORT_LATENCY) nROBSlots = ?;
        _scr <- mkUnmarshalledScratchpadImpl(scratchpadID,
                                             nContainerObjects,
                                             nROBSlots,
                                             conf);

        robSlots = valueOf(SCRATCHPAD_PORT_ROB_SLOTS_SHORT_LATENCY);
    end
    else
    begin
        NumTypeParam#(SCRATCHPAD_PORT_ROB_SLOTS_LONG_LATENCY) nROBSlots = ?;
        _scr <- mkUnmarshalledScratchpadImpl(scratchpadID,
                                             nContainerObjects,
                                             nROBSlots,
                                             conf);

        robSlots = valueOf(SCRATCHPAD_PORT_ROB_SLOTS_LONG_LATENCY);
    end


    _scr <- mkMergedScratchpad(_scr, conf, robSlots, mkMemReadBypassWrapperMultiRead);

    return _scr;
endmodule

module [CONNECTED_MODULE] mkUnmarshalledScratchpadImpl#(
    Integer scratchpadID,
    NumTypeParam#(n_OBJECTS) nContainerObjects,
    NumTypeParam#(n_ROB_SLOTS) nROBSlots,
    SCRATCHPAD_CONFIG conf)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE))
    provisos (Bits#(t_MEM_ADDRESS, t_MEM_ADDRESS_SZ),
              Bits#(SCRATCHPAD_MEM_ADDRESS, t_SCRATCHPAD_MEM_ADDRESS_SZ),

              // Index in a reorder buffer
              Alias#(SCOREBOARD_FIFO_ENTRY_ID#(n_ROB_SLOTS), t_REORDER_ID),
              
              // MAF for in-flight reads
              Alias#(Tuple2#(Bit#(TLog#(n_READERS)), t_REORDER_ID), t_MAF_IDX),
              Bits#(t_MAF_IDX, t_MAF_IDX_SZ));
    
    if (valueOf(t_MEM_ADDRESS_SZ) > valueOf(t_SCRATCHPAD_MEM_ADDRESS_SZ))
    begin
        error("Scratchpad ID " + integerToString(scratchpadIntPortId(scratchpadID)) + " address is too large: " + integerToString(valueOf(t_MEM_ADDRESS_SZ)) + " bits");
    end

    DEBUG_FILE debugLog;
    if (conf.debugLogPath matches tagged Valid .debugLogPath)
    begin 
        debugLog <- mkDebugFile(debugLogPath);
    end
    else if (`PLATFORM_SCRATCHPAD_DEBUG_ENABLE == 1)
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
    Vector#(n_READERS, SCOREBOARD_FIFOF#(n_ROB_SLOTS, SCRATCHPAD_MEM_VALUE)) sortResponseQ <- replicateM(mkScoreboardFIFOF());

    // Merge FIFOF combines read and write requests in temporal order,
    // with reads from the same cycle as a write going first.  Each read port
    // gets a slot.  The write port is always last.
    MERGE_FIFOF#(TAdd#(n_READERS, 1),
                 Tuple2#(t_MEM_ADDRESS, SCOREBOARD_FIFO_ENTRY_ID#(n_ROB_SLOTS))) incomingReqQ <- mkMergeBypassFIFOF();

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
        debugLog.record($format("doInit: init ID %0d: last word idx 0x%x", my_port, r.allocLastWordIdx));
    endrule


    //
    // Forward merged requests to the memory.
    //
    // Read requests
    (* fire_when_enabled *)
    rule forwardReadReq (initialized && (incomingReqQ.firstPortID() < fromInteger(valueOf(n_READERS))));
        let port = incomingReqQ.firstPortID();
        match {.addr, .rob_idx} = incomingReqQ.first();
        incomingReqQ.deq();

        // The read UID for this request is the concatenation of the
        // port ID and the ROB index.
        Bit#(TLog#(n_READERS)) p = truncateNP(port);
        t_MAF_IDX maf_idx = tuple2(p, rob_idx);

        let req = SCRATCHPAD_READ_REQ { port: my_port,
                                        addr: zeroExtendNP(pack(addr)),
                                        byteReadMask: replicate(True),
                                        readUID: zeroExtendNP(pack(maf_idx)),
                                        globalReadMeta: defaultValue() };
        link_mem_req.enq(0, tagged SCRATCHPAD_MEM_READ req);
    endrule

    // Write requests
    (* fire_when_enabled *)
    rule forwardWriteReq (initialized && (incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS))));
        let addr = tpl_1(incomingReqQ.first());
        incomingReqQ.deq();
        
        let val = writeDataQ.first();
        writeDataQ.deq();

        let req = SCRATCHPAD_WRITE_REQ { port: my_port,
                                         addr: zeroExtendNP(pack(addr)),
                                         val: val };

        link_mem_req.enq(0, tagged SCRATCHPAD_MEM_WRITE req);
    endrule

    //
    // receiveResp --
    //     Push unordered read responses to the reorder buffers.  Responses will
    //     be returned through readRsp() in order.
    //
    (* fire_when_enabled *)
    rule receiveResp (True);
        let s = link_mem_rsp.first();
        link_mem_rsp.deq();

        // The read UID field holds the concatenation of the port ID and
        // the port's reorder buffer index.
        t_MAF_IDX maf_idx = unpack(truncateNP(s.readUID));
        match {.port, .rob_idx} = maf_idx;

        sortResponseQ[port].setValue(rob_idx, s.val);
    endrule


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
// mkMergedScratchpad --
//     Scratchpads may have an optional merger, which will try to place 
//     back-to-back requests together to conserve memory bandwidth.  Here, 
//     we apply the merger, based on the 1) the scratchpad configuration 2) 
//     a merger implementation provided by the caller. Returns scratchpad
//     with the same interface
//
module [m] mkMergedScratchpad#(scratchpadIfc baseScratchpad,
                               SCRATCHPAD_CONFIG conf, 
                               Integer numRobSlots, 
                               function m#(scratchpadIfc) mkMergerImpl(scratchpadIfc unmergedScratchpad, Integer robSlots)) 
     // Interface:
    (scratchpadIfc)
    provisos(IsModule#(m, a__));

    scratchpadIfc resultScratchpad = baseScratchpad;
    if (conf.requestMerging)
    begin
        resultScratchpad <- mkMergerImpl(baseScratchpad, numRobSlots);
    end
    
    return resultScratchpad;
      
endmodule


    
//
// mkUnmarshalledCachedScratchpad --
//     Allocate a cached connection to the platform's scratchpad interface for
//     a single scratchpad region.  This module does no marshalling of
//     data sizes.
//
//     This module is just a convenience wrapper for the implementation
//     that adds an optional read request combining shim.
//
module [CONNECTED_MODULE] mkUnmarshalledCachedScratchpad#(
    Integer scratchpadID, 
    SCRATCHPAD_CONFIG conf,
    NumTypeParam#(n_OBJECTS) nContainerObjects, 
    NumTypeParam#(n_CACHE_ENTRIES) nCacheEntries,
    NumTypeParam#(n_PREFETCH_LEARNER_SIZE) nPrefetchLearners,
    NumTypeParam#(t_ADDR_SZ) userAddrWidth,
    SCRATCHPAD_STATS_CONSTRUCTOR statsConstructor,
    SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR prefetchStatsConstructor,
    Bool maskedWriteEn)
    // interface:
    (MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_READERS, t_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE, t_MEM_MASK))
    provisos (Bits#(t_MEM_ADDRESS, t_MEM_ADDRESS_SZ),
              Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ),
              Bits#(t_MEM_MASK, t_MEM_MASK_SZ));

    // Size the ROB.  Eventually, we might need other means of filling
    // in the NumTypeParams, since each module can really only fill in
    // one at a time.

    Integer robSlots = ?;
    MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_READERS, t_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE, t_MEM_MASK) _scr = ?;

    if(conf.backingStore == RL_CACHE_STORE_FLAT_BRAM) 
    begin
        NumTypeParam#(SCRATCHPAD_PORT_ROB_SLOTS_SHORT_LATENCY) nROBSlots = ?;
        _scr <- mkUnmarshalledCachedScratchpadImpl(scratchpadID, 
                                                   conf,
                                                   nContainerObjects, 
                                                   nCacheEntries,
                                                   nPrefetchLearners,
                                                   nROBSlots,
                                                   userAddrWidth,
                                                   statsConstructor,
                                                   prefetchStatsConstructor,
                                                   maskedWriteEn);

        robSlots = valueOf(SCRATCHPAD_PORT_ROB_SLOTS_SHORT_LATENCY);         
    end
    else
    begin
        NumTypeParam#(SCRATCHPAD_PORT_ROB_SLOTS_LONG_LATENCY) nROBSlots = ?;
        _scr <- mkUnmarshalledCachedScratchpadImpl(scratchpadID, 
                                                   conf,
                                                   nContainerObjects, 
                                                   nCacheEntries,
                                                   nPrefetchLearners,
                                                   nROBSlots,
                                                   userAddrWidth,
                                                   statsConstructor,
                                                   prefetchStatsConstructor,
                                                   maskedWriteEn);

        robSlots = valueOf(SCRATCHPAD_PORT_ROB_SLOTS_LONG_LATENCY);
    end
        
    _scr <- mkMergedScratchpad(_scr, conf, robSlots, mkMemReadBypassWrapperMultiReadMaskedWrite);

    return _scr;
endmodule

module [CONNECTED_MODULE] mkUnmarshalledCachedScratchpadImpl#(
    Integer scratchpadID, 
    SCRATCHPAD_CONFIG conf,
    NumTypeParam#(n_OBJECTS) nContainerObjects, 
    NumTypeParam#(n_CACHE_ENTRIES) nCacheEntries,
    NumTypeParam#(n_PREFETCH_LEARNER_SIZE) nPrefetchLearners,
    NumTypeParam#(n_ROB_SLOTS) nROBSlots,
    NumTypeParam#(t_ADDR_SZ) userAddrWidth, 
    SCRATCHPAD_STATS_CONSTRUCTOR statsConstructor,
    SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR prefetchStatsConstructor,
    Bool maskedWriteEn)
    // interface:
    (MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_READERS, t_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE, t_MEM_MASK))
    provisos (Bits#(t_MEM_ADDRESS, t_MEM_ADDRESS_SZ),
              Bits#(SCRATCHPAD_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ),
              Bits#(t_MEM_MASK, t_MEM_MASK_SZ),

              // Index in a reorder buffer
              Alias#(SCOREBOARD_FIFO_ENTRY_ID#(n_ROB_SLOTS), t_REORDER_ID),
              
              // MAF for in-flight reads
              Alias#(Tuple2#(Bit#(TLog#(n_READERS)), t_REORDER_ID), t_MAF_IDX),
              Bits#(t_MAF_IDX, t_MAF_IDX_SZ));

    DEBUG_FILE debugLog;
    DEBUG_FILE debugLogForPrefetcher;
 
    Bool enableAddressHashing = conf.enableAddressHashing;

    if (conf.debugLogPath matches tagged Valid .debugLogPath)
    begin 
        debugLog              <- mkDebugFile(debugLogPath);
        debugLogForPrefetcher <- mkDebugFile("prefetcher_" + debugLogPath);
    end
    else if (`PLATFORM_SCRATCHPAD_DEBUG_ENABLE == 1)
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
    Param#(3) cacheMode              <- mkDynamicParameter(`PARAMS_SCRATCHPAD_MEMORY_SERVICE_SCRATCHPAD_PVT_CACHE_MODE, paramNode);
    Param#(6) prefetchMechanism      <- mkDynamicParameter(`PARAMS_SCRATCHPAD_MEMORY_SERVICE_SCRATCHPAD_PREFETCHER_MECHANISM, paramNode);
    Param#(4) prefetchLearnerSizeLog <- mkDynamicParameter(`PARAMS_SCRATCHPAD_MEMORY_SERVICE_SCRATCHPAD_PREFETCHER_LEARNER_SIZE_LOG, paramNode);
    Param#(2) prefetchPrioritySpec   <- mkDynamicParameter(`PARAMS_SCRATCHPAD_MEMORY_SERVICE_SCRATCHPAD_PREFETCHER_PRIORITY_SPEC, paramNode);

    // Connection between private cache and the scratchpad virtual device
    let sourceData <- mkScratchpadCacheSourceData(scratchpadID, conf, debugLog);
                   
    // Choose a prefetcher. The prefetcher may need to translate
    // between the user-level address, and the cache address. 
    SCRATCHPAD_PREFETCHER_IMPL prefetch_type = unpack(`SCRATCHPAD_STD_PVT_CACHE_PREFETCH_ENABLE);
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
    
    // Private cache
    RL_DM_CACHE#(Bit#(t_MEM_ADDRESS_SZ),
                 SCRATCHPAD_MEM_VALUE,
                 t_MEM_MASK, 
                 t_MAF_IDX) cache <- mkCacheDirectMapped(sourceData,
                                                         prefetcher, 
                                                         nCacheEntries,
                                                         conf.privateCacheImplementation,
                                                         enableAddressHashing,
                                                         maskedWriteEn,
                                                         debugLog);

    // Hook up stats
    let cacheStats <- statsConstructor(cache.stats);
    let prefetchStats <- prefetchStatsConstructor(prefetcher.stats);

    // Merge FIFOF combines read and write requests in temporal order,
    // with reads from the same cycle as a write going first.  Each read port
    // gets a slot.  The write port is always last.
    MERGE_FIFOF#(TAdd#(n_READERS, 1),
                 Tuple2#(t_MEM_ADDRESS, SCOREBOARD_FIFO_ENTRY_ID#(n_ROB_SLOTS))) incomingReqQ <- mkMergeFIFOF();

    // Write data is sent in a side port to keep the incomingReqQ smaller.
    FIFO#(SCRATCHPAD_MEM_VALUE) writeDataQ <- mkFIFO();
    
    FIFO#(t_MEM_MASK) writeMaskQ = ?;
    if (maskedWriteEn)
    begin
        writeMaskQ <- mkFIFO();
    end

    // Cache responses are not ordered.  Sort them with a reorder buffer.
    Vector#(n_READERS, SCOREBOARD_FIFOF#(n_ROB_SLOTS, SCRATCHPAD_MEM_VALUE)) sortResponseQ <- replicateM(mkScoreboardFIFOF());
    
    // Initialization
    Reg#(Bool) initialized <- mkReg(False);
    rule doInit (! initialized);
        cache.setCacheMode(unpack(cacheMode[1:0]), unpack(cacheMode[2]));
        prefetcher.setPrefetchMode(unpack(prefetchMechanism), unpack(prefetchLearnerSizeLog), unpack(prefetchPrioritySpec));
        initialized <= True;
    endrule


    // Write requests
    rule forwardWriteReq (initialized && (incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS))));
        let addr = tpl_1(incomingReqQ.first());
        incomingReqQ.deq();

        let val = writeDataQ.first();
        writeDataQ.deq();

        if (maskedWriteEn)
        begin
            let mask = writeMaskQ.first();
            writeMaskQ.deq();
            cache.writeMasked(pack(addr), val, mask);
        end
        else
        begin
            cache.write(pack(addr), val);
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

            // Request data from the cache
            cache.readReq(pack(addr), maf_idx, defaultValue());
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
            match {.port, .idx} = r.readMeta;
            sortResponseQ[p].setValue(idx, r.val);
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

    method Action write(t_MEM_ADDRESS addr, SCRATCHPAD_MEM_VALUE val, t_MEM_MASK mask);
        // The write port is last in the merge FIFO
        incomingReqQ.ports[valueOf(n_READERS)].enq(tuple2(addr, ?));
        writeDataQ.enq(val);
        if (maskedWriteEn)
        begin
            writeMaskQ.enq(mask);
        end
        debugLog.record($format("write addr=0x%x, val=0x%x, mask=0x%x", addr, val, mask));
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

              Alias#(Bit#(t_ADDR_SZ), t_ADDR));

    let _scr <- mkUncachedScratchpadImpl(scratchpadID, conf);

    if (conf.requestMerging)
    begin
        _scr <- mkMemReadBypassWrapperMultiRead(
                   _scr, valueOf(SCRATCHPAD_UNCACHED_PORT_ROB_SLOTS));
    end

    return _scr;
endmodule


module [CONNECTED_MODULE] mkUncachedScratchpadImpl#(Integer scratchpadID,
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
    if (conf.debugLogPath matches tagged Valid .debugLogPath)
    begin 
        debugLog <- mkDebugFile(debugLogPath);
    end
    else if (`PLATFORM_SCRATCHPAD_DEBUG_ENABLE == 1)
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
    let platformID <- getSynthesisBoundaryPlatformID();

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_MEM_REQ) link_mem_req <-
        mkConnectionTokenRingNode("Scratchpad_Platform_" + integerToString(platformID) + "_Req", my_port);

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_READ_RSP) link_mem_rsp <-
        mkConnectionTokenRingNode("Scratchpad_Platform_" + integerToString(platformID) + "_Resp", my_port);


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
        debugLog.record($format("doInit: init ID %0d, last word idx 0x%x", r.port, r.allocLastWordIdx));
    endrule


    //
    // Forward merged requests to the memory.
    //

    // Read requests
    (* fire_when_enabled *)
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
            Bit#(TLog#(n_READERS)) p = truncateNP(port);
            t_MAF_IDX maf_idx = tuple2(p, rob_idx);
            maf.upd(maf_idx, addr_idx);

            let req = SCRATCHPAD_READ_REQ { port: my_port,
                                            addr: s_addr,
                                            byteReadMask: scratchpadByteMask(addr),
                                            readUID: zeroExtendNP(pack(maf_idx)),
                                            globalReadMeta: defaultValue() };

            link_mem_req.enq(0, tagged SCRATCHPAD_MEM_READ req);
            debugLog.record($format("read port %0d: req addr=0x%x, s_addr=0x%x, s_idx=%0d, rob_idx=%0d",
                                    port, addr, s_addr, addr_idx, rob_idx));
        end
    endrule


    // Write requests
    (* fire_when_enabled *)
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

        debugLog.record($format("write addr=0x%x, val=0x%x, s_addr=0x%x, s_val=0x%x, s_bmask=%b", addr, w_data, scratchpadAddr(addr), pack(d), pack(b_mask)));
    endrule

    //
    // receiveResp --
    //     Push unordered read responses to the reorder buffers.  Responses will
    //     be returned through readRsp() in order.
    //
    (* fire_when_enabled *)
    rule receiveResp (True);
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

        debugLog.record($format("read port %0d: resp val=0x%x, s_idx=%0d, rob_idx=%0d", 
                        port, v, addr_idx, rob_idx));
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
                    debugLog.record($format("read port %0d: req addr=0x%x, rob_idx=%0d", p, addr, rob_idx));
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
