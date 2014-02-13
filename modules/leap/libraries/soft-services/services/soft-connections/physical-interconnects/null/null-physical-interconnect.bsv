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

import List::*;

`include "awb/provides/soft_connections.bsh"


typedef struct
{
}
ROUTING_TABLE;

typedef struct
{
    ROUTING_TABLE routingTable;
    List#(LOGICAL_SEND_INFO) outgoingInfo;
    List#(LOGICAL_RECV_INFO) incomingInfo;
    List#(LOGICAL_SEND_MULTI_INFO) outgoingMultiInfo;
    List#(LOGICAL_RECV_MULTI_INFO) incomingMultiInfo;
}
PHYSICAL_STATION_INFO;


module mkEmptyRoot#(PHYSICAL_STATION st) ();
endmodule


module initRoutingTable#(List#(PHYSICAL_STATION_INFO) children_infos) 
    // interface:
    (PHYSICAL_STATION_INFO);
    return ?;
endmodule

module initRoutingTableLeaf#(List#(LOGICAL_RECV_INFO) recvs,
                             List#(LOGICAL_SEND_INFO) sends,
                             List#(LOGICAL_RECV_MULTI_INFO) recv_multis,
                             List#(LOGICAL_SEND_MULTI_INFO) send_multis)
    // Interface:
    (PHYSICAL_STATION_INFO);
    return ?;
endmodule


module mkPhysicalStation#(List#(PHYSICAL_STATION) children, 
                          ROUTING_TABLE routing_table)
    // Interface:
    (PHYSICAL_STATION);
    return ?;
endmodule

module mkConnStationWrappers#(List#(LOGICAL_RECV_INFO) recvs,
                              List#(LOGICAL_SEND_INFO) sends,
                              List#(LOGICAL_RECV_MULTI_INFO) recv_multis,
                              List#(LOGICAL_SEND_MULTI_INFO) send_multis)
    // Interface:
    (List#(PHYSICAL_STATION));
    return List::nil;
endmodule

module printStationInfo#(PHYSICAL_STATION_INFO info) ();
endmodule

module mkSendStationWrapper#(PHYSICAL_CONNECTION_OUT physical_send)
    // interface:
    (PHYSICAL_STATION);
    return ?;
endmodule

module mkRecvStationWrapper#(PHYSICAL_CONNECTION_IN physical_recv)
    // interface:
    (PHYSICAL_STATION);
    return ?;
endmodule

module mkSendMultiStationWrapper#(PHYSICAL_CONNECTION_OUT_MULTI physical_send)
    // interface:
    (PHYSICAL_STATION);
    return ?;
endmodule

module mkRecvMultiStationWrapper#(PHYSICAL_CONNECTION_IN_MULTI physical_recv)
    // interface:
    (PHYSICAL_STATION);
    return ?;
endmodule
