//
// Copyright (c) 2017, Intel Corporation
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

//
// A parametric crossbar router for network topologies. 
// 


import FIFOF::*;
import Vector::*;

`include "awb/provides/librl_bsv.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/librl_bsv_cache.bsh"

typedef struct {
   t_NODE_ID  dstNode;
   t_DATA     data;
} NETWORK_MSG#(type t_NODE_ID, type t_DATA)
    deriving (Eq, Bits);

interface PORT_IN#(type t_NODE_ID, type t_DATA);

    method Action enq(NETWORK_MSG#(t_NODE_ID, t_DATA) msg);
    method Bool notFull();

endinterface

interface PORT_OUT#(type t_NODE_ID, type t_DATA);

    method Action deq();
    method NETWORK_MSG#(t_NODE_ID, t_DATA) first();
    method Bool notEmpty();

endinterface


interface NETWORK_ROUTER#(numeric type ports_out, type t_NODE_ID, type t_DATA);

    // Outgoing portion of the network 
    interface Vector#(ports_out, PORT_OUT#(t_NODE_ID, t_DATA)) portsOut;

endinterface

instance Dequeuable#(PORT_OUT#(t_NODE_ID, t_DATA));

    function isNotEmpty(PORT_OUT#(t_NODE_ID, t_DATA) portOut) = portOut.notEmpty;

endinstance
         
instance Enqueuable#(PORT_IN#(t_NODE_ID, t_DATA));

    function isNotFull(PORT_IN#(t_NODE_ID, t_DATA) portIn) = portIn.notFull;

endinstance


//
// mkCrossbarRouter --
//  A parametric crossbar router with hooks for steering data packets and QoS.
//

module [m] mkCrossbarRouter#(function Integer portMappings(t_NODE_ID id), 
                             function m#(LOCAL_ARBITER#(n_INGRESS_PORTS)) mkArbiter(),
                             Vector#(n_INGRESS_PORTS, PORT_OUT#(t_NODE_ID, t_DATA)) children) 
    (NETWORK_ROUTER#(n_EGRESS_PORTS, t_NODE_ID, t_DATA))
    provisos( Bits#(t_NODE_ID, t_NODE_ID_SZ), 
              Bits#(t_DATA, t_DATA_SZ),
              Ord#(t_NODE_ID), 
              IsModule#(m, t_MODULE));

    let curriedFanInRouter = mkFanInRouter(children, portMappings, mkArbiter);    
    let ports <- genWithM(curriedFanInRouter());
    interface portsOut = ports;

endmodule




//
// mkFanInRouter --
//
//   Instantiates a tree-based router. The router takes as an argument a set of interfaces to its children, 
//   as well as a function to determine routing. It also takes as an argument a constructor for 
//   an arbiter, which can be supplied externally.  
//

module [m] mkFanInRouter#(Vector#(n_INGRESS_PORTS, PORT_OUT#(t_NODE_ID, t_DATA)) children,
                         function Integer portMappings(t_NODE_ID id),                          
                         function m#(LOCAL_ARBITER#(n_INGRESS_PORTS)) mkArbiter(),
                         Integer egressPortId) 
    (PORT_OUT#(t_NODE_ID, t_DATA))
    provisos( Bits#(t_NODE_ID, t_NODE_ID_SZ), 
              Bits#(t_DATA, t_DATA_SZ),
              Ord#(t_NODE_ID), 
              IsModule#(m, t_MODULE));

    // 
    //  State elements
    //

    // We must select among the inbound channels for the one that wins
    // the arbitration.
    let inboundArbiter <- mkArbiter();


    // Egress buffering.  Injects a cycle of latency to cut path between tree layers.
    FIFOF#(NETWORK_MSG#(t_NODE_ID, t_DATA)) outgoingBuffer <- mkFIFOF();

    //
    // Wires -- these are used to implement muxes in the child selection algorithm 
    // 

    let  selectionIndex     <- mkRWire; 
   
    // 
    //  Request side. Manages messages moving to root of tree. 
    //

    // Figure our which children a) have data, b) want to use this port
    Vector#(n_INGRESS_PORTS, Wire#(Bool))  childCheck <- replicateM(mkDWire(False));

    for(Integer i = 0; i < valueof(n_INGRESS_PORTS); i = i + 1)
    begin
    
        rule determineDirection;
            childCheck[i] <= portMappings(children[i].first.dstNode) == egressPortId; 
        endrule

    end


    function Bool doRead(Wire#(Bool) child);
        return child;
    endfunction

    //
    // Because of the local arbiter methods are Actions, we need to select the arbited 
    // client here and then feed it via a wire. 
    // 
    rule doArbitration (outgoingBuffer.notFull);
        let selectionResult <- inboundArbiter.arbitrate(map(doRead,childCheck), False);

        if(selectionResult matches tagged Valid .child)
        begin
            selectionIndex.wset(child); 
        end
    endrule
    

    // 
    // Rules to manage child sources. 
    // 
    for(Integer child = 0; child < fromInteger(valueof(n_INGRESS_PORTS)); child = child + 1) 
    begin
    
        // 
        //  Steer winning child to output. 
        //
        rule selectChild (isValid(selectionIndex.wget) && selectionIndex.wget().Valid == fromInteger(child));
            outgoingBuffer.enq(children[selectionIndex.wget().Valid].first);
            children[selectionIndex.wget().Valid].deq();
            //$display("%m Routing message %h to %d from port %d via port %d", children[selectionIndex.wget().Valid].first.data, children[selectionIndex.wget().Valid].first.dstNode, selectionIndex.wget().Valid, egressPortId);
        endrule
 
    end


    // 
    //  External interface definition.  We are only plumbing FIFOs here. 
    //
  
    method first = outgoingBuffer.first();

    method deq = outgoingBuffer.deq();
 
    method notEmpty = outgoingBuffer.notEmpty();

endmodule
