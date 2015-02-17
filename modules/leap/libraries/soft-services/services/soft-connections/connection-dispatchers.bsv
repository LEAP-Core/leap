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

// These dispatchers bridge the gap between physical and logical connection
// constructors. Based on the information that the user provided, they
// pick the correct physical implementation, and possibly add a guard to
// the methods.


// mkConnectionDispatchSend

// Dispatcher of a send connection. If the data is small enough to fit into a 
// single physical connection than only one is used. Otherwise a vector of
// physical connections is instantiated.

module [t_CONTEXT] mkConnectionDispatchSend#(
    String name,
    Maybe#(STATION) m_station,
    CONNECTION_SEND_PARAM param)
    // Interface:
    (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Div#(t_MSG_SIZE, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Figure out logical type for user-level typechecking.
    t_MSG msg = ?;
    String conntype = printType(typeOf(msg));
    
    PHYSICAL_SEND#(t_MSG) c <- 
        case (valueof(t_NUM_PHYSICAL_CONNS))
            0: mkPhysicalConnectionSend(name, m_station, conntype, param);
            1: mkPhysicalConnectionSend(name, m_station, conntype, param);
            default: mkConnectionSendVector(name, m_station, conntype, param);
        endcase;
    
    method Action send(t_MSG data) if (c.notFull() || ! param.guarded);
        c.send(data);
    endmethod

    method Bool notFull() = c.notFull();
endmodule


// mkConnectionDispatchSendMulti

// Dispatcher of a one-to-many connection.  If the data is small enough to fit into a 
// single physical connection than only one is used. Otherwise a vector of
// physical connections is instantiated.

module [t_CONTEXT] mkConnectionDispatchSendMulti#(
    String name,
    Maybe#(STATION) m_station,
    CONNECTION_SEND_PARAM param) 
    // Interface:
    (CONNECTION_SEND_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Div#(t_MSG_SIZE, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Figure out logical type for user-level typechecking.
    t_MSG msg = ?;
    String conntype = printType(typeOf(msg));
    
    PHYSICAL_SEND_MULTI#(t_MSG) c <- case (valueof(t_NUM_PHYSICAL_CONNS))
                0: mkPhysicalConnectionSendMulti(name, m_station, conntype, param);
                1: mkPhysicalConnectionSendMulti(name, m_station, conntype, param);
                default: mkConnectionSendMultiVector(name, m_station, conntype, param);
            endcase;
    
    method Action broadcast(t_MSG data) if (c.notFull() || ! param.guarded);
        c.broadcast(data);
    endmethod

    method Action sendTo(CONNECTION_IDX dst, t_MSG data) if (c.notFull() || ! param.guarded);
        c.sendTo(dst, data);
    endmethod 

    method Bool notFull() = c.notFull();
    
endmodule


// mkConnectionDispatchRecv

// Dispatcher of a receive connection. If the data is small enough to fit into a
// single physical connection than only one is used. Otherwise a vector of
// physical connections is instantiated.

module [t_CONTEXT] mkConnectionDispatchRecv#(
    String name,
    Maybe#(STATION) m_station,
    CONNECTION_RECV_PARAM param)
    // Interface:
    (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Div#(t_MSG_SIZE, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Figure out the logical type for user-level typechecking
    t_MSG msg = ?;
    String conntype = printType(typeOf(msg));
    
    CONNECTION_RECV#(t_MSG) c <- case (valueof(t_NUM_PHYSICAL_CONNS))
                0: mkPhysicalConnectionRecv(name, m_station, conntype, param);
                1: mkPhysicalConnectionRecv(name, m_station, conntype, param);
                default: mkConnectionRecvVector(name, m_station, conntype, param);
            endcase;

    method t_MSG receive() if (c.notEmpty() || ! param.guarded);
        return c.receive();
    endmethod

    method Bool notEmpty();
        return c.notEmpty();
    endmethod

    method Action deq() if (c.notEmpty());
        c.deq();
    endmethod

endmodule

// mkConnectionDispatchRecvMulti

// Dispatcher of a many-to-1 receive connection. If the data is small enough to fit into a
// single physical connection than only one is used. Otherwise a vector of
// physical connections is instantiated.
module [t_CONTEXT] mkConnectionDispatchRecvMulti#(
    String name,
    Maybe#(STATION) m_station,
    CONNECTION_RECV_PARAM param) 
    // Interface:
    (CONNECTION_RECV_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Div#(t_MSG_SIZE, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Figure out the logical type for user-level typechecking
    t_MSG msg = ?;
    String conntype = printType(typeOf(msg));
    
    CONNECTION_RECV_MULTI#(t_MSG) c <- case (valueof(t_NUM_PHYSICAL_CONNS))
                0: mkPhysicalConnectionRecvMulti(name, m_station, conntype, param);
                1: mkPhysicalConnectionRecvMulti(name, m_station, conntype, param);
                default: mkConnectionRecvMultiVector(name, m_station, conntype, param);
            endcase;

    method Tuple2#(CONNECTION_IDX, t_MSG) receive() if (c.notEmpty() || ! param.guarded);
        return c.receive();
    endmethod

    method Bool notEmpty();
        return c.notEmpty();
    endmethod

    method Action deq() if (c.notEmpty() || ! param.guarded);
        c.deq();
    endmethod
endmodule


// mkConnectionDispatchClient

// Dispatcher of a client connection. Requests and responses are "chunked"
// separately using the send/recv dispatchers.

module [t_CONTEXT] mkConnectionDispatchClient#(
    String name,
    Maybe#(STATION) m_station,
    CONNECTION_SEND_PARAM sendParam,
    CONNECTION_RECV_PARAM recvParam)
    // Interface:
    (CONNECTION_CLIENT#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Instantiate using dispatchers to "chunk" connections.
    CONNECTION_SEND#(t_REQ) req <- mkConnectionDispatchSend(getReqName(name), m_station, sendParam);
    CONNECTION_RECV#(t_RSP) rsp <- mkConnectionDispatchRecv(getRspName(name), m_station, recvParam);

    // Methods are already guarded (if requested). No need to add further guards.
    method Action makeReq(t_REQ data) = req.send(data);
    method Bool reqNotFull() = req.notFull();
    method t_RSP getRsp() = rsp.receive();
    method Bool rspNotEmpty() = rsp.notEmpty();
    method Action deq() = rsp.deq();
endmodule


// mkConnectionDispatchClientMulti

// Dispatcher of a client multicast (client of many servers) connection.
// Reqs and rsps are "chunked" separately using the sendMulti/recvMulti 
// dispatchers.

module [t_CONTEXT] mkConnectionDispatchClientMulti#(
    String name,
    Maybe#(STATION) m_station,
    CONNECTION_SEND_PARAM sendParam,
    CONNECTION_RECV_PARAM recvParam)
    // Interface:
    (CONNECTION_CLIENT_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Instantiate using dispatchers to "chunk" connections.
    CONNECTION_SEND_MULTI#(t_REQ) req <- mkConnectionDispatchSendMulti(getReqName(name), m_station, sendParam);
    CONNECTION_RECV_MULTI#(t_RSP) rsp <- mkConnectionDispatchRecvMulti(getRspName(name), m_station, recvParam);

    // Methods are already guarded (if requested). No need to add further guards.
    method Action makeReqTo(CONNECTION_IDX dst, t_REQ data) = req.sendTo(dst, data);
    method Action broadcastReq(t_REQ data) = req.broadcast(data);
    method Bool reqNotFull() = req.notFull();

    method Tuple2#(CONNECTION_IDX, t_RSP) getRsp() = rsp.receive();
    method Bool rspNotEmpty() = rsp.notEmpty();
    method Action deq() = rsp.deq();
endmodule


// mkConnectionDispatchServer

// Dispatcher of a server connection. Requests and responses are "chunked"
// separately using the send/recv dispatchers.

module [t_CONTEXT] mkConnectionDispatchServer#(
    String name, Maybe#(STATION) m_station,
    CONNECTION_SEND_PARAM sendParam,
    CONNECTION_RECV_PARAM recvParam)
    // Interface:
    (CONNECTION_SERVER#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Instantiate using dispatchers to "chunk" connections.
    CONNECTION_RECV#(t_REQ) req <- mkConnectionDispatchRecv(getReqName(name), m_station, recvParam);
    CONNECTION_SEND#(t_RSP) rsp <- mkConnectionDispatchSend(getRspName(name), m_station, sendParam);

    // Methods are already guarded (if requested). No need to add further guards.
    method t_REQ getReq() = req.receive();
    method Bool reqNotEmpty() = req.notEmpty();
    method Action deq() = req.deq();

    method Action makeRsp(t_RSP data) = rsp.send(data);
    method Bool rspNotFull() = rsp.notFull();

endmodule


// mkConnectionDispatchServerMulti

// Dispatcher of a server_multi connection. Requests and responses are "chunked"
// separately using the sendMulti/recvMulti dispatchers.

module [t_CONTEXT] mkConnectionDispatchServerMulti#(
    String name,
    Maybe#(STATION) m_station,
    CONNECTION_SEND_PARAM sendParam,
    CONNECTION_RECV_PARAM recvParam)
    // Interface:
    (CONNECTION_SERVER_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Instantiate using dispatchers to "chunk" connections.
    CONNECTION_RECV_MULTI#(t_REQ) req <- mkConnectionDispatchRecvMulti(getReqName(name), m_station, recvParam);
    CONNECTION_SEND_MULTI#(t_RSP) rsp <- mkConnectionDispatchSendMulti(getRspName(name), m_station, sendParam);

    // Methods are already guarded (if requested). No need to add further guards.
    method Tuple2#(CONNECTION_IDX, t_REQ) getReq() = req.receive();

    method Bool reqNotEmpty() = req.notEmpty();

    method Action deq();
        req.deq();
    endmethod

    method Action makeRspTo(CONNECTION_IDX dst, t_RSP data);
      rsp.sendTo(dst, data);
    endmethod
  
    // NOTE: Perhaps this method should be removed. It does not seem to be obviously useful.
    method Action broadcastRsp(t_RSP data);
      rsp.broadcast(data);
    endmethod
  
    method Bool rspNotFull() = rsp.notFull();
endmodule


function String getReqName(String s) = s + "__req";
function String getRspName(String s) = s + "__rsp";


// Dispatcher of a send connection. If the data is small enough to fit into a 
// single physical connection than only one is used. Otherwise a vector of
// physical connections is instantiated.

module [t_CONTEXT] mkConnectionDispatchChain#(String name, Maybe#(STATION) m_station, Bool guarded) 
  // interface:
        (CONNECTION_CHAIN#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Div#(t_MSG_SIZE, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Figure out logical type for user-level typechecking.
    t_MSG msg = ?;
    String conntype = printType(typeOf(msg));
    
    CONNECTION_CHAIN#(t_MSG) c <- 
        case (valueof(t_NUM_PHYSICAL_CONNS))
            0: mkPhysicalConnectionChain(name, conntype);
            1: mkPhysicalConnectionChain(name, conntype);
            default: mkConnectionChainVector(name, conntype);
        endcase;
    
    // Phsyical sends are unguarded. If the user asks for a guard we add it here.
    // Currently all our implementations ask for the guard. However a "power user" can get an
    // unguarded connection conveniently by invoking the dispatcher directly.
    

  method peekFromPrev = c.peekFromPrev;

  method recvNotEmpty= c.recvNotEmpty;

  method sendNotFull = c.sendNotFull;

  method sendToNext = c.sendToNext;

  method recvFromPrev = c.recvFromPrev;

endmodule
