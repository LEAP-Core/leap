import FIFOF::*;

//-------------------- Soft Connections --------------------------//
//                                                                //
// This file contains the user-visible interfaces and constructors//
// for Soft Connections, which are conected by name at compilation//
// time.                                                          //
//----------------------------------------------------------------//


// The basic sending half of a connection.

interface CONNECTION_SEND#(type t_MSG);

    method Action send(t_MSG data);
    method Bool notFull();
  
endinterface


// The basic receiving connection.

interface CONNECTION_RECV#(type t_MSG);
  
    method Action deq();
    method Bool   notEmpty();
    method t_MSG  receive();

endinterface


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
// It can take any amount of time. Hopefully the responses are FIFO,
// but the interface does not actually enforce this.

interface CONNECTION_SERVER#(type t_REQ, type t_RSP);

    method t_REQ  getReq();
    method Bool   reqNotEmpty();
    method Action deq();

    method Action makeRsp(t_RSP data);
    method Bool   rspNotFull();
  
endinterface

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

// Connection Constructors

// These are implemented as calls to the actual constructor dispatcher later.


// Base 1-to-1 logical send.
module [CONNECTED_MODULE] mkConnectionSend#(String name) (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchSend(name, Invalid, False, True);
   return m;

endmodule

// 1-to-1 logical send that is optional. (No error if unconnected at top level.)
module [CONNECTED_MODULE] mkConnectionSendOptional#(String name) (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchSend(name, Invalid, True, True);
   return m;

endmodule

// 1-to-1 logical send that is implemented via a shared interconnect.
module [CONNECTED_MODULE] mkConnectionSendShared#(String name, STATION station) (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchSend(name, tagged Valid station, False, True);
   return m;

endmodule

// 1-to-1 logical send that is implemented via a shared interconnect and
// does not result in an error if no dual endpoint is connected to the same
// network. NOTE: Unlike unshared optional these cost actual hardware and
// can generate spurious network traffic! This traffic is dropped by the root
// node.
module [CONNECTED_MODULE] mkConnectionSendSharedOptional#(String name, STATION station) (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchSend(name, tagged Valid station, True, True);
   return m;

endmodule

// 1-to-Many logical send. These are always optional.
module [CONNECTED_MODULE] mkConnectionSendMulti#(String name) (CONNECTION_SEND_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchSendMulti(name, Invalid, True);
   return m;

endmodule

// 1-to-Many logical send on a shared interconnect. These are always optional.
// NOTE: Like a 1-to-1 optional shared send, these can generate network traffic
// even if there is no dual endpoint connected to the same network. This
// traffic is dropped at the root node.
module [CONNECTED_MODULE] mkConnectionSendMultiShared#(String name, STATION station) (CONNECTION_SEND_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchSendMulti(name, tagged Valid station, True);
   return m;

endmodule

// Base 1-to-1 logical receive.
module [CONNECTED_MODULE] mkConnectionRecv#(String name) (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchRecv(name, Invalid, False, True);
   return m;

endmodule

// 1-to-1 logical recv that is optional. (No error if unconnected at top level.)
module [CONNECTED_MODULE] mkConnectionRecvOptional#(String name) (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchRecv(name, Invalid, True, True);
   return m;

endmodule

// 1-to-1 logical recv that is implemented using a shared interconnect.
module [CONNECTED_MODULE] mkConnectionRecvShared#(String name, STATION station) (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchRecv(name, tagged Valid station, False, True);
   return m;

endmodule

// 1-to-1 logical recv that is implemented using a shared interconnect, and
// does not generate a compilation error if no sender is connected to the same
// network.
module [CONNECTED_MODULE] mkConnectionRecvSharedOptional#(String name, STATION station) (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchRecv(name, tagged Valid station, True, True);
   return m;

endmodule

// Many-to-1 logical receive. These are always optional.
module [CONNECTED_MODULE] mkConnectionRecvMulti#(String name) (CONNECTION_RECV_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchRecvMulti(name, Invalid, True);
   return m;

endmodule

// Many-to-1 receive using shared interconnect. These are always optional.
module [CONNECTED_MODULE] mkConnectionRecvMultiShared#(String name, STATION station) (CONNECTION_RECV_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionDispatchRecvMulti(name, tagged Valid station, True);
   return m;

endmodule


