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

import DefaultValue::*;


`include "awb/provides/physical_platform_utils.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/local_mem.bsh"
`include "awb/provides/debug_scan_service.bsh"

`include "awb/dict/VDEV.bsh"


// ========================================================================
//
// Scratchpad memory
//
// ========================================================================

//
// Compute the clients of scratchpad memory.  Clients register by adding entries
// to the VDEV.SCRATCH dictionary.
//

`ifndef VDEV_SCRATCH__NENTRIES
// No clients.
`define VDEV_SCRATCH__NENTRIES 0
`endif

//
// Port 0 is reserved for the server.  Add 1 to the number of clients.
//
typedef TAdd#(`VDEV_SCRATCH__NENTRIES, 1) SCRATCHPAD_N_CLIENTS;

//
// Scratchpad port number.  Add 1 to the number of clients in case there are
// no clients.  Bit#(0) is not a valid array index.
//
typedef Bit#(TLog#(TAdd#(1, SCRATCHPAD_N_CLIENTS))) SCRATCHPAD_PORT_NUM;

//
// Scratchpads are not required to return read results in order.  Clients
// are expected to use the SCRATCHPAD_CLIENT_READ_UID type to tag read requests
// with information to sort them correctly.
//
// DON'T MAKE THE READ UID TOO LARGE!  It is used as an index to arrays
// holding details of in-flight reads.
//
typedef `SCRATCHPAD_CLIENT_READ_UID_BITS SCRATCHPAD_CLIENT_READ_UID_SZ;
typedef Bit#(SCRATCHPAD_CLIENT_READ_UID_SZ) SCRATCHPAD_CLIENT_READ_UID;


//
// Caching options for scratchpads.  The caching option also affects the way
// data structures are marshalled to scratchpad containers.
//
typedef enum
{
    // Fully cached.  Elements are packed tightly in scratchpad containers.
    SCRATCHPAD_CACHED,

    // No private L1 cache, but data may be stored in a shared, central cache.
    SCRATCHPAD_NO_PVT_CACHE,

    // Raw, right to memory.  Elements are aligned to natural sizes within
    // a scratchpad container.  (E.g. 1, 2, 4 or 8 bytes.)  Byte masks are
    // used on writes to avoid requiring read/modify/write.  The current
    // implementation supports object sizes up to the size of a
    // SCRATCHPAD_MEM_VALUE.
    SCRATCHPAD_UNCACHED
}
SCRATCHPAD_CACHE_MODE
    deriving (Eq, Bits);

//
// Prefetching options for scratchpads.  
//
typedef enum
{
    // Turn off prefetching.
    SCRATCHPAD_NON_PREFETCH = 0,

    // Use a gateware stride prefetcher
    SCRATCHPAD_STRIDE_PREFETCH = 1,

    // Expose prefetch request interface to user, using li channels.
    SCRATCHPAD_USER_PREFETCH = 2 
}
SCRATCHPAD_PREFETCHER_IMPL
    deriving (Eq, Bits);


//
// Scratchpad configuration (passed to scratchpad constructors.)
//
typedef struct
{
    // Construct/participate in cache hierarchy?
    SCRATCHPAD_CACHE_MODE cacheMode;

    // Backing store to use in cache.
    RL_CACHE_STORE_TYPE backingStore;

    // The number of entries in scratchpad's private cache
    Integer cacheEntries;

    // Initialize the scratchpad from a file?  If yes, the global string is
    // the path of the initialization file, which is a raw memory image.
    // If not, the scratchpad is initialized to zeros.
    Maybe#(GLOBAL_STRING_UID) initFilePath;

    // Enable prefetching in scratchpad's private cache
    Maybe#(SCRATCHPAD_PREFETCHER_IMPL) enablePrefetching;

    // Allows programmer to select private cache implementation of scratchpad. 
    // If none is selected, then the global default, set in librl, will be used. 
    Maybe#(RL_CACHE_STORE_TYPE) privateCacheImplementation;

    // Enable address hashing for the scratchpad
    Bool enableAddressHashing;
    
    // Enable the request merging optimization to merge multiple read requests
    // accessing the same scratchpad internal address
    Bool requestMerging;

    // A unique string naming the scratchpad debug log.  If no string is
    // provided, logging will be disabled. 
    Maybe#(String) debugLogPath;

    // Enables statistics collection for this scratchpad. The string argument 
    // is used to provide a unique and meaningful prefix name for the stats.
    Maybe#(String) enableStatistics;
}
SCRATCHPAD_CONFIG
    deriving (Eq, Bits);

instance DefaultValue#(SCRATCHPAD_CONFIG);
    defaultValue = SCRATCHPAD_CONFIG {
        cacheMode: SCRATCHPAD_CACHED,
        cacheEntries: 0,
        backingStore: unpack(`RL_DM_CACHE_BRAM_TYPE),
        initFilePath: tagged Invalid,
        enablePrefetching: tagged Invalid,
        enableAddressHashing: True,
        requestMerging: False,
        debugLogPath: tagged Invalid,
        enableStatistics: tagged Invalid
    };
