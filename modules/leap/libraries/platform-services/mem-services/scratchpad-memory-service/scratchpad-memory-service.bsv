//
// Copyright (C) 2009 Intel Corporation
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

import Arbiter::*;

`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/central_cache_service.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/RINGID.bsh"
`include "awb/dict/ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE.bsh"


module [CONNECTED_MODULE] mkScratchpadMemoryService#(CENTRAL_CACHE_IFC centralCache)
    // interface:
    ();
    
    //
    // Instantiate a scratchpad implementation.
    //
    let memory <- mkScratchpadMemory(centralCache);

    // ***** Assertion Checkers *****
    ASSERTION_NODE assertNode <- mkAssertionNode(`ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE__BASE);
    ASSERTION assertScratchpadSpace <- mkAssertionChecker(`ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE_FULL, ASSERT_ERROR, assertNode);

    // ====================================================================
    //
    // Scratchpad clients and this server are connected on a ring.  We
    // use a ring to avoid congested routing on the FPGA when there are
    // a lot of scratchpads.  When there is a small number of scratchpads
    // the ring is small, so it doesn't add much latency.
    //
    // Two rings are required to avoid deadlocks:  one for requests and
    // one for responses.
    //
    // ====================================================================

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_MEM_REQ) link_mem_req <-
        mkConnectionTokenRingNode(`SCRATCHPAD_PLATFORM + integerToString(`RINGID_SCRATCHPAD_MEMORY_REQ), 0);

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_READ_RSP) link_mem_rsp <-
        mkConnectionTokenRingNode(`SCRATCHPAD_PLATFORM + integerToString(`RINGID_SCRATCHPAD_MEMORY_RSP), 0);


    //
    // sendScratchpadReq --
    //     Forward a scratchpad client's request to the scratchpad
    //     device.
    //
    //     At most one instance of this rule will fire, based on the
    //     arbiter.
    //
    rule sendScratchpadReq (True);
        let req = link_mem_req.first();
        link_mem_req.deq();

        case (req) matches
            tagged SCRATCHPAD_MEM_INIT .init:
            begin
                let s <- memory.init(init.allocLastWordIdx,
                                     init.port,
                                     init.cached);
                assertScratchpadSpace(s);
            end

            tagged SCRATCHPAD_MEM_READ .r_req:
            begin
                let ref_info = SCRATCHPAD_REF_INFO { portNum: r_req.port,
                                                     clientRefInfo: r_req.clientRefInfo };
                memory.readReq(r_req.addr, r_req.byteReadMask, ref_info);
            end

            tagged SCRATCHPAD_MEM_WRITE .w_req:
            begin
                memory.write(w_req.addr, w_req.val, w_req.port);
            end

            tagged SCRATCHPAD_MEM_WRITE_MASKED .w_req:
            begin
                memory.writeMasked(w_req.addr,
                                   w_req.val,
                                   w_req.byteWriteMask,
                                   w_req.port);

            end
        endcase
    endrule
    

    rule sendScratchpadResp (True);
        let r <- memory.readRsp();

        SCRATCHPAD_READ_RSP resp;
        resp.val = r.val;
        resp.addr = r.addr;
        resp.clientRefInfo = r.refInfo.clientRefInfo;

        link_mem_rsp.enq(r.refInfo.portNum, resp);
    endrule

endmodule
