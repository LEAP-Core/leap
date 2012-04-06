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

// These dispatchers bridge the gap between physical and logical connection
// constructors. Based on the information that the user provided, they
// pick the correct physical implementation, and possibly add a guard to
// the methods.


// mkConnectionDispatchSend

// Dispatcher of a send connection. If the data is small enough to fit into a 
// single physical connection than only one is used. Otherwise a vector of
// physical connections is instantiated.

module [t_CONTEXT] mkConnectionDispatchSend#(String name, Maybe#(STATION) m_station, Bool optional, Bool guarded) 
  // interface:
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
            0: mkPhysicalConnectionSend(name, m_station, optional, conntype, True);
            1: mkPhysicalConnectionSend(name, m_station, optional, conntype, True);
            default: mkConnectionSendVector(name, m_station, optional, conntype);
        endcase;
    
    // Phsyical sends are unguarded. If the user asks for a guard we add it here.
    // Currently all our implementations ask for the guard. However a "power user" can get an
    // unguarded connection conveniently by invoking the dispatcher directly.
    
    method Action send(t_MSG data) if (c.notFull());
      c.send(data);
    endmethod

    method Bool notFull() = c.notFull();

endmodule


// mkConnectionDispatchSendMulti

// Dispatcher of a one-to-many connection.  If the data is small enough to fit into a 
// single physical connection than only one is used. Otherwise a vector of
// physical connections is instantiated.

module [t_CONTEXT] mkConnectionDispatchSendMulti#(String name, Maybe#(STATION) m_station, Bool guarded) 
  // interface:
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
                0: mkPhysicalConnectionSendMulti(name, m_station, conntype, True);
                1: mkPhysicalConnectionSendMulti(name, m_station, conntype, True);
                default: mkConnectionSendMultiVector(name, m_station, conntype);
            endcase;
    
    // Phsyical sends are unguarded. If the user asks for a guard we add it here.
    // Currently all our implementations ask for the guard. However a "power user" can get an
    // unguarded connection conveniently by invoking the dispatcher directly.
    
    method Action broadcast(t_MSG data) if (c.notFull());
        c.broadcast(data);
    endmethod

    method Action sendTo(CONNECTION_IDX dst, t_MSG data) if (c.notFull());
        c.sendTo(dst, data);
    endmethod 

    method Bool notFull() = c.notFull();
    
endmodule


// mkConnectionDispatchRecv

// Dispatcher of a receive connection. If the data is small enough to fit into a
// single physical connection than only one is used. Otherwise a vector of
// physical connections is instantiated.

module [t_CONTEXT] mkConnectionDispatchRecv#(String name, Maybe#(STATION) m_station, Bool optional, Bool guarded) 
  // interface:
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
                0: mkPhysicalConnectionRecv(name, m_station, optional, conntype);
                1: mkPhysicalConnectionRecv(name, m_station, optional, conntype);
                default: mkConnectionRecvVector(name, m_station, optional, conntype);
            endcase;

    // Phsyical receives are unguarded. If the user asks for a guard add it here. Note that all default
    // constructors add guards. However "power users" can make unguarded connections by calling this 
    // function directly.

    method t_MSG receive() if (c.notEmpty());
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
module [t_CONTEXT] mkConnectionDispatchRecvMulti#(String name, Maybe#(STATION) m_station, Bool guarded) 
  // interface:
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
                0: mkPhysicalConnectionRecvMulti(name, m_station, conntype);
                1: mkPhysicalConnectionRecvMulti(name, m_station, conntype);
                default: mkConnectionRecvMultiVector(name, m_station, conntype);
            endcase;

    // Phsyical receives are unguarded. If the user asks for a guard add it here. Note that all default
    // constructors add guards. However "power users" can make unguarded connections by calling this 
    // function directly.

    method Tuple2#(CONNECTION_IDX, t_MSG) receive() if (c.notEmpty());
        return c.receive();
    endmethod

    method Bool notEmpty();
        return c.notEmpty();
    endmethod

    method Action deq() if (c.notEmpty());
        c.deq();
    endmethod
    
endmodule


// mkConnectionDispatchClient

// Dispatcher of a client connection. Requests and responses are "chunked"
// separately using the send/recv dispatchers.

module [t_CONTEXT] mkConnectionDispatchClient#(String name, Maybe#(STATION) m_station, Bool optional, Bool guarded) 
  // interface:
        (CONNECTION_CLIENT#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Instantiate using dispatchers to "chunk" connections.
    CONNECTION_SEND#(t_REQ) req <- mkConnectionDispatchSend(getReqName(name), m_station, optional, guarded);
    CONNECTION_RECV#(t_RSP) rsp <- mkConnectionDispatchRecv(getRspName(name), m_station, optional, guarded);

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

module [t_CONTEXT] mkConnectionDispatchClientMulti#(String name, Maybe#(STATION) m_station, Bool guarded) 
  // interface:
        (CONNECTION_CLIENT_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Instantiate using dispatchers to "chunk" connections.
    CONNECTION_SEND_MULTI#(t_REQ) req <- mkConnectionDispatchSendMulti(getReqName(name), m_station, guarded);
    CONNECTION_RECV_MULTI#(t_RSP) rsp <- mkConnectionDispatchRecvMulti(getRspName(name), m_station, guarded);

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

module [t_CONTEXT] mkConnectionDispatchServer#(String name, Maybe#(STATION) m_station, Bool optional, Bool guarded) 
  // interface:
        (CONNECTION_SERVER#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Instantiate using dispatchers to "chunk" connections.
    CONNECTION_RECV#(t_REQ) req <- mkConnectionDispatchRecv(getReqName(name), m_station, optional, guarded);
    CONNECTION_SEND#(t_RSP) rsp <- mkConnectionDispatchSend(getRspName(name), m_station, optional, guarded);

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

module [t_CONTEXT] mkConnectionDispatchServerMulti#(String name, Maybe#(STATION) m_station, Bool guarded) 
  // interface:
        (CONNECTION_SERVER_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Instantiate using dispatchers to "chunk" connections.
    CONNECTION_RECV_MULTI#(t_REQ) req <- mkConnectionDispatchRecvMulti(getReqName(name), m_station, guarded);
    CONNECTION_SEND_MULTI#(t_RSP) rsp <- mkConnectionDispatchSendMulti(getRspName(name), m_station, guarded);

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