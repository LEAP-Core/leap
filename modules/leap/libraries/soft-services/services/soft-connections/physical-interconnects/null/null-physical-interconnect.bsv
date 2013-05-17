//
// Copyright (C) 2013 Intel Corporation
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
