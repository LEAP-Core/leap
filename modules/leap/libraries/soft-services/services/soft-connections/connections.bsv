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
import GetPut::*;
import DefaultValue::*;


//-------------------- Soft Connections --------------------------//
//                                                                //
// This file contains the user-visible interfaces and modules     //
// for Soft Connections, which are conected by name at compilation//
// time.                                                          //
//----------------------------------------------------------------//
 

// The basic sending half of a connection.

interface CONNECTION_SEND#(type t_MSG);
  
    method Action send(t_MSG data);
    method Bool notFull();
  
endinterface

typeclass ToConnectionSend#(type t_IFC, type t_MSG)
    dependencies (t_IFC determines t_MSG);
    // Encode the original data into compressed form.
    function CONNECTION_SEND#(t_MSG) toConnectionSend (t_IFC ifc);

endtypeclass




// The basic receiving connection.

interface CONNECTION_RECV#(type t_MSG);
  
    method Action deq();
    method Bool   notEmpty();
    method t_MSG  receive();

endinterface

typeclass ToConnectionRecv#(type t_IFC, type t_MSG)
    dependencies (t_IFC determines t_MSG);
    // Encode the original data into compressed form.
    function CONNECTION_RECV#(t_MSG) toConnectionRecv (t_IFC ifc);

endtypeclass



// A client sends requests and receives responses
// (which may not come instantly)

interface CONNECTION_CLIENT#(type t_REQ, type t_RSP);

    method Action makeReq(t_REQ data);
    method Bool   reqNotFull();

    method Bool   rspNotEmpty();
    method t_RSP  getRsp();
    method Action deq();
  
endinterface


// A server receives requests and gives back responses
// It can take any amount of time, and there is no assumption
// that the responses are FIFO.

interface CONNECTION_SERVER#(type t_REQ, type t_RSP);

    method t_REQ  getReq();
    method Bool   reqNotEmpty();
    method Action deq();

    method Action makeRsp(t_RSP data);
    method Bool   rspNotFull();
  
endinterface

// Multicast interfaces

// These extend the logical one-to-one communication to a logical one-to-many
// and many-to-one arrangement. A tag indicates message src/dst. Broadcast
// is exposed as a separate primitive operation so that the physical fabric
// can implement it efficiently.

interface CONNECTION_SEND_MULTI#(type t_MSG);

    method Action broadcast(t_MSG msg);
    method Action sendTo(CONNECTION_IDX dst, t_MSG msg);
    method Bool notFull();
 
endinterface

interface CONNECTION_RECV_MULTI#(type t_MSG);
   
    method Action deq();
    method Bool   notEmpty();
    method Tuple2#(CONNECTION_IDX, t_MSG)  receive();

endinterface

interface CONNECTION_CLIENT_MULTI#(type t_REQ, type t_RSP);

    method Action makeReqTo(CONNECTION_IDX dst, t_REQ data);
    method Action broadcastReq(t_REQ data);
    method Bool   reqNotFull();

    method Bool   rspNotEmpty();
    method Tuple2#(CONNECTION_IDX, t_RSP) getRsp();
    method Action deq();

endinterface

interface CONNECTION_SERVER_MULTI#(type t_REQ, type t_RSP);

    method Tuple2#(CONNECTION_IDX, t_REQ) getReq();
    method Bool   reqNotEmpty();
    method Action deq();

    method Action makeRspTo(CONNECTION_IDX dst, t_RSP data);
    method Action broadcastRsp(t_RSP data);
    method Bool   rspNotFull();

endinterface

// Chains
interface CONNECTION_CHAIN#(type msg_T);

    method ActionValue#(msg_T) recvFromPrev();
    method msg_T               peekFromPrev();
    method Bool                recvNotEmpty();

    method Action              sendToNext(msg_T data);
    method Bool                sendNotFull();

endinterface

// Connection Constructors

// These are implemented as calls to the actual constructor dispatcher later.


// Base 1-to-1 logical send.
module [t_CONTEXT] mkConnectionSend#(String name) (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchSend(name, Invalid, defaultValue);
    return m;

endmodule

// 1-to-1 logical send that is optional. (No error if unconnected at top level.)
module [t_CONTEXT] mkConnectionSendOptional#(String name) (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    CONNECTION_SEND_PARAM param = defaultValue;
    param.optional = True;

    let m <- mkConnectionDispatchSend(name, Invalid, param);
    return m;

