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

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/scratchpad_memory_service.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

// ========================================================================
//
// Shared scratchpad common definitions. 
//
// ========================================================================

//
// The maximum number of shared scratchpad clients associated with each
// shared scratchpad controller
//
typedef `SHARED_SCRATCHPAD_MAX_CLIENT_NUM SHARED_SCRATCH_N_CLIENTS;

//
// Port 0 is reserved for the shared scratchpad controller.  
// Add 1 to the number of clients. 
//
typedef TAdd#(1, SHARED_SCRATCH_N_CLIENTS) SHARED_SCRATCH_N_PORTS;

//
// Shared scratchpad port number.  Add 1 to the number of ports in case 
// there are no clients.  Bit#(0) is not a valid array index.
//
typedef Bit#(TLog#(TAdd#(1, SHARED_SCRATCH_N_PORTS))) SHARED_SCRATCH_PORT_NUM;

//
// The maximum number of scratchpad controllers in a shared region
//
`ifndef SHARED_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z
    typedef `SHARED_SCRATCHPAD_MAX_CONTROLLER_NUM SHARED_SCRATCH_N_CONTROLLERS;
`else
    typedef 1 SHARED_SCRATCH_N_CONTROLLERS;
`endif

typedef Bit#(TLog#(SHARED_SCRATCH_N_CONTROLLERS)) SHARED_SCRATCH_CTRLR_PORT_NUM;

//
// Scratchpads are not required to return read results in order.  Clients
// are expected to use the SCRATCHPAD_CLIENT_META type to tag read requests
// with information to sort them correctly.
//
typedef SCRATCHPAD_CLIENT_READ_UID SHARED_SCRATCH_CLIENT_META;
typedef Bit#(`SHARED_SCRATCHPAD_MEMORY_ADDR_BITS) SHARED_SCRATCH_MEM_ADDRESS;

// For cached shared scratchpads, the shared scratchpad memory word/mask size 
// should be the same as scratchpad memory word/mask size
typedef SCRATCHPAD_MEM_VALUE SHARED_SCRATCH_MEM_VALUE;
typedef SCRATCHPAD_MEM_MASK  SHARED_SCRATCH_MEM_MASK;

// Number of slots in a shared scratchpad client's read port's reorder buffer.
typedef SCRATCHPAD_PORT_ROB_SLOTS SHARED_SCRATCH_PORT_ROB_SLOTS;

//
// Caching options for shared scratchpads.
//
// For coherent scratchpad service, it requires that all clients
// in the same coherence domain have same cache option.
typedef enum
{
    // Shared scratchpad client has a private cache
    SHARED_SCRATCH_CACHED,
    // Shared scratchpad client does not have a private cache
    // Reads/writes are forwarded to the next level memory
    SHARED_SCRATCH_UNCACHED
}
SHARED_SCRATCH_CACHE_MODE
    deriving (Eq, Bits);

// SHARED_SCRATCH_CACHE_STORE_TYPE --
//   Used to define the underlying store used by the shared cache.
typedef enum
{
    SHARED_SCRATCH_CACHE_STORE_FLAT_BRAM = 0,
    SHARED_SCRATCH_CACHE_STORE_BANKED_BRAM = 1
}
SHARED_SCRATCH_CACHE_STORE_TYPE
    deriving (Eq, Bits);
//
// Shared scratchpad client type
// Shared scratchpad clients in the same memory region should have
// same shared scratchpad client type
typedef enum
{
    // Shared scratchpad client has a coherent cache
    COHERENT_SCRATCHPAD,
    // Shared scratchpad client is read-only
    READ_ONLY_SCRATCHPAD,
    // Shared scratchpad client is a normal scratchpad with flush/invalidate controlled by users
    NORMAL_SCRATCHPAD, 
    // Shared scratchpad client does not have a private cache
    UNCACHED_SCRATCHPAD
}
SHARED_SCRATCH_CLIENT_TYPE
    deriving (Eq, Bits);

// Shared scratchpad controller type
typedef enum
{
    // Controller for coherent scratchpad clients
    COHERENT_SCRATCHPAD_CONTROLLER,
    // Controller for cached shared scratchpad clients
    CACHED_SCRATCHPAD_CONTROLLER,
    // Controller for uncached shared scratchpad clients
    UNCACHED_SCRATCHPAD_CONTROLLER
}
SHARED_SCRATCH_CONTROLLER_TYPE
    deriving (Eq, Bits);

