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

import FIFO::*;

`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/physical_platform_utils.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/RINGID.bsh"
`include "awb/dict/ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/dict/DEBUG_SCAN_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/dict/STATS_SCRATCHPAD.bsh"
`include "awb/rrr/service_ids.bsh"
`include "awb/rrr/client_stub_SCRATCHPAD_MEMORY.bsh"
`include "awb/rrr/server_stub_SCRATCHPAD_MEMORY.bsh"


//
// mkScratchpadConnector --
//     Convert scratchpad requests arriving on localReqQ to RRR requests and
//     return RRR responses on localRespQ.
//
//     This wrapper picks the connector appropriate to the FPGA topology.
//
module [CONNECTED_MODULE] mkScratchpadConnector#(FIFO#(SCRATCHPAD_RRR_REQ) localReqQ,
                                                 FIFO#(SCRATCHPAD_RRR_LOAD_LINE_RESP) localRespQ)
    // Interface:
    (Empty);

    if (fpgaNumPlatforms() == 1)
    begin
        // Single FPGA system
        let c <- mkScratchpadConnectorSingle(localReqQ, localRespQ);
    end
    else
    begin
        // Multi-FPGA system
        if (fpgaPlatformID() == 0)
        begin
            // Master FPGA
            let c <- mkScratchpadConnectorMultiMaster(localReqQ, localRespQ);
        end
        else
        begin
            // Slave FPGA
            let c <- mkScratchpadConnectorMultiSlave(localReqQ, localRespQ);
        end
    end
endmodule


//
// scratchSendReq --
//     Utility to convert a scratchpad request struct to an RRR request.
//
function Action scratchSendReq(SCRATCHPAD_RRR_REQ req,
                               SCRATCHPAD_RING_STOP_ID num,
                               ClientStub_SCRATCHPAD_MEMORY scratchpad_rrr,
                               FIFO#(SCRATCHPAD_RING_STOP_ID) tags);
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


//
// mkScratchpadConnectorSingle --
//     RRR connection for a single FPGA system.
//
module [CONNECTED_MODULE] mkScratchpadConnectorSingle#(FIFO#(SCRATCHPAD_RRR_REQ) localReqQ,
                                                       FIFO#(SCRATCHPAD_RRR_LOAD_LINE_RESP) localRespQ)
    // Interface:
    (Empty);

    ClientStub_SCRATCHPAD_MEMORY scratchpad_rrr <- mkClientStub_SCRATCHPAD_MEMORY(); 

    Vector#(2, STATS_DICT_TYPE) statIDs = newVector();

    statIDs[0] = `STATS_SCRATCHPAD_LOCAL_REQUESTS;
    let statLocalReq = 0;

    statIDs[1] = `STATS_SCRATCHPAD_LOCAL_RESPONSES;
    let statLocalResp = 1;

    let stats <- mkStatCounter_Vector(statIDs);

    // Dummy FIFO needed for generality with the multi-FPGA implementation
    FIFO#(SCRATCHPAD_RING_STOP_ID) tags = ?;

    rule eatReqLocal;
        let req = localReqQ.first();
        localReqQ.deq();

        scratchSendReq(req, 0, scratchpad_rrr, tags);
        stats.incr(statLocalReq);
    endrule
 
    rule eatRespLocal;
        let r <- scratchpad_rrr.getResponse_LoadLine();
        localRespQ.enq(SCRATCHPAD_RRR_LOAD_LINE_RESP { data0:r.data0,
                                                       data1:r.data1,
                                                       data2:r.data2,
                                                       data3:r.data3 });
        stats.incr(statLocalResp);
    endrule
endmodule


//
// mkScratchpadConnectorMultiMaster --
//     RRR connection for the master node in a multi-FPGA configuration.
//     In addition to the local connection, allocate a ring stop on which
//     requests from remote FPGAs will be serviced.
//
module [CONNECTED_MODULE] mkScratchpadConnectorMultiMaster#(FIFO#(SCRATCHPAD_RRR_REQ) localReqQ,
                                                            FIFO#(SCRATCHPAD_RRR_LOAD_LINE_RESP) localRespQ)
    // Interface:
    (Empty);

    DEBUG_FILE debugLog <- mkDebugFile("memory_scratchpad_ring_rrr.out");

    ClientStub_SCRATCHPAD_MEMORY scratchpad_rrr <- mkClientStub_SCRATCHPAD_MEMORY(); 

    let multiFPGA = (fpgaNumPlatforms() > 1);

    //
    // Ring stop 0 is the bridge between remote FPGAs and the RRR hybrid
    // interface.
    //
    CONNECTION_ADDR_RING#(SCRATCHPAD_RING_STOP_ID, SCRATCHPAD_RING_REQ) link_mem_req <-
        mkConnectionAddrRingNode("ScratchpadGlobalReq", 0);

    CONNECTION_ADDR_RING#(SCRATCHPAD_RING_STOP_ID, SCRATCHPAD_RRR_LOAD_LINE_RESP) link_mem_rsp <-
        mkConnectionAddrRingNode("ScratchpadGlobalResp", 0);

    Vector#(4, STATS_DICT_TYPE) statIDs = newVector();

    statIDs[0] = `STATS_SCRATCHPAD_LOCAL_REQUESTS;
    let statLocalReq = 0;

    statIDs[1] = `STATS_SCRATCHPAD_LOCAL_RESPONSES;
    let statLocalResp = 1;

    statIDs[2] = `STATS_SCRATCHPAD_REMOTE_REQUESTS;
    let statRemoteReq = 2;

    statIDs[3] = `STATS_SCRATCHPAD_REMOTE_RESPONSES;
    let statRemoteResp = 3;

    let stats <- mkStatCounter_Vector(statIDs);

    // Size of tags defines max outstanding requests.
    FIFO#(SCRATCHPAD_RING_STOP_ID) tags <- mkSizedFIFO(32);

    rule eatReqLocal;
        let req = localReqQ.first();
        localReqQ.deq();

        scratchSendReq(req, 0, scratchpad_rrr, tags);
        stats.incr(statLocalReq);
    endrule
 
    rule eatRespLocal (tags.first == 0);
        tags.deq;
        let r <- scratchpad_rrr.getResponse_LoadLine();
        localRespQ.enq(SCRATCHPAD_RRR_LOAD_LINE_RESP { data0:r.data0,
                                                       data1:r.data1,
                                                       data2:r.data2,
                                                       data3:r.data3 });
        stats.incr(statLocalResp);
    endrule

    // Also handle non-local requests
    (* descending_urgency = "eatReqLocal, eatReqNonLocal" *)
    rule eatReqNonLocal;
        let req = link_mem_req.first();
        link_mem_req.deq();

        scratchSendReq(req.req, req.stopID, scratchpad_rrr, tags);
        stats.incr(statRemoteReq);

        debugLog.record($format("Scratchpad recv non-local req %d", req.stopID));
    endrule

    rule eatRespNonLocal (tags.first != 0);
        tags.deq;
        let r <- scratchpad_rrr.getResponse_LoadLine();
        link_mem_rsp.enq(tags.first,
                         SCRATCHPAD_RRR_LOAD_LINE_RESP { data0:r.data0,
                                                         data1:r.data1,
                                                         data2:r.data2,
                                                         data3:r.data3 });
        stats.incr(statRemoteResp);

        debugLog.record($format("Scratchpad serviced non-local resp %d", tags.first));
    endrule
endmodule


//
// mkScratchpadConnectorMultiSlave --
//     RRR connection for any slave node in a multi-FPGA configuration.
//     Forward all requests to the master.
//
module [CONNECTED_MODULE] mkScratchpadConnectorMultiSlave#(FIFO#(SCRATCHPAD_RRR_REQ) localReqQ,
                                                           FIFO#(SCRATCHPAD_RRR_LOAD_LINE_RESP) localRespQ)
    // Interface:
    (Empty);
    
    DEBUG_FILE debugLog <- mkDebugFile("memory_scratchpad_ring_" + integerToString(fpgaPlatformID()) + ".out");

    CONNECTION_ADDR_RING#(SCRATCHPAD_RING_STOP_ID, SCRATCHPAD_RING_REQ) link_mem_req <-
        mkConnectionAddrRingNode("ScratchpadGlobalReq", fromInteger(fpgaPlatformID()));

    CONNECTION_ADDR_RING#(SCRATCHPAD_RING_STOP_ID, SCRATCHPAD_RRR_LOAD_LINE_RESP) link_mem_rsp <-
        mkConnectionAddrRingNode("ScratchpadGlobalResp", fromInteger(fpgaPlatformID()));
 
    rule eatReq;
        let req = localReqQ.first();
        localReqQ.deq();

        // patch through requests to base handler.
        link_mem_req.enq(0, SCRATCHPAD_RING_REQ { stopID: fromInteger(fpgaPlatformID()),
                                                  req: req });

        debugLog.record($format("Scratchpad req"));
    endrule
 
    rule eatResp;
        localRespQ.enq(link_mem_rsp.first());
        link_mem_rsp.deq;

        debugLog.record($format("Scratchpad resp"));
    endrule

endmodule
