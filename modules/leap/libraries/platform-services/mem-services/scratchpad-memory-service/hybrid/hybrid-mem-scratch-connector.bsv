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

`include "awb/provides/common_services_params.bsh"

//
// mkScratchpadConnector --
//     Convert scratchpad requests arriving on localReqQ to RRR requests and
//     return RRR responses on localRespQ.
//
//     This wrapper picks the connector appropriate to the FPGA topology.
//
module [CONNECTED_MODULE] mkScratchpadConnector#(FIFO#(SCRATCHPAD_RRR_REQ) localReqQ,
                                                 FIFO#(SCRATCHPAD_RRR_LOAD_LINE_RESP) localRespQ, 
                                                 Integer scratchpadBankIdx)
    // Interface:
    (Empty);

    if (fpgaNumPlatforms() == 1 && valueOf(SCRATCHPAD_N_SERVERS) == 1)
    begin
        // Single FPGA system with single memory bank
        let c <- mkScratchpadConnectorSingle(localReqQ, localRespQ);
    end
    else
    begin
        // Multi-FPGA system or single fpga system with multiple memory banks
        // let platformID <- getSynthesisBoundaryPlatformID();
        if (`BUILD_COMMON_SERVICES == 1 && scratchpadBankIdx == 0) 
        begin
            // Master FPGA
            let c <- mkScratchpadConnectorMultiMaster(localReqQ, localRespQ);
        end
        else
        begin
            // Slave FPGA
            let c <- mkScratchpadConnectorMultiSlave(localReqQ, localRespQ, scratchpadBankIdx);
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

        scratchSendReq(req, unpack(0), scratchpad_rrr, tags);
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
    (Empty)
    provisos (Bits#(SCRATCHPAD_RING_STOP_ID, t_SCRATCH_IDX_SZ),
              Alias#(Bit#(t_SCRATCH_IDX_SZ), t_SCRATCH_IDX));

    DEBUG_FILE debugLog <- mkDebugFile("memory_scratchpad_ring_rrr.out");

    ClientStub_SCRATCHPAD_MEMORY scratchpad_rrr <- mkClientStub_SCRATCHPAD_MEMORY(); 

    //
    // Ring stop 0 is the bridge between remote FPGAs and the RRR hybrid
    // interface.
    //
    CONNECTION_ADDR_RING#(t_SCRATCH_IDX, SCRATCHPAD_RING_REQ) link_mem_req <-
        mkConnectionAddrRingNode("ScratchpadGlobalReq", 0);

    CONNECTION_ADDR_RING#(t_SCRATCH_IDX, SCRATCHPAD_RRR_LOAD_LINE_RESP) link_mem_rsp <-
        mkConnectionAddrRingNode("ScratchpadGlobalResp", 0);

    STAT_ID statIDs[6];

    statIDs[0] = statName("LEAP_SCRATCHPAD_LOCAL_REQUESTS",
                          "Requests from the local scratchpads");
    let statLocalReq = 0;

    statIDs[1] = statName("LEAP_SCRATCHPAD_LOCAL_RESPONSES",
                          "Responses to the local scratchpads");
    let statLocalResp = 1;

    statIDs[2] = statName("LEAP_SCRATCHPAD_REMOTE_PLATFORM_REQUESTS",
                          "Requests from the scratchpads on a remote platform");
    let statRemotePlatformReq = 2;

    statIDs[3] = statName("LEAP_SCRATCHPAD_REMOTE_PLATFORM_RESPONSES",
                          "Responses to the scratchpads on a remote platform");
    let statRemotePlatformResp = 3;
    
    statIDs[4] = statName("LEAP_SCRATCHPAD_REMOTE_BANK_REQUESTS",
                          "Requests from the remote scratchpads on the local platform");
    let statRemoteBankReq = 4;
    
    statIDs[5] = statName("LEAP_SCRATCHPAD_REMOTE_BANK_RESPONSES",
                          "Responses to the remote scratchpads on the local platform");
    let statRemoteBankResp = 5;

    STAT_VECTOR#(6) stats <- mkStatCounter_Vector(statIDs);

    // Size of tags defines max outstanding requests.
    FIFO#(SCRATCHPAD_RING_STOP_ID) tags <- mkSizedFIFO(32);
    Reg#(Bit#(1)) localArb <- mkReg(0);

    rule eatReqLocal (localArb == 0 || !link_mem_req.notEmpty);
        let req = localReqQ.first();
        localReqQ.deq();

        scratchSendReq(req, tuple2(0,0), scratchpad_rrr, tags);
        stats.incr(statLocalReq);
        localArb <= localArb + 1;
        debugLog.record($format("Scratchpad recv local req..."));
    endrule
 
    rule eatRespLocal (pack(tags.first) == 0);
        tags.deq;
        let r <- scratchpad_rrr.getResponse_LoadLine();
        localRespQ.enq(SCRATCHPAD_RRR_LOAD_LINE_RESP { data0:r.data0,
                                                       data1:r.data1,
                                                       data2:r.data2,
                                                       data3:r.data3 });
        stats.incr(statLocalResp);
        debugLog.record($format("Scratchpad serviced local resp..."));
    endrule

    // Also handle non-local requests
    (* descending_urgency = "eatReqLocal, eatReqNonLocal" *)
    rule eatReqNonLocal;
        let req = link_mem_req.first();
        link_mem_req.deq();
        
        scratchSendReq(req.req, req.stopID, scratchpad_rrr, tags);
        
        match {.platform_id, .bank_id} = req.stopID;
        
        if (platform_id == 0)
        begin
            stats.incr(statRemoteBankReq);
        end
        else
        begin
            stats.incr(statRemotePlatformReq);
        end

        debugLog.record($format("Scratchpad recv non-local req, platform=%d, bank=%d", platform_id, bank_id));
        localArb <= localArb + 1;
    endrule

    rule eatRespNonLocal (pack(tags.first) != 0);
        let r <- scratchpad_rrr.getResponse_LoadLine();
        link_mem_rsp.enq(pack(tags.first),
                         SCRATCHPAD_RRR_LOAD_LINE_RESP { data0:r.data0,
                                                         data1:r.data1,
                                                         data2:r.data2,
                                                         data3:r.data3 });
        
        match {.platform_id, .bank_id} = tags.first();
        tags.deq;
        
        if (platform_id == 0)
        begin
            stats.incr(statRemoteBankResp);
        end
        else
        begin
            stats.incr(statRemotePlatformResp);
        end
        
        debugLog.record($format("Scratchpad serviced non-local resp, platform=%d, bank=%d", platform_id, bank_id));
    endrule
endmodule


//
// mkScratchpadConnectorMultiSlave --
//     RRR connection for any slave node in a multi-FPGA configuration.
//     Forward all requests to the master.
//
module [CONNECTED_MODULE] mkScratchpadConnectorMultiSlave#(FIFO#(SCRATCHPAD_RRR_REQ) localReqQ,
                                                           FIFO#(SCRATCHPAD_RRR_LOAD_LINE_RESP) localRespQ,
                                                           Integer scratchpadBankIdx)
    // Interface:
    (Empty)
    provisos (Bits#(SCRATCHPAD_RING_STOP_ID, t_SCRATCH_IDX_SZ),
              Alias#(Bit#(t_SCRATCH_IDX_SZ), t_SCRATCH_IDX));
    
    let platformName <- getSynthesisBoundaryPlatform();
    let platformID   <- getSynthesisBoundaryPlatformID();
    
    SCRATCHPAD_RING_STOP_ID curStopId = tuple2(fromInteger(platformID), fromInteger(scratchpadBankIdx));

    DEBUG_FILE debugLog <- mkDebugFile("memory_scratchpad_ring_" + platformName + "_bank_" + integerToString(scratchpadBankIdx) + ".out");

    CONNECTION_ADDR_RING#(t_SCRATCH_IDX, SCRATCHPAD_RING_REQ) link_mem_req <-
        mkConnectionAddrRingNode("ScratchpadGlobalReq", pack(curStopId));

    CONNECTION_ADDR_RING#(t_SCRATCH_IDX, SCRATCHPAD_RRR_LOAD_LINE_RESP) link_mem_rsp <-
        mkConnectionAddrRingNode("ScratchpadGlobalResp", pack(curStopId));
 
    rule eatReq;
        let req = localReqQ.first();
        localReqQ.deq();

        // patch through requests to base handler.
        link_mem_req.enq(0, SCRATCHPAD_RING_REQ { stopID: curStopId,
                                                  req: req });

        debugLog.record($format("Scratchpad req"));
    endrule
 
    rule eatResp;
        localRespQ.enq(link_mem_rsp.first());
        link_mem_rsp.deq;

        debugLog.record($format("Scratchpad resp"));
    endrule

endmodule
