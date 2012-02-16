//
// Copyright (C) 2012 Intel Corporation
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

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv.bsh"

`include "awb/rrr/server_stub_STDIO.bsh"
`include "awb/rrr/client_stub_STDIO.bsh"


module [CONNECTED_MODULE] mkStdIOService
    // interface:
    ();

    // ****** State Elements ******

    // Communication to/from our SW via RRR
    ClientStub_STDIO clientStub <- mkClientStub_STDIO();
    ServerStub_STDIO serverStub <- mkServerStub_STDIO();

    // Request ring.  All requests are handled by the service.
    CONNECTION_CHAIN#(Tuple2#(STDIO_REQ_RING_CHUNK, Bool)) reqChain <-
        mkConnectionChain("stdio_req_ring");

    // Response ring is addressable, since responses are to specific clients.
    CONNECTION_ADDR_RING#(STDIO_CLIENT_ID, STDIO_RSP) rspChain <-
        mkConnectionAddrRingNode("stdio_rsp_ring", 0);
    

    // ****** Rules ******

    //
    // processReq --
    //
    //    Process a request from an individual scan node.
    //  
    rule processReq (True);
        match {.chunk, .eom} <- reqChain.recvFromPrev();
        clientStub.makeRequest_Req(chunk, zeroExtend(pack(eom)));
    endrule

    //
    // processRsp --
    //
    //     Process a response from software.
    //
    rule processRsp (True);
        let rsp <- serverStub.acceptRequest_Rsp();
        rspChain.enq(rsp.tgtNode,
                     STDIO_RSP { eom: unpack(rsp.meta[2]),
                                 nValid: rsp.meta[1:0],
                                 data: rsp.data,
                                 operation: unpack(truncate(rsp.command)) });
    endrule
endmodule
