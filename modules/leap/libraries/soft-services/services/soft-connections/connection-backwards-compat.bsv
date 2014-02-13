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

import GetPut::*;


`include "awb/provides/soft_connections_common.bsh"

// Backwards compatability

// This file contains MOST of the code needed for backwards compatability.
// Some code, particularly relating to connection chains, lives in other 
// files because other things need to invoke it.

// This file mostly deals with backwards compatability functions and 
// interfaces seen by the user.


// Legacy typdefs
typedef CONNECTED_MODULE Connected_Module;
typedef CONNECTED_MODULE ConnectedModule;

//The data type that is sent in connections
typedef `CON_CWIDTH PHYSICAL_CONNECTION_SIZE;
typedef Bit#(PHYSICAL_CONNECTION_SIZE) CON_Data;

typedef `CON_CHAIN_CWIDTH CON_CHAIN_DATA_SZ;
typedef Bit#(CON_CHAIN_DATA_SZ) CON_CHAIN_Data;

// Legacy naming conventions

typedef CONNECTION_SEND#(t) Connection_Send#(type t);
typedef CONNECTION_RECV#(t) Connection_Receive#(type t);

module [ConnectedModule] mkConnection_Send#(String name) (Connection_Send#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionSend(name);
   return m;

endmodule

module [ConnectedModule] mkConnection_Receive#(String name) (Connection_Receive#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE));

   let m <- mkConnectionRecv(name);
   return m;

endmodule


interface Connection_Server#(type req_T, type resp_T);

  method Bool   reqNotEmpty(); 
  method req_T  getReq();
  method Action deq();
  method Action makeResp(resp_T data);
  method Bool   respNotFull();
  
endinterface


module [ConnectedModule] mkConnection_Server#(String server_name)
    //interface:
                (Connection_Server#(t_REQ, t_RSP))
    provisos
            (Bits#(t_REQ, t_REQ_SIZE),
	     Bits#(t_RSP, t_RSP_SIZE));

  CONNECTION_SERVER#(t_REQ, t_RSP) s <- mkConnectionServer(server_name);

  method Bool   reqNotEmpty() = s.reqNotEmpty();
  method t_REQ  getReq() = s.getReq();
  method Action deq() = s.deq();
  method Action makeResp(t_RSP data) = s.makeRsp(data);
  method Bool   respNotFull() = s.rspNotFull();

endmodule

interface Connection_Client#(type req_T, type resp_T);

  method Action makeReq(req_T data);
  method Bool   reqNotFull();
  method Bool   respNotEmpty(); 
  method resp_T getResp();
  method Action deq();
  
endinterface

module [ConnectedModule] mkConnection_Client#(String client_name)
    //interface:
                (Connection_Client#(t_REQ, t_RSP))
    provisos
            (Bits#(t_REQ, t_REQ_SIZE),
	     Bits#(t_RSP, t_RSP_SIZE));

  CONNECTION_CLIENT#(t_REQ, t_RSP) c <- mkConnectionClient(client_name);

  method Action makeReq(t_REQ data) = c.makeReq(data);
  method Bool   respNotEmpty() = c.rspNotEmpty();
  method t_RSP  getResp() = c.getRsp();
  method Action deq() = c.deq();
  method Bool   reqNotFull() = c.reqNotFull();

endmodule


interface Connection_Chain#(type msg_T);

  method ActionValue#(msg_T) recvFromPrev();
  method msg_T               peekFromPrev();
  method Bool                recvNotEmpty();

  method Action              sendToNext(msg_T data);
  method Bool                sendNotFull();
  
endinterface


module [ConnectedModule] mkConnection_Chain#(Integer chain_id)
    //interface:
		(Connection_Chain#(msg_T))
    provisos
	    (Bits#(msg_T, msg_SZ));
  CONNECTION_CHAIN#(msg_T) c <- mkConnectionChain("OldSchoolChain" + integerToString(chain_id));

  method recvFromPrev = c.recvFromPrev;
  method peekFromPrev = c.peekFromPrev;
  method recvNotEmpty = c.recvNotEmpty;

  method sendToNext = c.sendToNext;
  method sendNotFull = c.sendNotFull;

endmodule


instance ToPut#(Connection_Server#(t_REQ, t_RSP), t_RSP);
    function Put#(t_RSP) toPut(Connection_Server#(t_REQ, t_RSP) send);
        let put = interface Put;
                      method Action put(t_RSP value) if (send.respNotFull);
                          send.makeResp(value);
                      endmethod
                  endinterface; 
        return put; 
    endfunction
endinstance

instance ToGet#(Connection_Server#(t_REQ, t_RSP), t_REQ);
    function Get#(t_REQ) toGet(Connection_Server#(t_REQ, t_RSP) recv);
        let get = interface Get;
                      method ActionValue#(t_REQ) get() if (recv.reqNotEmpty());
                          recv.deq;
                          return recv.getReq(); 
                      endmethod
                  endinterface;  
        return get;
    endfunction
endinstance

instance ToPut#(Connection_Client#(t_REQ, t_RSP), t_REQ);
    function Put#(t_REQ) toPut(Connection_Client#(t_REQ, t_RSP) send);
        let put = interface Put;
                      method Action put(t_REQ value) if (send.reqNotFull);
                          send.makeReq(value);
                      endmethod
                  endinterface; 
        return put; 
    endfunction
endinstance

instance ToGet#(Connection_Client#(t_REQ, t_RSP), t_RSP);
    function Get#(t_RSP) toGet(Connection_Client#(t_REQ, t_RSP) recv);
        let get = interface Get;
                      method ActionValue#(t_RSP) get() if (recv.respNotEmpty());
                          recv.deq;
                          return recv.getResp(); 
                      endmethod
                  endinterface;  
        return get;
    endfunction
endinstance
