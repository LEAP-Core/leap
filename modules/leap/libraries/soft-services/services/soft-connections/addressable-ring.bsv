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
// Various addressable rings, based on the standard soft-connection based ring.
// Addressable rings hold messages bound for specific ring stops.
//
// Multiple implementations are provided, including a fair token ring and a
// simple ring with no arbitration.
//

import FIFOF::*;

`include "awb/provides/librl_bsv_base.bsh"

//
// Addressable ring interface looks like a FIFO, except that enq() takes an
// extra argument for the destination node ID.
//
interface CONNECTION_ADDR_RING#(type t_NODE_ID, type t_MSG);
    // Outgoing portion of the interface
    method Action enq(t_NODE_ID dstNode, t_MSG data);
    method Bool notFull();

    // Incoming portion
    method t_MSG first();
    method Action deq();
    method Bool notEmpty();

    method t_NODE_ID nodeID();
    method t_NODE_ID maxID();
    
`ifndef ADDR_RING_DEBUG_ENABLE_Z
    method Bool localMsgSent();
    method Bool msgReceived();
    method Bit#(2) fwdMsgSent();
`endif
endinterface


//
// Two flavors of rings are available:  token rings that enforce fairness
// and non-token rings.  The non-token rings are simpler and save bandwidth
// on rings that cross FPGA boundaries, where sending the token repeatedly
// could cause a performance problem on the physical channel connecting
// FPGAs.
//

//
// mkConnectionAddrRingNode --
//     A non-token, addressable ring with a compile-time static ring stop ID.
//
module [CONNECTED_MODULE] mkConnectionAddrRingNode#(String chainID,
                                                    t_NODE_ID staticID)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID));

    let n <- mkConnectionAddrRingNode_Impl(chainID, tagged Valid staticID);
    return n;
endmodule

//
// mkConnectionAddrRingDynNode --
//     A non-token, addressable ring with a run-time computed ring stop ID.
//
module [CONNECTED_MODULE] mkConnectionAddrRingDynNode#(String chainID)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID));

    let n <- mkConnectionAddrRingNode_Impl(chainID, tagged Invalid);
    return n;
endmodule

//
// mkConnectionTokenRingNode --
//     A token-based, addressable ring with a compile-time static ring stop ID.
//
module [CONNECTED_MODULE] mkConnectionTokenRingNode#(String chainID,
                                                     t_NODE_ID staticID)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID));

    let n <- mkConnectionTokenRingNode_Impl(chainID, tagged Valid staticID);
    return n;
endmodule


//
// mkConnectionTokenRingDynNode --
//     A token-based, addressable ring with a run-time computed ring stop ID.
//
module [CONNECTED_MODULE] mkConnectionTokenRingDynNode#(String chainID)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID));

    let n <- mkConnectionTokenRingNode_Impl(chainID, tagged Invalid);
    return n;
endmodule

//
// mkConnectionAddrRingNodeNtoN --
//     A non-token, addressable ring with a compile-time static ring stop ID.
// This implementation supports N sources and N sinks (N-to-N), while 
// mkConnectionAddrRingNode only suuports single source (1-to-N) or single 
// sink (N-to-1).
//
module [CONNECTED_MODULE] mkConnectionAddrRingNodeNtoN#(String chainID,
                                                        t_NODE_ID staticID)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID));

    DEBUG_FILE debugLog <- mkDebugFileNull(""); 
    let n <- mkConnectionAddrRingNodeNtoN_Impl(chainID, tagged Valid staticID, debugLog);
    return n;
endmodule

module [CONNECTED_MODULE] mkDebugConnectionAddrRingNodeNtoN#(String chainID,
                                                             t_NODE_ID staticID,
                                                             DEBUG_FILE debugLog)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID));

    let n <- mkConnectionAddrRingNodeNtoN_Impl(chainID, tagged Valid staticID, debugLog);
    return n;
endmodule
//
// mkConnectionAddrRingDynNodeNtoN --
//     A non-token, addressable ring with a run-time computed ring stop ID.
// This implementation supports N sources and N sinks (N-to-N), while 
// mkConnectionTokenRingDynNode only suuports single source (1-to-N) or 
// single sink (N-to-1).
//
module [CONNECTED_MODULE] mkConnectionAddrRingDynNodeNtoN#(String chainID)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID));

    DEBUG_FILE debugLog <- mkDebugFileNull(""); 
    let n <- mkConnectionAddrRingNodeNtoN_Impl(chainID, tagged Invalid, debugLog);
    return n;
endmodule

module [CONNECTED_MODULE] mkDebugConnectionAddrRingDynNodeNtoN#(String chainID,
                                                                DEBUG_FILE debugLog)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID));

    let n <- mkConnectionAddrRingNodeNtoN_Impl(chainID, tagged Invalid, debugLog);
    return n;
endmodule


// ========================================================================
//
// Internal modules
//
// ========================================================================

//
// mkConnectionAddrRingNode_Impl --
//     Build a node on an addressable ring.  This implementation does not
//     enforce fairness.  For that, use the token ring below.  What this ring
//     offers is no extra overhead of passing around a token, which may be
//     important for rings that extend off a single FPGA.
//
module [CONNECTED_MODULE] mkConnectionAddrRingNode_Impl#(String chainID,
                                                         Maybe#(t_NODE_ID) staticID)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID),
       
              Alias#(Tuple2#(t_NODE_ID, t_MSG), t_RING_MSG));

    // Allocate a node on the physical chain
    CONNECTION_CHAIN#(t_RING_MSG) chain <- mkConnectionChain(chainID);

    // Inbound & outbound FIFOs provide buffering, mostly useful to relax
    // timing constraints on potentially long wires between ring stops.
    FIFOF#(t_MSG) recvQ <- mkFIFOF();
    FIFOF#(Tuple2#(t_NODE_ID, t_MSG)) sendQ <- mkFIFOF();

    PulseWire localMsgSentW <- mkPulseWire();
    PulseWire fwdMsgPrior   <- mkPulseWire();
    PulseWire fwdMsgSentW   <- mkPulseWire();
    PulseWire msgReceivedW  <- mkPulseWire();

    //
    // Initialization of the ring.
    //

    // Send just the ID to the next node.  Message doesn't matter.
    function Action initSendToNext(t_NODE_ID id) = chain.sendToNext(tuple2(id, ?));

    // Receive an ID from the previous node.
    function ActionValue#(t_NODE_ID) initRecvFromPrev();
    actionvalue
        match {.id, .msg} <- chain.recvFromPrev();
        return id;
    endactionvalue
    endfunction

    CONNECTION_ADDR_RING_INIT#(t_NODE_ID) init <-
        mkConnectionAddrRingInitializer(chainID, staticID,
                                        initSendToNext,
                                        initRecvFromPrev);


    //
    // newMsgIsForMe --
    //     Does incoming message on the ring have data for this node?
    //
    function Bool newMsgIsForMe() = (tpl_1(chain.peekFromPrev()) == init.nodeID);


    //
    // recvFromRing --
    //     Receive a new message from the ring destined for this node.
    //
    rule recvFromRing (newMsgIsForMe());
        match {.id, .msg} <- chain.recvFromPrev();
        recvQ.enq(msg);
        msgReceivedW.send();
    endrule

    //
    // checkMsgSendPrior
    //
    if (`ADDR_RING_MSG_MODE == 2)
    begin
        Reg#(Bool)  localPrior <- mkReg(True);
        rule checkMsgSendPrior(init.initialized && chain.recvNotEmpty());
            if (!newMsgIsForMe() && !localPrior)
            begin
                fwdMsgPrior.send();
            end
        endrule
        rule updArbiter(localMsgSentW || fwdMsgSentW);
            localPrior <= fwdMsgSentW;
        endrule
    end
    else if (`ADDR_RING_MSG_MODE == 1)
    begin
        rule checkMsgSendPrior(init.initialized && chain.recvNotEmpty());
            if (!newMsgIsForMe())
            begin
                fwdMsgPrior.send();
            end
        endrule
    end

    //
    // sendToRing --
    //     This node has a new message for the ring.
    //
    rule sendToRing (init.initialized && !fwdMsgPrior);
        chain.sendToNext(sendQ.first());
        sendQ.deq();
        localMsgSentW.send();
    endrule

    //
    // forwardOnRing --
    //     Local node did not send a message this cycle and message coming
    //     from ring is not for this node.  Is there a message to forward?
    //
    rule forwardOnRing (init.initialized && ! localMsgSentW && ! newMsgIsForMe());
        let m <- chain.recvFromPrev();
        chain.sendToNext(m);
        fwdMsgSentW.send();
    endrule


    //
    // Methods...
    //

    //
    // Outbound messages
    //
    method Action enq(t_NODE_ID dstNode, t_MSG data);
        sendQ.enq(tuple2(dstNode, data));
    endmethod

    method Bool notFull() = sendQ.notFull();


    //
    // Incoming messages
    //
    method t_MSG first() = recvQ.first();

    method Action deq();
        recvQ.deq();
    endmethod

    method Bool notEmpty() = recvQ.notEmpty();


    method t_NODE_ID nodeID() = init.nodeID();
    method t_NODE_ID maxID() = init.maxID();

`ifndef ADDR_RING_DEBUG_ENABLE_Z
    // Signals for debugging
    method Bool localMsgSent() = localMsgSentW;
    method Bool msgReceived() = msgReceivedW;
    method Bit#(2) fwdMsgSent();
        return (fwdMsgSentW)? 1 : 0;
    endmethod
`endif 
endmodule

//
// mkConnectionAddrRingNodeNtoN_Impl --
//     Build a node on an addressable ring.  This implementation uses dateline
// technique to guarantee deadlock freedom when there are multiple sources and
// multiple sinks on the ring. Similar to mkConnectionAddrRingNode_Impl, this
// implementation does not enforce fairness.  
//
module [CONNECTED_MODULE] mkConnectionAddrRingNodeNtoN_Impl#(String chainID,
                                                             Maybe#(t_NODE_ID) staticID,
                                                             DEBUG_FILE debugLog)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID),

              Alias#(Tuple2#(t_NODE_ID, t_MSG), t_RING_MSG));

    //
    // Allocate a node on two physical chains (to prevent deadlocks)
    //
    // The dateline is inserted at the node 0 (the primary node). Local messages
    // are injected to chain0. Any message (on chain0) passing node 0 is forwarded 
    // to chain1. 
    //
    CONNECTION_CHAIN#(t_RING_MSG) chain0 <- mkConnectionChain(chainID+"_0");
    CONNECTION_CHAIN#(t_RING_MSG) chain1 <- mkConnectionChain(chainID+"_1");

    // Inbound & outbound FIFOs provide buffering, mostly useful to relax
    // timing constraints on potentially long wires between ring stops.
    FIFOF#(t_MSG) recvQ <- mkFIFOF();
    FIFOF#(t_RING_MSG) sendQ <- mkFIFOF();

    PulseWire localMsgSentW <- mkPulseWire();
    PulseWire fwdMsgPrior   <- mkPulseWire();
    PulseWire fwdMsgSent0W  <- mkPulseWire();
    PulseWire fwdMsgSent1W  <- mkPulseWire();
    PulseWire msgReceived0W <- mkPulseWire();
    PulseWire msgReceived1W <- mkPulseWire();

    //
    // Initialization of the ring.
    //

    // Send just the ID to the next node.  Message doesn't matter.
    function Action initSendToNext(t_NODE_ID id) = chain0.sendToNext(tuple2(id, ?));

    // Receive an ID from the previous node.
    function ActionValue#(t_NODE_ID) initRecvFromPrev();
    actionvalue
        match {.id, .msg} <- chain0.recvFromPrev();
        return id;
    endactionvalue
    endfunction

    CONNECTION_ADDR_RING_INIT#(t_NODE_ID) init <-
        mkConnectionAddrRingInitializer(chainID, staticID,
                                        initSendToNext,
                                        initRecvFromPrev);


    //
    // newMsgIsForMe --
    //     Does incoming message on the ring have data for this node?
    //
    function Bool newMsgIsForMe0() = (tpl_1(chain0.peekFromPrev()) == init.nodeID);
    function Bool newMsgIsForMe1() = (tpl_1(chain1.peekFromPrev()) == init.nodeID);

    function Bool nodeIsPrimary() = (isValid(staticID) &&
                                     (validValue(staticID) == 0));

    //
    // recvFromRing --
    //     Receive a new message from the ring destined for this node.
    //
    Reg#(Bool) chain0Prior     <- mkReg(True);
    PulseWire chain0RecvPriorW <- mkPulseWire();
    
    // Check if chain0 has priority to receive a message
    rule checkMsgRecv0Prior(newMsgIsForMe0() && chain0Prior);
        chain0RecvPriorW.send();
    endrule
    
    // Receive a new message from the chain1 if chain0 does not have priority
    rule recvFromRing1 (newMsgIsForMe1() && !chain0RecvPriorW && !nodeIsPrimary);
        match {.id, .msg} <- chain1.recvFromPrev();
        recvQ.enq(msg);
        msgReceived1W.send();
        chain0Prior <= True;
        debugLog.record($format("Ring Node 0x%x: recvFromRing1: id:0x%x", init.nodeID, id));
    endrule
    
    // Receive a new message from chain0 if chain1 doesn't receive a message
    rule recvFromRing0 (newMsgIsForMe0() && !msgReceived1W);
        match {.id, .msg} <- chain0.recvFromPrev();
        recvQ.enq(msg);
        msgReceived0W.send();
        chain0Prior <= False;
        debugLog.record($format("Ring Node 0x%x: recvFromRing0: id:0x%x", init.nodeID, id));
    endrule

    
    //
    // checkMsgSendPrior
    //
    if (`ADDR_RING_MSG_MODE == 2)
    begin
        Reg#(Bool)  localPrior <- mkReg(True);
        rule checkMsgSendPrior(init.initialized && chain0.recvNotEmpty() && !nodeIsPrimary);
            if (!newMsgIsForMe0() && !localPrior)
            begin
                fwdMsgPrior.send();
            end
        endrule
        rule updArbiter(localMsgSentW || fwdMsgSent0W);
            localPrior <= fwdMsgSent0W;
        endrule
    end
    else if (`ADDR_RING_MSG_MODE == 1)
    begin
        rule checkMsgSendPrior(init.initialized && chain0.recvNotEmpty() && !nodeIsPrimary);
            if (!newMsgIsForMe0())
            begin
                fwdMsgPrior.send();
            end
        endrule
    end

    //
    // sendToRing --
    //     This node has a new message for the ring.
    //
    rule sendToRing (init.initialized && !fwdMsgPrior);
        chain0.sendToNext(sendQ.first());
        sendQ.deq();
        localMsgSentW.send();
        debugLog.record($format("Ring Node 0x%x: sendToRing: id:0x%x", init.nodeID, tpl_1(sendQ.first())));
    endrule

    //
    // forwardOnRing0 --
    //     A non-primary node forwards a message on chain0 if the local node 
    // did not send a message this cycle and message coming from ring is not 
    // for this node.
    //
    rule forwardOnRing0 (init.initialized && ! localMsgSentW && ! newMsgIsForMe0() && ! nodeIsPrimary);
        let m <- chain0.recvFromPrev();
        chain0.sendToNext(m);
        fwdMsgSent0W.send();
        debugLog.record($format("Ring Node 0x%x: forwardOnRing0: id:0x%x", init.nodeID, tpl_1(m)));
    endrule

    //
    // forwardOnRing1 --
    //     A non-primary node forwards a message on chain1 if the message from 
    // the ring is not for this node.
    //
    rule forwardOnRing1 (init.initialized && ! newMsgIsForMe1() && ! nodeIsPrimary);
        let m <- chain1.recvFromPrev();
        chain1.sendToNext(m);
        fwdMsgSent1W.send();
        debugLog.record($format("Ring Node 0x%x: forwardOnRing1: id:0x%x", init.nodeID, tpl_1(m)));
    endrule
    
    //
    // forwardOnRingPrimary --
    //     The primary node forwards a message from chain0 to chain1 if the message
    // comming from the ring is not for this node.
    //
    rule forwardOnRingPrimary (init.initialized && ! newMsgIsForMe0() && nodeIsPrimary);
        let m <- chain0.recvFromPrev();
        chain1.sendToNext(m);
        fwdMsgSent1W.send();
        debugLog.record($format("Ring Node 0x%x: forwardOnRingPrimary: id:0x%x", init.nodeID, tpl_1(m)));
    endrule

    // This should not fire
    rule recvRing1Primary (init.initialized && nodeIsPrimary);
        let m <- chain1.recvFromPrev();
        debugLog.record($format("Ring Node 0x%x: ERROR recvRing1Primary: id:0x%x", init.nodeID, tpl_1(m)));
    endrule
    

    //
    // Methods...
    //

    //
    // Outbound messages
    //
    method Action enq(t_NODE_ID dstNode, t_MSG data);
        sendQ.enq(tuple2(dstNode, data));
    endmethod

    method Bool notFull() = sendQ.notFull();


    //
    // Incoming messages
    //
    method t_MSG first() = recvQ.first();

    method Action deq();
        recvQ.deq();
    endmethod

    method Bool notEmpty() = recvQ.notEmpty();


    method t_NODE_ID nodeID() = init.nodeID();
    method t_NODE_ID maxID() = init.maxID();

`ifndef ADDR_RING_DEBUG_ENABLE_Z
    // Signals for debugging
    method Bool localMsgSent() = localMsgSentW;
    method Bool msgReceived() = msgReceived0W || msgReceived1W;
    method Bit#(2) fwdMsgSent();
        Bit#(2) fwd_msg = 0;
        if (fwdMsgSent0W && fwdMsgSent1W)
        begin
            fwd_msg = 2;
        end
        else if (fwdMsgSent0W || fwdMsgSent1W)
        begin
            fwd_msg = 1;
        end
        return fwd_msg;
    endmethod
`endif 
endmodule

//
// Internal types
//
typedef struct
{
    Bool token;
    Maybe#(Tuple2#(t_NODE_ID, t_MSG)) data;
}
TOKEN_RING_MSG#(type t_NODE_ID, type t_MSG)
    deriving (Eq, Bits);


//
// mkConnectionTokenRingNode_Impl --
//     Build a node on a token ring.  The token enforces fairness.
//
//     WARNING:  there must be a node with a NODE_ID of 0.  The token starts
//               on this node.
//
module [CONNECTED_MODULE] mkConnectionTokenRingNode_Impl#(String chainID,
                                                          Maybe#(t_NODE_ID) staticID)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID),
       
              Alias#(TOKEN_RING_MSG#(t_NODE_ID, t_MSG), t_RING_MSG));

    function Bool nodeIsPrimary() = (isValid(staticID) &&
                                     (validValue(staticID) == 0));

    // Allocate a node on the physical chain
    CONNECTION_CHAIN#(t_RING_MSG) chain <- mkConnectionChain(chainID);

    // Inbound & outbound FIFOs
    FIFOF#(t_MSG) recvQ <- mkFIFOF();
    FIFOF#(Tuple2#(t_NODE_ID, t_MSG)) sendQ <- mkFIFOF();

    COUNTER#(1) sawToken <- mkLCounter(0);
    COUNTER#(1) haveToken <- mkLCounter(0);

    PulseWire localSentMsg <- mkPulseWire();
    PulseWire forwardMsg <- mkPulseWire();

    //
    // Initialization of the ring.
    //

    // Send just the ID to the next node.  Message doesn't matter.
    function Action initSendToNext(t_NODE_ID id);
    action
        t_RING_MSG r = ?;
        r.data = tagged Valid tuple2(id, ?);
        chain.sendToNext(r);
    endaction
    endfunction

    // Receive an ID from the previous node.
    function ActionValue#(t_NODE_ID) initRecvFromPrev();
    actionvalue
        let r <- chain.recvFromPrev();
        return tpl_1(validValue(r.data));
    endactionvalue
    endfunction

    CONNECTION_ADDR_RING_INIT#(t_NODE_ID) init <-
        mkConnectionAddrRingInitializer(chainID, staticID,
                                        initSendToNext,
                                        initRecvFromPrev);

    //
    // Initialization of the token counters. 
    //
    Reg#(Bool) tokenInitialized <- mkReg(False);
    rule tokenCounterInit (!tokenInitialized);
        sawToken.setC(nodeIsPrimary ? 1 : 0);
        haveToken.setC(nodeIsPrimary ? 1 : 0);
        tokenInitialized <= True;
    endrule

    //
    // newMsgIsForMe --
    //     Does incoming message on the ring have data for this node?
    //
    function Bool newMsgIsForMe();
        if (chain.peekFromPrev().data matches tagged Valid {.tgt, .msg})
            return tgt == init.nodeID;
        else
            return False;
    endfunction


    //
    // recvFromRing --
    //     Receive a new message from the ring destined for this node.
    //
    rule recvFromRing (newMsgIsForMe() && tokenInitialized);
        let r <- chain.recvFromPrev();
        
        // Does the message have the token?
        if (r.token)
        begin
            haveToken.up();
            sawToken.setC(1);
        end

        recvQ.enq(tpl_2(validValue(r.data)));
    endrule


    //
    // sendToRing --
    //     This node has a new message for the ring and has permission to send
    //     either because it has seen the token since last sending or there is
    //     no message to forward.
    //
    rule sendToRing (init.initialized && tokenInitialized && ((sawToken.value() != 0) ||
                                          ! chain.recvNotEmpty() ||
                                          newMsgIsForMe()));
        t_RING_MSG r;

        // Is this node holding the token?  Forward it.
        r.token = (haveToken.value() != 0);
        if (r.token)
        begin
            haveToken.down();
        end

        // Clear the local token
        if (sawToken.value() != 0)
        begin
            sawToken.down();
        end

        r.data = tagged Valid sendQ.first();
        sendQ.deq();

        chain.sendToNext(r);
        localSentMsg.send();
    endrule


    //
    // forwardOnRing --
    //     Local node did not send a message this cycle and message coming
    //     from ring is not for this node.  Is there a message to forward?
    //
    rule forwardOnRing (init.initialized && tokenInitialized && ! localSentMsg && ! newMsgIsForMe());
        let r <- chain.recvFromPrev();

        if (r.token)
        begin
            sawToken.setC(1);
        end

        // Was this node holding the token?  Pass it on.
        if (haveToken.value() != 0)
        begin
            r.token = True;
            haveToken.down();
        end

        chain.sendToNext(r);
        forwardMsg.send();
    endrule


    //
    // forwardTokenOnRing --
    //     No ring activity this cycle.  Is this node holding the token?  If
    //     so, send the token on to the next hop.
    //
    rule forwardTokenOnRing (init.initialized &&
                             tokenInitialized &&
                             ! localSentMsg &&
                             ! forwardMsg &&
                             (haveToken.value() != 0));
        t_RING_MSG r;
        r.token = True;
        r.data = tagged Invalid;

        chain.sendToNext(r);
        haveToken.down();
    endrule


    //
    // Methods...
    //

    //
    // Outbound messages
    //
    method Action enq(t_NODE_ID dstNode, t_MSG data);
        sendQ.enq(tuple2(dstNode, data));
    endmethod

    method Bool notFull() = sendQ.notFull();


    //
    // Incoming messages
    //
    method t_MSG first() = recvQ.first();

    method Action deq();
        recvQ.deq();
    endmethod

    method Bool notEmpty() = recvQ.notEmpty();


    method t_NODE_ID nodeID() = init.nodeID();
    method t_NODE_ID maxID() = init.maxID();
    
`ifndef ADDR_RING_DEBUG_ENABLE_Z
    // Signals for debugging
    method Bool localMsgSent() = False;
    method Bool msgReceived()  = False;
    method Bit#(2) fwdMsgSent() = 0;
`endif
endmodule


// ========================================================================
//
// Internal module to initialize an addressed ring, computing the ID of
// each node.  The ID is either specified statically if the staticID
// parameter is valid or the ID will be computed dynamically.  The dynamic
// computation depends on exactly one node being allocated with static
// ID 0.
//
// ========================================================================

interface CONNECTION_ADDR_RING_INIT#(type t_NODE_ID);
    method Bool initialized();
    method t_NODE_ID nodeID;
    method t_NODE_ID maxID;
endinterface

module mkConnectionAddrRingInitializer#(String chainID,
                                        Maybe#(t_NODE_ID) staticID,
                                        function Action sendToNext(t_NODE_ID id),
                                        function ActionValue#(t_NODE_ID) recvFromPrev())
    (CONNECTION_ADDR_RING_INIT#(t_NODE_ID))
    provisos (Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
              Bounded#(t_NODE_ID),
              Ord#(t_NODE_ID),
              Arith#(t_NODE_ID));

    Reg#(t_NODE_ID) myID <- mkRegU();
    Reg#(t_NODE_ID) dynMaxID <- mkRegU();

    Reg#(Bool) initDone <- mkReg(False);
    Reg#(Bit#(2)) initPhase <- mkReg(0);
    
    function Bool nodeIsPrimary() = (isValid(staticID) &&
                                     (validValue(staticID) == 0));


    //
    // Initialization phase 0:  discover the largest static ID on the ring.
    //
    rule initPhase0 (! initDone && (initPhase == 0));
        if (nodeIsPrimary)
        begin
            // Root node sends out a discovery packet.
            sendToNext(0);
        end
        else
        begin
            // Other nodes update the packet's node ID with the maximum
            // static ID.
            let id <- recvFromPrev();

            if (staticID matches tagged Valid .s_id &&& s_id > id)
            begin
                id = s_id;
            end

            sendToNext(id);
        end

        initPhase <= 1;
    endrule

    //
    // Initialization phase 1:  set dynamic node IDs.
    //
    rule initPhase1 (! initDone && (initPhase == 1));
        // Forward the token around one more time and set a dynamic ID if
        // needed.
        let id <- recvFromPrev();

        if (! isValid(staticID))
        begin
            if (id == maxBound)
            begin
                $display("Ring " + chainID + " ran out of node IDs!");
                $finish(1);
            end

            id = id + 1;
            myID <= id;
        end
        else
        begin
            myID <= validValue(staticID);
        end

        sendToNext(id);

        initPhase <= 2;
    endrule

    //
    // Initialization phase 2:  Send around the maximum ID
    //
    rule initPhase2 (! initDone && (initPhase == 2));
        let id <- recvFromPrev();
        dynMaxID <= id;

        if (! nodeIsPrimary)
        begin
            initDone <= True;
        end

        sendToNext(id);
        initPhase <= 3;
    endrule

    //
    // Initialization phase 3:  primary node syncs the setup token.
    //
    rule initPhase3 (! initDone && (initPhase == 3) && nodeIsPrimary);
        let id <- recvFromPrev();
        initDone <= True;
    endrule


    //
    // Methods
    //
    method Bool initialized() = initDone;

    method t_NODE_ID nodeID if (initDone);
        return myID;
    endmethod

    method t_NODE_ID maxID if (initDone);
        return dynMaxID;
    endmethod
endmodule
