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

// ========================================================================
//
// Coherent scratchpad common definitions. 
//
// ========================================================================

//
// The maximum number of coherent scratchpad clients in a coherence region
//
typedef 64 COH_SCRATCH_N_CLIENTS;

//
// Port 0 is reserved for the coherent scratchpad controller.  
// Add 1 to the number of clients. 
//
typedef TAdd#(1, COH_SCRATCH_N_CLIENTS) COH_SCRATCH_N_PORTS;

//
// Coherent scratchpad port number.  Add 1 to the number of ports in case 
// there are no clients.  Bit#(0) is not a valid array index.
//
typedef Bit#(TLog#(TAdd#(1, COH_SCRATCH_N_PORTS))) COH_SCRATCH_PORT_NUM;

//
// Coherent scratchpad data
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

// If coherent scratchpad clients do not have private caches, the client's 
// request information is sent along with the remote coherent scratchpad request
typedef SCRATCHPAD_CLIENT_READ_UID COH_SCRATCH_REMOTE_CLIENT_META;

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
// Coherent scratchpad configuration (passed to the constructors of coherent 
// scratchpad controller and client)
//
typedef struct
{
    COH_SCRATCH_CACHE_MODE cacheMode;
}
COH_SCRATCH_CONFIG
    deriving (Eq, Bits);

instance DefaultValue#(COH_SCRATCH_CONFIG);
    defaultValue = COH_SCRATCH_CONFIG {
        cacheMode: COH_SCRATCH_CACHED
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
// Coherence get request -- 
// request for data/ownership (read request)
//
typedef struct
{
    COH_SCRATCH_PORT_NUM       requester;
    t_ADDR                     addr;
    COH_SCRATCH_CLIENT_META    clientMeta;
    RL_CACHE_GLOBAL_READ_META  globalReadMeta;
}
COH_SCRATCH_GET_REQ#(type t_ADDR)
    deriving(Bits, Eq);


//
// Coherence put request -- 
// give up ownership and write-back data
//
typedef struct
{
    COH_SCRATCH_PORT_NUM     requester;
    t_ADDR                   addr;
    Bool                     isCleanWB;
}
COH_SCRATCH_PUT_REQ#(type t_ADDR)
    deriving(Bits, Eq);

//
// Coherence activated put request -- 
// add COH_SCRATCH_CTRL_META to the COH_SCRATCH_PUT_REQ 
// 
typedef struct
{
    COH_SCRATCH_PORT_NUM     requester;
    t_ADDR                   addr;
    COH_SCRATCH_CTRL_META    controllerMeta;
    Bool                     isCleanWB;
}
COH_SCRATCH_ACTIVATED_PUT_REQ#(type t_ADDR)
    deriving(Bits, Eq);

//
// Coherence request message
//
typedef union tagged
{
    // Get shared
    COH_SCRATCH_GET_REQ#(t_ADDR) COH_SCRATCH_GETS;

    // Get exclusive
    COH_SCRATCH_GET_REQ#(t_ADDR) COH_SCRATCH_GETX;

    // Put exclusive
    COH_SCRATCH_PUT_REQ#(t_ADDR) COH_SCRATCH_PUTX;
}
COH_SCRATCH_MEM_REQ#(type t_ADDR)
    deriving(Bits, Eq);

//
// Coherence activated request message
//
typedef union tagged
{
    // Get shared
    COH_SCRATCH_GET_REQ#(t_ADDR) COH_SCRATCH_ACTIVATED_GETS;

    // Get exclusive
    COH_SCRATCH_GET_REQ#(t_ADDR) COH_SCRATCH_ACTIVATED_GETX;

    // Put exclusive
    COH_SCRATCH_ACTIVATED_PUT_REQ#(t_ADDR) COH_SCRATCH_ACTIVATED_PUTX;
}
COH_SCRATCH_ACTIVATED_REQ#(type t_ADDR)
    deriving(Bits, Eq);

//
// Coherence load response -- 
// response for data/ownership
//
typedef struct
{
    COH_SCRATCH_MEM_VALUE      val;
    Bool                       ownership;
    COH_SCRATCH_META           meta;
    RL_CACHE_GLOBAL_READ_META  globalReadMeta;
    Bool                       isCacheable;
    Bool                       retry;
}
COH_SCRATCH_RESP
    deriving (Eq, Bits);


// ========================================================================
//
// Data structures flowing through soft connections between coherent 
// scratchpad clients (without private caches) and the coherent scratchpad 
// controller.
//
// ========================================================================

typedef struct
{
    COH_SCRATCH_PORT_NUM            requester;
    t_ADDR                          addr;
    COH_SCRATCH_REMOTE_CLIENT_META  clientMeta;
    RL_CACHE_GLOBAL_READ_META       globalReadMeta;
}
COH_SCRATCH_REMOTE_READ_REQ#(type t_ADDR)
    deriving (Eq, Bits);

typedef struct
{
    COH_SCRATCH_PORT_NUM            requester;
    t_ADDR                          addr;
    t_DATA                          data;
}
COH_SCRATCH_REMOTE_WRITE_REQ#(type t_ADDR,
                              type t_DATA)
    deriving (Eq, Bits);

typedef union tagged 
{
    COH_SCRATCH_REMOTE_READ_REQ#(t_ADDR)           COH_SCRATCH_REMOTE_READ;
    COH_SCRATCH_REMOTE_WRITE_REQ#(t_ADDR, t_DATA)  COH_SCRATCH_REMOTE_WRITE;
}
COH_SCRATCH_REMOTE_REQ#(type t_ADDR,
                        type t_DATA)
    deriving (Eq, Bits);

typedef struct
{
    t_DATA                          val;
    COH_SCRATCH_REMOTE_CLIENT_META  clientMeta;
    RL_CACHE_GLOBAL_READ_META       globalReadMeta;
}
COH_SCRATCH_REMOTE_READ_RESP#(type t_DATA)
    deriving (Eq, Bits);

typedef union tagged 
{
    COH_SCRATCH_REMOTE_READ_RESP#(t_DATA)  COH_SCRATCH_REMOTE_READ;
    void                                   COH_SCRATCH_REMOTE_WRITE;
}
COH_SCRATCH_REMOTE_RESP#(type t_DATA)
    deriving (Eq, Bits);

