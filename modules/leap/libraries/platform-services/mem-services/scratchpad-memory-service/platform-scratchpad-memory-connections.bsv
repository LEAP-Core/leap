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
// mkScratchpadClientInterleaver --
//     Connect a scratchpad client to multiple controller networks. Requests
//     are forwarded based on address partitioning. 
//
module [CONNECTED_MODULE] mkScratchpadClientInterleaver#(Vector#(n_CONTROLLERS, CONNECTION_IN#(SERVICE_CON_DATA_SIZE)) controllerReqPorts,
                                                         Vector#(n_CONTROLLERS, CONNECTION_OUT#(SERVICE_CON_DATA_SIZE)) controllerRspPorts,
                                                         Integer scratchPortId, 
                                                         function UInt#(TLog#(n_CONTROLLERS)) getControllerIdxFromAddr(SCRATCHPAD_MEM_ADDRESS addr), 
                                                         Bool crossClockDomain)
    (CONNECTION_SERVICE_CLIENT_COUNTERPART_IFC#(SERVICE_CON_DATA_SIZE, SERVICE_CON_DATA_SIZE))
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
    
    // Local Clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();

    DEBUG_FILE debugLog <- mkDebugFile("scratchpad_client_" + integerToString(scratchPortId) + "_interleaver.out");
    
    Reg#(Bool) initialized     <- mkReg(crossClockDomain);
    Reg#(Bit#(2)) addrMapMode  <- mkReg(0);
    
    if (!crossClockDomain)
    begin
        // Dynamic parameters
        PARAMETER_NODE   paramNode  <- mkDynamicParameterNode();
        Param#(2) addrMapModeParam  <- mkDynamicParameter(`PARAMS_SCRATCHPAD_MEMORY_SERVICE_SCRATCHPAD_ADDR_MAP_MODE, paramNode);
        // Initialization
        rule doInit (! initialized);
            addrMapMode <= addrMapModeParam;
            initialized <= True;
        endrule
    end

    // address map pre-processing function
    function SCRATCHPAD_MEM_ADDRESS addrMap (SCRATCHPAD_MEM_ADDRESS addr);
        // Interleaving unit: max(dram burst size, local memory line size)
        if (addrMapMode[0] == 0)
        begin
            Tuple2#(t_LOCAL_MEM_ADDR, t_LOCAL_MEM_DATA_IDX) local_addr = unpack(addr);
            //let a = (addrMapMode[1] == 0)? tpl_1(local_addr) :  hashBits(tpl_1(local_addr));
            Bit#(10) a1 = resize(tpl_1(local_addr));
            let a2 = (addrMapMode[1] == 0)? a1 :  hashBits(a1);
            return zeroExtend(a2); 
        end
        else 
        begin // Interleaving unit: local memory line size
            Tuple2#(Bit#(TSub#(t_ADDR_SZ, TLog#(t_WORDS_PER_LINE))), Bit#(TLog#(t_WORDS_PER_LINE))) local_addr = unpack(addr); 
            //let a = (addrMapMode[1] == 0)? tpl_1(local_addr) :  hashBits(tpl_1(local_addr));
            let a = tpl_1(local_addr);
            return zeroExtend(a); 
        end
    endfunction
    
    // Interact with the client side
    RWire#(SCRATCHPAD_MEM_REQ)  clientReqW      <- mkRWire();
    PulseWire                   clientReqDeqW   <- mkPulseWire();
    FIFOF#(SCRATCHPAD_READ_RSP) rspFromNetworkQ <- mkUGFIFOF();
    
    // Interact with the controller side
    FIFOF#(Tuple2#(UInt#(TLog#(n_CONTROLLERS)), SCRATCHPAD_MEM_REQ))  reqToNetworkQ   <- mkUGFIFOF();
    Reg#(Bool)                        sendScratchpadInit <- mkReg(False);
    Reg#(SCRATCHPAD_MEM_REQ)          scratchpadInitReq  <- mkRegU;
    Reg#(UInt#(TLog#(n_CONTROLLERS))) scratchpadInitCnt  <- mkRegU;

    rule sendScratchpadReq (clientReqW.wget() matches tagged Valid .req &&& initialized &&& reqToNetworkQ.notFull() && !sendScratchpadInit);
        clientReqDeqW.send();
        case (req) matches
            tagged SCRATCHPAD_MEM_INIT .init:
            begin
                reqToNetworkQ.enq(tuple2(0, req));
                debugLog.record($format("sendScratchpadReq: forward master INIT req to controller %d", 0));
                let slave_init = init;
                slave_init.initCacheOnly = True;
                scratchpadInitReq  <= tagged SCRATCHPAD_MEM_INIT slave_init;
                scratchpadInitCnt  <= 1;
                sendScratchpadInit <= True;
            end

            tagged SCRATCHPAD_MEM_READ .r_req:
            begin
                let idx = getControllerIdxFromAddr(addrMap(r_req.addr));
                reqToNetworkQ.enq(tuple2(idx, req));
                debugLog.record($format("sendScratchpadReq: forward READ req to controller %d, addr=0x%x", idx, r_req.addr));
            end

            tagged SCRATCHPAD_MEM_WRITE .w_req:
            begin
                let idx = getControllerIdxFromAddr(addrMap(w_req.addr));
                reqToNetworkQ.enq(tuple2(idx, req));
                debugLog.record($format("sendScratchpadReq: forward WRITE req to controller %d, addr=0x%x", idx, w_req.addr));
            end

            tagged SCRATCHPAD_MEM_WRITE_MASKED .w_req:
            begin
                let idx = getControllerIdxFromAddr(addrMap(w_req.addr));
                reqToNetworkQ.enq(tuple2(idx, req));
                debugLog.record($format("sendScratchpadReq: forward WRITE req to controller %d, addr=0x%x", idx, w_req.addr));
            end
        endcase
    endrule
   
    rule sendScratchpadInitReq (reqToNetworkQ.notFull() && sendScratchpadInit);
        reqToNetworkQ.enq(tuple2(scratchpadInitCnt, scratchpadInitReq));
        debugLog.record($format("sendScratchpadReq: forward slave INIT req to controller %d", scratchpadInitCnt));
        if (scratchpadInitCnt == fromInteger(valueOf(n_CONTROLLERS)-1))
        begin
            sendScratchpadInit <= False;
        end
        else
        begin
            scratchpadInitCnt <= scratchpadInitCnt + 1;
        end
    endrule

    rule forwardReqToController (reqToNetworkQ.notEmpty());
        match {.idx, .req} = reqToNetworkQ.first();
        controllerReqPorts[idx].try(zeroExtendNP(pack(req)));
    endrule
    
    rule deqReqToController (reqToNetworkQ.notEmpty());
        match {.idx, .req} = reqToNetworkQ.first();
        if (controllerReqPorts[idx].success())
        begin
            reqToNetworkQ.deq();
        end
    endrule

    Rules resp_rules = emptyRules; 
    
    for (Integer c = 0; c < valueOf(n_CONTROLLERS); c = c + 1)
    begin 
        let resp_fwd = 
            (rules 
                 rule sendScratchpadResp (initialized && rspFromNetworkQ.notFull && controllerRspPorts[c].notEmpty); 
                     SCRATCHPAD_READ_RSP resp = unpack(truncateNP(controllerRspPorts[c].first()));
                     controllerRspPorts[c].deq();
                     rspFromNetworkQ.enq(resp);
                     debugLog.record($format("sendScratchpadResp: forward response from controller %d, addr=0x%x, val=0x%x", c, resp.addr, resp.val));
                 endrule 
            endrules); 
        resp_rules = rJoinDescendingUrgency(resp_rules,resp_fwd); 
    end 
    
    addRules(resp_rules); 

    // ========================================================================
    //
    // Methods
    //
    // ========================================================================
    
    // Request port from the service client
    interface clientReqIncoming = interface CONNECTION_IN#(SERVICE_CON_DATA_SIZE);
                                      method Action try(Bit#(SERVICE_CON_DATA_SIZE) msg);
                                          clientReqW.wset(unpack(truncateNP(msg)));
                                      endmethod
                                      method Bool success() = clientReqDeqW;
                                      method Bool dequeued() = clientReqDeqW;
                                      interface Clock clock = localClock;
                                      interface Reset reset = localReset;
                                  endinterface; 
    
    // Response port to the service client
    interface clientRspOutgoing = interface CONNECTION_OUT#(SERVICE_CON_DATA_SIZE);
                                      method Bit#(SERVICE_CON_DATA_SIZE) first() = zeroExtendNP(pack(rspFromNetworkQ.first()));
                                      method Action deq();
                                          rspFromNetworkQ.deq();
                                      endmethod
                                      method Bool notEmpty = rspFromNetworkQ.notEmpty();
                                      interface clock = localClock;
                                      interface reset = localReset;
                                  endinterface; 

endmodule

//
// remapScratchpadServiceConnectionOut --
//     For complex scratchpad network topologies where client IDs need to follow 
// certain rules (ex: tree network or hierarchical ring network), one client may
// be assigned to multiple IDs if memory interleaving is applied. In this case, 
// we need to remap the destinations of response sent from the server with the 
// newly assigned ID.
//
function CONNECTION_OUT#(SERVICE_CON_RESP_SIZE) remapScratchpadServiceConnectionOut(CONNECTION_OUT#(SERVICE_CON_RESP_SIZE) cout, 
                                                                                    function SCRATCHPAD_PORT_NUM getRemappedIdx(SCRATCHPAD_PORT_NUM idx));
    CONNECTION_OUT#(SERVICE_CON_RESP_SIZE) retval = interface CONNECTION_OUT;
                                                        method Bit#(SERVICE_CON_RESP_SIZE) first();
                                                            Tuple2#(Bit#(SERVICE_CON_IDX_SIZE), Bit#(SERVICE_CON_DATA_SIZE)) msg = unpack(cout.first());
                                                            SCRATCHPAD_PORT_NUM idx = truncateNP(tpl_1(msg));
                                                            Bit#(SERVICE_CON_IDX_SIZE) new_idx = zeroExtendNP(getRemappedIdx(idx));
                                                            return pack(tuple2(new_idx, tpl_2(msg)));
                                                        endmethod
                                                        method deq = cout.deq;
                                                        method notEmpty = cout.notEmpty;
                                                        interface clock = cout.clock;
                                                        interface reset = cout.reset;
                                                    endinterface; 
    return retval;
endfunction


