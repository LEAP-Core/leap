//
// Copyright (c) 2015, Intel Corporation
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
// A parametric router for tree-based network topologies. The router expects child
// addresses to be monotonically ordered.
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

// t_DATA_UP: message type from leaf to root (from child to parent)
// t_DATA_DOWN: message type from root to leaf (from parent to child)
interface CONNECTION_ADDR_TREE#(type t_NODE_ID, type t_DATA_UP, type t_DATA_DOWN);

    // Outgoing portion of the network 
    method Action enq(TREE_MSG#(t_NODE_ID, t_DATA_DOWN) msg);
    method Bool notFull();

    // Incoming portion
    method t_DATA_UP first();
    method Action deq();
    method Bool notEmpty();

endinterface

// Define some instances for the CONNECTION_ADDR_TREE type. 
instance Dequeuable#(CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA_UP, t_DATA_DOWN));

    function isNotEmpty(CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA_UP, t_DATA_DOWN) treeNode) = treeNode.notEmpty;

endinstance
         
instance Enqueuable#(CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA_UP, t_DATA_DOWN));

    function isNotFull(CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA_UP, t_DATA_DOWN) treeNode) = treeNode.notFull;

endinstance


//
// mkTreeRouter --
//
//   Instantiates a tree-based router. The router takes as an argument a set of interfaces to its children, 
//   as well as the address ranges of the child subtrees. It also takes as an argument a constructor for 
//   an arbiter, which can be supplied externally.  
//

module [m] mkTreeRouter#(Vector#(n_INGRESS_PORTS, CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA_UP, t_DATA_DOWN)) children, 
                         Vector#(TAdd#(1, n_INGRESS_PORTS) , t_NODE_ID) addressBounds, 
                         function m#(LOCAL_ARBITER#(n_INGRESS_PORTS)) mkArbiter() ) 
    (CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA_UP, t_DATA_DOWN))
    provisos( Bits#(t_NODE_ID, t_NODE_ID_SZ), 
              Bits#(t_DATA_UP, t_DATA_UP_SZ),
              Bits#(t_DATA_DOWN, t_DATA_DOWN_SZ),
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
    FIFOF#(TREE_MSG#(t_NODE_ID, t_DATA_DOWN)) incomingBuffer <- mkFIFOF();

    // Egress buffering.  Injects a cycle of latency to cut path between tree layers.
    FIFOF#(t_DATA_UP) outgoingBuffer <- mkFIFOF();


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
        endrule
 
    end


    // 
    //  Response side. Manages messages moving towards leaves of tree. 
    //
   
    //
    // Since child addresses are guaranteed to be ordered, we can generate the control signals
    // with relatively simple operations.  
    //
    let dest = incomingBuffer.first.dstNode;
    let greaterThanEqualRanges = zipWith( \<= , addressBounds, replicate(dest)); 

    //
    // We use to identify the transistion between range of the children
    // this manifests as the 1 to 0 step of greaterThanEqualRanges.
    function Bool aAndNotB(Bool a, Bool b) = a && !b;

    Vector#(n_INGRESS_PORTS, Bool) useChild = zipWith( aAndNotB , take(greaterThanEqualRanges), takeTail(greaterThanEqualRanges));

    //
    // Sanity check that for each packet, it goes somewhere in our range. 
    //
    rule assertRouting1 (countElem(True, useChild) == 0);
        $display("Routing tree node has a message which is not routable to any of its children. Dest: %d", dest);
        $finish;
    endrule

    rule assertRouting2 (countElem(True, useChild) > 1);
        $display("Routing tree logic thinks there are several children ready to execute. This is a failure. Dest: %d, Children Ready %b GEQRange: %b", dest, pack(useChild), greaterThanEqualRanges);
        $finish;
    endrule


    for(Integer child = 0; child < fromInteger(valueof(n_INGRESS_PORTS)); child = child + 1) 
    begin

        // Check that child address ranges are, in fact, ordered.
        if ( addressBounds[child] > addressBounds[child + 1] )
        begin
            errorM("Tree router found non-monotonic address ranges.");
        end


        //
        // We do a range check to select the child 
        //
        rule enqChild if(useChild[fromInteger(child)]);
            incomingBuffer.deq;
            children[fromInteger(child)].enq(incomingBuffer.first);
        endrule
  
    end


    // 
    //  External interface definition.  We anre only plumbing FIFOs here. 
    //

    method Action enq(TREE_MSG#(t_NODE_ID, t_DATA_DOWN) msg) ;
        incomingBuffer.enq(msg); 
    endmethod

    method Bool notFull();
        return incomingBuffer.notFull();
    endmethod
  
    method first = outgoingBuffer.first();

    method deq = outgoingBuffer.deq();
 
    method notEmpty = outgoingBuffer.notEmpty();

endmodule

//
//  mkLeafNode --
//    Instantiates a leaf node in the router tree. The external interface is 
//    channel based. 
module [CONNECTED_MODULE] mkTreeLeafNode#(String treeName, Integer index) 
    (CONNECTION_ADDR_TREE#(t_NODE_ID, t_DATA_UP, t_DATA_DOWN))
    provisos( Bits#(t_NODE_ID, t_NODE_ID_SZ), 
              Bits#(t_DATA_UP, t_DATA_UP_SZ),
              Bits#(t_DATA_DOWN, t_DATA_DOWN_SZ));

    CONNECTION_RECV#(t_DATA_UP) incomingRequest <-
        mkConnectionRecv(treeName + "_TREE_NODE_IN_" + integerToString(index));

    CONNECTION_SEND#(TREE_MSG#(t_NODE_ID, t_DATA_DOWN)) outgoingRequest <-
        mkConnectionSend(treeName + "_TREE_NODE_OUT_" + integerToString(index));
    
    // Outgoing portion of the network
    method enq = outgoingRequest.send;
    method notFull = outgoingRequest.notFull;

    // Incoming portion
    method first = incomingRequest.receive;
    method deq = incomingRequest.deq;
    method notEmpty = incomingRequest.notEmpty;

endmodule

