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

// The actual instatiation of a physical send. For efficiency contains an 
// unguarded FIFO, which makes the scheduler's life much easier.
// The dispatcher which invokes this may guard the FIFO as appropriate.

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
