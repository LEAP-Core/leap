//
// Copyright (C) 2011 Intel Corporation
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

`include "awb/provides/physical_platform_utils.bsh"

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/local_mem.bsh"
`include "awb/provides/model_params.bsh"
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
    Bit#(32) regionEndIdx;
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
                          SCRATCHPAD_READ_UID readUID);
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
                                   Bool useCentralCache);
endinterface: SCRATCHPAD_MEMORY_VIRTUAL_DEVICE

