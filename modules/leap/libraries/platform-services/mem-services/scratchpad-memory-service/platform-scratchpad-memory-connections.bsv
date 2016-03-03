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

//
// Scratchpad memory connections.
//

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import DefaultValue::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/soft_connections_util.bsh"
`include "awb/provides/stats_service.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/scratchpad_memory.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/provides/local_mem_interface.bsh"
`include "awb/provides/local_mem.bsh"

`include "awb/dict/PARAMS_SCRATCHPAD_MEMORY_SERVICE.bsh"

//
// mkScratchpadClientRingConnector --
//     Connect a scratchpad client to multiple controller rings. Requests
//     are forwarded based on address partitioning. 
//
module [CONNECTED_MODULE] mkScratchpadClientRingConnector#(String clientReqRingName,
                                                           String clientRespRingName,
                                                           SCRATCHPAD_PORT_NUM portNum, 
                                                           Vector#(n_CONTROLLERS, String) controllerReqRingNames, 
                                                           Vector#(n_CONTROLLERS, String) controllerRespRingNames, 
                                                           function UInt#(TLog#(n_CONTROLLERS)) getControllerIdxFromAddr(SCRATCHPAD_MEM_ADDRESS addr))
    (Empty)
    provisos (NumAlias#(TMax#(LOCAL_MEM_BURST_DATA_SZ, LOCAL_MEM_LINE_SZ), t_LOCAL_MEM_DATA_SZ),
              Add#(a_, SCRATCHPAD_MEM_VALUE_SZ, t_LOCAL_MEM_DATA_SZ),
              NumAlias#(TLog#(TDiv#(t_LOCAL_MEM_DATA_SZ, SCRATCHPAD_MEM_VALUE_SZ)), t_LOCAL_MEM_DATA_IDX_SZ),
              NumAlias#(TDiv#(LOCAL_MEM_LINE_SZ, SCRATCHPAD_MEM_VALUE_SZ), t_WORDS_PER_LINE),
              Alias#(Bit#(t_LOCAL_MEM_DATA_IDX_SZ), t_LOCAL_MEM_DATA_IDX),
              Bits#(SCRATCHPAD_MEM_ADDRESS, t_ADDR_SZ),
              Bits#(SCRATCHPAD_MEM_REQ, t_SCRATCHPAD_MEM_REQ_SZ), 
              Bits#(SCRATCHPAD_READ_RSP, t_SCRATCHPAD_READ_RSP_SZ), 
              NumAlias#(TSub#(t_ADDR_SZ, t_LOCAL_MEM_DATA_IDX_SZ), t_LOCAL_MEM_ADDR_SZ),
              Alias#(Bit#(t_LOCAL_MEM_ADDR_SZ), t_LOCAL_MEM_ADDR));

    // Connection node on the client ring
    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, Bit#(t_SCRATCHPAD_MEM_REQ_SZ)) link_client_req <- 
        mkConnectionAddrRingNode(clientReqRingName, 0);
    
    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, Bit#(t_SCRATCHPAD_READ_RSP_SZ)) link_client_rsp <- 
        mkConnectionAddrRingNode(clientRespRingName, 0);

    // Connection nodes on controller rings
    Vector#(n_CONTROLLERS, CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, Bit#(t_SCRATCHPAD_MEM_REQ_SZ))) link_ctrl_reqs = newVector();
    Vector#(n_CONTROLLERS, CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, Bit#(t_SCRATCHPAD_READ_RSP_SZ))) link_ctrl_rsps = newVector();   

    DEBUG_FILE debugLog <- mkDebugFile("scratchpad_connector_" + clientReqRingName + ".out");
    
    // Dynamic parameters
    PARAMETER_NODE   paramNode  <- mkDynamicParameterNode();
    Param#(2) addrMapModeParam  <- mkDynamicParameter(`PARAMS_SCRATCHPAD_MEMORY_SERVICE_SCRATCHPAD_ADDR_MAP_MODE, paramNode);
    Reg#(Bit#(2))  addrMapMode  <- mkReg(0);

    // address map pre-processing function
    function SCRATCHPAD_MEM_ADDRESS addrMap (SCRATCHPAD_MEM_ADDRESS addr);
        if (addrMapMode[0] == 0)
        begin
            Tuple2#(t_LOCAL_MEM_ADDR, t_LOCAL_MEM_DATA_IDX) local_addr = unpack(addr);
            //let a = (addrMapMode[1] == 0)? tpl_1(local_addr) :  hashBits(tpl_1(local_addr));
            Bit#(10) a1 = resize(tpl_1(local_addr));
            let a2 = (addrMapMode[1] == 0)? a1 :  hashBits(a1);
            return zeroExtend(a2); 
        end
        else
        begin
            Tuple2#(Bit#(TSub#(t_ADDR_SZ, TLog#(t_WORDS_PER_LINE))), Bit#(TLog#(t_WORDS_PER_LINE))) local_addr = unpack(addr); 
            //let a = (addrMapMode[1] == 0)? tpl_1(local_addr) :  hashBits(tpl_1(local_addr));
            let a = tpl_1(local_addr);
            return zeroExtend(a); 
        end
    endfunction

    for (Integer p = 0; p < valueOf(n_CONTROLLERS); p = p + 1)
    begin
        link_ctrl_reqs[p] <- mkConnectionAddrRingNode(controllerReqRingNames[p], portNum);
        link_ctrl_rsps[p] <- mkConnectionAddrRingNode(controllerRespRingNames[p], portNum);
    end
    
    // Initialization
    Reg#(Bool) initialized <- mkReg(False);
    rule doInit (! initialized);
        addrMapMode <= addrMapModeParam;
        initialized <= True;
    endrule
        
    rule sendScratchpadReq (initialized);
        SCRATCHPAD_MEM_REQ req = unpack(link_client_req.first());
        link_client_req.deq();

        case (req) matches
            tagged SCRATCHPAD_MEM_INIT .init:
            begin
                link_ctrl_reqs[0].enq(0, pack(req));
                debugLog.record($format("sendScratchpadReq: forward master INIT req to controller %d", 0));
                for (Integer p = 1; p < valueOf(n_CONTROLLERS); p = p + 1)
                begin
                    let slave_init = init;
                    slave_init.initCacheOnly = True;
                    link_ctrl_reqs[p].enq(0, pack(tagged SCRATCHPAD_MEM_INIT slave_init));
                    debugLog.record($format("sendScratchpadReq: forward slave INIT req to controller %d", p));
                end
            end

            tagged SCRATCHPAD_MEM_READ .r_req:
            begin
                let idx = getControllerIdxFromAddr(addrMap(r_req.addr));
                link_ctrl_reqs[idx].enq(0, pack(req));
                debugLog.record($format("sendScratchpadReq: forward READ req to controller %d, addr=0x%x", idx, r_req.addr));
            end

            tagged SCRATCHPAD_MEM_WRITE .w_req:
            begin
                let idx = getControllerIdxFromAddr(addrMap(w_req.addr));
                link_ctrl_reqs[idx].enq(0, pack(req));
                debugLog.record($format("sendScratchpadReq: forward WRITE req to controller %d, addr=0x%x", idx, w_req.addr));
            end

            tagged SCRATCHPAD_MEM_WRITE_MASKED .w_req:
            begin
                let idx = getControllerIdxFromAddr(addrMap(w_req.addr));
                link_ctrl_reqs[idx].enq(0, pack(req));
                debugLog.record($format("sendScratchpadReq: forward WRITE req to controller %d, addr=0x%x", idx, w_req.addr));
            end
        endcase
    endrule
    
    Rules resp_rules = emptyRules; 
    
    for (Integer c = 0; c < valueOf(n_CONTROLLERS); c = c + 1)
    begin 
        let resp_fwd = 
            (rules 
                 rule sendScratchpadResp (initialized); 
                     SCRATCHPAD_READ_RSP resp = unpack(link_ctrl_rsps[c].first());
                     link_ctrl_rsps[c].deq();
                     link_client_rsp.enq(portNum, pack(resp));
                     debugLog.record($format("sendScratchpadResp: forward response from controller %d, addr=0x%x, val=0x%x", c, resp.addr, resp.val));
                 endrule 
            endrules); 
        resp_rules = rJoinDescendingUrgency(resp_rules,resp_fwd); 
    end 
    
    addRules(resp_rules); 

