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
import FIFOF::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_service.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/shared_scratchpad_memory_common.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/dict/PARAMS_SCRATCHPAD_MEMORY_SERVICE.bsh"
`include "awb/dict/VDEV.bsh"
`include "awb/dict/VDEV_SCRATCH.bsh"

// ========================================================================
//
// Shared scratchpad controller with private caches 
//
// ========================================================================

function SCRATCHPAD_PORT_NUM sharedScratchControllerPortId(Integer n);
    return fromInteger(n - `VDEV_SCRATCH__BASE + 1);
endfunction

//
// Interface of uncached shared scratchpad controller's router
//
typedef Tuple2#(SHARED_SCRATCH_REQ#(t_ADDR), SHARED_SCRATCH_CTRLR_PORT_NUM) SHARED_SCRATCH_CACHED_CTRLR_REQ#(type t_ADDR);

interface SHARED_SCRATCH_CACHED_CONTROLLER_ROUTER#(type t_ADDR);
    // response to network
    method Action sendResp(SHARED_SCRATCH_PORT_NUM dest, 
                           SHARED_SCRATCH_CTRLR_PORT_NUM controllerId, 
                           SHARED_SCRATCH_RESP#(t_ADDR) resp);
    // client's request from network
    method ActionValue#(SHARED_SCRATCH_CACHED_CTRLR_REQ#(t_ADDR)) getReq();
    method SHARED_SCRATCH_CACHED_CTRLR_REQ#(t_ADDR) peekReq();
endinterface: SHARED_SCRATCH_CACHED_CONTROLLER_ROUTER

typedef struct
{
    SHARED_SCRATCH_PORT_NUM         requester;
    SHARED_SCRATCH_CTRLR_PORT_NUM   reqControllerId;
    SHARED_SCRATCH_CLIENT_META      clientMeta;
}
SHARED_SCRATCH_CACHED_CTRLR_READ_REQ_INFO
    deriving (Eq, Bits);


typedef Bit#(8) SHARED_SCRATCH_CACHED_CTRLR_MEM_REQ_IDX;

//
// mkCachedSharedScratchpadController --
//     Initialize a controller for a new shared scratchpad memory region.
//
module [CONNECTED_MODULE] mkCachedSharedScratchpadController#(Integer scratchpadID, 
                                                              NumTypeParam#(t_IN_ADDR_SZ) inAddrSz,
                                                              NumTypeParam#(t_IN_DATA_SZ) inDataSz,
                                                              SHARED_SCRATCH_CONTROLLER_CONFIG conf)
    // interface:
    ()
    provisos (// Compute the natural size in bits.  The natural size is rounded up to
              // a power of 2 bits that is one byte or larger.
              Max#(8, TExp#(TLog#(t_IN_DATA_SZ)), t_NATURAL_SZ),
              Bits#(SHARED_SCRATCH_MEM_VALUE, t_SCRATCHPAD_MEM_VALUE_SZ),
              // Compute the container (scratchpad) address size
              NumAlias#(TLog#(TDiv#(t_SCRATCHPAD_MEM_VALUE_SZ, t_NATURAL_SZ)), t_NATURAL_IDX_SZ),
              // Addresses
              NumAlias#(TSub#(t_IN_ADDR_SZ, t_NATURAL_IDX_SZ), t_ADDR_SZ),
              Alias#(Bit#(t_ADDR_SZ), t_ADDR),
              Bits#(SHARED_SCRATCH_MEM_ADDRESS, t_SCRATCHPAD_MEM_ADDRESS_SZ));
    
    String debugLogFilename = "shared_scratchpad_" + integerToString(scratchpadID) + "_controller.out";
    if (conf.debugLogPath matches tagged Valid .log_name)
    begin
        debugLogFilename = log_name;
    end

    DEBUG_FILE debugLog <- (isValid(conf.debugLogPath) || (`SHARED_SCRATCHPAD_DEBUG_ENABLE == 1))?
                           mkDebugFile(debugLogFilename):
                           mkDebugFileNull(debugLogFilename); 
    
    if (valueOf(t_ADDR_SZ) > valueOf(t_SCRATCHPAD_MEM_ADDRESS_SZ))
    begin
        error("Cached shared scratchpad address size is not big enough. Increase parameter SHARED_SCRATCHPAD_MEMORY_ADDR_BITS.");
    end
    
    // =======================================================================
    //
    // Scratchpad controller partition module
    //
    // =======================================================================
    
    let partition <- conf.partition();

    // =======================================================================
    //
    // Cached shared scratchpad controller router
    //
    // =======================================================================
    
    SHARED_SCRATCH_CACHED_CONTROLLER_ROUTER#(t_ADDR) router;

