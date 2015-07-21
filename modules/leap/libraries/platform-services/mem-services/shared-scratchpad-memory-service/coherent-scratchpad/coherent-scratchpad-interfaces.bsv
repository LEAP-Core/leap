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

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/shared_scratchpad_memory_common.bsh"

// ========================================================================
//
// Coherent scratchpad common definitions. 
//
// ========================================================================


// Number of ports in local coherence rings and global controller rings
typedef SHARED_SCRATCH_PORT_NUM COH_SCRATCH_PORT_NUM;
typedef SHARED_SCRATCH_CTRLR_PORT_NUM COH_SCRATCH_CTRLR_PORT_NUM;

//
// Coherent scratchpad memory data
//
typedef SCRATCHPAD_MEM_VALUE COH_SCRATCH_MEM_VALUE;

//
// Responses returned to cherent scratchpad clients may not be in order. 
// Coherent scratchpad clients keep the copy of the request information in 
// their local cache and use the COH_SCRATCH_CLIENT_META type to tag requests 
// with the corresponding responses.  
// 
typedef `COHERENT_SCRATCHPAD_CLIENT_META_BITS COH_SCRATCH_CLIENT_META_SZ;
typedef Bit#(COH_SCRATCH_CLIENT_META_SZ) COH_SCRATCH_CLIENT_META;

//
// COH_SCRATCH_CTRL_META is the index of the entry that stores the associated 
// PUTX request in the coherent scratchpad controller's request status 
// handling registers (RSHR)
// PUTX responses (write back data) are tagged with COH_SCRATCH_CTRL_META to 
// help the coherence controller find the associated RSHR entries
//
typedef `COHERENT_SCRATCHPAD_CONTROLLER_META_BITS COH_SCRATCH_CONTROLLER_META_SZ;
typedef Bit#(COH_SCRATCH_CONTROLLER_META_SZ) COH_SCRATCH_CTRL_META;

typedef TMax#(COH_SCRATCH_CLIENT_META_SZ, COH_SCRATCH_CONTROLLER_META_SZ) COH_SCRATCH_META_SZ;
typedef Bit#(COH_SCRATCH_META_SZ) COH_SCRATCH_META;

//
// Caching options for coherent scratchpads.
//
typedef enum
{
    // Each coherent scratchpad has a private coherent cache
    COH_SCRATCH_CACHED,
    // Each coherent scratchpad does not have a private cache
    // All reads/writes need to be sent to the centralized private scratchpad
    COH_SCRATCH_UNCACHED
}
COH_SCRATCH_CACHE_MODE
    deriving (Eq, Bits);

//
// Coherent scratchpad configurations (passed to the constructors of coherent 
// scratchpad controller and client)
//
typedef struct
{
    // Does the coherent scratchpad client have a private cache?
    COH_SCRATCH_CACHE_MODE  cacheMode;
    
    // The number of entries in coherent scratchpad's private cache
    Integer                 cacheEntries;

    // Does the coherent scratchpad domain has multiple controllers?
    Bool                    multiController;

    // Enable prefetching in scratchpad's private cache
    Maybe#(SCRATCHPAD_PREFETCHER_IMPL) enablePrefetching;

    // Enable address hashing for the scratchpad
    Bool enableAddressHashing;
    
    // Enable the request merging optimization to merge multiple read requests
    // accessing the same scratchpad internal address
    Bool                    requestMerging;

    // A unique string naming the scratchpad debug log file. If no string is
    // provided, logging will be disabled. 
    Maybe#(String)          debugLogPath;

    // A unique name for the scratchpad debug scan. If no string is provided, 
    // debug scan will be disabled. 
    Maybe#(String)          enableDebugScan;
    
    // Enables statistics collection for this coherent scratchpad client. 
    // The string argument is used to provide a unique and meaningful 
    // prefix name for the stats.
    Maybe#(String)          enableStatistics;

}
COH_SCRATCH_CLIENT_CONFIG
    deriving (Eq, Bits);

instance DefaultValue#(COH_SCRATCH_CLIENT_CONFIG);
    defaultValue = COH_SCRATCH_CLIENT_CONFIG {
        cacheMode: COH_SCRATCH_CACHED,
        cacheEntries: `SHARED_SCRATCHPAD_PVT_CACHE_ENTRIES,
        multiController: False,
        enablePrefetching: tagged Invalid, 
        enableAddressHashing: True,
        requestMerging: (`SHARED_SCRATCHPAD_REQ_MERGE_ENABLE==1),
        debugLogPath: tagged Invalid,
        enableDebugScan: tagged Invalid,
        enableStatistics: tagged Invalid
    };
endinstance

typedef struct
{
    // Do coherent scratchpad clients have private caches?
    COH_SCRATCH_CACHE_MODE                cacheMode;
    
    // Does the coherent scratchpad domain has multiple controllers?
    Bool                                  multiController;
    
    Integer                               coherenceDomainID;
    Bool                                  isMaster;
    SHARED_SCRATCH_PARTITION_CONSTRUCTOR  partition;
    
    // Initialize the shared memory from a file?  If yes, the global string is
    // the path of the initialization file, which is a raw memory image.
    // If not, the scratchpad shared memory is initialized to zeros.
    Maybe#(GLOBAL_STRING_UID)             initFilePath;
    
    // A unique string naming the scratchpad debug log.  If no string is
    // provided, logging will be disabled. 
    Maybe#(String)                        debugLogPath;

    // A unique name for the scratchpad debug scan. If no string is provided, 
    // debug scan will be disabled. 
    Maybe#(String)                        enableDebugScan;
    
    // Enables statistics collection for this scratchpad controller. 
    // The string argument is used to provide a unique and meaningful 
    // prefix name for the stats.
    Maybe#(String)                        enableStatistics;
}
COH_SCRATCH_CONTROLLER_CONFIG;