endmodule

//
// mkScratchpadHierarchicalRingConnector --
//     Connect a scratchpad ring to another. This is used in 
// hierarchical-ring networks. 
//
module [CONNECTED_MODULE] mkScratchpadHierarchicalRingConnector#(String childReqRingName,
                                                                 String childRespRingName,
                                                                 String parentReqRingName, // next-level client ring
                                                                 String parentRespRingName, 
                                                                 function Bool isChildNode(SCRATCHPAD_PORT_NUM nodeID))
    // interface:
    (Empty)
    provisos (Bits#(SCRATCHPAD_PORT_NUM, t_NODE_ID_SZ),
              Bits#(SCRATCHPAD_READ_RSP, t_RSP_SZ), 
              Bits#(SCRATCHPAD_MEM_REQ,  t_REQ_SZ));

    NumTypeParam#(t_NODE_ID_SZ) nodeIdSz = ?; 
    NumTypeParam#(t_RSP_SZ) rspSz = ?; 
    NumTypeParam#(t_REQ_SZ) reqSz = ?; 

    mkConnectionHierarchicalAddrRingConnector(childReqRingName, parentReqRingName, nodeIdSz, reqSz, isChildNode, `PLATFORM_SCRATCHPAD_PROFILE_ENABLE == 1);
    mkConnectionHierarchicalAddrRingConnector(childRespRingName, parentRespRingName, nodeIdSz, rspSz, isChildNode, `PLATFORM_SCRATCHPAD_PROFILE_ENABLE == 1);

endmodule


//
//  mkScratchpadTreeLeafNodeConnector --
//      Connect a scratchpad to a tree leaf node. 
//
module [CONNECTED_MODULE] mkScratchpadTreeLeafNodeConnector#(String clientReqRingName,
                                                             String clientRespRingName,
                                                             SCRATCHPAD_PORT_NUM portNum)
    (CONNECTION_ADDR_TREE#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_MEM_REQ, SCRATCHPAD_READ_RSP))
    provisos (Bits#(SCRATCHPAD_MEM_REQ, t_SCRATCHPAD_MEM_REQ_SZ), 
              Bits#(SCRATCHPAD_READ_RSP, t_SCRATCHPAD_READ_RSP_SZ));

    // Connection node on the client ring
    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, Bit#(t_SCRATCHPAD_MEM_REQ_SZ)) link_client_req <- 
        mkConnectionAddrRingNode(clientReqRingName, 0);
    CONNECTION_ADDR_RING#(SCRATCHPAD_PORT_NUM, Bit#(t_SCRATCHPAD_READ_RSP_SZ)) link_client_rsp <- 
        mkConnectionAddrRingNode(clientRespRingName, 0);

    // Outgoing portion of the tree network
    method Action enq(TREE_MSG#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_READ_RSP) resp);
         link_client_rsp.enq(portNum, pack(resp.data));
    endmethod

    method Bool notFull() = link_client_rsp.notFull();

    // Incoming portion of the tree network
    method SCRATCHPAD_MEM_REQ first();
        return unpack(link_client_req.first());
    endmethod
    method Action deq();
        link_client_req.deq;
    endmethod
    method Bool notEmpty() = link_client_req.notEmpty();

endmodule

//
//  mkScratchpadTreeRoot --
//      Scratchpad tree root module that connects a scratchpad controller to the rest 
//  scratchpad tree nodes.
//
module [CONNECTED_MODULE] mkScratchpadTreeRoot#(String controllerReqRingName,
                                                String controllerRespRingName,
                                                SCRATCHPAD_PORT_NUM maxPortNum,
                                                Vector#(n_INGRESS_PORTS, CONNECTION_ADDR_TREE#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_MEM_REQ, SCRATCHPAD_READ_RSP)) children, 
                                                Vector#(TAdd#(1, n_INGRESS_PORTS) , SCRATCHPAD_PORT_NUM) addressBounds, 
                                                Vector#(n_INGRESS_PORTS, UInt#(nFRACTION)) bandwidthFractions)
    (Empty)
    provisos (Bits#(SCRATCHPAD_MEM_REQ, t_SCRATCHPAD_MEM_REQ_SZ), 
              Bits#(SCRATCHPAD_READ_RSP, t_SCRATCHPAD_READ_RSP_SZ),
              Add#(1, nFRACTION_extra_bits, nFRACTION),
              Add#(1, nFRACTION_VALUES_extra_bits, TLog#(TAdd#(1, TExp#(nFRACTION)))));

    // Connect to the controller rings (use broadcast chains instead of addressable rings)
    CONNECTION_CHAIN#(Tuple2#(SCRATCHPAD_PORT_NUM, Bit#(t_SCRATCHPAD_MEM_REQ_SZ)))  reqChain  <- mkConnectionChain(controllerReqRingName);
    CONNECTION_CHAIN#(Tuple2#(SCRATCHPAD_PORT_NUM, Bit#(t_SCRATCHPAD_READ_RSP_SZ))) respChain <- mkConnectionChain(controllerRespRingName);
    
    // Instantiate the tree root
    CONNECTION_ADDR_TREE#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_MEM_REQ, SCRATCHPAD_READ_RSP) root <- 
        mkTreeRouter(children, addressBounds, mkLocalArbiterBandwidth(bandwidthFractions));

    DEBUG_FILE debugLog <- mkDebugFile("scratchpad_tree_connector_" + controllerReqRingName + ".out");

    // Take care of the initialization phases needed for addressable rings
    Reg#(Bool)    reqChainInitDone   <- mkReg(False);
    Reg#(Bit#(2)) reqChainInitPhase  <- mkReg(0);
    Reg#(Bool)    respChainInitDone  <- mkReg(False);
    Reg#(Bit#(2)) respChainInitPhase <- mkReg(0);
    
    rule doReqChainInit (!reqChainInitDone);
        let msg <- reqChain.recvFromPrev();
        reqChain.sendToNext(tuple2(maxPortNum, ?));
        if (reqChainInitPhase == 2)
        begin
            reqChainInitDone <= True;
        end
        else
        begin
            reqChainInitPhase <= reqChainInitPhase + 1;
        end
        debugLog.record($format("doReqChainInit: phase %0d", reqChainInitPhase));
    endrule

    rule doRespChainInit (!respChainInitDone);
        let msg <- respChain.recvFromPrev();
        respChain.sendToNext(tuple2(maxPortNum, ?));
        if (respChainInitPhase == 2)
        begin
            respChainInitDone <= True;
        end
        else
        begin
            respChainInitPhase <= respChainInitPhase + 1;
        end
        debugLog.record($format("doRespChainInit: phase %0d", respChainInitPhase));
    endrule

    // Forward requests to the scratchpad controller
    rule fwdReq (reqChainInitDone);
        reqChain.sendToNext(tuple2(0, pack(root.first())));
        root.deq();
        debugLog.record($format("fwdReq: msg=0x%x", pack(root.first())));
    endrule

    // Forward responses from the scratchpad controller 
    rule fwdResp (respChainInitDone);
        match {.id, .msg} <- respChain.recvFromPrev();
        root.enq(TREE_MSG{dstNode: id, data: unpack(msg)});
        debugLog.record($format("fwdResp: node_id=%0d, msg=0x%x", id, msg));
    endrule

endmodule