`ifndef SHARED_SCRATCHPAD_MULTI_CONTROLLER_ENABLE_Z

    router <- (!conf.multiController)? mkCachedSharedScratchpadSingleControllerRouter(scratchpadID, debugLog):
                                       mkCachedSharedScratchpadMultiControllerRouter(scratchpadID, conf.sharedDomainID, 
                                                                                     partition.isLocalReq, conf.isMaster, debugLog);
`else
    
    if (conf.multiController)
    begin
        error("SHARED_SCRATCHPAD_MULTI_CONTROLLER_ENABLE is not enabled");
    end
    router <- mkCachedSharedScratchpadSingleControllerRouter(scratchpadID, debugLog);

`endif

    // =======================================================================
    //
    // Connections to the platform-level scratchpad controller
    //
    // =======================================================================

    let my_port = sharedScratchControllerPortId(scratchpadID);
    let platformID <- getSynthesisBoundaryPlatformID();

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_MEM_REQ) link_mem_req <-
        mkConnectionTokenRingNode("Scratchpad_Platform_" + integerToString(platformID) + "_Req", my_port);

    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_READ_RSP) link_mem_rsp <-
        mkConnectionTokenRingNode("Scratchpad_Platform_" + integerToString(platformID) + "_Resp", my_port);

    Reg#(Bool) initialized <- mkReg(False);

    //
    // Allocate memory for this shared scratchpad region
    //
    rule doInit (! initialized);
        initialized <= True;
        
        Bit#(t_ADDR_SZ) alloc = maxBound;
        SCRATCHPAD_INIT_REQ r;
        r.port = my_port;
        r.allocLastWordIdx = zeroExtendNP(alloc);
        r.cached = True;
        r.initFilePath = conf.initFilePath;
        link_mem_req.enq(0, tagged SCRATCHPAD_MEM_INIT r);

        debugLog.record($format("sharedScratchpadController: init ID %0d: last word idx 0x%x", my_port, r.allocLastWordIdx));
    endrule

    // =======================================================================
    //
    // Forward clients' requests/responses to/from the platform-level 
    // scratchpad controller
    //
    // =======================================================================

    MEMORY_HEAP#(SHARED_SCRATCH_CACHED_CTRLR_MEM_REQ_IDX, SHARED_SCRATCH_CACHED_CTRLR_READ_REQ_INFO) reqInfo <- mkMemoryHeapUnionBRAM();
    FIFOF#(Tuple2#(SHARED_SCRATCH_PORT_NUM, SHARED_SCRATCH_CTRLR_PORT_NUM)) ackRespQ <- mkBypassFIFOF();
    FIFOF#(Tuple3#(SHARED_SCRATCH_PORT_NUM, SHARED_SCRATCH_CTRLR_PORT_NUM, SHARED_SCRATCH_READ_RESP#(t_ADDR))) memRespQ  <- mkBypassFIFOF();
    FIFOF#(Tuple3#(SHARED_SCRATCH_PORT_NUM, SHARED_SCRATCH_CTRLR_PORT_NUM, SHARED_SCRATCH_RESP#(t_ADDR))) outputRespQ    <- mkSizedFIFOF(8);

    //
    // forwardClientReq --
    //     Collect scratchpad client requests from the router.
    // Forward client requests to platform-side scratchpad. 
    // For write and fence requests, send ack back to the clients. 
    //
    rule forwardClientReq (True);
        let client_req <- router.getReq();
        match {.req, .controller_id} = client_req;
        if (req.reqInfo matches tagged SHARED_SCRATCH_READ .read_info)
        begin
            let mem_req_idx <- reqInfo.malloc();
            let mem_req = SCRATCHPAD_READ_REQ { port: my_port,
                                                addr: zeroExtendNP(pack(req.addr)),
                                                byteReadMask: replicate(True),
                                                readUID: zeroExtendNP(pack(mem_req_idx)),
                                                globalReadMeta: read_info.globalReadMeta };
            
            link_mem_req.enq(0, tagged SCRATCHPAD_MEM_READ mem_req);

            let mem_req_info = SHARED_SCRATCH_CACHED_CTRLR_READ_REQ_INFO { requester: req.requester, 
                                                                           reqControllerId: controller_id,
                                                                           clientMeta: read_info.clientMeta }; 
            reqInfo.write(mem_req_idx, mem_req_info);
            
            debugLog.record($format("  forward READ request: sender=%d, addr=0x%x, meta=0x%x, new_meta=0x%x",  
                            req.requester, req.addr, read_info.clientMeta, mem_req_idx));
        end
        else if (req.reqInfo matches tagged SHARED_SCRATCH_WRITE .write_info)
        begin
            let mem_req = SCRATCHPAD_WRITE_REQ { port: my_port,
                                                 addr: zeroExtendNP(pack(req.addr)),
                                                 val: write_info.data };
            link_mem_req.enq(0, tagged SCRATCHPAD_MEM_WRITE mem_req);
            ackRespQ.enq(tuple2(req.requester, controller_id));
            debugLog.record($format("  forward WRITE request: sender=%d, addr=0x%x, data=0x%x", 
                            req.requester, req.addr, write_info.data));
        end
    endrule

    FIFO#(SCRATCHPAD_READ_REQ) reqInfoReadReqQ <- mkFIFO();

    rule recvDataResp (True);
        let s = link_mem_rsp.first();
        link_mem_rsp.deq();
        reqInfo.readReq(unpack(truncateNP(s.readUID)));
        reqInfoReadReqQ.enq(s);
        debugLog.record($format("    recvDataResp: receive resp from platform: data=0x%x, meta=0x%x", 
                        s.val, s.readUID));
    endrule

    rule sendReadResp (True);
        let meta <- reqInfo.readRsp();
        reqInfo.free(unpack(trucateNP(s.readUID)));
        memRespQ.enq(tuple3(meta.requester, meta.reqControllerId, SHARED_SCRATCH_READ_RESP { addr: s.addr,
                                                                                             val: s.val,
                                                                                             clientMeta: meta.clientMeta, 
                                                                                             globalReadMeta: s.globalReadMeta, 
                                                                                             isCacheable: s.isCacheable}));
        debugLog.record($format("    sendDataResp: dest=%03d, controllerId=%02d, val=0x%x, meta=0x%x", 
                        meta.requester, meta.reqControllerId, s.val, meta.clientMeta));
    endrule

    Reg#(Bit#(2)) ackRespArb <- mkReg(0);

    (* fire_when_enabled *)
    rule sendToOutputRespQ (True);
        if (ackRespQ.notEmpty() && ((ackRespArb != 0) || !memRespQ.notEmpty()))
        begin
            match {.client_id, .controller_id} = ackRespQ.first();
            ackRespQ.deq();
            outputRespQ.enq(tuple3(client_id, controller_id, tagged CACHED_WRITE_ACK));    
            debugLog.record($format("    sendToOutputRespQ: WRITE ACK response: dest=%03d, controllerId=%02d", 
                            client_id, controller_id)); 
        end
        else
        begin
            let mem_resp = memRespQ.first();
            memRespQ.deq();
            outputRespQ.enq(tuple3(tpl_1(mem_resp), tpl_2(mem_resp), tagged CACHED_READ_RESP tpl_3(mem_resp)));
            debugLog.record($format("    sendToOutputRespQ: READ DATA response: dest=%03d, controllerId=%02d, val=0x%x, meta=0x%x",
                            tpl_1(mem_resp), tpl_2(mem_resp), tpl_3(mem_resp).val, tpl_3(mem_resp).clientMeta));
        end
        ackRespArb <= ackRespArb + 1;
    endrule

    (* fire_when_enabled *)
    rule sendSharedScratchpadResp (True);
        let resp = outputRespQ.first();
        outputRespQ.deq();
        router.sendResp(tpl_1(resp), tpl_2(resp), tpl_3(resp));
    endrule

    // // =======================================================================
    // //
    // // Connections to its local clients
    // //
    // // =======================================================================

    // String localClientRingName = "Shared_Scratchpad_" + integerToString(scratchpadID);
    // 
    // // Addressable ring
    // CONNECTION_ADDR_RING#(SHARED_SCRATCH_PORT_NUM, SCRATCHPAD_MEM_REQ) local_mem_req <- 
    //     mkConnectionAddrRingNode(localClientRingName + "_Req", 0);

    // // Addressable ring
    // CONNECTION_ADDR_RING#(SHARED_SCRATCH_PORT_NUM, SCRATCHPAD_READ_RSP) local_mem_resp <-
    //     mkConnectionAddrRingNode(localClientRingName + "_Resp", 0);

endmodule

//
// mkCachedSharedScratchpadMultiControllerRouter --
//     This module handles the situation where there are private caches
//     in this shared memory region. 
//
//     The controller router collects requests from its local clients, forwards 
//     local requests to its local controller and forwards the rest to the 
//     remote controller(s). The router also forwards associated responses 
//     to its local clients. 
//
module [CONNECTED_MODULE] mkCachedSharedScratchpadMultiControllerRouter#(Integer dataScratchpadID,
                                                                         Integer sharedDomainID,  
                                                                         function Bool isLocalReq(SHARED_SCRATCH_MEM_ADDRESS addr),
                                                                         Bool isMaster,
                                                                         DEBUG_FILE debugLog)
    // interface:
    (SHARED_SCRATCH_CACHED_CONTROLLER_ROUTER#(t_ADDR))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              // request/response messages
              Alias#(SHARED_SCRATCH_REQ#(t_ADDR), t_SHARED_SCRATCH_REQ),
              Alias#(SHARED_SCRATCH_RESP#(t_ADDR), t_SHARED_SCRATCH_RESP),
              Alias#(SHARED_SCRATCH_CACHED_CTRLR_REQ#(t_ADDR), t_CTRLR_REQ),
              Alias#(SHARED_SCRATCH_CONTROLLERS_REQ#(t_ADDR), t_CONTROLLERS_REQ),
              Alias#(SHARED_SCRATCH_CONTROLLERS_RESP#(t_ADDR), t_CONTROLLERS_RESP));
    
    FIFOF#(t_CTRLR_REQ) remoteReqQ <- mkFIFOF();
    FIFOF#(Tuple3#(SHARED_SCRATCH_PORT_NUM, SHARED_SCRATCH_CTRLR_PORT_NUM, t_SHARED_SCRATCH_RESP)) localMemRespQ <- mkBypassFIFOF();
    
    // ==============================================================================
    //
    // Shared scratchpad clients and this controller are connected via rings.
    //
    // Two rings are required to avoid deadlocks: one for requests, one for responses.
    //
    // For multi-controller settings, hierarchical rings are used, which means
    // controllers are also connected via two rings.
    //
    // To prevent deadlocks, the broadcast request ring require 2 channels and the 
    // dateline technique is used to avoid circular dependency. 
    // Dateline is allocated at the master controller. 
    //
    // ===============================================================================

    //
    // Connections between the uncached shared scratchpad controller and its local clients
    //
    String clientControllerRingName = "Cached_Shared_Scratchpad_" + integerToString(dataScratchpadID);
    
    // Addressable ring
    CONNECTION_ADDR_RING#(SHARED_SCRATCH_PORT_NUM, t_SHARED_SCRATCH_REQ) link_mem_req <- 
        (`SHARED_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode(clientControllerRingName + "_Req", 0):
        mkConnectionTokenRingNode(clientControllerRingName + "_Req", 0);

    // Addressable ring
    CONNECTION_ADDR_RING#(SHARED_SCRATCH_PORT_NUM, t_SHARED_SCRATCH_RESP) link_mem_resp <-
        (`SHARED_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode(clientControllerRingName + "_Resp", 0):
        mkConnectionTokenRingNode(clientControllerRingName + "_Resp", 0);

    //
    // Connections between multiple controllers
    //
    String controllersRingName = "Cached_Shared_Scratchpad_Controllers_" + integerToString(sharedDomainID);
    
    // Broadcast ring (with 2 channels)
    Vector#(2, CONNECTION_CHAIN#(t_CONTROLLERS_REQ)) links_controllers_req = newVector();
    links_controllers_req[0] <- mkConnectionChain(controllersRingName + "_Req_0");
    links_controllers_req[1] <- mkConnectionChain(controllersRingName + "_Req_1");

    // Addressable ring
    CONNECTION_ADDR_RING#(SHARED_SCRATCH_CTRLR_PORT_NUM, t_CONTROLLERS_RESP) link_controllers_resp <- (isMaster)?
        mkConnectionAddrRingNodeNtoN(controllersRingName + "_Resp", 0):
        mkConnectionAddrRingDynNodeNtoN(controllersRingName + "_Resp");

    Reg#(SHARED_SCRATCH_CTRLR_PORT_NUM) controllerPort <- mkReg(0);
    Reg#(Bool) initialized <- mkReg(False);
    
    rule doInit (!initialized);
        let port_num = link_controllers_resp.nodeID();
        debugLog.record($format("    router: assigned controller port ID = %02d", port_num));
        controllerPort <= port_num;
        initialized    <= True;
    endrule
    
    // =======================================================================
    //
    // Remote requests (from clients or from global request ring)
    //  (1) local: forward to the local controller
    //  (2) non-local: forward to the link_controllers_req ring
    //
    // =======================================================================
    
    PulseWire   clientReqLocalW             <- mkPulseWire();
    PulseWire   clientReqRemoteW            <- mkPulseWire();
    PulseWire   localReqToRemoteW           <- mkPulseWire();
    Vector#(2, PulseWire) networkReqLocalW  <- replicateM(mkPulseWire());
    Vector#(2, PulseWire) networkReqRemoteW <- replicateM(mkPulseWire());
    LOCAL_ARBITER#(3) reqRecvArb            <- mkLocalArbiter();
    Wire#(Bit#(2)) pickLocalReqIdx          <- mkWire();
    Reg#(Bool) reqFwdArb                    <- mkReg(True);

    (* fire_when_enabled *)
    rule checkClientReq (True);
        let req  = link_mem_req.first();
        let addr = req.addr;
        Bool is_local = isLocalReq(zeroExtendNP(pack(addr)));
        Bool is_read = False;
        if (req.reqInfo matches tagged SHARED_SCRATCH_READ .info)
        begin
            is_read = True;
        end
        debugLog.record($format("    router: check a request from client: addr=0x%x, %s %s request", 
                        addr, is_local? "local" : "remote", is_read? "READ" : "WRITE" ));
        if (is_local)
        begin
            clientReqLocalW.send();
        end
        else
        begin
            clientReqRemoteW.send();
        end
    endrule

    for(Integer p = 0; p < 2; p = p + 1)
    begin
        (* fire_when_enabled *)
        rule checkGlobalRingReq (True);
            let req = links_controllers_req[p].peekFromPrev();
            let addr = req.reqLocal.addr;
            Bool is_local = isLocalReq(zeroExtendNP(pack(addr)));
            Bool is_read = False;
            if (req.reqLocal.reqInfo matches tagged SHARED_SCRATCH_READ .info)
            begin
                is_read = True;
            end
            debugLog.record($format("    router: check a request from global chain[%01d]: addr=0x%x, %s %s request, requester=%03d, reqControllerId=%02d",
                            p, addr, is_local? "local" : "remote", is_read? "READ" : "WRITE", req.reqLocal.requester, req.reqControllerId));
            if (is_local)
            begin
                networkReqLocalW[p].send();
            end
            else
            begin
                networkReqRemoteW[p].send();
            end
        endrule
    end

    (* fire_when_enabled *)
    rule pickLocalReq (initialized);
        LOCAL_ARBITER_CLIENT_MASK#(3) reqs = newVector();
        reqs[0] = clientReqLocalW;
        reqs[1] = networkReqLocalW[0];
        reqs[2] = networkReqLocalW[1];
        let winner_idx <- reqRecvArb.arbitrate(reqs, False);
        if (winner_idx matches tagged Valid .req_idx)
        begin
            pickLocalReqIdx <= pack(req_idx);
        end
    endrule

    (* fire_when_enabled *)
    rule recvLocalReqFromClient (initialized && pickLocalReqIdx == 0);
        let req = link_mem_req.first(); 
        link_mem_req.deq(); 
        remoteReqQ.enq(tuple2(req, controllerPort));
        debugLog.record($format("    router: receive a local request from %s, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        "clients", req.addr, req.requester, controllerPort));
    endrule

    (* fire_when_enabled *)
    rule recvLocalReqFromGlobalChain0 (initialized && pickLocalReqIdx == 1);
        let req <- links_controllers_req[0].recvFromPrev();
        remoteReqQ.enq(tuple2(req.reqLocal, req.reqControllerId));
        debugLog.record($format("    router: receive a local request from %s, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        "global chain 0", req.reqLocal.addr, req.reqLocal.requester, req.reqControllerId));
    endrule

    (* fire_when_enabled *)
    rule recvLocalReqFromGlobalChain1 (initialized && pickLocalReqIdx == 2);
        let req <- links_controllers_req[1].recvFromPrev();
        remoteReqQ.enq(tuple2(req.reqLocal, req.reqControllerId));
        debugLog.record($format("    router: receive a local request from %s, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        "global chain 1", req.reqLocal.addr, req.reqLocal.requester, req.reqControllerId));
    endrule

    (* fire_when_enabled *)
    rule fwdLocalReqToChain0NonMaster (!isMaster && initialized && clientReqRemoteW && (reqFwdArb || !networkReqRemoteW[0]));
        let req = link_mem_req.first();
        link_mem_req.deq();
        let controller_req = SHARED_SCRATCH_CONTROLLERS_REQ { reqControllerId: controllerPort, 
                                                              reqLocal: req };
        links_controllers_req[0].sendToNext(controller_req);
        reqFwdArb <= False;
        localReqToRemoteW.send();
        debugLog.record($format("    router: forward client's request to global chain 0, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.addr, req.requester, controller_req.reqControllerId));
    endrule

    (* mutually_exclusive = "fwdLocalReqToChain0NonMaster, fwdRemoteReqToChain0NonMaster" *)
    (* fire_when_enabled *)
    rule fwdRemoteReqToChain0NonMaster (!isMaster && initialized && !localReqToRemoteW && networkReqRemoteW[0]);
        let req <- links_controllers_req[0].recvFromPrev();
        links_controllers_req[0].sendToNext(req);
        reqFwdArb <= True;
        debugLog.record($format("    router: forward a global request to global chain 0, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.reqLocal.addr, req.reqLocal.requester, req.reqControllerId));
    endrule

    (* mutually_exclusive = "recvLocalReqFromGlobalChain1, fwdReqToChain1NonMaster" *)
    (* fire_when_enabled *)
    rule fwdReqToChain1NonMaster (!isMaster && networkReqRemoteW[1]);
        let req <- links_controllers_req[1].recvFromPrev();
        links_controllers_req[1].sendToNext(req);
        debugLog.record($format("    router: forward a global request to global chain 1, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.reqLocal.addr, req.reqLocal.requester, req.reqControllerId));
    endrule

    (* mutually_exclusive = "recvLocalReqFromClient, fwdReqToChain0Master, fwdLocalReqToChain0NonMaster" *)
    (* fire_when_enabled *)
    rule fwdReqToChain0Master (isMaster && clientReqRemoteW);
        let req = link_mem_req.first();
        link_mem_req.deq();
        let controller_req = SHARED_SCRATCH_CONTROLLERS_REQ { reqControllerId: controllerPort, 
                                                              reqLocal: req };
        links_controllers_req[0].sendToNext(controller_req);
        debugLog.record($format("    router: forward client's request to global chain 0, addr=0x%x, requester=%03d, reqControllerId=%02d",
                        req.addr, req.requester, controller_req.reqControllerId));
    endrule
    
    (* mutually_exclusive = "recvLocalReqFromGlobalChain0, fwdReqToChain1Master, fwdRemoteReqToChain0NonMaster" *)
    (* fire_when_enabled *)
    rule fwdReqToChain1Master (isMaster && networkReqRemoteW[0]);
        let req <- links_controllers_req[0].recvFromPrev();
        links_controllers_req[1].sendToNext(req);
        debugLog.record($format("    router: forward global unactivated request to global chain 1, addr =0x%x, requester=%03d, reqControllerId=%02d",
                        req.reqLocal.addr, req.reqLocal.requester, req.reqControllerId));
    endrule


    // =======================================================================
    //
    // Responses
    //
    // (1) Responses from local memory 
    // (2) Responses from remote memories
    //
    // =======================================================================
    
    Reg#(Bool)  localRespArb      <- mkReg(True);
    PulseWire   memoryLocalRespW  <- mkPulseWire();

    (* fire_when_enabled *)
    rule memoryFwdResp (tpl_2(localMemRespQ.first()) != controllerPort);
        match {.client_id, .controller_id, .resp} = localMemRespQ.first();
        localMemRespQ.deq();
        link_controllers_resp.enq(controller_id, SHARED_SCRATCH_CONTROLLERS_RESP{ clientId: client_id, resp: resp});
        debugLog.record($format("    router: forward memory response to remote response network, dest=%03d, controller=%02d",
                        client_id, controller_id));
    endrule

    (* fire_when_enabled *)
    rule memoryLocalResp (tpl_2(localMemRespQ.first()) == controllerPort && (localRespArb || !link_controllers_resp.notEmpty()));
        match {.client_id, .controller_id, .resp} = localMemRespQ.first();
        localMemRespQ.deq();
        link_mem_resp.enq(client_id, resp);
        localRespArb <= False;
        memoryLocalRespW.send();
        debugLog.record($format("    router: send memory response to local response network, dest=%03d, controller=%02d",
                        client_id, controller_id));
    endrule

    (* mutually_exclusive = "memoryLocalResp, remoteToLocalResp" *)
    (* fire_when_enabled *)
    rule remoteToLocalResp (!memoryLocalRespW);
        let controller_resp = link_controllers_resp.first();
        link_controllers_resp.deq();
        link_mem_resp.enq(controller_resp.clientId, controller_resp.resp);
        localRespArb <= True;
        debugLog.record($format("    router: send remote response to local response network, dest=%03d, controller=%02d",
                        controller_resp.clientId, controllerPort));
    endrule
    
    // =======================================================================
    //
    // Methods
    //
    // =======================================================================
    
    method Action sendResp(SHARED_SCRATCH_PORT_NUM dest, 
                           SHARED_SCRATCH_CTRLR_PORT_NUM controllerId, 
                           SHARED_SCRATCH_RESP#(t_ADDR) resp);
        localMemRespQ.enq(tuple3(dest, controllerId, resp));
        debugLog.record($format("    router: receive a controller response, dest=%03d, controllerId=%02d", 
                        dest, controllerId));
    endmethod
    
    method ActionValue#(SHARED_SCRATCH_CACHED_CTRLR_REQ#(t_ADDR)) getReq();
        let r = remoteReqQ.first();
        remoteReqQ.deq();
        return r;
    endmethod

    method SHARED_SCRATCH_CACHED_CTRLR_REQ#(t_ADDR) peekReq();
        return remoteReqQ.first();
    endmethod

endmodule

//
// mkCachedSharedScratchpadSingleControllerRouter --
//     This module handles the situation where there are private caches
//     in this shared memory region. 
//
//     The controller router collects read/write requests from shared 
//     scratchpad clients and send responses back to the clients. 
//
module [CONNECTED_MODULE] mkCachedSharedScratchpadSingleControllerRouter#(Integer dataScratchpadID,
                                                                          DEBUG_FILE debugLog)
    // interface:
    (SHARED_SCRATCH_CACHED_CONTROLLER_ROUTER#(t_ADDR))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              // request/response messages
              Alias#(SHARED_SCRATCH_REQ#(t_ADDR), t_SHARED_SCRATCH_REQ),
              Alias#(SHARED_SCRATCH_RESP#(t_ADDR), t_SHARED_SCRATCH_RESP));
    
    FIFOF#(t_SHARED_SCRATCH_REQ) remoteReqQ <- mkFIFOF();
    FIFOF#(Tuple2#(SHARED_SCRATCH_PORT_NUM, t_SHARED_SCRATCH_RESP)) localMemRespQ <- mkBypassFIFOF();

    // ===============================================================================
    //
    // Shared scratchpad clients and this controller are connected via rings.
    //
    // Two rings are required to avoid deadlocks: one for requests, one for responses.
    //
    // ===============================================================================

    String clientControllerRingName = "Cached_Shared_Scratchpad_" + integerToString(dataScratchpadID);
    
    // Addressable ring
    CONNECTION_ADDR_RING#(SHARED_SCRATCH_PORT_NUM, t_SHARED_SCRATCH_REQ) link_mem_req <- 
        (`SHARED_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode(clientControllerRingName + "_Req", 0):
        mkConnectionTokenRingNode(clientControllerRingName + "_Req", 0);

    // Addressable ring
    CONNECTION_ADDR_RING#(SHARED_SCRATCH_PORT_NUM, t_SHARED_SCRATCH_RESP) link_mem_resp <-
        (`SHARED_SCRATCHPAD_REQ_RESP_LINK_TYPE == 0) ?
        mkConnectionAddrRingNode(clientControllerRingName + "_Resp", 0):
        mkConnectionTokenRingNode(clientControllerRingName + "_Resp", 0);

    //
    // collectClientReq --
    //     Collect scratchpad client requests from the router.
    // For write and fence requests, send ack back to the clients. 
    //
    (* fire_when_enabled *)
    rule colletClientReq (True);
        let req = link_mem_req.first();
        link_mem_req.deq();
        debugLog.record($format("    router: receive a client request: sender=%03d, addr=0x%x",
                        req.requester, req.addr));
        remoteReqQ.enq(req);
    endrule
    
    // =======================================================================
    //
    // Responses
    //
    // =======================================================================
    
    (* fire_when_enabled *)
    rule sendResponse (True);
        let resp = localMemRespQ.first();
        localMemRespQ.deq();
        debugLog.record($format("    router: send a controller response: dest=%03d", tpl_1(resp)));
        link_mem_resp.enq(tpl_1(resp), tpl_2(resp));
    endrule

    // =======================================================================
    //
    // Methods
    //
    // =======================================================================
    
    method Action sendResp(SHARED_SCRATCH_PORT_NUM dest, 
                           SHARED_SCRATCH_CTRLR_PORT_NUM controllerId, 
                           SHARED_SCRATCH_RESP#(t_ADDR) resp);
        localMemRespQ.enq(tuple2(dest,resp));
        debugLog.record($format("    router: receive a controller response, dest=%03d", dest));
    endmethod
    
    method ActionValue#(SHARED_SCRATCH_CACHED_CTRLR_REQ#(t_ADDR)) getReq();
        let r = remoteReqQ.first();
        remoteReqQ.deq();
        return tuple2(r, ?);
    endmethod

    method SHARED_SCRATCH_CACHED_CTRLR_REQ#(t_ADDR) peekReq();
        return tuple2(remoteReqQ.first(), ?);
    endmethod

endmodule

