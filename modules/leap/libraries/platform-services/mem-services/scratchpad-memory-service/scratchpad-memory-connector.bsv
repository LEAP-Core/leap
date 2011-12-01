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
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/RINGID.bsh"
`include "awb/dict/ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/dict/DEBUG_SCAN_SCRATCHPAD_MEMORY_SERVICE.bsh"


// Platform ID 0 reserved for the RRR connector ring stop.
function Integer scratchpadPlatformID = fpgaPlatformID + 1;


module [CONNECTED_MODULE] mkScratchpadConnector#(SCRATCHPAD_MEMORY_VDEV vdev) (Empty);

    DEBUG_FILE debugLog <- mkDebugFile("memory_scratchpad_ring_" + integerToString(scratchpadPlatformID()) + ".out");

    CONNECTION_ADDR_RING#(SCRATCHPAD_RING_STOP_ID, SCRATCHPAD_RING_REQ) link_mem_req <-
        mkConnectionAddrRingNode("ScratchpadGlobalReq", fromInteger(scratchpadPlatformID()));

    CONNECTION_ADDR_RING#(SCRATCHPAD_RING_STOP_ID, SCRATCHPAD_RRR_LOAD_LINE_RESP) link_mem_rsp <-
        mkConnectionAddrRingNode("ScratchpadGlobalResp", fromInteger(scratchpadPlatformID()));
 
    // We all live on the token ring...  And there's one per platform... So we need to disambiguate
    // Create platform ID in compiler

    rule eatReq;
        let req <- vdev.rrrReq();
        // patch through requests to base handler.
        link_mem_req.enq(0, SCRATCHPAD_RING_REQ { stopID: fromInteger(scratchpadPlatformID()),
                                                  req: req });

        debugLog.record($format("Scratchpad req"));
    endrule
 
    rule eatResp;
        vdev.loadLineResp(link_mem_rsp.first());
        link_mem_rsp.deq;

        debugLog.record($format("Scratchpad resp"));
    endrule

endmodule