// Base Client: send requests to 1 logical server, receive responses.
module [CONNECTED_MODULE] mkConnectionClient#(String name) (CONNECTION_CLIENT#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchClient(name, Invalid, False, True);
   return m;

endmodule

// Client optional: send requests to 1 logical server, but do not generate a 
// copmilation error if that server does not exist. Requests sent are
// dropped and will never receive a response.
module [CONNECTED_MODULE] mkConnectionClientOptional#(String name) (CONNECTION_CLIENT#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchClient(name, Invalid, True, True);
   return m;

endmodule

// Client which connects to 1 logical server over a shared interconnect.
module [CONNECTED_MODULE] mkConnectionClientShared#(String name, STATION station) (CONNECTION_CLIENT#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchClient(name, tagged Valid station, False, True);
   return m;

endmodule

// Client which connects to 1 server using a shared interconnect and does not
// generate a compilation error if there is no corresponding server connected
// to the same network. NOTE: This will result in hardware and spurious network
// traffic. Any requests sent will be dropped at the root node and never receive
// a response.
module [CONNECTED_MODULE] mkConnectionClientSharedOptional#(String name, STATION station) (CONNECTION_CLIENT#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchClient(name, tagged Valid station, True, True);
   return m;

endmodule


// Client of Many logical servers. Connect to as many servers as are out there. 
// Send requests to any or all of them, receive responses as a tagged many-to-one.
// These are always optional.
module [CONNECTED_MODULE] mkConnectionClientMulti#(String name) (CONNECTION_CLIENT_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchClientMulti(name, Invalid, True);
   return m;

endmodule

// Client which sends requests to many servers using a shared interconnect.
// This is always optional and does not generate a compilation error if no 
// corresponding servers are connected to the network. NOTE: This case will result
// in hardware and spurious network traffic. Any requests sent will be dropped
// at the root node and never receive a response.
module [CONNECTED_MODULE] mkConnectionClientMultiShared#(String name, STATION station) (CONNECTION_CLIENT_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchClientMulti(name, tagged Valid station, True);
   return m;

endmodule


// Base Server: receive requests from 1 logical client, make responses.
module [CONNECTED_MODULE] mkConnectionServer#(String name) (CONNECTION_SERVER#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchServer(name, Invalid, False, True);
   return m;

endmodule

// Optional Server: receive requests from up to 1 logical client, make 
// responses. If no client connects no compilation error is generated. Such a
// server will never receive requests, and any responses generated are dropped.
module [CONNECTED_MODULE] mkConnectionServerOptional#(String name) (CONNECTION_SERVER#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchServer(name, Invalid, True, True);
   return m;

endmodule

// Server of 1 logical client implemented using a shared interconnect.
module [CONNECTED_MODULE] mkConnectionServerShared#(String name, STATION station) (CONNECTION_SERVER#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchServer(name, tagged Valid station, False, True);
   return m;

endmodule

// Server of up to 1 logical client implemented using a shared interconnect.
// If no client is present then no compilation error is generated. Instead
// the server will never receive requests. Note that if such a server ever
// generates a response this will result in spurious network traffic that is
// dropped by the root node.
module [CONNECTED_MODULE] mkConnectionServerSharedOptional#(String name, STATION station) (CONNECTION_SERVER#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchServer(name, tagged Valid station, True, True);
   return m;

endmodule

// Server of Many Clients. Connect to as many clients as are out there. 
// Accept requests from them and send the response only to the requester. 
// This is always optional. If no clients are connected then the server will 
// never receive any requests, and any responses sent will be dropped.
module [CONNECTED_MODULE] mkConnectionServerMulti#(String name) (CONNECTION_SERVER_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchServerMulti(name, Invalid, True);
   return m;

endmodule

// Server of up to N logical clients connected over a shared interconnect.
// This server is always optional. If no clients are present then the server
// will never receive requests. Note that if such a server ever generates a
// response this will result in spurious network traffic that is dropped by
// the root node.
module [CONNECTED_MODULE] mkConnectionServerMultiShared#(String name, STATION station) (CONNECTION_SERVER_MULTI#(t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SIZE),
         Bits#(t_RSP, t_RSP_SIZE));

   let m <- mkConnectionDispatchServerMulti(name, tagged Valid station, True);
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

module [ConnectedModule] mkStation#(String station_name)
    // interface:
        (STATION);

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
