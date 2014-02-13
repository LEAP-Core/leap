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
import Vector::*;


`include "awb/provides/channelio.bsh"
`include "awb/provides/umf.bsh"

`define NUM_SERVICES 0


typedef Bit#(8)  UINT8;
typedef Bit#(16) UINT16;
typedef Bit#(32) UINT32;
typedef Bit#(64) UINT64;


typedef Bit#(32) RRR_ServiceID;
typedef Bit#(32) RRR_Param;
typedef Bit#(32) RRR_Response;
typedef Bit#(32) RRR_Chunk;

typedef struct
{
    RRR_ServiceID   serviceID;
    RRR_Param       param0;
    RRR_Param       param1;
    RRR_Param       param2;
    Bool            needResponse;
} RRR_Request   deriving (Eq, Bits);

// request/response port interfaces
interface CLIENT_REQUEST_PORT;
    method Action write(UMF_PACKET data);
endinterface

interface CLIENT_RESPONSE_PORT;
    method ActionValue#(UMF_PACKET) read();
endinterface


interface RRR_CLIENT;
    interface Vector#(`NUM_SERVICES, CLIENT_REQUEST_PORT)  requestPorts;
    interface Vector#(`NUM_SERVICES, CLIENT_RESPONSE_PORT) responsePorts;
endinterface


// request/response port interfaces
interface SERVER_REQUEST_PORT;
    method ActionValue#(UMF_PACKET) read();
endinterface

interface SERVER_RESPONSE_PORT;
    method Action write(UMF_PACKET data);
endinterface

// channelio interface
interface RRR_SERVER;
    interface Vector#(`NUM_SERVICES, SERVER_REQUEST_PORT)  requestPorts;
    interface Vector#(`NUM_SERVICES, SERVER_RESPONSE_PORT) responsePorts;
endinterface

module mkRRRClient#(CHANNEL_IO#(umf) channel) (RRR_CLIENT);

    Vector#(`NUM_SERVICES, CLIENT_REQUEST_PORT)  reqPorts = newVector();
    Vector#(`NUM_SERVICES, CLIENT_RESPONSE_PORT) rspPorts = newVector();    

    interface requestPorts = reqPorts;
    interface responsePorts = rspPorts;


endmodule


module mkRRRServer#(CHANNEL_IO#(umf) channel) (RRR_SERVER);

    Vector#(`NUM_SERVICES, SERVER_REQUEST_PORT)  reqPorts = newVector();
    Vector#(`NUM_SERVICES, SERVER_RESPONSE_PORT) rspPorts = newVector();

    interface requestPorts = reqPorts;
    interface responsePorts = rspPorts;

endmodule


