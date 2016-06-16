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

import Vector::*;
import FIFOF::*;
import SpecialFIFOs::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/physical_interconnect.bsh"
`include "awb/provides/soft_connections_common.bsh"
`include "awb/provides/soft_connections_alg.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"

//
// The interface of a network module to be connected with service clients and the service server
//
interface CONNECTION_SERVICE_NETWORK_IFC#(numeric type t_NUM_CLIENTS);
  interface Vector#(t_NUM_CLIENTS, CONNECTION_IN#(SERVICE_CON_DATA_SIZE))   clientReqPorts;
  interface Vector#(t_NUM_CLIENTS, CONNECTION_OUT#(SERVICE_CON_DATA_SIZE))  clientRspPorts;
  interface CONNECTION_IN#(SERVICE_CON_RESP_SIZE) serverRspPort;
  interface CONNECTION_OUT#(SERVICE_CON_DATA_SIZE) serverReqPort;
endinterface

//
// The interface of a ring node module for service connections
//
interface CONNECTION_SERVICE_RING_NODE_IFC#(numeric type t_REQ_SZ, 
                                            numeric type t_RSP_SZ, 
                                            numeric type t_IDX_SZ);
    // Request port from the service client (or child rings)
    interface CONNECTION_IN#(t_REQ_SZ)  clientReqIncoming; 
    // Response port to the service client (or child rings)
    interface CONNECTION_OUT#(TAdd#(t_IDX_SZ, t_RSP_SZ)) clientRspOutgoing;
    // Request chain 
    interface CONNECTION_IN#(t_REQ_SZ)  reqChainIncoming;
    interface CONNECTION_OUT#(t_REQ_SZ) reqChainOutgoing;
    // Response chain 
    interface CONNECTION_IN#(TAdd#(t_IDX_SZ, t_RSP_SZ)) rspChainIncoming;
    interface CONNECTION_OUT#(TAdd#(t_IDX_SZ, t_RSP_SZ)) rspChainOutgoing;

endinterface

//
// The counterpart interface for a service client connection
//
interface CONNECTION_SERVICE_CLIENT_COUNTERPART_IFC#(numeric type t_REQ_SZ, 
                                                     numeric type t_RSP_SZ);
    // Request port from the service client
    interface CONNECTION_IN#(t_REQ_SZ)  clientReqIncoming; 
    // Response port to the service client
    interface CONNECTION_OUT#(t_RSP_SZ) clientRspOutgoing;
endinterface

//
// The interface of a tree leaf module for service connections
//
interface CONNECTION_SERVICE_TREE_LEAF_IFC#(type t_REQ, type t_RSP, type t_IDX);
    // Request port from the service client
    interface CONNECTION_IN#(SERVICE_CON_DATA_SIZE)  clientReqIncoming; 
    // Response port to the service client
    interface CONNECTION_OUT#(SERVICE_CON_DATA_SIZE) clientRspOutgoing;
    // Tree interface
    interface CONNECTION_ADDR_TREE#(t_IDX, t_REQ, t_RSP) tree;
endinterface

//
// The interface of the connector for service connections
//
interface CONNECTION_SERVICE_CONNECTOR_IFC#(numeric type t_MSG_SZ); 
    interface CONNECTION_IN#(t_MSG_SZ)  incoming; 
    interface CONNECTION_OUT#(t_MSG_SZ) outgoing;
endinterface

//
// connectOutToInWithIdx --
//   This is the module that actually performs the connection between two
//   physical endpoints, CONNECTION_OUT and CONNECTION_IN_WITH_IDX. 
//   This is for 1-to-1 communication only.
//
//   Incoming connection requires a one-time client Id assignment.
//
//   A configurable number of buffer stages may be added to relax timing
//   between distant endpoints.
//
module connectOutToInWithIdx#(CONNECTION_OUT#(t_MSG_SIZE) cout,
                              CONNECTION_IN_WITH_IDX#(t_MSG_SIZE, t_IDX_SIZE) cin,
                              Integer idx, 
                              Integer bufferStages)
    // Interface:
    ();
  
    let buf_cout <- mkBufferedConnectionOut(cout, bufferStages);

    rule trySend (buf_cout.notEmpty());
        // Try to move the data
        Bit#(t_MSG_SIZE) x = buf_cout.first();
        cin.try(x);
    endrule

    rule success (cin.success());
        // We succeeded in moving the data
        buf_cout.deq();
    endrule

    Reg#(Bool) idIsSet <- mkReg(False);
    
    rule setClientId (!idIsSet);
        idIsSet <= True;
        cin.setId(fromInteger(idx));
    endrule