endmodule

// Expose connection parameters to client
module [t_CONTEXT] mkConnectionSendWithParam#(
    String name,
    CONNECTION_SEND_PARAM param)
    // Interface:
    (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchSend(name, Invalid, param);
    return m;

endmodule

// 1-to-1 logical send that is implemented via a shared interconnect.
module [t_CONTEXT] mkConnectionSendShared#(String name, STATION station) (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchSend(name, tagged Valid station, defaultValue);
    return m;

endmodule

// 1-to-1 logical send that is implemented via a shared interconnect and
// does not result in an error if no dual endpoint is connected to the same
// network. NOTE: Unlike unshared optional these cost actual hardware and
// can generate spurious network traffic! This traffic is dropped by the root
// node.
module [t_CONTEXT] mkConnectionSendSharedOptional#(String name, STATION station) (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    CONNECTION_SEND_PARAM param = defaultValue;
    param.optional = True;

    let m <- mkConnectionDispatchSend(name, tagged Valid station, param);
    return m;

endmodule

// Dummy connection, useful when no data is actually required but a client
// expects a connection.
module mkConnectionSendDummy#(String name) (CONNECTION_SEND#(t_MSG));

    method Action send(t_MSG data) = ?;
    method Bool notFull() = True;

endmodule

// 1-to-Many logical send. These are always optional.
module [t_CONTEXT] mkConnectionSendMulti#(String name) (CONNECTION_SEND_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchSendMulti(name, Invalid, defaultValue);
    return m;

endmodule

// 1-to-Many logical send on a shared interconnect. These are always optional.
// NOTE: Like a 1-to-1 optional shared send, these can generate network traffic
// even if there is no dual endpoint connected to the same network. This
// traffic is dropped at the root node.
module [t_CONTEXT] mkConnectionSendMultiShared#(String name, STATION station) (CONNECTION_SEND_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchSendMulti(name, tagged Valid station, defaultValue);
    return m;

endmodule

// Base 1-to-1 logical receive.
module [t_CONTEXT] mkConnectionRecv#(String name) (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchRecv(name, Invalid, defaultValue);
    return m;

endmodule

// 1-to-1 logical recv that is optional. (No error if unconnected at top level.)
module [t_CONTEXT] mkConnectionRecvOptional#(String name) (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    CONNECTION_RECV_PARAM param = defaultValue;
    param.optional = True;

    let m <- mkConnectionDispatchRecv(name, Invalid, param);
    return m;

endmodule

// Expose connection parameters to client
module [t_CONTEXT] mkConnectionRecvWithParam#(
    String name,
    CONNECTION_RECV_PARAM param)
    // Interface:
    (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchRecv(name, Invalid, param);
    return m;

endmodule

// 1-to-1 logical recv that is implemented using a shared interconnect.
module [t_CONTEXT] mkConnectionRecvShared#(String name, STATION station) (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchRecv(name, tagged Valid station, defaultValue);
    return m;

endmodule

// 1-to-1 logical recv that is implemented using a shared interconnect, and
// does not generate a compilation error if no sender is connected to the same
// network.
module [t_CONTEXT] mkConnectionRecvSharedOptional#(String name, STATION station) (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    CONNECTION_RECV_PARAM param = defaultValue;
    param.optional = True;

    let m <- mkConnectionDispatchRecv(name, tagged Valid station, param);
    return m;

endmodule

// Dummy connection, useful when no data is actually required but a client
// expects a connection.
module mkConnectionRecvDummy#(String name) (CONNECTION_RECV#(t_MSG));

    method Action deq() = ?;
    method Bool   notEmpty() = False;
    method t_MSG  receive() = ?;

endmodule

// Many-to-1 logical receive. These are always optional.
module [t_CONTEXT] mkConnectionRecvMulti#(String name) (CONNECTION_RECV_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchRecvMulti(name, Invalid, defaultValue);
    return m;

endmodule

// Many-to-1 receive using shared interconnect. These are always optional.
module [t_CONTEXT] mkConnectionRecvMultiShared#(String name, STATION station) (CONNECTION_RECV_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchRecvMulti(name, tagged Valid station, defaultValue);
    return m;

endmodule


// Base Client: send requests to 1 logical server, receive responses.
module [t_CONTEXT] mkConnectionClient#(String name) (CONNECTION_CLIENT#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchClient(name, Invalid, defaultValue, defaultValue);
    return m;

endmodule

// Client optional: send requests to 1 logical server, but do not generate a 
// copmilation error if that server does not exist. Requests sent are
// dropped and will never receive a response.
module [t_CONTEXT] mkConnectionClientOptional#(String name) (CONNECTION_CLIENT#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    CONNECTION_SEND_PARAM send_param = defaultValue;
    send_param.optional = True;

    CONNECTION_RECV_PARAM recv_param = defaultValue;
    recv_param.optional = True;

    let m <- mkConnectionDispatchClient(name, Invalid, send_param, recv_param);
    return m;

endmodule

// Client which connects to 1 logical server over a shared interconnect.
module [t_CONTEXT] mkConnectionClientShared#(String name, STATION station) (CONNECTION_CLIENT#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchClient(name, tagged Valid station, defaultValue, defaultValue);
    return m;

endmodule

// Client which connects to 1 server using a shared interconnect and does not
// generate a compilation error if there is no corresponding server connected
// to the same network. NOTE: This will result in hardware and spurious network
// traffic. Any requests sent will be dropped at the root node and never receive
// a response.
module [t_CONTEXT] mkConnectionClientSharedOptional#(String name, STATION station) (CONNECTION_CLIENT#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    CONNECTION_SEND_PARAM send_param = defaultValue;
    send_param.optional = True;

    CONNECTION_RECV_PARAM recv_param = defaultValue;
    recv_param.optional = True;

    let m <- mkConnectionDispatchClient(name, tagged Valid station, send_param, recv_param);
    return m;

endmodule


// Client of Many logical servers. Connect to as many servers as are out there. 
// Send requests to any or all of them, receive responses as a tagged many-to-one.
// These are always optional.
module [t_CONTEXT] mkConnectionClientMulti#(String name) (CONNECTION_CLIENT_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchClientMulti(name, Invalid, defaultValue, defaultValue);
    return m;

endmodule

// Client which sends requests to many servers using a shared interconnect.
// This is always optional and does not generate a compilation error if no 
// corresponding servers are connected to the network. NOTE: This case will result
// in hardware and spurious network traffic. Any requests sent will be dropped
// at the root node and never receive a response.
module [t_CONTEXT] mkConnectionClientMultiShared#(String name, STATION station) (CONNECTION_CLIENT_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchClientMulti(name, tagged Valid station, defaultValue, defaultValue);
    return m;

endmodule


// Base Server: receive requests from 1 logical client, make responses.
module [t_CONTEXT] mkConnectionServer#(String name) (CONNECTION_SERVER#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchServer(name, Invalid, defaultValue, defaultValue);
    return m;

endmodule

// Optional Server: receive requests from up to 1 logical client, make 
// responses. If no client connects no compilation error is generated. Such a
// server will never receive requests, and any responses generated are dropped.
module [t_CONTEXT] mkConnectionServerOptional#(String name) (CONNECTION_SERVER#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    CONNECTION_SEND_PARAM send_param = defaultValue;
    send_param.optional = True;

    CONNECTION_RECV_PARAM recv_param = defaultValue;
    recv_param.optional = True;

    let m <- mkConnectionDispatchServer(name, Invalid, send_param, recv_param);
    return m;

endmodule

// Server of 1 logical client implemented using a shared interconnect.
module [t_CONTEXT] mkConnectionServerShared#(String name, STATION station) (CONNECTION_SERVER#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchServer(name, tagged Valid station, defaultValue, defaultValue);
    return m;

endmodule

// Server of up to 1 logical client implemented using a shared interconnect.
// If no client is present then no compilation error is generated. Instead
// the server will never receive requests. Note that if such a server ever
// generates a response this will result in spurious network traffic that is
// dropped by the root node.
module [t_CONTEXT] mkConnectionServerSharedOptional#(String name, STATION station) (CONNECTION_SERVER#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    CONNECTION_SEND_PARAM send_param = defaultValue;
    send_param.optional = True;

    CONNECTION_RECV_PARAM recv_param = defaultValue;
    recv_param.optional = True;

    let m <- mkConnectionDispatchServer(name, tagged Valid station, send_param, recv_param);
    return m;

endmodule

// Server of Many Clients. Connect to as many clients as are out there. 
// Accept requests from them and send the response only to the requester. 
// This is always optional. If no clients are connected then the server will 
// never receive any requests, and any responses sent will be dropped.
module [t_CONTEXT] mkConnectionServerMulti#(String name) (CONNECTION_SERVER_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchServerMulti(name, Invalid, defaultValue, defaultValue);
    return m;

endmodule

// Server of up to N logical clients connected over a shared interconnect.
// This server is always optional. If no clients are present then the server
// will never receive requests. Note that if such a server ever generates a
// response this will result in spurious network traffic that is dropped by
// the root node.
module [t_CONTEXT] mkConnectionServerMultiShared#(String name, STATION station) (CONNECTION_SERVER_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- mkConnectionDispatchServerMulti(name, tagged Valid station, defaultValue, defaultValue);
    return m;

endmodule


// mkStation deals with connections that are logical point-to-point connections, but that
// are actually implemented via a shared physical interconnect such as a ring or tree.

// These interconnects consist of stations. Shared connections register themselves to particular
// stations. Later the stations themselves are connected into a particular physical topology,
// and a routing table between them is determined.


// Create a new station for a logical tree. If there's already
// a station out there, become it's child. Otherwise we are
// the root node.

module [t_CONTEXT] mkStation#(String station_name)
    // interface:
        (STATION)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    registerStation(station_name, "TREE", "0");

    // If there's a parent station in existence, then add this as a child.
    let currM <- getCurrentStationM();
    
    if (currM matches tagged Valid .parent)
    begin
        registerChildToStation(parent.name, station_name);
    end
    else
    begin
        putRootStationName(station_name);
    end

    method String name() = station_name;

endmodule


// =============================================================================
//
//   Chains
//
// =============================================================================

module [CONNECTED_MODULE] mkConnectionChain#(String chainName)
    //interface:
        (CONNECTION_CHAIN#(t_MSG))
    provisos
	    (Bits#(t_MSG, t_MSG_SZ));

    let c <- mkConnectionDispatchChain(chainName, tagged Invalid, True);
    return c;
endmodule


//
// mkGPMarshalledConnectionChain --
//     A connection chain with external data type t_MSG but internally
//     messages are broken down into t_MARSHALLED chunks.  They are
//     reconstructed as they leave the chain.
//
typedef GetPut#(t_MSG) GP_MARSHALLED_CHAIN#(type t_MARSHALLED, type t_MSG);

module [CONNECTED_MODULE] mkGPMarshalledConnectionChain#(String chainName)
    //interface:
        (GP_MARSHALLED_CHAIN#(t_MARSHALLED, t_MSG))
    provisos
	    (Bits#(t_MSG, t_MSG_SZ),
             Bits#(t_MARSHALLED, t_MARSHALLED_SZ));

    CONNECTION_CHAIN#(t_MARSHALLED) chain <- mkConnectionChain(chainName);

    // Make an inbound marshaller and connect the output of the marshaller
    // to the chain.
    MARSHALLER#(t_MARSHALLED, t_MSG) chainMar <- mkSimpleMarshaller();
    let marToChain <- mkConnection(toGet(chainMar), toPut(chain));

    // Make an outbound demarshaller and connect the output of the chain to
    // the input of the demarshaller.
    DEMARSHALLER#(t_MARSHALLED, t_MSG) chainDem <- mkSimpleDemarshaller();
    let chainToDem <- mkConnection(toGet(chain), toPut(chainDem));

    return tuple2(toGet(chainDem), toPut(chainMar));
endmodule


// =============================================================================
//
//   Helper functions
//
// =============================================================================

instance Connectable#(Get#(data_t), CONNECTION_SEND#(data_t));
    module mkConnection#(Get#(data_t) server,
                         CONNECTION_SEND#(data_t) client) (Empty);
  
        rule connect;
            let data <- server.get();
            client.send(data);
        endrule

    endmodule
endinstance


instance ToPut#(CONNECTION_CLIENT#(t_REQ, t_RSP), t_REQ);
    function Put#(t_REQ) toPut(CONNECTION_CLIENT#(t_REQ, t_RSP) send);
        let put = interface Put;
                      method Action put(t_REQ value) if (send.reqNotFull);
                          send.makeReq(value);
                      endmethod
                  endinterface; 
        return put; 
    endfunction
endinstance

instance ToPut#(CONNECTION_SERVER#(t_REQ, t_RSP), t_RSP);
    function Put#(t_RSP) toPut(CONNECTION_SERVER#(t_REQ, t_RSP) send);
        let put = interface Put;
                      method Action put(t_RSP value) if (send.rspNotFull);
                          send.makeRsp(value);
                      endmethod
                  endinterface; 
        return put; 
    endfunction
endinstance

instance ToGet#(CONNECTION_CLIENT#(t_REQ, t_RSP), t_RSP);
    function Get#(t_RSP) toGet(CONNECTION_CLIENT#(t_REQ, t_RSP) recv);
        let get = interface Get;
                      method ActionValue#(t_RSP) get() if (recv.rspNotEmpty());
                          recv.deq;
                          return recv.getRsp(); 
                      endmethod
                  endinterface;  
        return get;
    endfunction
endinstance

instance ToGet#(CONNECTION_SERVER#(t_REQ, t_RSP), t_REQ);
    function Get#(t_REQ) toGet(CONNECTION_SERVER#(t_REQ, t_RSP) recv);
        let get = interface Get;
                      method ActionValue#(t_REQ) get() if (recv.reqNotEmpty());
                          recv.deq;
                          return recv.getReq(); 
                      endmethod
                  endinterface;  
        return get;
    endfunction
endinstance


instance ToPut#(CONNECTION_SEND#(data_t), data_t);
    function Put#(data_t) toPut(CONNECTION_SEND#(data_t) send);
        let put = interface Put;
                      method Action put(data_t value) if(send.notFull);
                          send.send(value);
                      endmethod
                  endinterface; 
        return put; 
    endfunction
endinstance

instance ToPut#(PHYSICAL_SEND#(data_t), data_t);
    function Put#(data_t) toPut(PHYSICAL_SEND#(data_t) send);
        let put = interface Put;
                      method Action put(data_t value) if(send.notFull()); // Physical sends may be unguarded!
                          send.send(value);
                      endmethod
                  endinterface; 
        return put; 
    endfunction
endinstance

instance ToGet#(CONNECTION_RECV#(data_t), data_t);
    function Get#(data_t) toGet(CONNECTION_RECV#(data_t) recv);
        let get = interface Get;
                      method ActionValue#(data_t) get() if(recv.notEmpty());
                          recv.deq;
                          return recv.receive; 
                      endmethod
                  endinterface;  
        return get;
    endfunction
endinstance

instance Connectable#(CONNECTION_SEND#(data_t), Get#(data_t));
    module mkConnection#(CONNECTION_SEND#(data_t) client, 
                         Get#(data_t) server) (Empty);

        rule connect(client.notFull);
            let data <- server.get();
            client.send(data);
        endrule

    endmodule
endinstance


instance Connectable#(function ActionValue#(data_t) f(),
                      CONNECTION_SEND#(data_t));
    module mkConnection#(function ActionValue#(data_t) f(),
                         CONNECTION_SEND#(data_t) client) (Empty);

        rule connect(client.notFull);
            let data <- f();
            client.send(data);
        endrule

    endmodule
endinstance

instance Connectable#(CONNECTION_SEND#(data_t),
                      function ActionValue#(data_t) f());
    module mkConnection#(CONNECTION_SEND#(data_t) client,
                         function ActionValue#(data_t) f()) (Empty);

        rule connect;
            let data <- f();
            client.send(data);
        endrule

    endmodule
endinstance


instance Connectable#(CONNECTION_RECV#(data_t), Put#(data_t));
    module mkConnection#(CONNECTION_RECV#(data_t) server,
                         Put#(data_t) client) (Empty);
  
        rule connect;
            client.put(server.receive());
            server.deq();
        endrule

    endmodule
endinstance

instance Connectable#(Put#(data_t), CONNECTION_RECV#(data_t));
    module mkConnection#(Put#(data_t) client, 
                         CONNECTION_RECV#(data_t) server) (Empty);

        rule connect;
            client.put(server.receive());
            server.deq();
        endrule

    endmodule
endinstance


instance Connectable#(CONNECTION_RECV#(data_t), function Action f(data_t t));
    module mkConnection#(CONNECTION_RECV#(data_t) server,
                         function Action f(data_t t)) (Empty);

        rule connect;
            f(server.receive());
            server.deq();
        endrule

    endmodule
endinstance

instance Connectable#(function Action f(data_t t), 
                      CONNECTION_RECV#(data_t));
    module mkConnection#(function Action f(data_t t),
                         CONNECTION_RECV#(data_t) server) (Empty);

        rule connect;
            f(server.receive());
            server.deq();
        endrule

    endmodule
endinstance


instance ToPut#(CONNECTION_CHAIN#(data_t), data_t);
    function Put#(data_t) toPut(CONNECTION_CHAIN#(data_t) send);
        let put = interface Put;
                      method Action put(data_t value);
                          send.sendToNext(value);
                      endmethod
                  endinterface; 
        return put; 
    endfunction
endinstance

instance ToGet#(CONNECTION_CHAIN#(data_t), data_t);
    function Get#(data_t) toGet(CONNECTION_CHAIN#(data_t) recv);
        let get = interface Get;
                      method ActionValue#(data_t) get();
                          let data <- recv.recvFromPrev();
                          return data;
                      endmethod
                  endinterface;  
        return get;
    endfunction
endinstance

instance Connectable#(Get#(data_t), CONNECTION_CHAIN#(data_t));
    module mkConnection#(Get#(data_t) server,
                         CONNECTION_CHAIN#(data_t) client) (Empty);
  
        rule connect;
            let data <- server.get();
            toPut(client).put(data);
        endrule

    endmodule
endinstance

instance Connectable#(CONNECTION_CHAIN#(data_t), Get#(data_t));
    module mkConnection#(CONNECTION_CHAIN#(data_t) client, 
                         Get#(data_t) server) (Empty);

        rule connect;
            let data <- server.get();
            toPut(client).put(data);
        endrule

    endmodule
endinstance


instance Connectable#(function ActionValue#(data_t) f(),
                      CONNECTION_CHAIN#(data_t));
    module mkConnection#(function ActionValue#(data_t) f(),
                         CONNECTION_CHAIN#(data_t) client) (Empty);

        rule connect;
            let data <- f();
            toPut(client).put(data);
        endrule

    endmodule
endinstance

instance Connectable#(CONNECTION_CHAIN#(data_t),
                      function ActionValue#(data_t) f());
    module mkConnection#(CONNECTION_CHAIN#(data_t) client,
                         function ActionValue#(data_t) f()) (Empty);

        rule connect;
            let data <- f();
            toPut(client).put(data);
        endrule

    endmodule
endinstance


instance Connectable#(CONNECTION_CHAIN#(data_t), Put#(data_t));
    module mkConnection#(CONNECTION_CHAIN#(data_t) server,
                         Put#(data_t) client) (Empty);
  
        rule connect;
            let data <- toGet(server).get();
            client.put(data);
        endrule

    endmodule
endinstance

instance Connectable#(Put#(data_t), CONNECTION_CHAIN#(data_t));
    module mkConnection#(Put#(data_t) client, 
                         CONNECTION_CHAIN#(data_t) server) (Empty);

        rule connect;
            let data <- toGet(server).get();
            client.put(data);
        endrule

    endmodule
endinstance


instance Connectable#(CONNECTION_CHAIN#(data_t), function Action f(data_t t));
    module mkConnection#(CONNECTION_CHAIN#(data_t) server,
                         function Action f(data_t t)) (Empty);

        rule connect;
            let data <- toGet(server).get();
            f(data);
        endrule

    endmodule
endinstance

instance Connectable#(function Action f(data_t t), 
                      CONNECTION_CHAIN#(data_t));
    module mkConnection#(function Action f(data_t t),
                         CONNECTION_CHAIN#(data_t) server) (Empty);

        rule connect;
            let data <- toGet(server).get();
            f(data);
        endrule

    endmodule
endinstance


//
// Convert a libRL marshaller to a CONNECTION_SEND.
//
function CONNECTION_SEND#(t_DATA) marshallerToConnectionSend(MARSHALLER#(t_FIFO_DATA, t_DATA) mar);
    return
        interface CONNECTION_SEND#(t_DATA);
            method Action send(t_DATA data) = mar.enq(data);
            method Bool notFull() = mar.notFull();
        endinterface;
endfunction

//
// Convert a libRL demarshaller to a CONNECTION_RECV.
//
function CONNECTION_RECV#(t_DATA) demarshallerToConnectionReceive(DEMARSHALLER#(t_FIFO_DATA, t_DATA) dem);
    return
        interface CONNECTION_RECV#(t_DATA);
            method Action deq() = dem.deq();
            method Bool notEmpty() = dem.notEmpty();
            method t_DATA receive() = dem.first();
        endinterface;
endfunction