instance DefaultValue#(COH_SCRATCH_CONTROLLER_CONFIG);
    defaultValue = COH_SCRATCH_CONTROLLER_CONFIG {
        cacheMode: COH_SCRATCH_CACHED,
        multiController: False,
        coherenceDomainID: ?,
        isMaster: False,
        partition: mkSharedScratchControllerNullPartition,
        initFilePath: tagged Invalid,
        debugLogPath: tagged Invalid,
        enableDebugScan: tagged Invalid,
        enableStatistics: tagged Invalid
    };
endinstance

// ========================================================================
//
// Data structures flowing through soft connections between coherent 
// scratchpad clients (with private caches) and the coherent scratchpad 
// controller.
//
// ========================================================================

//
// Coherence get request info -- 
// request for data/ownership (read request)
//
typedef struct
{
    COH_SCRATCH_CLIENT_META     clientMeta;
    RL_CACHE_GLOBAL_READ_META   globalReadMeta;
}
COH_SCRATCH_GET_REQ_INFO
    deriving(Bits, Eq);

//
// Coherence put request info -- 
// give up ownership and write-back data
//
typedef struct
{
    Bool                        isCleanWB;
    Bool                        isExclusive;
}
COH_SCRATCH_PUT_REQ_INFO
    deriving(Bits, Eq);

//
// Coherence activated put request info -- 
// add COH_SCRATCH_CTRL_META to the COH_SCRATCH_PUT_REQ_INFO
// 
typedef struct
{
    COH_SCRATCH_CTRL_META       controllerMeta;
    Bool                        isCleanWB;
}
COH_SCRATCH_ACTIVATED_PUT_REQ_INFO
    deriving(Bits, Eq);

//
// Coherence request info message
//
typedef union tagged
{
    // Get shared
    COH_SCRATCH_GET_REQ_INFO COH_SCRATCH_GETS;

    // Get exclusive
    COH_SCRATCH_GET_REQ_INFO COH_SCRATCH_GETX;

    // Put exclusive
    COH_SCRATCH_PUT_REQ_INFO COH_SCRATCH_PUTX;
}
COH_SCRATCH_MEM_REQ_INFO
    deriving(Bits, Eq);

//
// Coherence activated request info message
//
typedef union tagged
{
    // Get shared
    COH_SCRATCH_GET_REQ_INFO COH_SCRATCH_ACTIVATED_GETS;

    // Get exclusive
    COH_SCRATCH_GET_REQ_INFO COH_SCRATCH_ACTIVATED_GETX;

    // Put exclusive
    COH_SCRATCH_ACTIVATED_PUT_REQ_INFO COH_SCRATCH_ACTIVATED_PUTX;
}
COH_SCRATCH_ACTIVATED_REQ_INFO
    deriving(Bits, Eq);

//
// Coherence unactivated request message 
//
typedef struct
{
    COH_SCRATCH_PORT_NUM        requester;
    COH_SCRATCH_CTRLR_PORT_NUM  reqControllerId;
    t_ADDR                      addr;
    COH_SCRATCH_MEM_REQ_INFO    reqInfo;
}
COH_SCRATCH_MEM_REQ#(type t_ADDR)
    deriving (Eq, Bits);

//
// Coherence activated request message 
//
typedef struct
{
    COH_SCRATCH_PORT_NUM            requester;
    COH_SCRATCH_CTRLR_PORT_NUM      reqControllerId;
    COH_SCRATCH_CTRLR_PORT_NUM      homeControllerId;
    t_ADDR                          addr;
    COH_SCRATCH_ACTIVATED_REQ_INFO  reqInfo;
}
COH_SCRATCH_ACTIVATED_REQ#(type t_ADDR)
    deriving (Eq, Bits);

//
// Coherence load response -- 
// response for data/ownership
//
typedef struct
{
    COH_SCRATCH_MEM_VALUE       val;
    Bool                        ownership;
    Bool                        isExclusive;
`ifndef SHARED_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z
    COH_SCRATCH_CTRLR_PORT_NUM  controllerId;
    COH_SCRATCH_PORT_NUM        clientId;
`endif    
`ifndef COHERENT_SCRATCHPAD_RESP_FWD_CHAIN_ENABLE_Z
    Bool                        needFwd;
    COH_SCRATCH_CTRLR_PORT_NUM  lastFwdControllerId;
    COH_SCRATCH_PORT_NUM        lastFwdClientId;
`endif
    COH_SCRATCH_META            meta;
    RL_CACHE_GLOBAL_READ_META   globalReadMeta;
    Bool                        isCacheable;
    Bool                        retry;
    Bool                        fromCache;
}
COH_SCRATCH_RESP
    deriving (Eq, Bits);

