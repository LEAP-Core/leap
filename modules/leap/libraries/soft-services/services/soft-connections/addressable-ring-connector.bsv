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
// Connectors for various addressable rings. 
//

`include "awb/provides/librl_bsv_base.bsh"

//
// mkConnectionHierarchicalAddrRingConnector --
//     A connector that connects two non-token, addressable rings
// with a statically assigned function that checks whether a given node ID 
// belongs to the child ring. 
//
module [CONNECTED_MODULE] mkConnectionHierarchicalAddrRingConnector#(String childChainID, 
                                                                     String parentChainID, 
                                                                     NumTypeParam#(t_NODE_ID_SZ) nodeIdSz,
                                                                     NumTypeParam#(t_MSG_SZ) msgSz, 
                                                                     function Bool isChildNodeFunc(Bit#(t_NODE_ID_SZ) nodeId))
    // Interface:
    (Empty);
     
    function Maybe#(Bool) isChildNode(Bit#(t_NODE_ID_SZ) nodeID) = tagged Valid isChildNodeFunc(nodeID);
    mkConnectionHierarchicalAddrRingConnector_Impl(childChainID, parentChainID, nodeIdSz, msgSz, isChildNode);
endmodule

//
// mkConnectionHierarchicalAddrRingDynConnector --
//     A connector that connects two non-token, addressable rings. The ring 
// stop IDs on the child ring are computed at run-time. 
//
module [CONNECTED_MODULE] mkConnectionHierarchicalAddrRingDynConnector#(String childChainID, 
                                                                        String parentChainID, 
                                                                        NumTypeParam#(t_NODE_ID_SZ) nodeIdSz,
                                                                        NumTypeParam#(t_MSG_SZ) msgSz)
    // Interface:
    (Empty);

    function Maybe#(Bool) isChildNode(Bit#(t_NODE_ID_SZ) nodeID) = tagged Invalid;
    mkConnectionHierarchicalAddrRingConnector_Impl(childChainID, parentChainID, nodeIdSz, msgSz, isChildNode);
endmodule


//
// mkConnectionHierarchicalTokenRingConnector --
//     A connector that connects two token-based, addressable rings
// with a statically assigned function that checks whether a given node ID belongs
// to the child ring. 
//
module [CONNECTED_MODULE] mkConnectionHierarchicalTokenRingConnector#(String childChainID, 
                                                                      String parentChainID, 
                                                                      NumTypeParam#(t_NODE_ID_SZ) nodeIdSz,
                                                                      NumTypeParam#(t_MSG_SZ) msgSz, 
                                                                      function Bool isChildNodeFunc(Bit#(t_NODE_ID_SZ) nodeId))
    // Interface:
    (Empty);
    
    function Maybe#(Bool) isChildNode(Bit#(t_NODE_ID_SZ) nodeID) = tagged Valid isChildNodeFunc(nodeID);
    mkConnectionHierarchicalTokenRingConnector_Impl(childChainID, parentChainID, nodeIdSz, msgSz, isChildNode);
endmodule

//
// mkConnectionHierarchicalTokenRingDynConnector --
//     A connector that connects two token-based, addressable rings. The ring 
// stop IDs on the child ring are consecutive or computed at run-time. 
//
module [CONNECTED_MODULE] mkConnectionHierarchicalTokenRingDynConnector#(String childChainID, 
                                                                         String parentChainID, 
                                                                         NumTypeParam#(t_NODE_ID_SZ) nodeIdSz,
                                                                         NumTypeParam#(t_MSG_SZ) msgSz)
    // Interface:
    (Empty);

    function Maybe#(Bool) isChildNode(Bit#(t_NODE_ID_SZ) nodeID) = tagged Invalid;
    mkConnectionHierarchicalTokenRingConnector_Impl(childChainID, parentChainID, nodeIdSz, msgSz, isChildNode);
endmodule


// ========================================================================
//
// Internal modules
//
// ========================================================================

//
// mkConnectionHierarchicalAddrRingConnector_Impl --
//     Build a connector to connect two non-token rings.  
//
module [CONNECTED_MODULE] mkConnectionHierarchicalAddrRingConnector_Impl#(String childChainID,
                                                                          String parentChainID, 
                                                                          NumTypeParam#(t_NODE_ID_SZ) nodeIdSz,
                                                                          NumTypeParam#(t_MSG_SZ) msgSz, 
                                                                          function Maybe#(Bool) isChildNodeFunc(Bit#(t_NODE_ID_SZ) nodeId))
    // Interface:
    (Empty)
    provisos (Alias#(Bit#(t_MSG_SZ), t_MSG),
              Alias#(Bit#(t_NODE_ID_SZ), t_NODE_ID),
              Alias#(Tuple2#(t_NODE_ID, t_MSG), t_RING_MSG));

    // Allocate a node on each physical chain
    CONNECTION_CHAIN#(t_RING_MSG) childChain <- mkConnectionChain(childChainID);
    CONNECTION_CHAIN#(t_RING_MSG) parentChain <- mkConnectionChain(parentChainID);

    PulseWire fwdFromChildToParentW  <- mkPulseWire();
    PulseWire fwdFromChildToChildW   <- mkPulseWire();
    PulseWire fwdFromParentToParentW <- mkPulseWire();
    PulseWire fwdFromParentToChildW  <- mkPulseWire();

    //
    // Initialization of the ring.
    //
    // Send just the ID to the next node on the child ring
    function Action initSendToChildRing(t_NODE_ID id) = childChain.sendToNext(tuple2(id, ?));
    
    // Send just the ID to the next node on the parent ring
    function Action initSendToParentRing(t_NODE_ID id) = parentChain.sendToNext(tuple2(id, ?));

    // Receive an ID from the previous node on the child ring.
    function ActionValue#(t_NODE_ID) initRecvFromChildRing();
    actionvalue
        match {.id, .msg} <- childChain.recvFromPrev();
        return id;
    endactionvalue
    endfunction
    
    // Receive an ID from the previous node on the parent ring.
    function ActionValue#(t_NODE_ID) initRecvFromParentRing();
    actionvalue
        match {.id, .msg} <- parentChain.recvFromPrev();
        return id;
    endactionvalue
    endfunction

    CONNECTION_ADDR_RING_CONNECTOR_INIT#(t_NODE_ID) init <- 
        mkConnectionAddrRingConnectorInitializer(isChildNodeFunc,
                                                 initSendToChildRing, 
                                                 initRecvFromChildRing,
                                                 initSendToParentRing, 
                                                 initRecvFromParentRing);

    PulseWire fwdParentMsgPrior  <- mkPulseWire();
    PulseWire fwdChildMsgPrior   <- mkPulseWire();
    
    //
    // newMsgFromChildToParent --
    //     Does incoming message on the child ring have data for one of the parent nodes?
    //
    function Bool newMsgFromChildIsForParent() = !init.isChildNode(tpl_1(childChain.peekFromPrev()));
    
    //
    // newMsgFromParentToChild --
    //     Does incoming message on the parent ring have data for one of the child nodes?
    //
    function Bool newMsgFromParentIsForChild() = init.isChildNode(tpl_1(parentChain.peekFromPrev()));

    //
    // checkMsgSendPrior
    //
    if (`ADDR_RING_MSG_MODE == 2)
    begin
        Reg#(Bool)  childToParentPrior <- mkReg(True);
        Reg#(Bool)  parentToChildPrior <- mkReg(True);
        rule checkParentMsgSendPrior(init.initialized && parentChain.recvNotEmpty());
            if (!newMsgFromParentIsForChild() && !childToParentPrior)
            begin
                fwdParentMsgPrior.send();
            end
        endrule
        rule updParentArbiter(fwdFromParentToParentW || fwdFromChildToParentW);
            childToParentPrior <= fwdFromParentToParentW;
        endrule
        rule checkChildMsgSendPrior(init.initialized && childChain.recvNotEmpty());
            if (!newMsgFromChildIsForParent() && !parentToChildPrior)
            begin
                fwdChildMsgPrior.send();
            end
        endrule
        rule updChildArbiter(fwdFromChildToChildW || fwdFromParentToChildW);
            parentToChildPrior <= fwdFromChildToChildW;
        endrule
    end
    else if (`ADDR_RING_MSG_MODE == 1)
    begin
        rule checkParentMsgSendPrior(init.initialized && parentChain.recvNotEmpty());
            if (!newMsgFromParentIsForChild())
            begin
                fwdParentMsgPrior.send();
            end
        endrule
        rule checkChildMsgSendPrior(init.initialized && childChain.recvNotEmpty());
            if (!newMsgFromChildIsForParent())
            begin
                fwdChildMsgPrior.send();
            end
        endrule
    end

    //
    // forwardFromChildRingToParentRing --
    //     Forward message from child ring to parent ring. 
    //
    rule forwardFromChildRingToParentRing (init.initialized && 
                                           !fwdParentMsgPrior && 
                                           newMsgFromChildIsForParent());
        let r <- childChain.recvFromPrev();
        parentChain.sendToNext(r);
        fwdFromChildToParentW.send();
    endrule

    //
    // forwardOnParentRing --
    //     Message coming from the parent ring is not for child nodes. 
    //
    rule forwardOnParentRing (init.initialized && 
                              !fwdFromChildToParentW && 
                              !newMsgFromParentIsForChild());
        let r <- parentChain.recvFromPrev();
        parentChain.sendToNext(r);
        fwdFromParentToParentW.send();
    endrule
    
    //
    // forwardFromParentRingToChildRing --
    //     Forward message from parent ring to child ring. 
    //
    rule forwardFromParentRingToChildRing (init.initialized && 
                                           !fwdChildMsgPrior && 
                                           newMsgFromParentIsForChild());
        let r <- parentChain.recvFromPrev();
        childChain.sendToNext(r);
        fwdFromParentToChildW.send();
    endrule

    //
    // forwardOnChildRing --
    //     Message coming from the child ring is not for parent nodes. 
    //
    rule forwardOnChildRing (init.initialized && 
                             !fwdFromParentToChildW && 
                             !newMsgFromChildIsForParent());
        let r <- childChain.recvFromPrev();
        childChain.sendToNext(r);
        fwdFromChildToChildW.send();
    endrule

endmodule


//
// mkConnectionHierarchicalTokenRingConnector_Impl --
//     Build a connector to connect two token rings.  The token enforces 
// fairness.
//
module [CONNECTED_MODULE] mkConnectionHierarchicalTokenRingConnector_Impl#(String childChainID,
                                                                           String parentChainID, 
                                                                           NumTypeParam#(t_NODE_ID_SZ) nodeIdSz,
                                                                           NumTypeParam#(t_MSG_SZ) msgSz, 
                                                                           function Maybe#(Bool) isChildNodeFunc(Bit#(t_NODE_ID_SZ) nodeId))
    // Interface:
    (Empty)
    provisos (Alias#(Bit#(t_MSG_SZ), t_MSG),
              Alias#(Bit#(t_NODE_ID_SZ), t_NODE_ID),
              Alias#(TOKEN_RING_MSG#(t_NODE_ID, t_MSG), t_RING_MSG));

    // Allocate a node on each physical chain
    CONNECTION_CHAIN#(t_RING_MSG) childChain <- mkConnectionChain(childChainID);
    CONNECTION_CHAIN#(t_RING_MSG) parentChain <- mkConnectionChain(parentChainID);
        
    COUNTER#(1) sawChildToken <- mkLCounter(0);
    COUNTER#(1) haveChildToken <- mkLCounter(0);
    COUNTER#(1) sawParentToken <- mkLCounter(0);
    COUNTER#(1) haveParentToken <- mkLCounter(0);

    PulseWire fwdFromChildToParentW  <- mkPulseWire();
    PulseWire fwdFromChildToChildW   <- mkPulseWire();
    PulseWire fwdFromParentToParentW <- mkPulseWire();
    PulseWire fwdFromParentToChildW  <- mkPulseWire();

    //
    // Initialization of the ring.
    //
    // Send just the ID to the next node on the child ring
    function Action initSendToChildRing(t_NODE_ID id);
    action
        t_RING_MSG r = ?;
        r.data = tagged Valid tuple2(id, ?);
        childChain.sendToNext(r);
    endaction
    endfunction
    
    // Send just the ID to the next node on the parent ring
    function Action initSendToParentRing(t_NODE_ID id);
    action
        t_RING_MSG r = ?;
        r.data = tagged Valid tuple2(id, ?);
        parentChain.sendToNext(r);
    endaction
    endfunction

    // Receive an ID from the previous node on the child ring.
    function ActionValue#(t_NODE_ID) initRecvFromChildRing();
    actionvalue
        let r <- childChain.recvFromPrev();
        return tpl_1(validValue(r.data));
    endactionvalue
    endfunction
    
    // Receive an ID from the previous node on the parent ring.
    function ActionValue#(t_NODE_ID) initRecvFromParentRing();
    actionvalue
        let r <- parentChain.recvFromPrev();
        return tpl_1(validValue(r.data));
    endactionvalue
    endfunction

    CONNECTION_ADDR_RING_CONNECTOR_INIT#(t_NODE_ID) init <- 
        mkConnectionAddrRingConnectorInitializer(isChildNodeFunc,
                                                 initSendToChildRing, 
                                                 initRecvFromChildRing,
                                                 initSendToParentRing, 
                                                 initRecvFromParentRing);

    //
    // Initialization of the token counters. 
    //
    Reg#(Bool) tokenInitialized <- mkReg(False);
    rule tokenCounterInit (!tokenInitialized);
        sawParentToken.setC(0);
        haveParentToken.setC(0);
        // connector can be seen as the primary node on the child ring
        sawChildToken.setC(1); 
        haveChildToken.setC(1);
        tokenInitialized <= True;
    endrule

    //
    // newMsgFromChildToParent --
    //     Does incoming message on the child ring have data for one of the parent nodes?
    //
    function Bool newMsgFromChildIsForParent();
        if (childChain.peekFromPrev().data matches tagged Valid {.tgt, .msg})
            return !init.isChildNode(tgt);
        else
            return False;
    endfunction
    
    //
    // newMsgFromParentToChild --
    //     Does incoming message on the parent ring have data for one of the child nodes?
    //
    function Bool newMsgFromParentIsForChild();
        if (parentChain.peekFromPrev().data matches tagged Valid {.tgt, .msg})
            return init.isChildNode(tgt);
        else
            return False;
    endfunction
        
    //
    // forwardFromChildRingToParentRing --
    //     Forward message from child ring to parent ring. 
    //
    rule forwardFromChildRingToParentRing (init.initialized && tokenInitialized && 
                                           newMsgFromChildIsForParent() && ((sawParentToken.value() != 0) ||
                                           !parentChain.recvNotEmpty() || newMsgFromParentIsForChild()));
        let r <- childChain.recvFromPrev();
        
        if (r.token)
        begin
            sawChildToken.setC(1);
            haveChildToken.up();
        end

        // Is this node holding the parent ring token?  Forward it.
        r.token = (haveParentToken.value() != 0);
        if (r.token)
        begin
            haveParentToken.down();
        end

        // Clear the local parent token
        if (sawParentToken.value() != 0)
        begin
            sawParentToken.down();
        end

        parentChain.sendToNext(r);
        fwdFromChildToParentW.send();
    endrule


    //
    // forwardOnParentRing --
    //     Message coming from the parent ring is not for child nodes. 
    //
    rule forwardOnParentRing (init.initialized && tokenInitialized && 
                              ! fwdFromChildToParentW && ! newMsgFromParentIsForChild());
        let r <- parentChain.recvFromPrev();
        if (r.token)
        begin
            sawParentToken.setC(1);
        end
        // Was this node holding the token?  Pass it on.
        if (haveParentToken.value() != 0)
        begin
            r.token = True;
            haveParentToken.down();
        end
        parentChain.sendToNext(r);
        fwdFromParentToParentW.send();
    endrule
    
    //
    // forwardTokenOnParentRing --
    //     No ring activity this cycle.  Is this node holding the token?  If
    //     so, send the token on to the next hop.
    //
    rule forwardTokenOnParentRing (init.initialized &&
                                   tokenInitialized &&
                                   ! fwdFromChildToParentW &&
                                   ! fwdFromParentToParentW &&
                                   (haveParentToken.value() != 0));
        t_RING_MSG r;
        r.token = True;
        r.data = tagged Invalid;

        parentChain.sendToNext(r);
        haveParentToken.down();
    endrule

    //
    // forwardFromParentRingToChildRing --
    //     Forward message from parent ring to child ring. 
    //
    rule forwardFromParentRingToChildRing (init.initialized && tokenInitialized && 
                                           newMsgFromParentIsForChild() && ((sawChildToken.value() != 0) ||
                                           !childChain.recvNotEmpty() || newMsgFromChildIsForParent()));
        let r <- parentChain.recvFromPrev();
        
        if (r.token)
        begin
            sawParentToken.setC(1);
            haveParentToken.up();
        end

        // Is this node holding the child ring token?  Forward it.
        r.token = (haveChildToken.value() != 0);
        if (r.token)
        begin
            haveChildToken.down();
        end

        // Clear the local child ring token
        if (sawChildToken.value() != 0)
        begin
            sawChildToken.down();
        end

        childChain.sendToNext(r);
        fwdFromParentToChildW.send();
    endrule


    //
    // forwardOnChildRing --
    //     Message coming from the child ring is not for parent nodes. 
    //
    rule forwardOnChildRing (init.initialized && tokenInitialized && 
                             ! fwdFromParentToChildW && ! newMsgFromChildIsForParent());
        let r <- childChain.recvFromPrev();
        if (r.token)
        begin
            sawChildToken.setC(1);
        end
        // Was this node holding the token?  Pass it on.
        if (haveChildToken.value() != 0)
        begin
            r.token = True;
            haveChildToken.down();
        end
        childChain.sendToNext(r);
        fwdFromChildToChildW.send();
    endrule

    //
    // forwardTokenOnChildRing --
    //     No ring activity this cycle.  Is this node holding the token?  If
    //     so, send the token on to the next hop.
    //
    rule forwardTokenOnChildRing (init.initialized &&
                                  tokenInitialized &&
                                  ! fwdFromChildToChildW &&
                                  ! fwdFromParentToChildW &&
                                  (haveChildToken.value() != 0));
        t_RING_MSG r;
        r.token = True;
        r.data = tagged Invalid;

        childChain.sendToNext(r);
        haveChildToken.down();
    endrule

endmodule

// ========================================================================
//
// Internal module to initialize an hierarchical addressed ring connector, 
// creating the function that determines whether a given ring stop ID belongs
// to the child ring.  
//
// ========================================================================

interface CONNECTION_ADDR_RING_CONNECTOR_INIT#(type t_NODE_ID);
    method Bool initialized();
    method Bool isChildNode(t_NODE_ID nodeID);
endinterface

module mkConnectionAddrRingConnectorInitializer#(function Maybe#(Bool) isChildNodeFunc(t_NODE_ID id),
                                                 function Action sendToChildRing(t_NODE_ID id),
                                                 function ActionValue#(t_NODE_ID) recvFromChildRing(),
                                                 function Action sendToParentRing(t_NODE_ID id),
                                                 function ActionValue#(t_NODE_ID) recvFromParentRing())
    (CONNECTION_ADDR_RING_CONNECTOR_INIT#(t_NODE_ID))
    provisos (Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID));

    Reg#(t_NODE_ID) minChildNodeID <- mkRegU();
    Reg#(t_NODE_ID) maxChildNodeID <- mkRegU();

    Reg#(Bool) initDone <- mkReg(False);
    Reg#(Bit#(3)) initPhase <- mkReg(0);
    
    function Bool isChildNodeStatic() = isValid(isChildNodeFunc(0));

    //
    // Initialization phase 0 and 1:  forward the initialization message to 
    // discover the largest static ID on the hierarchical ring.
    //
    // Initialization phase 4 and 5:  Send around the maximum ID on the 
    // hierarchical ring.
    //
    rule initPhase04 (! initDone && ((initPhase == 0) || (initPhase == 4)));
        let id <- recvFromParentRing();
        sendToChildRing(id);
        initPhase <= initPhase + 1;
    endrule
    
    rule initPhase15 (! initDone && ((initPhase == 1) || (initPhase == 5)));
        let id <- recvFromChildRing();
        sendToParentRing(id);
        initPhase <= initPhase + 1;
        if (initPhase == 5)
        begin
            initDone <= True;
        end
    endrule

    //
    // Initialization phase 2 and 3:  set the child ring ID range.
    //
    rule initPhase2 (! initDone && (initPhase == 2));
        let id <- recvFromParentRing();
        minChildNodeID <= id;
        sendToChildRing(id);
        initPhase <= 3;
    endrule
    
    rule initPhase3 (! initDone && (initPhase == 3));
        let id <- recvFromChildRing();
        maxChildNodeID <= id;
        sendToParentRing(id);
        initPhase <= 4;
    endrule

    //
    // Methods
    //
    method Bool initialized() = initDone;

    method Bool isChildNode(t_NODE_ID nodeID) if (initDone);
        if (isChildNodeStatic)
        begin
             return validValue(isChildNodeFunc(nodeID));
        end
        else
        begin
             return (nodeID > minChildNodeID) && (nodeID <= maxChildNodeID);
        end
    endmethod

endmodule
