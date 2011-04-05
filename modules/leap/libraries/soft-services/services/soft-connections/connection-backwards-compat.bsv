`include "asim/provides/soft_connections_common.bsh"

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


module [ConnectedModule] mkConnection_Chain#(Integer chain_num)
    //interface:
		(Connection_Chain#(msg_T))
    provisos
	    (Bits#(msg_T, msg_SZ));

  // Local Clock and reset
  Clock localClock <- exposeCurrentClock();
  Reset localReset <- exposeCurrentReset();

  RWire#(msg_T)  dataW  <- mkRWire();
  PulseWire      enW    <- mkPulseWire();
  FIFOF#(msg_T)  q       <- mkFIFOF();

  let inc = (interface PHYSICAL_CHAIN_IN;

               // Part 1 of the anti-method to get(). Unmarshall the data and send it on the wire.
               method Action try(x);
                 Bit#(msg_SZ) tmp = truncateNP(x);
                 dataW.wset(unpack(tmp));
               endmethod

               // Part 2 of the anti-method to get(). If someone actually was listening, then the get() succeeded.
               method Bool success();
                 return enW;
               endmethod

               interface Clock clock = localClock;
               interface Reset reset = localReset;               
              
     	     endinterface);

  let outg = (interface PHYSICAL_CHAIN_OUT;

               // Trying to transmit something means marshalling up the first thing in the queue.
	       method PHYSICAL_CHAIN_DATA first();
                 Bit#(msg_SZ) tmp = pack(q.first());
                 return zeroExtendNP(tmp);
               endmethod

               // Sometimes its useful to have an explicit notEmpty
               method Bool notEmpty() = q.notEmpty();

               // If we were successful we can dequeue.
	       method Action deq() = q.deq();

               interface Clock clock = localClock;
               interface Reset reset = localReset;

	     endinterface);

  //Figure out my type for typechecking
  msg_T msg = ?;
  String my_type = printType(typeOf(msg));

  // Collect up our info.
  let info = 
      LOGICAL_CHAIN_INFO 
      {
          logicalIdx: chain_num, 
          logicalType: my_type, 
          incoming: inc,
          outgoing: outg
      };

  // Register the chain
  registerChain(info);

  method msg_T peekFromPrev() if (dataW.wget() matches tagged Valid .val);
    return val;
  endmethod 

  method Bool recvNotEmpty();
    Bool retVal = False;
    if(dataW.wget() matches tagged Valid .val)
      begin
        retVal = True;
      end
    return retVal;
  endmethod 

  method sendNotFull = q.notFull;

  method Action sendToNext(msg_T data);
    q.enq(data);
  endmethod

  method ActionValue#(msg_T) recvFromPrev() if (dataW.wget() matches tagged Valid .val);

    enW.send();
    return val;

  endmethod

endmodule
