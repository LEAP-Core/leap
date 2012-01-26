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

// The actual instatiation of a physical send. For efficiency contains an 
// unguarded FIFO, which makes the scheduler's life much easier.
// The dispatcher which invokes this may guard the FIFO as appropriate.


`include "awb/provides/physical_platform.bsh"


module [t_CONTEXT] mkPhysicalConnectionSend#(
    String send_name,
    Maybe#(STATION) m_station,
    Bool optional,
    String original_type,
    Bool enableDebug)
    // interface:
        (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Local clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();

    // ****** Local State ****** //

    // This queue could be turned into a BypassFIFO to reduce latency. 
    FIFOF#(t_MSG) q <- mkUGSizedFIFOF(`CON_BUFFERING);
    
    // Bind a local interface to a name for convenience.
    let outg = (interface PHYSICAL_CONNECTION_OUT;

                 // Marshall up the first thing in the queue.
	         method PHYSICAL_CONNECTION_DATA first();
                      Bit#(t_MSG_SIZE) tmp = pack(q.first());
                      return zeroExtendNP(tmp);
                 endmethod
                 
                 // As we use an unguarded FIFO we must explicitly dequeue.
                 method Bool notEmpty() = q.notEmpty();
                 
                 // If we were successful we can dequeue.
	         method Action deq() = q.deq();

                 interface Clock clock = localClock;
                 interface Reset reset = localReset;

	       endinterface);

    // Collect up our info.
    String platformName <- getSynthesisBoundaryPlatform(); 
    let info = 
        LOGICAL_SEND_INFO 
        {
            logicalName: send_name, 
            logicalType: original_type, 
            computePlatform: platformName,
            bitWidth: valueof(SizeOf#(t_MSG)), 
            optional: optional, 
            outgoing: outg
        };

    // Is this a shared connection?
    if (m_station matches tagged Valid .station)
    begin

        // Yes, so register ourselves with that station.
        registerSendToStation(info, station.name);

    end
    else
    begin

        // Nope, so just register and try to find a match.
        registerSend(info);

    end


    // ****** Register debug state ****** //

    if (enableDebug)
    begin
        let dbg_state = (
            interface PHYSICAL_CONNECTION_DEBUG_STATE;
                method Bool notEmpty() = q.notEmpty();
                method Bool notFull() = q.notFull();
            endinterface);

        let dbg_info =
            CONNECTION_DEBUG_INFO
            {
                sendName: send_name,
                state: dbg_state
            };

        addConnectionDebugInfo(dbg_info);
    end


    // ****** Interface to User ****** //

    // This just accesses the internal queue.

    method Action send(t_MSG data);

        q.enq(data);

    endmethod

    method Bool notFull() = q.notFull();

endmodule


// The actual instantation of the physical receive. Just contains wires.

module [t_CONTEXT] mkPhysicalConnectionRecv#(String recv_name, Maybe#(STATION) m_station, Bool optional, String original_type)
    // interface:
        (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Local Clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();

    // ****** Local State ****** //

    // Some wires for interacting with our counterpart.
    PulseWire      enW    <- mkPulseWire();
    RWire#(t_MSG)  dataW  <- mkRWire();

    // Bind a local interface to a name for convenience.
    let inc = (interface PHYSICAL_CONNECTION_IN;

                 // Part 1 of the anti-method to get(). Unmarshall the data and send it on the wire.
	         method Action try(PHYSICAL_CONNECTION_DATA d);
                     Bit#(t_MSG_SZ) tmp = truncateNP(d);
	             dataW.wset(unpack(tmp));
	         endmethod

	         // Part 2 of the anti-method to get(). If someone actually was listening, then the get() succeeded.
                 method Bool success();
	           return enW;
	         endmethod

                 interface Clock clock = localClock;
                 interface Reset reset = localReset;

	       endinterface);

    // Collect up our info.
    String platformName <- getSynthesisBoundaryPlatform(); 
    let info = 
        LOGICAL_RECV_INFO 
        {
            logicalName: recv_name, 
            logicalType: original_type, 
            computePlatform: platformName,
            bitWidth: valueof(SizeOf#(t_MSG)), 
            optional: optional, 
            incoming: inc
        };

    // Is this a shared connection?
    if (m_station matches tagged Valid .station)
    begin

        // Yes, but we don't do any actual connecting now, because if 
        // our counterpart registers with the same station
        // we become point-to-point.
        registerRecvToStation(info, station.name);

    end
    else
    begin

        // Nope, so just register and try to find a match.
        registerRecv(info);

    end


    // ****** Interface ****** //

    // These methods are unguarded. The invoker of this may add a guard as
    // appropriate.

    method t_MSG receive();
        return validValue(dataW.wget());
    endmethod

    method Bool notEmpty();
        return isValid(dataW.wget());
    endmethod

    method Action deq();
        enW.send();
    endmethod

endmodule

// The actual instatiation of a physical send multicast. For efficiency contains an 
// unguarded FIFO, which makes the scheduler's life much easier.
// The dispatcher which invokes this may guard the FIFO as appropriate.

module [t_CONTEXT] mkPhysicalConnectionSendMulti#(
    String send_name,
    Maybe#(STATION) m_station,
    String original_type,
    Bool enableDebug)
    //interface:
        (CONNECTION_SEND_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Local clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();

    // ****** Local State ****** //

    FIFOF#(Tuple2#(CONNECTION_TAG, t_MSG)) q <- mkUGSizedFIFOF(`CON_BUFFERING);
    
    // Bind a local interface to a name for convenience.
    let outg = (interface PHYSICAL_CONNECTION_OUT_MULTI;

                 // Marshall up the first thing in the queue.
	         method Tuple2#(CONNECTION_TAG, PHYSICAL_CONNECTION_DATA) first();
                      match {.tag, .data} = q.first();
                      Bit#(t_MSG_SIZE) tmp = pack(data);
                      PHYSICAL_CONNECTION_DATA tmp2 = zeroExtendNP(tmp);
                      return tuple2(tag, tmp2);
                 endmethod
                 
                 // As we use an unguarded FIFO we must explicitly dequeue.
                 method Bool notEmpty() = q.notEmpty();
                 
                 // If we were successful we can dequeue.
	         method Action deq() = q.deq();

                 interface Clock clock = localClock;
                 interface Reset reset = localReset;

	       endinterface);

    // Collect up our info.
    String platformName <- getSynthesisBoundaryPlatform(); 
    let info = 
        LOGICAL_SEND_MULTI_INFO 
        {
            logicalName: send_name, 
            logicalType: original_type, 
            computePlatform: platformName,
            outgoing: outg
        };

    // Is this a shared connection?
    if (m_station matches tagged Valid .station)
    begin

        // Yes, so register ourselves with that station.
        registerSendMultiToStation(info, station.name);

    end
    else
    begin

        // Nope, so just register and try to find a match.
        registerSendMulti(info);

    end


    // ****** Register debug state ****** //

    if (enableDebug)
    begin
        let dbg_state = (
            interface PHYSICAL_CONNECTION_DEBUG_STATE;
                method Bool notEmpty() = q.notEmpty();
                method Bool notFull() = q.notFull();
            endinterface);

        let dbg_info =
            CONNECTION_DEBUG_INFO
            {
                sendName: send_name,
                state: dbg_state
            };

        addConnectionDebugInfo(dbg_info);
    end


    // ****** Interface to User ****** //

    // This just accesses the internal queue.

    method Action broadcast(t_MSG data);

        q.enq(tuple2(tagged CONNECTION_BROADCAST, data));

    endmethod

    method Action sendTo(CONNECTION_IDX dst, t_MSG data);

        q.enq(tuple2(tagged CONNECTION_ROUTED dst, data));

    endmethod

    method Bool notFull() = q.notFull();

endmodule


// The actual instantation of the physical many-to-one receive. Just contains wires.
module [t_CONTEXT] mkPhysicalConnectionRecvMulti#(String recv_name, Maybe#(STATION) m_station, String original_type)
    // interface:
        (CONNECTION_RECV_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Local Clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();

    // ****** Local State ****** //

    // Some wires for interacting with our counterpart.
    PulseWire                              enW    <- mkPulseWire();
    RWire#(Tuple2#(CONNECTION_IDX, t_MSG)) dataW  <- mkRWire();

    // Bind a local interface to a name for convenience.
    let inc = (interface PHYSICAL_CONNECTION_IN_MULTI;

                 // Part 1 of the anti-method to get(). Unmarshall the data and send it on the wire.
	         method Action try(CONNECTION_IDX src, PHYSICAL_CONNECTION_DATA d);
                     Bit#(t_MSG_SZ) tmp = truncateNP(d);
	             dataW.wset(tuple2(src, unpack(tmp)));
	         endmethod

	         // Part 2 of the anti-method to get(). If someone actually was listening, then the get() succeeded.
                 method Bool success();
	           return enW;
	         endmethod

                 interface Clock clock = localClock;
                 interface Reset reset = localReset;

	       endinterface);

    // Collect up our info.
    String platformName <- getSynthesisBoundaryPlatform(); 
    let info = 
        LOGICAL_RECV_MULTI_INFO 
        {
            logicalName: recv_name, 
            logicalType: original_type,  
            computePlatform: platformName,
            incoming: inc
        };

    // Is this a shared connection?
    if (m_station matches tagged Valid .station)
    begin

        // Yes, so let the station know we're here.
        registerRecvMultiToStation(info, station.name);

    end
    else
    begin

        // Nope, so just register and try to find a match.
        registerRecvMulti(info);

    end


    // ****** Interface ****** //

    // These methods are unguarded. The invoker of this may add a guard as
    // appropriate.

    method Tuple2#(CONNECTION_IDX, t_MSG) receive();
        return validValue(dataW.wget());
    endmethod

    method Bool notEmpty();
        return isValid(dataW.wget());
    endmethod

    method Action deq();
        enW.send();
    endmethod

endmodule

module [t_CONTEXT] mkPhysicalConnectionChain#(String chain_name, String original_type)
    //interface:
		(CONNECTION_CHAIN#(msg_T))
    provisos
	    (Bits#(msg_T, msg_SZ),
             Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
             IsModule#(t_CONTEXT, t_DUMMY));

  // Local Clock and reset
  Clock localClock <- exposeCurrentClock();
  Reset localReset <- exposeCurrentReset();

  RWire#(msg_T)  dataW  <- mkRWire();
  PulseWire      enW    <- mkPulseWire();
  FIFOF#(msg_T)  q       <- mkUGFIFOF();

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

  String platform <- getSynthesisBoundaryPlatform();

  // Collect up our info.
  let info = 
      LOGICAL_CHAIN_INFO 
      {
          logicalName: chain_name, 
          logicalType: original_type, 
          computePlatform: platform,
          bitWidth: valueof(SizeOf#(msg_T)),  
          incoming: inc,
          outgoing: outg
      };

  String platformName <- getSynthesisBoundaryPlatform(); 
  if(platformName == fpgaPlatformName)
    begin
      // Register the chain
      registerChain(info);
    end

  method msg_T peekFromPrev() if (dataW.wget() matches tagged Valid .val);
    return val;
  endmethod 

  method Bool recvNotEmpty();
    return isValid(dataW.wget());
  endmethod 

  method sendNotFull = q.notFull;

  method Action sendToNext(msg_T data) if (q.notFull());
    q.enq(data);
  endmethod

  method ActionValue#(msg_T) recvFromPrev() if (dataW.wget() matches tagged Valid .val);

    enW.send();
    return val;

  endmethod

endmodule
