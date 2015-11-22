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

//
// A parametric router for tree-based network topologies. 
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
} TREE_MSG#(type t_NODE_ID, type t_DATA)
    deriving (Eq, Bits);

interface CONNECTION_ADDR_TREE#(type t_NODE_ID, type t_DATA);

    // Outgoing portion of the network 
    method Action enq(TREE_MSG#(t_NODE_ID, t_DATA) msg);
    method Bool notFull();

    // Incoming portion
    method TREE_MSG#(t_NODE_ID, t_DATA) first();
    method Action deq();
    method Bool notEmpty();

endinterface

// Define some instances for the CONNECTION_ADDR_TREE type. 
instance Dequeuable#(CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA));

    function isNotEmpty(CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA) treeNode) = treeNode.notEmpty;

endinstance
         
instance Enqueuable#(CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA));

    function isNotFull(CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA) treeNode) = treeNode.notFull;

endinstance



module [m] mkTreeRouter#(Vector#(n_INGRESS_PORTS, CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA)) children, Vector#(TAdd#(1, n_INGRESS_PORTS) , t_NODE_ID) addressBounds, function m#(LOCAL_ARBITER#(n_INGRESS_PORTS)) mkArbiter() ) (CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA))
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

    // Ingress buffering.  We need to accept incoming requests to a buffer 
    // before we decide what to do with them. 
    FIFOF#(TREE_MSG#(t_NODE_ID, t_DATA)) incomingBuffer <- mkFIFOF();

    // Egress buffering.  Injects a cycle of latency to cut path between tree layers.
    FIFOF#(TREE_MSG#(t_NODE_ID, t_DATA)) outgoingBuffer <- mkFIFOF();


    //
    // Wires -- these are used to implement muxes in the child selection algorithm 
    // 

    let  selectionIndex     <- mkRWire; 
   
    // 
    //  Request side. Manages messages moving to root of tree. 
    //

    //
    // Because of the local arbiter methods are Actions, we need to select the arbited 
    // client here and then feed it via a wire. 
    // 
    rule doArbitration (outgoingBuffer.notFull);
        let selectionResult <- inboundArbiter.arbitrate( map(isNotEmpty,children), False);

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
            $display("Selected message from child %d (%d): %h", selectionIndex.wget().Valid, children[selectionIndex.wget().Valid].first.dstNode, children[selectionIndex.wget().Valid].first.data); 
        endrule
 
    end


    // 
    //  Response side. Manages messages moving towards leaves of tree. 
    //

    // Since ranges are mutually exclusive, we generate the control signals in this rule. 
    let dest = incomingBuffer.first.dstNode;
    let greaterThanRanges = zipWith( \<= , addressBounds, replicate(dest)); 

    // We use to identify the transistion between range of the 
    function Bool aAndNotB(Bool a, Bool b) = a && !b;

    Vector#(n_INGRESS_PORTS, Bool) useChild = zipWith( aAndNotB , take(greaterThanRanges), takeTail(greaterThanRanges));

    // Sanity check that for each packet, it goes somewhere in our range. 
    rule assertRouting1 (countElem(True, useChild) == 0);
        $display("Routing tree node has a message which is not routable to any of its children");
        $finish;
    endrule

    rule assertRouting2 (countElem(True, useChild) > 1);
        $display("Routing tree logic thinks there are several children ready to execute. This is a failure. Dest: %d, Children Ready %b GEQRange: %b", dest, pack(useChild), greaterThanRanges);
        $finish;
    endrule

    for(Integer child = 0; child < fromInteger(valueof(n_INGRESS_PORTS)); child = child + 1) 
    begin

        rule dump;
            $display("%t Child has message message for %d (%d): %h", $time, child, children[fromInteger(child)].first.dstNode, children[fromInteger(child)].first.data); 
        endrule      

        // We do a range check to select the child 
        rule enqChild if(useChild[fromInteger(child)]);
            incomingBuffer.deq;
            children[fromInteger(child)].enq(incomingBuffer.first);
            $display("Placing message for %d (%d): %h", child, incomingBuffer.first.dstNode, incomingBuffer.first.data); 
        endrule
  
    end


    method Action enq(TREE_MSG#(t_NODE_ID, t_DATA) msg) ;
        incomingBuffer.enq(msg); 
    endmethod

    method Bool notFull();
        return incomingBuffer.notFull();
    endmethod
  
    method first = outgoingBuffer.first();

    method deq = outgoingBuffer.deq();
 
    method notEmpty = outgoingBuffer.notEmpty();

endmodule
