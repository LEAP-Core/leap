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

import SpecialFIFOs::*;

`include "awb/provides/librl_bsv_base.bsh"

//
// The actual instatiation of a physical send. For efficiency contains an 
// unguarded FIFO, which makes the scheduler's life much easier.
// The dispatcher which invokes this may guard the FIFO as appropriate.
//
module [t_CONTEXT] mkPhysicalConnectionSend#(String send_name,
                                             Maybe#(STATION) m_station,
                                             String original_type,
                                             CONNECTION_SEND_PARAM param)
    // Interface:
    (PHYSICAL_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Local clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();

    // ****** Local State ****** //
 
    SCFIFOF#(t_MSG) sc_buffer = ?; 
    FIFOF#(t_MSG) q = ?; 
    if (param.enableLatency)
    begin
        sc_buffer <- mkSCFIFOFUG(); 
        q = sc_buffer.fifo;  
    end
    else if (param.nBufferSlots == 0)
    begin
        q <- mkBypassFIFOF();
    end
    else 
    begin
        q <- mkUGSizedFIFOF(param.nBufferSlots);
    end
  
    // some wiring needed in the multi-FPGA implementations
    PulseWire sendDequeued <- mkPulseWire;

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
                    method Action deq();
                        q.deq();
                        sendDequeued.send;
                        if (`DUMP_CHANNEL_TRAFFIC_ENABLE != 0)
                        begin
                            $display(fshow("Dequeue:" + send_name + ":") + fshow(pack(q.first))); 
                        end                  
                    endmethod                     
                    
                    interface Clock clock = localClock;
                    interface Reset reset = localReset;

                endinterface);

    // Collect up our info.
    String moduleName <- getSynthesisBoundaryName(); 
    let info = 
        LOGICAL_SEND_INFO 
        {
            logicalType: original_type, 
            moduleName: moduleName,
            bitWidth: valueof(SizeOf#(t_MSG)), 
            optional: param.optional, 
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
        registerSend(send_name, info);
    end


    // ****** Register debug state ****** //

    if (param.enableDebug)
    begin
        Bool not_empty = q.notEmpty();
        if (param.nBufferSlots == 0)
        begin
            // With a bypass FIFO, reading both notFull and notEmpty leads to
            // a cycle.
            not_empty = False;
        end

        let dbg_state = (
            interface PHYSICAL_CONNECTION_DEBUG_STATE;
                method Bool notEmpty() = not_empty;
                method Bool notFull() = q.notFull;
                method Bool dequeued() = sendDequeued;
            endinterface);

        let dbg_info =
            CONNECTION_DEBUG_INFO
            {
                sendName: send_name,
                state: dbg_state
            };

        addConnectionDebugInfo(dbg_info);
    end

    if(`CON_LATENCY_ENABLE > 0)
    begin
        addConnectionLatencyInfo(CONNECTION_LATENCY_INFO{ sendName: send_name, control:sc_buffer.control});
    end

    // ****** Interface to User ****** //

    // This just accesses the internal queue.

    method Action send(t_MSG data);
        q.enq(data);
    endmethod

    method Bool notFull() = q.notFull();

    method Bool dequeued() = sendDequeued;
endmodule


// The actual instantation of the physical receive. Just contains wires.

module [t_CONTEXT] mkPhysicalConnectionRecv#(String recv_name,
                                             Maybe#(STATION) m_station,
                                             String original_type,
                                             CONNECTION_RECV_PARAM param)
    // Interface:
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

                   // Part 2 of the anti-method to get(). If someone actually was listening, then the get() succeeded.
                   method Bool dequeued();
                       return enW;
                   endmethod

                   interface Clock clock = localClock;
                   interface Reset reset = localReset;

               endinterface);

    // Collect up our info.
    String moduleName   <- getSynthesisBoundaryName(); 
    let info = 
        LOGICAL_RECV_INFO 
        {
            logicalType: original_type, 
            moduleName: moduleName,
            bitWidth: valueof(SizeOf#(t_MSG)), 
            optional: param.optional, 
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
        registerRecv(recv_name, info);
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

module [t_CONTEXT] mkPhysicalConnectionSendMulti#(String send_name,
                                                  Maybe#(STATION) m_station,
                                                  String original_type,
                                                  CONNECTION_SEND_PARAM param)
    // Interface:
    (PHYSICAL_SEND_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SIZE),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Local clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();

    // ****** Local State ****** //

    FIFOF#(Tuple2#(CONNECTION_TAG, t_MSG)) q <- mkUGSizedFIFOF(`CON_BUFFERING);
    
    // some wiring needed in the multi-FPGA implementations
    PulseWire sendDequeued <- mkPulseWire;

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
                    method Action deq();
                        q.deq();
                        sendDequeued.send();
                    endmethod

                    interface Clock clock = localClock;
                    interface Reset reset = localReset;

                endinterface);

    // Collect up our info.
    String moduleName   <- getSynthesisBoundaryName();       
    let info = 
        LOGICAL_SEND_MULTI_INFO 
        {
            logicalName: send_name, 
            logicalType: original_type,
            bitWidth: valueof(SizeOf#(t_MSG)),  
            outgoing: outg,
            moduleName: moduleName
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

    if (param.enableDebug)
    begin
        let dbg_state = (
            interface PHYSICAL_CONNECTION_DEBUG_STATE;
                method Bool notEmpty() = q.notEmpty();
                method Bool notFull() = q.notFull();
                method Bool dequeued() = sendDequeued;
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

    method Bool dequeued = sendDequeued;

endmodule


// The actual instantation of the physical many-to-one receive. Just contains wires.
module [t_CONTEXT] mkPhysicalConnectionRecvMulti#(String recv_name,
                                                  Maybe#(STATION) m_station,
                                                  String original_type,
                                                  CONNECTION_RECV_PARAM param)
    // Interface:
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
    String moduleName   <- getSynthesisBoundaryName();  
    let info = 
        LOGICAL_RECV_MULTI_INFO 
        {
            logicalName: recv_name, 
            logicalType: original_type,  
            bitWidth: valueof(SizeOf#(t_MSG)), 
            incoming: inc,
            moduleName: moduleName
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
    
    // some wiring needed in the multi-FPGA implementations
    PulseWire sendDequeued <- mkPulseWire;

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

                   method Bool dequeued() = sendDequeued;
 
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
                    method Action deq();
                        q.deq();
                        sendDequeued.send;
                    endmethod

                    interface Clock clock = localClock;
                    interface Reset reset = localReset;

                endinterface);

    String moduleName   <- getSynthesisBoundaryName(); 
    // Collect up our info.
    let info = 
        LOGICAL_CHAIN_INFO 
        {
            logicalName: chain_name, 
            logicalType: original_type, 
            moduleNameIncoming: moduleName,
            moduleNameOutgoing: moduleName,
            bitWidth: valueof(SizeOf#(msg_T)),  
            incoming: inc,
            outgoing: outg
        };

    // Register the chain
    registerChain(info);
 
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


//
// The actual instatiation of a physical service connection client. 
// For efficiency contains an unguarded FIFO, which makes the scheduler's life much easier.
// The dispatcher which invokes this guards the FIFO as appropriate.
//
module [t_CONTEXT] mkPhysicalConnectionServiceClient#(String serviceName, 
                                                      String reqType, 
                                                      String respType, 
                                                      Maybe#(t_CLIENT_ID) clientId)
    //interface:
    (CONNECTION_SERVICE_CLIENT#(t_CLIENT_ID, t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SZ),
         Bits#(t_RSP, t_RSP_SZ),
         Bits#(t_CLIENT_ID, t_CLIENT_ID_SZ),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Local Clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();

    RWire#(t_RSP)  respW    <- mkRWire();
    PulseWire      deqEnW   <- mkPulseWire();
    FIFOF#(t_REQ)  q        <- mkUGFIFOF();
    
    Reg#(t_CLIENT_ID) myId  <- mkWriteValidatedReg();
    RWire#(t_CLIENT_ID) idW <- mkRWire();
   
    // some wiring needed in the multi-FPGA implementations
    PulseWire sendDequeued <- mkPulseWire;

    let inc = (interface PHYSICAL_SERVICE_CON_RESP_IN;

                   // Part 1 of the anti-method to get(). Unmarshall the data and send it on the wire.
                   method Action try(x);
                       Bit#(t_RSP_SZ) tmp = truncateNP(x);
                       respW.wset(unpack(tmp));
                   endmethod

                   // Part 2 of the anti-method to get(). If someone actually was listening, then the get() succeeded.
                   method Bool success();
                       return deqEnW;
                   endmethod

                   method Bool dequeued() = deqEnW;

                   method Action setId(id);
                       Bit#(t_CLIENT_ID_SZ) tmp = truncateNP(id);
                       idW.wset(unpack(tmp));
                   endmethod
                   
                   interface Clock clock = localClock;
                   interface Reset reset = localReset;               
                
               endinterface);

    let outg = (interface PHYSICAL_SERVICE_CON_REQ_OUT;

                    // Trying to transmit something means marshalling up the first thing in the queue.
                    method PHYSICAL_SERVICE_CON_DATA first();
                        Bit#(t_REQ_SZ) tmp = pack(q.first());
                        return zeroExtendNP(tmp);
                    endmethod

                    // Sometimes its useful to have an explicit notEmpty
                    method Bool notEmpty() = q.notEmpty();

                    // If we were successful we can dequeue.
                    method Action deq();
                        q.deq();
                        sendDequeued.send();
                    endmethod

                    interface Clock clock = localClock;
                    interface Reset reset = localReset;

                endinterface);

    (* fire_when_enabled *)
    rule setClientId (idW.wget() matches tagged Valid .id);
        myId <= id;
    endrule
    
    String moduleName <- getSynthesisBoundaryName(); 
    String clientIdStr = isValid(clientId)? bitToString(pack(validValue(clientId))) : "unassigned";

    // Collect up our info.
    let info = 
        LOGICAL_SERVICE_CLIENT_INFO
        {
            logicalName: serviceName,
            logicalReqType: reqType,
            logicalRespType: respType,
            moduleName: moduleName, 
            clientId: clientIdStr,
            reqBitWidth: valueof(t_REQ_SZ), 
            respBitWidth: valueof(t_RSP_SZ),
            clientIdBitWidth: valueof(t_CLIENT_ID_SZ),
            incoming: inc,
            outgoing: outg
        };

    // Register the service client
    registerServiceClient(info);
 
    method Action makeReq(t_REQ data);
        q.enq(data); 
    endmethod
    
    method Bool reqNotFull() = q.notFull();
    method Bool rspNotEmpty() = isValid(respW.wget());
    method t_RSP  getRsp() if (respW.wget() matches tagged Valid .val);
        return val;
    endmethod
    method Action deqRsp();
        deqEnW.send();
    endmethod
    method t_CLIENT_ID clientId() = myId;

endmodule

//
// The actual instatiation of a physical service connection server. 
// For efficiency contains an unguarded FIFO, which makes the scheduler's life much easier.
// The dispatcher which invokes this guards the FIFO as appropriate.
//
module [t_CONTEXT] mkPhysicalConnectionServiceServer#(String serviceName, 
                                                      String reqType, 
                                                      String respType)
    //interface:
    (CONNECTION_SERVICE_SERVER#(t_CLIENT_ID, t_REQ, t_RSP))
    provisos
        (Bits#(t_REQ, t_REQ_SZ),
         Bits#(t_RSP, t_RSP_SZ),
         Bits#(t_CLIENT_ID, t_CLIENT_ID_SZ),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    // Local Clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();

    RWire#(t_REQ) reqW  <- mkRWire();
    PulseWire deqEnW    <- mkPulseWire();
    FIFOF#(Tuple2#(t_CLIENT_ID,t_RSP))  q <- mkUGFIFOF();
    
    // some wiring needed in the multi-FPGA implementations
    PulseWire sendDequeued <- mkPulseWire;

    let inc = (interface PHYSICAL_SERVICE_CON_REQ_IN;

                   // Part 1 of the anti-method to get(). Unmarshall the data and send it on the wire.
                   method Action try(x);
                       Bit#(t_REQ_SZ) tmp = truncateNP(x);
                       reqW.wset(unpack(tmp));
                   endmethod

                   // Part 2 of the anti-method to get(). If someone actually was listening, then the get() succeeded.
                   method Bool success();
                       return deqEnW;
                   endmethod

                   method Bool dequeued() = deqEnW;

                   interface Clock clock = localClock;
                   interface Reset reset = localReset;               
                
               endinterface);

    let outg = (interface PHYSICAL_SERVICE_CON_RESP_OUT;

                    // Trying to transmit something means marshalling up the first thing in the queue.
                    method PHYSICAL_SERVICE_CON_RESP first();
                        match {.id, .msg} = q.first();
                        PHYSICAL_SERVICE_CON_IDX  tmp1 = zeroExtendNP(pack(id)); 
                        PHYSICAL_SERVICE_CON_DATA tmp2 = zeroExtendNP(pack(msg)); 
                        return pack(tuple2(tmp1, tmp2));
                    endmethod

                    // Sometimes its useful to have an explicit notEmpty
                    method Bool notEmpty() = q.notEmpty();

                    // If we were successful we can dequeue.
                    method Action deq();
                        q.deq();
                        sendDequeued.send();
                    endmethod

                    interface Clock clock = localClock;
                    interface Reset reset = localReset;

                endinterface);

    String moduleName <- getSynthesisBoundaryName(); 

    // Collect up our info.
    let info = 
        LOGICAL_SERVICE_SERVER_INFO
        {
            logicalName: serviceName,
            logicalReqType: reqType,
            logicalRespType: respType,
            moduleName: moduleName, 
            reqBitWidth: valueof(t_REQ_SZ), 
            respBitWidth: valueof(t_RSP_SZ),
            clientIdBitWidth: valueof(t_CLIENT_ID_SZ),
            incoming: inc,
            outgoing: outg
        };

    // Register the service client
    registerServiceServer(info);
    
    method Bool reqNotEmpty() = isValid(reqW.wget());
    method t_REQ  getReq() if (reqW.wget() matches tagged Valid .val);
        return val;
    endmethod
    method Action deqReq();
        deqEnW.send();
    endmethod
    method Action makeRsp(t_CLIENT_ID dst, t_RSP data);
        q.enq(tuple2(dst, data));
    endmethod
    method Bool rspNotFull() = q.notFull();
 
endmodule