//
// Shared scratchpad configurations (passed to the constructors of shared
// scratchpad controller and client)
//
typedef struct
{
    // Does this shared scratchpad client have a private cache?
    SHARED_SCRATCH_CACHE_MODE  cacheMode;
    
    // The number of entries in shared scratchpad's private cache
    Integer                    cacheEntries;

    // The type of the shared scratchpad client
    SHARED_SCRATCH_CLIENT_TYPE clientType;
    
    // Does the shared scratchpad domain has multiple controllers?
    Bool                       multiController;

    // Enable prefetching in shared scratchpad's private cache
    Maybe#(SCRATCHPAD_PREFETCHER_IMPL)        enablePrefetching;
    
    // Enable the request merging optimization to merge multiple read requests
    // accessing the same scratchpad internal address
    Bool                       requestMerging;

    // A unique string naming the scratchpad debug log file. If no string is
    // provided, logging will be disabled. 
    Maybe#(String)             debugLogPath;

    // A unique name for the scratchpad debug scan. If no string is provided, 
    // debug scan will be disabled. 
    Maybe#(String)             enableDebugScan;
    
    // Enables statistics collection for this shared scratchpad client. 
    // The string argument is used to provide a unique and meaningful 
    // prefix name for the stats.
    Maybe#(String)             enableStatistics;

}
SHARED_SCRATCH_CLIENT_CONFIG
    deriving (Eq, Bits);

instance DefaultValue#(SHARED_SCRATCH_CLIENT_CONFIG);
    defaultValue = SHARED_SCRATCH_CLIENT_CONFIG {
        cacheMode: SHARED_SCRATCH_CACHED,
        cacheEntries: `SHARED_SCRATCHPAD_PVT_CACHE_ENTRIES,
        clientType: COHERENT_SCRATCHPAD,
        multiController: False,
        enablePrefetching: tagged Invalid, 
        requestMerging: (`SHARED_SCRATCHPAD_REQ_MERGE_ENABLE==1),
        debugLogPath: tagged Invalid,
        enableDebugScan: tagged Invalid,
        enableStatistics: tagged Invalid
    };
endinstance

typedef struct
{
    // The type of the shared scratchpad controller
    SHARED_SCRATCH_CONTROLLER_TYPE        controllerType;
    // Does the shared scratchpad domain has multiple controllers?
    Bool                                  multiController;
    
    Integer                               sharedDomainID;
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
SHARED_SCRATCH_CONTROLLER_CONFIG;

instance DefaultValue#(SHARED_SCRATCH_CONTROLLER_CONFIG);
    defaultValue = SHARED_SCRATCH_CONTROLLER_CONFIG {
        controllerType: COHERENT_SCRATCHPAD_CONTROLLER,
        multiController: False,
        sharedDomainID: ?,
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
// Data structures flowing through soft connections between shared 
// scratchpad clients and the shared scratchpad controller.
//
// (Note: coherent scratchpads have different message types defined in 
//        coherent-scratchpad-interfaces.bsv)
//
// ========================================================================


typedef struct
{
    SHARED_SCRATCH_CLIENT_META  clientMeta;
    RL_CACHE_GLOBAL_READ_META   globalReadMeta;
    Bool                        isWriteMiss;
}
SHARED_SCRATCH_READ_REQ_INFO
    deriving (Eq, Bits);

typedef struct
{
    SHARED_SCRATCH_MEM_VALUE data;
}
SHARED_SCRATCH_WRITE_REQ_INFO
    deriving (Eq, Bits);

typedef union tagged 
{
    SHARED_SCRATCH_READ_REQ_INFO   SHARED_SCRATCH_READ;
    SHARED_SCRATCH_WRITE_REQ_INFO  SHARED_SCRATCH_WRITE;
}
SHARED_SCRATCH_REQ_INFO
    deriving (Eq, Bits);

typedef struct
{
    SHARED_SCRATCH_PORT_NUM  requester;
    t_ADDR                   addr;
    SHARED_SCRATCH_REQ_INFO  reqInfo;
}
SHARED_SCRATCH_REQ#(type t_ADDR)
    deriving (Eq, Bits);

typedef struct
{
    t_ADDR                      addr;
    SHARED_SCRATCH_MEM_VALUE    val;
    SHARED_SCRATCH_CLIENT_META  clientMeta;
    RL_CACHE_GLOBAL_READ_META   globalReadMeta;
    Bool                        isCacheable;
}
SHARED_SCRATCH_READ_RESP#(type t_ADDR)
    deriving (Eq, Bits);

typedef union tagged 
{
    SHARED_SCRATCH_READ_RESP#(t_ADDR)  CACHED_READ_RESP;
    void                               UNCACHED_WRITE_ACK;
}
SHARED_SCRATCH_RESP#(type t_ADDR)
    deriving (Eq, Bits);

typedef struct
{
    SHARED_SCRATCH_CTRLR_PORT_NUM reqControllerId;
    SHARED_SCRATCH_REQ#(t_ADDR)   reqLocal;
}
SHARED_SCRATCH_CONTROLLERS_REQ#(type t_ADDR)
    deriving (Eq, Bits);

typedef struct
{
    SHARED_SCRATCH_PORT_NUM      clientId;
    SHARED_SCRATCH_RESP#(t_ADDR) resp;
}
SHARED_SCRATCH_CONTROLLERS_RESP#(type t_ADDR)
    deriving (Eq, Bits);
    
