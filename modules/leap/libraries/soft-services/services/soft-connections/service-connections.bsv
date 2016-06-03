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

import FIFOF::*;

`include "awb/provides/librl_bsv_base.bsh"

//
// Wrappers for centralized (multi-client-single-server) service connections. 
//
// The default implementation uses addressable rings. 
// For non-default implementations, the connections are handled by the LIM
// compiler.
//

interface CONNECTION_SERVICE_CLIENT#(type t_CLIENT_ID, type t_REQ, type t_RSP);
    // Request portion
    method Action makeReq(t_REQ data);
    method Bool   reqNotFull();
    // Response portion
    method Bool   rspNotEmpty();
    method t_RSP  getRsp();
    method Action deqRsp();
    // Return unique client ID
    method t_CLIENT_ID clientId();
endinterface

interface CONNECTION_SERVICE_SERVER#(type t_CLIENT_ID, type t_REQ, type t_RSP);
    // Request portion
    method Bool   reqNotEmpty();
    method t_REQ  getReq();
    method Action deqReq();
    // Response portion
    method Action makeRsp(t_CLIENT_ID dst, t_RSP data);
    method Bool   rspNotFull();
endinterface


//
// mkConnectionServiceClient --
//     A service client connection wrapper with a static client ID.
//
module [CONNECTED_MODULE] mkConnectionServiceClient#(String serviceName,
                                                     t_CLIENT_ID staticID, 
                                                     CONNECTION_SERVICE_PARAM param)
    // Interface:
    (CONNECTION_SERVICE_CLIENT#(t_CLIENT_ID, t_REQ, t_RSP))
    provisos (Bits#(t_REQ, t_REQ_SZ),
              Bits#(t_RSP, t_RSP_SZ),
              Bits#(t_CLIENT_ID, t_CLIENT_ID_SZ),
              Eq#(t_CLIENT_ID),
              Bounded#(t_CLIENT_ID),
              Ord#(t_CLIENT_ID),
              Arith#(t_CLIENT_ID));

    if (param.networkType == CONNECTION_NON_TOKEN_RING || param.networkType == CONNECTION_TOKEN_RING)
    begin
        // Request ring
        CONNECTION_ADDR_RING#(t_CLIENT_ID, t_REQ) link_req  <- (param.networkType == CONNECTION_NON_TOKEN_RING)?
            mkConnectionAddrRingNode(serviceName + "_Req", staticID):
            mkConnectionTokenRingNode(serviceName + "_Req", staticID);
        
        // Response ring
        CONNECTION_ADDR_RING#(t_CLIENT_ID, t_RSP) link_resp <- (param.networkType == CONNECTION_NON_TOKEN_RING)?
            mkConnectionAddrRingNode(serviceName + "_Resp", staticID):
            mkConnectionTokenRingNode(serviceName + "_Resp", staticID);
        
        // Methods
        method Action makeReq(t_REQ data);
            link_req.enq(0, data);
        endmethod
        method Bool reqNotFull() = link_req.notFull();
        method Bool rspNotEmpty() = link_resp.notEmpty();
        method t_RSP  getRsp() = link_resp.first();
        method Action deqRsp();
            link_resp.deq();
        endmethod
        method t_CLIENT_ID clientId() = link_req.nodeID();
    end
    else // Compiler generated network
    begin
        let n <- mkConnectionDispatchServiceClient(serviceName, tagged Valid staticID);
        return n;
    end

endmodule

//
// mkConnectionServiceDynClient --
//     A service client connection wrapper without a static client ID.
// The client ID will be assigned by the compiler or computed at run-time.
//
module [CONNECTED_MODULE] mkConnectionServiceDynClient#(String serviceName,
                                                        CONNECTION_SERVICE_PARAM param)
    // Interface:
    (CONNECTION_SERVICE_CLIENT#(t_CLIENT_ID, t_REQ, t_RSP))
    provisos (Bits#(t_REQ, t_REQ_SZ),
              Bits#(t_RSP, t_RSP_SZ),
              Bits#(t_CLIENT_ID, t_CLIENT_ID_SZ),
              Eq#(t_CLIENT_ID),
              Bounded#(t_CLIENT_ID),
              Ord#(t_CLIENT_ID),
              Arith#(t_CLIENT_ID));

    if (param.networkType == CONNECTION_NON_TOKEN_RING || param.networkType == CONNECTION_TOKEN_RING)
    begin
        Reg#(t_CLIENT_ID) myPort <- mkWriteValidatedReg();
        Reg#(Bool)   initialized <- mkReg(False);
        
        // Request ring
        CONNECTION_ADDR_RING#(t_CLIENT_ID, t_REQ) link_req  <- (param.networkType == CONNECTION_NON_TOKEN_RING)?
            mkConnectionAddrRingDynNode(serviceName + "_Req"):
            mkConnectionTokenRingDynNode(serviceName + "_Req");
        
        // Response ring
        CONNECTION_ADDR_RING#(t_CLIENT_ID, t_RSP) link_resp <- (param.networkType == CONNECTION_NON_TOKEN_RING)?
            mkConnectionAddrRingNode(serviceName + "_Resp", myPort._read()):
            mkConnectionTokenRingNode(serviceName + "_Resp", myPort._read());
        
        rule doInit (!initialized);
            initialized <= True;
            let port_num = link_req.nodeID();
            myPort <= port_num;
        endrule
        
        // Methods
        method Action makeReq(t_REQ data);
            link_req.enq(0, data);
        endmethod
        method Bool reqNotFull() = link_req.notFull();
        method Bool rspNotEmpty() = link_resp.notEmpty();
        method t_RSP  getRsp() = link_resp.first();
        method Action deqRsp();
            link_resp.deq();
        endmethod
        method t_CLIENT_ID clientId() = myPort;
    end
    else // Compiler generated network
    begin
        let n <- mkConnectionDispatchServiceClient(serviceName, tagged Invalid);
        return n;
    end

endmodule

//
// mkConnectionServiceServer --
//     A service server connection wrapper.
//
module [CONNECTED_MODULE] mkConnectionServiceServer#(String serviceName,
                                                     CONNECTION_SERVICE_PARAM param)
    // Interface:
    (CONNECTION_SERVICE_SERVER#(t_CLIENT_ID, t_REQ, t_RSP))
    provisos (Bits#(t_REQ, t_REQ_SZ),
              Bits#(t_RSP, t_RSP_SZ),
              Bits#(t_CLIENT_ID, t_CLIENT_ID_SZ),
              Eq#(t_CLIENT_ID),
              Bounded#(t_CLIENT_ID),
              Ord#(t_CLIENT_ID),
              Arith#(t_CLIENT_ID));

    if (param.networkType == CONNECTION_NON_TOKEN_RING || param.networkType == CONNECTION_TOKEN_RING)
    begin
        // Request ring
        CONNECTION_ADDR_RING#(t_CLIENT_ID, t_REQ) link_req  <- (param.networkType == CONNECTION_NON_TOKEN_RING)?
            mkConnectionAddrRingNode(serviceName + "_Req", 0):
            mkConnectionTokenRingNode(serviceName + "_Req", 0);
        
        // Response ring
        CONNECTION_ADDR_RING#(t_CLIENT_ID, t_RSP) link_resp <- (param.networkType == CONNECTION_NON_TOKEN_RING)?
            mkConnectionAddrRingNode(serviceName + "_Resp", 0):
            mkConnectionTokenRingNode(serviceName + "_Resp", 0);
        
        // Methods
        method Bool reqNotEmpty() = link_req.notEmpty();
        method t_REQ getReq() = link_req.first();
        method Action deqReq();
            link_req.deq();
        endmethod
        method Action makeRsp(t_CLIENT_ID dst, t_RSP data);
            link_resp.enq(dst, data);
        endmethod
        method Bool rspNotFull() = link_resp.notFull();
    end
    else // Compiler generated network
    begin
        let n <- mkConnectionDispatchServiceServer(serviceName);
        return n;
    end

endmodule

