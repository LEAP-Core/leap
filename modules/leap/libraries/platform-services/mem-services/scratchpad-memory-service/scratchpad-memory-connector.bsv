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


`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/RINGID.bsh"
`include "awb/dict/ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/dict/DEBUG_SCAN_SCRATCHPAD_MEMORY_SERVICE.bsh"


module [CONNECTED_MODULE] mkScratchpadConnector#(SCRATCHPAD_MEMORY_VDEV vdev) (Empty);

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_RING_REQ) link_mem_req <-
        mkConnectionAddrRingNode("ScratchpadGlobalReq", `SCRATCHPAD_PLATFORM_ID);

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_RRR_LOAD_LINE_RESP) link_mem_rsp <-
        mkConnectionAddrRingNode("ScratchpadGlobalResp", `SCRATCHPAD_PLATFORM_ID);
 
    Reg#(Bit#(32)) reqCount <- mkReg(0);
    Reg#(Bit#(32)) respCount <- mkReg(0);

    // We all live on the token ring...  And there's one per platform... So we need to disambiguate
    // Create platform ID in compiler

    rule eatReq;
        $display("Scratchpad store %d sent a req %d", `SCRATCHPAD_PLATFORM_ID, reqCount+1);
        reqCount <= reqCount + 1;
        let req <- vdev.rrrReq();
        link_mem_req.enq(0,SCRATCHPAD_RING_REQ{portID: `SCRATCHPAD_PLATFORM_ID, req:req}); // patch through requests to base handler.
    endrule
 
    rule eatResp;
        $display("Scratchpad store %d got a resp %d", `SCRATCHPAD_PLATFORM_ID, respCount+1);
        respCount <= respCount + 1;
        vdev.loadLineResp(link_mem_rsp.first());
        link_mem_rsp.deq;
    endrule

endmodule