endmodule

//
// connectManyOutToIn --
//   This is the module that actually performs the connection between multiple
//   physical endpoints. This is for many-to-1 communication.
//
//   A configurable number of buffer stages may be added to relax timing
//   between distant endpoints.
//
module [m] connectManyOutToIn#(Vector#(n_OUT_PORTS, CONNECTION_OUT#(t_MSG_SIZE)) couts,
                               CONNECTION_IN#(t_MSG_SIZE) cin,
                               Integer bufferStages,
                               function m#(LOCAL_ARBITER#(n_OUT_PORTS)) mkArbiter()) 
    // Interface:
    ()
    provisos(Add#(1, extras, n_OUT_PORTS),
             IsModule#(m, t_MODULE));
  
    let msgArbiter <- mkArbiter();
    
    Vector#(n_OUT_PORTS, CONNECTION_OUT#(t_MSG_SIZE)) buf_couts <- zipWithM(mkBufferedConnectionOut, couts, replicate(bufferStages));
    
    RWire#(LOCAL_ARBITER_CLIENT_IDX#(n_OUT_PORTS)) selectionIndex <- mkRWire();
    RWire#(LOCAL_ARBITER_OPAQUE#(n_OUT_PORTS)) selectionState <- mkRWire();

    function Bool isNotEmpty(CONNECTION_OUT#(t_MSG_SIZE) conn);
         return conn.notEmpty();
    endfunction
    
    Vector#(n_OUT_PORTS, Bool) notEmptyVec = map(isNotEmpty, buf_couts);

    rule doArbitration (fold(\|| , notEmptyVec));
        let selectionResult <- msgArbiter.arbitrateNoUpd(notEmptyVec, False);
        if(tpl_1(selectionResult) matches tagged Valid .port_id)
        begin
            selectionIndex.wset(port_id); 
            selectionState.wset(tpl_2(selectionResult));
        end
    endrule
    
    rule trySend (selectionIndex.wget() matches tagged Valid .idx);
        cin.try(buf_couts[idx].first());
    endrule
    
    rule success (cin.success());
        let idx = fromMaybe(?, selectionIndex.wget()); 
        buf_couts[idx].deq(); 
        let state_upd = fromMaybe(?, selectionState.wget());
        msgArbiter.update(state_upd);
    endrule

    // function Bool isNotEmpty(CONNECTION_OUT#(t_MSG_SIZE) conn);
    //      return conn.notEmpty();
    // endfunction

    // FIFOF#(Bit#(t_MSG_SIZE)) msgQ <- mkBypassFIFOF();

    // rule doArbitration (msgQ.notFull);
    //     let selectionResult <- msgArbiter.arbitrate( map(isNotEmpty,buf_couts), False);
    //     if(selectionResult matches tagged Valid .port_id)
    //     begin
    //         selectionIndex.wset(port_id); 
    //     end
    // endrule
    // 
    // for (Integer idx = 0; idx < valueof(n_OUT_PORTS); idx = idx + 1) 
    // begin
    //     rule selectOutputPort (selectionIndex.wget() matches tagged Valid .s &&& s == fromInteger(idx));
    //         msgQ.enq(buf_couts[idx].first());
    //         buf_couts[idx].deq();
    //     endrule
    // end

    // rule trySend (msgQ.notEmpty());
    //     Bit#(t_MSG_SIZE) x = msgQ.first();
    //     cin.try(x);
    // endrule

    // rule success (cin.success());
    //     msgQ.deq();
    // endrule

endmodule

//
// connectOutToManyInWithIdx --
//   This is the module that actually performs the connection between multiple
//   physical endpoints, one CONNECTION_OUT and multiple CONNECTION_IN_WITH_IDX. 
//   This is for 1-to-many communication.
//
//   Each incoming connection requires a one-time client Id assignment.
//
//   A configurable number of buffer stages may be added to relax timing
//   between distant endpoints.
//
module connectOutToManyInWithIdx#(CONNECTION_OUT#(TAdd#(t_IDX_SIZE, t_MSG_SIZE)) cout,
                                  Vector#(n_IN_PORTS, CONNECTION_IN_WITH_IDX#(t_MSG_SIZE, t_IDX_SIZE)) cins,
                                  Vector#(n_IN_PORTS, Integer) ids, 
                                  Integer bufferStages)
    // Interface:
    ()
    provisos(Add#(1, extras, n_IN_PORTS));
  
    let buf_cout <- mkBufferedConnectionOut(cout, bufferStages);

    function Bool isSuccess(CONNECTION_IN_WITH_IDX#(t_MSG_SIZE, t_IDX_SIZE) conn);
        return conn.success();
    endfunction

    Vector#(n_IN_PORTS, Bit#(t_IDX_SIZE)) idx_vec = map(fromInteger, ids);
    Vector#(n_IN_PORTS, Bool) success_vec = map(isSuccess, cins);

    rule trySend (buf_cout.notEmpty());
        Tuple2#(Bit#(t_IDX_SIZE), Bit#(t_MSG_SIZE)) tmp = unpack(buf_cout.first());
        match {.dst, .rsp} = tmp;
        let dst_idx = findElem(dst, idx_vec); 
        if (dst_idx matches tagged Valid .idx)
        begin
            cins[idx].try(rsp);
        end
    endrule

    rule success (fold(\|| , success_vec));
        buf_cout.deq();
    endrule

    Reg#(Bool) idIsSet <- mkReg(False);
    
    rule setClientId (!idIsSet);
        idIsSet <= True;
        for (Integer idx = 0; idx < valueof(n_IN_PORTS); idx = idx + 1)
        begin
            cins[idx].setId(fromInteger(ids[fromInteger(idx)]));
        end
    endrule

endmodule

//
// Cross-domain connection
//
module connectOutToInDualClock#(CONNECTION_OUT#(t_MSG_SIZE) cout,
                                CONNECTION_IN#(t_MSG_SIZE) cin)
    // Interface:
    ();
  
    // choose a size large enough to cover latency of fifo
    let domainFIFO <- mkSyncFIFO(16,
                                 cout.clock, 
                                 cout.reset,
                                 cin.clock);

    rule receive (cout.notEmpty() && domainFIFO.notFull());
        Bit#(t_MSG_SIZE) x = cout.first();
        domainFIFO.enq(x);
        cout.deq();
    endrule
  
    rule trySend (domainFIFO.notEmpty());
        cin.try(domainFIFO.first());
    endrule

    rule succeedSend(cin.success());
        domainFIFO.deq();
    endrule

endmodule


module connectOutToInWithIdxDualClock#(CONNECTION_OUT#(t_MSG_SIZE) cout,
                                       CONNECTION_IN_WITH_IDX#(t_MSG_SIZE, t_IDX_SIZE) cin,
                                       Integer idx) 
    // Interface:
    ();
    
    // choose a size large enough to cover latency of fifo
    let domainFIFO <- mkSyncFIFO(16,
                                 cout.clock, 
                                 cout.reset,
                                 cin.clock);

    rule receive (cout.notEmpty() && domainFIFO.notFull());
        Bit#(t_MSG_SIZE) x = cout.first();
        domainFIFO.enq(x);
        cout.deq();
    endrule
  
    rule trySend (domainFIFO.notEmpty());
        cin.try(domainFIFO.first());
    endrule

    rule succeedSend(cin.success());
        domainFIFO.deq();
    endrule

    Reg#(Bool) idIsSet <- mkReg(False, clocked_by cin.clock, reset_by cin.reset);
    
    rule setClientId (!idIsSet);
        idIsSet <= True;
        cin.setId(fromInteger(idx));
    endrule

endmodule



//
// resizeServiceConnectionOut --
//   Resize the message size for service connection out interface. 
//   This is useful for directly connecting the service server with a single 
//   service client where the part of the response message that contains 
//   the client ID needs to be removed (in order to match the service client's 
//   connection width.)
//
function CONNECTION_OUT#(t_ACTUAL_SIZE) resizeServiceConnectionOut(CONNECTION_OUT#(t_MSG_SIZE) cout)
    provisos(Add#(t_EXTRA, t_ACTUAL_SIZE, t_MSG_SIZE));
    CONNECTION_OUT#(t_ACTUAL_SIZE) retval = interface CONNECTION_OUT;
                                                method Bit#(t_ACTUAL_SIZE) first();
                                                    Bit#(t_MSG_SIZE) x = cout.first();   
                                                    Bit#(t_ACTUAL_SIZE) xActual = truncateNP(x);
                                                    return xActual;
                                                endmethod
                                                method deq = cout.deq;
                                                method notEmpty = cout.notEmpty;
                                                interface clock = cout.clock;
                                                interface reset = cout.reset;
                                            endinterface; 

    return retval;
endfunction

//
// convertConnectionInToConnectionInWithIdx --
//   CONNECTION_IN to CONNECTION_IN_WITH_IDX interface conversion.
//
function CONNECTION_IN_WITH_IDX#(t_MSG_SIZE, t_IDX_SIZE) convertConnectionInToConnectionInWithIdx(CONNECTION_IN#(t_MSG_SIZE) cin);
    CONNECTION_IN_WITH_IDX#(t_MSG_SIZE, t_IDX_SIZE) new_cin = interface CONNECTION_IN_WITH_IDX;
                                                                  method try = cin.try;
                                                                  method success = cin.success;
                                                                  method dequeued = cin.dequeued;
                                                                  method Action setId(Bit#(t_IDX_SIZE) id);
                                                                      noAction;
                                                                  endmethod
                                                                  interface Clock clock = cin.clock;
                                                                  interface Reset reset = cin.reset;
                                                              endinterface;
    return new_cin;
endfunction

//
// mkServiceConnector --
//     A service connection connector. 
//
module mkServiceConnector(CONNECTION_SERVICE_CONNECTOR_IFC#(t_MSG_SIZE));
    
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();
    
    RWire#(Bit#(t_MSG_SIZE))  msgW  <- mkRWire();
    PulseWire deqW <- mkPulseWire();

    interface incoming = interface CONNECTION_IN#(t_MSG_SIZE);
                             method Action try(Bit#(t_MSG_SIZE) d);
                                 msgW.wset(d);
                             endmethod
                             method Bool success  = deqW;
                             method Bool dequeued = deqW;
                             interface Clock clock = localClock;
                             interface Reset reset = localReset;
                         endinterface; 
    
    interface outgoing = interface CONNECTION_OUT#(t_MSG_SIZE);
                             method Bit#(t_MSG_SIZE) first() if (msgW.wget() matches tagged Valid .d);
                                 return d;
                             endmethod
                             method Action deq();
                                 deqW.send();
                             endmethod
                             method notEmpty = isValid(msgW.wget());
                             interface Clock clock = localClock;
                             interface Reset reset = localReset;
                         endinterface; 

endmodule



//
// mkServiceRingNetworkModule --
//   The network module that connects service clients and the server in a ring
//
module mkServiceRingNetworkModule#(Vector#(t_NUM_CLIENTS, Integer) clientIdVec,
                                   NumTypeParam#(t_REQ_SZ) reqSz, 
                                   NumTypeParam#(t_RSP_SZ) rspSz, 
                                   NumTypeParam#(t_IDX_SZ) idxSz)
    // Interface:
    (CONNECTION_SERVICE_NETWORK_IFC#(t_NUM_CLIENTS))
    provisos(Alias#(Bit#(t_REQ_SZ), t_REQ), 
             Alias#(Bit#(t_RSP_SZ), t_RSP), 
             Alias#(Bit#(t_IDX_SZ), t_IDX), 
             Add#(2, extras, t_NUM_CLIENTS)); // the number of clients needs to be at least 2
    
    // Local Clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();
   
    // Ring nodes for service clients
    function Bool isLocalFunc(Integer clientId, t_IDX idx);
        return idx == fromInteger(clientId);
    endfunction

    Vector#(t_NUM_CLIENTS, CONNECTION_SERVICE_RING_NODE_IFC#(t_REQ_SZ, t_RSP_SZ, t_IDX_SZ)) ringNodes <- 
        mapM(mkServiceRingNode, map(isLocalFunc, clientIdVec));
    
    // Connect the ring nodes
    for (Integer i = 0; i < (valueOf(t_NUM_CLIENTS) - 1); i = i + 1)
    begin
        connectOutToIn(ringNodes[i].reqChainOutgoing, ringNodes[i+1].reqChainIncoming, 0);
        connectOutToIn(ringNodes[i].rspChainOutgoing, ringNodes[i+1].rspChainIncoming, 0);
    end

    Vector#(t_NUM_CLIENTS, CONNECTION_IN#(SERVICE_CON_DATA_SIZE))  clientReqPortsVec = newVector();
    Vector#(t_NUM_CLIENTS, CONNECTION_OUT#(SERVICE_CON_DATA_SIZE)) clientRspPortsVec = newVector();

    for (Integer x = 0; x < valueOf(t_NUM_CLIENTS); x = x + 1)
    begin
        clientReqPortsVec[x] = (interface CONNECTION_IN#(SERVICE_CON_DATA_SIZE);
                                    method Action try(Bit#(SERVICE_CON_DATA_SIZE) d);
                                        ringNodes[x].clientReqIncoming.try(truncateNP(d));
                                    endmethod
                                    method Bool success = ringNodes[x].clientReqIncoming.success;
                                    method Bool dequeued = ringNodes[x].clientReqIncoming.dequeued;
                                    interface Clock clock = localClock;
                                    interface Reset reset = localReset;
                                endinterface); 

        clientRspPortsVec[x] = (interface CONNECTION_OUT#(SERVICE_CON_DATA_SIZE);
                                    method Bit#(SERVICE_CON_DATA_SIZE) first();
                                        Tuple2#(t_IDX, t_RSP) tmp = unpack(ringNodes[x].clientRspOutgoing.first());
                                        return zeroExtendNP(tpl_2(tmp)); 
                                    endmethod
                                    method Action deq = ringNodes[x].clientRspOutgoing.deq;
                                    method Bool notEmpty = ringNodes[x].clientRspOutgoing.notEmpty;
                                    interface clock = localClock;
                                    interface Reset reset = localReset;
                                endinterface);
    end

    interface clientReqPorts = clientReqPortsVec;
    interface clientRspPorts = clientRspPortsVec;
    
    interface serverRspPort = interface CONNECTION_IN#(SERVICE_CON_RESP_SIZE);
                                  method Action try(Bit#(SERVICE_CON_RESP_SIZE) d);
                                      Tuple2#(Bit#(SERVICE_CON_IDX_SIZE),Bit#(SERVICE_CON_DATA_SIZE)) tmp = unpack(d);
                                      t_IDX idx = truncateNP(tpl_1(tmp));
                                      t_RSP rsp = truncateNP(tpl_2(tmp));
                                      ringNodes[0].rspChainIncoming.try(pack(tuple2(idx,rsp)));
                                  endmethod
                                  method Bool success  = ringNodes[0].rspChainIncoming.success;
                                  method Bool dequeued = ringNodes[0].rspChainIncoming.dequeued;
                                  interface Clock clock = localClock;
                                  interface Reset reset = localReset;
                              endinterface; 
    
    interface serverReqPort = interface CONNECTION_OUT#(SERVICE_CON_DATA_SIZE);
                                  method Bit#(SERVICE_CON_DATA_SIZE) first();
                                      t_REQ req = ringNodes[fromInteger(valueOf(t_NUM_CLIENTS)-1)].reqChainOutgoing.first();
                                      return zeroExtendNP(req);
                                  endmethod
                                  method Action deq = ringNodes[fromInteger(valueOf(t_NUM_CLIENTS)-1)].reqChainOutgoing.deq;
                                  method Bool notEmpty = ringNodes[fromInteger(valueOf(t_NUM_CLIENTS)-1)].reqChainOutgoing.notEmpty;
                                  interface clock = localClock;
                                  interface reset = localReset;
                              endinterface; 

endmodule



//
// mkServiceRingNode --
//   A single ring node for a service client.   
//
module mkServiceRingNode#(function Bool isLocal(Bit#(t_IDX_SZ) nodeId)) 
    // Interface:
    (CONNECTION_SERVICE_RING_NODE_IFC#(t_REQ_SZ, t_RSP_SZ, t_IDX_SZ))
    provisos(Alias#(Bit#(t_REQ_SZ), t_REQ), 
             Alias#(Bit#(t_RSP_SZ), t_RSP), 
             Alias#(Bit#(t_IDX_SZ), t_IDX));
    
    // Local Clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();
    
    // ========================================================================
    //
    // Handle the request path
    //
    // ========================================================================
   
    // Some wires for interacting with the client side
    RWire#(t_REQ)  clientReqW     <- mkRWire();
    PulseWire      clientReqDeqW  <- mkPulseWire();
    
    // Some wires for interacting with the previous ring node
    RWire#(t_REQ)  networkReqW     <- mkRWire();
    PulseWire      networkReqDeqW  <- mkPulseWire();
    
    FIFOF#(t_REQ)  reqToNetworkQ   <- mkUGFIFOF();
    Reg#(Bool)     reqLocalPrior   <- mkReg(True);
        
    //
    // sendReqToRing --
    //     This node has a new request for the ring.
    //
    rule sendReqToRing (clientReqW.wget() matches tagged Valid .req &&& reqToNetworkQ.notFull() &&&
                     (!isValid(networkReqW.wget()) || reqLocalPrior));
        reqToNetworkQ.enq(req);
        clientReqDeqW.send();
        reqLocalPrior <= False;
    endrule

    //
    // forwardReqOnRing --
    //     Local node did not send a request this cycle. Is there a request
    // to forward?
    //
    rule forwardReqOnRing (networkReqW.wget() matches tagged Valid .req &&& 
                          !clientReqDeqW &&& reqToNetworkQ.notFull());
        reqToNetworkQ.enq(req);
        networkReqDeqW.send();
        reqLocalPrior <= True;
    endrule
    
    
    // ========================================================================
    //
    // Handle the response path
    //
    // ========================================================================
    
    // Some wires for interacting with the previous ring node
    RWire#(Tuple2#(t_IDX, t_RSP))  networkRspW     <- mkRWire();
    PulseWire                      networkRspDeqW  <- mkPulseWire();
    
    FIFOF#(Tuple2#(t_IDX, t_RSP))  rspToNetworkQ   <- mkUGFIFOF();
    FIFOF#(Tuple2#(t_IDX, t_RSP))  rspFromNetworkQ <- mkUGFIFOF();
    
    //
    // recvRspFromRing --
    //     Receive a new response from the ring destined for this node.
    //
    rule recvRspFromRing (networkRspW.wget() matches tagged Valid .msg &&&
                          isLocal(tpl_1(msg)) &&& rspFromNetworkQ.notFull());
        rspFromNetworkQ.enq(msg);
        networkRspDeqW.send();
    endrule

    //
    // forwardRspOnRing --
    //     Receive a new response from the ring that is not destined for this node.
    //
    rule forwardRspOnRing (networkRspW.wget() matches tagged Valid .msg &&&
                          !isLocal(tpl_1(msg)) &&& rspToNetworkQ.notFull());
        rspToNetworkQ.enq(msg);
        networkRspDeqW.send();
    endrule
    
    // ========================================================================
    //
    // Methods
    //
    // ========================================================================
    
    // Request port from the service client
    interface clientReqIncoming = interface CONNECTION_IN#(t_REQ_SZ);
                                      method Action try(t_REQ msg);
                                          clientReqW.wset(msg);
                                      endmethod
                                      method Bool success() = clientReqDeqW;
                                      method Bool dequeued() = clientReqDeqW;
                                      interface Clock clock = localClock;
                                      interface Reset reset = localReset;
                                  endinterface; 
    
    // Response port to the service client
    interface clientRspOutgoing = interface CONNECTION_OUT#(t_RSP_SZ);
                                      method Bit#(TAdd#(t_IDX_SZ,t_RSP_SZ)) first() = pack(rspFromNetworkQ.first());
                                      method Action deq();
                                          rspFromNetworkQ.deq();
                                      endmethod
                                      method Bool notEmpty = rspFromNetworkQ.notEmpty();
                                      interface clock = localClock;
                                      interface reset = localReset;
                                  endinterface; 

    // Request chain 
    interface reqChainIncoming = interface CONNECTION_IN#(t_REQ_SZ);
                                     method Action try(t_REQ msg);
                                         networkReqW.wset(msg);
                                     endmethod
                                     method Bool success() = networkReqDeqW;
                                     method Bool dequeued() = networkReqDeqW;
                                     interface Clock clock = localClock;
                                     interface Reset reset = localReset;
                                 endinterface; 
    
    interface reqChainOutgoing = interface CONNECTION_OUT#(t_REQ_SZ);
                                     method Bit#(t_REQ_SZ) first() = reqToNetworkQ.first();
                                     method Action deq();
                                         reqToNetworkQ.deq();
                                     endmethod
                                     method Bool notEmpty = reqToNetworkQ.notEmpty;
                                     interface clock = localClock;
                                     interface reset = localReset;
                                 endinterface; 
    
    // Response chain 
    interface rspChainIncoming = interface CONNECTION_IN#(TAdd#(t_IDX_SZ, t_RSP_SZ));
                                     method Action try(Bit#(TAdd#(t_IDX_SZ, t_RSP_SZ)) msg);
                                         Tuple2#(Bit#(t_IDX_SZ), Bit#(t_RSP_SZ)) tmp = unpack(msg);
                                         networkRspW.wset(tmp);
                                     endmethod
                                     method Bool success() = networkRspDeqW;
                                     method Bool dequeued() = networkRspDeqW;
                                     interface Clock clock = localClock;
                                     interface Reset reset = localReset;
                                 endinterface; 
    
    interface rspChainOutgoing = interface CONNECTION_OUT#(TAdd#(t_IDX_SZ, t_RSP_SZ));
                                     method Bit#(TAdd#(t_IDX_SZ, t_RSP_SZ)) first() = pack(rspToNetworkQ.first());
                                     method Action deq();
                                         rspToNetworkQ.deq();
                                     endmethod
                                     method Bool notEmpty = rspToNetworkQ.notEmpty;
                                     interface clock = localClock;
                                     interface reset = localReset;
                                 endinterface; 

endmodule


//
// mkServiceTreeLeaf --
//   A tree leaf node for a service client.   
//
module mkServiceTreeLeaf
    // Interface:
    (CONNECTION_SERVICE_TREE_LEAF_IFC#(t_REQ, t_RSP, t_IDX))
    provisos(Bits#(t_REQ, t_REQ_SZ), 
             Bits#(t_RSP, t_RSP_SZ), 
             Bits#(t_IDX, t_IDX_SZ));
    
    // Local Clock and reset
    Clock localClock <- exposeCurrentClock();
    Reset localReset <- exposeCurrentReset();
    
    // Handle the request path
    RWire#(t_REQ)  clientReqW     <- mkRWire();
    PulseWire      clientReqDeqW  <- mkPulseWire();
    
    // Handle the response path
    FIFOF#(t_RSP)  rspFromNetworkQ <- mkUGFIFOF();
    
    // ========================================================================
    //
    // Methods
    //
    // ========================================================================
    
    // Request port from the service client
    interface clientReqIncoming = interface CONNECTION_IN#(SERVICE_CON_DATA_SIZE);
                                      method Action try(Bit#(SERVICE_CON_DATA_SIZE) msg);
                                          t_REQ tmp = unpack(truncateNP(msg));
                                          clientReqW.wset(tmp);
                                      endmethod
                                      method Bool success() = clientReqDeqW;
                                      method Bool dequeued() = clientReqDeqW;
                                      interface Clock clock = localClock;
                                      interface Reset reset = localReset;
                                  endinterface; 
    
    // Response port to the service client
    interface clientRspOutgoing = interface CONNECTION_OUT#(SERVICE_CON_DATA_SIZE);
                                      method Bit#(SERVICE_CON_DATA_SIZE) first() = zeroExtendNP(pack(rspFromNetworkQ.first()));
                                      method Action deq();
                                          rspFromNetworkQ.deq();
                                      endmethod
                                      method Bool notEmpty = rspFromNetworkQ.notEmpty();
                                      interface clock = localClock;
                                      interface reset = localReset;
                                  endinterface; 

    interface tree = interface CONNECTION_ADDR_TREE#(t_IDX, t_REQ, t_RSP);
                         // Response portion
                         method Action enq(TREE_MSG#(t_IDX, t_RSP) msg) if (rspFromNetworkQ.notFull());
                              rspFromNetworkQ.enq(msg.data);
                         endmethod
                         method Bool notFull() = rspFromNetworkQ.notFull();
                         // Request portion
                         method t_REQ first() if (clientReqW.wget() matches tagged Valid .req);
                             return req;
                         endmethod
                         method Action deq();
                             clientReqDeqW.send();
                         endmethod
                         method Bool notEmpty() = isValid(clientReqW.wget());
                     endinterface; 

endmodule

//
//  mkServiceTreeRoot --
//      The tree root module that connects service server connections to the 
//  rest of the tree nodes. 
//
module [CONNECTED_MODULE] mkServiceTreeRoot#(CONNECTION_IN#(SERVICE_CON_DATA_SIZE) serverReqPort,
                                             CONNECTION_OUT#(SERVICE_CON_RESP_SIZE) serverRspPort,
                                             Vector#(n_INGRESS_PORTS, CONNECTION_ADDR_TREE#(t_IDX, t_REQ, t_RSP)) children, 
                                             Vector#(TAdd#(1, n_INGRESS_PORTS), t_IDX) addressBounds, 
                                             Vector#(n_INGRESS_PORTS, UInt#(nFRACTION)) bandwidthFractions)
    (Empty)
    provisos (Bits#(t_REQ, t_REQ_SZ), 
              Bits#(t_RSP, t_RSP_SZ),
              Bits#(t_IDX, t_IDX_SZ),
              Ord#(t_IDX),
              Add#(1, nFRACTION_extra_bits, nFRACTION),
              Add#(1, nFRACTION_VALUES_extra_bits, TLog#(TAdd#(1, TExp#(nFRACTION)))));

    // Instantiate the tree root
    CONNECTION_ADDR_TREE#(t_IDX, t_REQ, t_RSP) root <- 
        mkTreeRouter(children, addressBounds, mkLocalArbiterBandwidth(bandwidthFractions));

    // Forward requests to the server
    rule fwdReq (root.notEmpty());
        Bit#(SERVICE_CON_DATA_SIZE) req = zeroExtendNP(pack(root.first()));
        serverReqPort.try(req);
    endrule

    rule deqReq (serverReqPort.success());
        root.deq();
    endrule

    // Forward responses from the server 
    rule fwdResp (serverRspPort.notEmpty);
        Tuple2#(Bit#(SERVICE_CON_IDX_SIZE), Bit#(SERVICE_CON_DATA_SIZE)) msg = unpack(serverRspPort.first());
        t_IDX id = unpack(truncateNP(tpl_1(msg)));
        t_RSP rsp = unpack(truncateNP(tpl_2(msg)));
        root.enq(TREE_MSG{dstNode: id, data: rsp});
        serverRspPort.deq();
    endrule

endmodule

//
//  mkServiceTreeRootDualClock --
//      Dual clock domain version of mkServiceTreeRoot.
//
module [CONNECTED_MODULE] mkServiceTreeRootDualClock#(CONNECTION_IN#(SERVICE_CON_DATA_SIZE) serverReqPort,
                                                      CONNECTION_OUT#(SERVICE_CON_RESP_SIZE) serverRspPort,
                                                      Vector#(n_INGRESS_PORTS, CONNECTION_ADDR_TREE#(t_IDX, t_REQ, t_RSP)) children, 
                                                      Vector#(TAdd#(1, n_INGRESS_PORTS), t_IDX) addressBounds, 
                                                      Vector#(n_INGRESS_PORTS, UInt#(nFRACTION)) bandwidthFractions)
    (Empty)
    provisos (Bits#(t_REQ, t_REQ_SZ), 
              Bits#(t_RSP, t_RSP_SZ),
              Bits#(t_IDX, t_IDX_SZ),
              Ord#(t_IDX),
              Add#(1, nFRACTION_extra_bits, nFRACTION),
              Add#(1, nFRACTION_VALUES_extra_bits, TLog#(TAdd#(1, TExp#(nFRACTION)))));

    // Instantiate the tree root
    CONNECTION_ADDR_TREE#(t_IDX, t_REQ, t_RSP) root <- 
        mkTreeRouter(children, addressBounds, mkLocalArbiterBandwidth(bandwidthFractions));
    
    SyncFIFOIfc#(t_REQ) reqDomainQ <- mkSyncFIFOFromCC(16,serverReqPort.clock);
    SyncFIFOIfc#(Tuple2#(t_IDX, t_RSP)) rspDomainQ <- mkSyncFIFOToCC(16, serverRspPort.clock, serverRspPort.reset);

    // Forward requests to the server
    rule fwdReq (root.notEmpty() && reqDomainQ.notFull());
        reqDomainQ.enq(root.first());
        root.deq();
    endrule

    rule trySend (reqDomainQ.notEmpty());
        Bit#(SERVICE_CON_DATA_SIZE) req = zeroExtendNP(pack(reqDomainQ.first()));
        serverReqPort.try(req);
    endrule

    rule succeedSend (serverReqPort.success());
        reqDomainQ.deq();
    endrule

    // Forward responses from the server 
    rule recvResp (serverRspPort.notEmpty() && rspDomainQ.notFull());
        Tuple2#(Bit#(SERVICE_CON_IDX_SIZE), Bit#(SERVICE_CON_DATA_SIZE)) msg = unpack(serverRspPort.first());
        t_IDX id = unpack(truncateNP(tpl_1(msg)));
        t_RSP rsp = unpack(truncateNP(tpl_2(msg)));
        rspDomainQ.enq(tuple2(id, rsp));
        serverRspPort.deq();
    endrule    
        
    rule fwdResp (rspDomainQ.notEmpty());
        match {.id, .rsp} = rspDomainQ.first();
        root.enq(TREE_MSG{dstNode: id, data: rsp});
        rspDomainQ.deq();
    endrule

endmodule