endinstance

//
// Scratchpad read UID.  Used for directing read responses to the right
// ports and sorting read responses.  The read UID associates a read
// request with its corresponding response and may be used by caches
// to build associative structures that track details of in-flight reads.
//
typedef struct
{
    SCRATCHPAD_PORT_NUM portNum;
    SCRATCHPAD_CLIENT_READ_UID clientReadUID;
}
SCRATCHPAD_READ_UID
    deriving (Eq, Bits);


//
// Scratchpad read response returns metadata along with the value.  The
// readUID field contains tags to direct the response to the correct port
// and to sort responses chronologically.  (The scratchpad memory may return
// results out of order due to cache effects.)
//
// The address of the value is returned because some clients with private
// caches need the address to insert the value into a cache.  Returning
// the address eliminates the need for private FIFOs in the clients to track
// addresses.
//
typedef struct
{
    t_DATA val;
    t_ADDR addr;
    SCRATCHPAD_READ_UID readUID;
    Bool isCacheable;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
SCRATCHPAD_READ_RESP#(type t_ADDR, type t_DATA)
    deriving (Eq, Bits);


// ========================================================================
//
// Data structures for hybrid scratchpad RRR host requests.
//
// ========================================================================

typedef struct 
{
    Bit#(32) regionID;
    Bit#(64) regionEndIdx;
    Bit#(64) initFilePath;
}
SCRATCHPAD_RRR_INIT_REGION_REQ
    deriving (Bits,Eq);

typedef struct 
{
    Bit#(64) byteMask;
    Bit#(64) addr;
    Bit#(64) data3;
    Bit#(64) data2;
    Bit#(64) data1;
    Bit#(64) data0;

}
SCRATCHPAD_RRR_STORE_LINE_REQ
    deriving (Bits,Eq);

typedef struct 
{
    Bit#(64) byteMask;
    Bit#(64) addr;
    Bit#(64) data;

}
SCRATCHPAD_RRR_STORE_WORD_REQ
    deriving (Bits,Eq);


typedef struct 
{
    Bit#(64) addr;
}
SCRATCHPAD_RRR_LOAD_LINE_REQ
    deriving (Bits,Eq);

typedef struct 
{
    Bit#(64) data3;
    Bit#(64) data2;
    Bit#(64) data1;
    Bit#(64) data0;
}
SCRATCHPAD_RRR_LOAD_LINE_RESP
    deriving (Bits,Eq);

typedef union tagged
{
    SCRATCHPAD_RRR_STORE_WORD_REQ StoreWordReq;
    SCRATCHPAD_RRR_STORE_LINE_REQ StoreLineReq;
    SCRATCHPAD_RRR_LOAD_LINE_REQ  LoadLineReq;
    SCRATCHPAD_RRR_INIT_REGION_REQ InitRegionReq;
}
SCRATCHPAD_RRR_REQ
    deriving (Bits,Eq);


// ========================================================================
//
// For multiple FPGAs, only a single FPGA manages the RRR requests to the
// host.  All other FPGAs make requests over an inter-FPGA ring.  The
// requests are translated to RRR requests by the primary FPGA.
//
// ========================================================================

typedef FPGA_PLATFORM_ID SCRATCHPAD_RING_STOP_ID;

typedef struct 
{
    SCRATCHPAD_RRR_REQ req;
    SCRATCHPAD_RING_STOP_ID stopID;
}
SCRATCHPAD_RING_REQ
    deriving (Bits,Eq);


//
// All scratchpad requests flow through a single request/response interface.
// The platform interface module may fan out connections to clients of the
// scratchpad using, for example, multiple soft connections.
//
// The READ_UID is used to determine address spaces and route reponses back
// to the corresponding requester.
//
interface SCRATCHPAD_MEMORY_VIRTUAL_DEVICE#(type t_ADDR, type t_DATA, type t_MASK);
    method Action readReq(t_ADDR addr,
                          t_MASK byteMask,
                          SCRATCHPAD_READ_UID readUID,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);
    method ActionValue#(SCRATCHPAD_READ_RESP#(t_ADDR, t_DATA)) readRsp();
 
    method Action write(t_ADDR addr,
                        t_DATA val,
                        SCRATCHPAD_PORT_NUM portNum);
    method Action writeMasked(t_ADDR addr,
                              t_DATA val,
                              t_MASK byteMask,
                              SCRATCHPAD_PORT_NUM portNum);

    // Initialize a port, requesting an allocation of allocLastWordIdx + 1
    // SCRATCHPAD_MEM_VALUE sized words.
    method ActionValue#(Bool) init(t_ADDR allocLastWordIdx,
                                   SCRATCHPAD_PORT_NUM portNum,
                                   Bool useCentralCache,
                                   Maybe#(GLOBAL_STRING_UID) initFilePath);
endinterface: SCRATCHPAD_MEMORY_VIRTUAL_DEVICE

