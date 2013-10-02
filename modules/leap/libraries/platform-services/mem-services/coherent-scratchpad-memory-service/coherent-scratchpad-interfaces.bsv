//
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

// ========================================================================
//
// Data structures flowing through soft connections between coherent 
// scratchpad clients and the coherent scratchpad controller. 
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

