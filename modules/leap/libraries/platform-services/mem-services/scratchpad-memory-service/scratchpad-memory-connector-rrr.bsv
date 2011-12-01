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


import Arbiter::*;

`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/RINGID.bsh"
`include "awb/dict/ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/dict/DEBUG_SCAN_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/dict/STATS_SCRATCHPAD.bsh"
`include "awb/rrr/service_ids.bsh"
`include "awb/rrr/client_stub_SCRATCHPAD_MEMORY.bsh"
`include "awb/rrr/server_stub_SCRATCHPAD_MEMORY.bsh"


module [CONNECTED_MODULE] mkScratchpadConnector#(SCRATCHPAD_MEMORY_VDEV vdev)
    // Interface:
    (Empty);

    DEBUG_FILE debugLog <- mkDebugFile("memory_scratchpad_ring_rrr.out");

    ClientStub_SCRATCHPAD_MEMORY scratchpad_rrr <- mkClientStub_SCRATCHPAD_MEMORY(); 

    CONNECTION_ADDR_RING#(SCRATCHPAD_RING_STOP_ID, SCRATCHPAD_RING_REQ) link_mem_req <-
        mkConnectionAddrRingNode("ScratchpadGlobalReq", 0);

    CONNECTION_ADDR_RING#(SCRATCHPAD_RING_STOP_ID, SCRATCHPAD_RRR_LOAD_LINE_RESP) link_mem_rsp <-
        mkConnectionAddrRingNode("ScratchpadGlobalResp", 0);

    STAT remote_requests <- mkStatCounter(`STATS_SCRATCHPAD_REMOTE_REQUESTS);
    STAT local_requests <- mkStatCounter(`STATS_SCRATCHPAD_LOCAL_REQUESTS);
    STAT remote_responses <- mkStatCounter(`STATS_SCRATCHPAD_REMOTE_RESPONSES);
    STAT local_responses<- mkStatCounter(`STATS_SCRATCHPAD_LOCAL_RESPONSES);

    // Size of tags defines max outstanding requests.
    FIFO#(SCRATCHPAD_RING_STOP_ID) tags <- mkSizedFIFO(32);

    function Action sendReq(SCRATCHPAD_RRR_REQ req, SCRATCHPAD_RING_STOP_ID num);
    action
        case (req) matches
          tagged StoreWordReq .storeWordReq:
            begin
            scratchpad_rrr.makeRequest_StoreWord(storeWordReq.byteMask,
                                                 storeWordReq.addr,
                                                 storeWordReq.data);
            end
          tagged StoreLineReq .storeLineReq:
            begin
            scratchpad_rrr.makeRequest_StoreLine(storeLineReq.byteMask,
                                                 storeLineReq.addr,
                                                 storeLineReq.data0,
                                                 storeLineReq.data1,
                                                 storeLineReq.data2,
                                                 storeLineReq.data3);
            end

          tagged LoadLineReq .loadLineReq:
            begin
            scratchpad_rrr.makeRequest_LoadLine(loadLineReq.addr);
            tags.enq(num);
            end

          tagged InitRegionReq .initRegionReq:
            begin
            scratchpad_rrr.makeRequest_InitRegion(initRegionReq.regionID,
                                                  initRegionReq.regionEndIdx);
            end
        endcase
    endaction
    endfunction

    rule eatReqLocal;
        let req <- vdev.rrrReq();
        sendReq(req, 0);
        local_requests.incr;
    endrule
 
    rule eatRespLocal(tags.first == 0);
        tags.deq;
        let r <- scratchpad_rrr.getResponse_LoadLine();
        vdev.loadLineResp(SCRATCHPAD_RRR_LOAD_LINE_RESP { data0:r.data0,
                                                          data1:r.data1,
                                                          data2:r.data2,
                                                          data3:r.data3 });
        local_responses.incr;
    endrule

    // Also handle non-local requests
    rule eatReqNonLocal;
        let req = link_mem_req.first();
        link_mem_req.deq();
        sendReq(req.req, req.stopID);
        remote_requests.incr;

        debugLog.record($format("Scratchpad recv non-local req %d", req.stopID));
    endrule

    rule eatRespNonLocal(tags.first != 0);
        tags.deq;
        let r <- scratchpad_rrr.getResponse_LoadLine();
        link_mem_rsp.enq(tags.first,
                         SCRATCHPAD_RRR_LOAD_LINE_RESP { data0:r.data0,
                                                         data1:r.data1,
                                                         data2:r.data2,
                                                         data3:r.data3 });
        remote_responses.incr;

        debugLog.record($format("Scratchpad serviced non-local resp %d", tags.first));
    endrule

endmodule
