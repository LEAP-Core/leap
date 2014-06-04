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

import FIFO::*;

`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/physical_platform_utils.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/ASSERTIONS_SCRATCHPAD_MEMORY_SERVICE.bsh"
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
        let platformID <- getSynthesisBoundaryPlatformID();
        if (platformID == 0)
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
                                              initRegionReq.regionEndIdx,
                                              initRegionReq.initFilePath);
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

    STAT_ID statIDs[2];

    statIDs[0] = statName("LEAP_SCRATCHPAD_LOCAL_REQUESTS",
                          "Requests from the local scratchpads");
    let statLocalReq = 0;

    statIDs[1] = statName("LEAP_SCRATCHPAD_LOCAL_RESPONSES",
                          "Responses from the local scratchpads");
    let statLocalResp = 1;

    STAT_VECTOR#(2) stats <- mkStatCounter_Vector(statIDs);

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

    STAT_ID statIDs[4];

    statIDs[0] = statName("LEAP_SCRATCHPAD_LOCAL_REQUESTS",
                          "Requests from the local scratchpads");
    let statLocalReq = 0;

    statIDs[1] = statName("LEAP_SCRATCHPAD_LOCAL_RESPONSES",
                          "Responses from the local scratchpads");
    let statLocalResp = 1;

    statIDs[2] = statName("LEAP_SCRATCHPAD_REMOTE_REQUESTS",
                          "Requests from the remote scratchpads");
    let statRemoteReq = 2;

    statIDs[3] = statName("LEAP_SCRATCHPAD_REMOTE_RESPONSES",
                          "Responses from the remote scratchpads");
    let statRemoteResp = 3;

    STAT_VECTOR#(4) stats <- mkStatCounter_Vector(statIDs);

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
    
    let platformName <- getSynthesisBoundaryPlatform();
    let platformID   <- getSynthesisBoundaryPlatformID();

    DEBUG_FILE debugLog <- mkDebugFile("memory_scratchpad_ring_" + platformName + ".out");

    CONNECTION_ADDR_RING#(SCRATCHPAD_RING_STOP_ID, SCRATCHPAD_RING_REQ) link_mem_req <-
        mkConnectionAddrRingNode("ScratchpadGlobalReq", fromInteger(platformID));

    CONNECTION_ADDR_RING#(SCRATCHPAD_RING_STOP_ID, SCRATCHPAD_RRR_LOAD_LINE_RESP) link_mem_rsp <-
        mkConnectionAddrRingNode("ScratchpadGlobalResp", fromInteger(platformID));
 
    rule eatReq;
        let req = localReqQ.first();
        localReqQ.deq();

        // patch through requests to base handler.
        link_mem_req.enq(0, SCRATCHPAD_RING_REQ { stopID: fromInteger(platformID()),
                                                  req: req });

        debugLog.record($format("Scratchpad req"));
    endrule
 
    rule eatResp;
        localRespQ.enq(link_mem_rsp.first());
        link_mem_rsp.deq;

        debugLog.record($format("Scratchpad resp"));
    endrule

endmodule
