//
// Copyright (C) 2010 Intel Corporation
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

    PulseWire localSentMsg <- mkPulseWire();


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
    endrule


    //
    // sendToRing --
    //     This node has a new message for the ring.
    //
    rule sendToRing (init.initialized);
        chain.sendToNext(sendQ.first());
        sendQ.deq();

        localSentMsg.send();
    endrule


    //
    // forwardOnRing --
    //     Local node did not send a message this cycle and message coming
    //     from ring is not for this node.  Is there a message to forward?
    //
    rule forwardOnRing (init.initialized && ! localSentMsg && ! newMsgIsForMe());
        let m <- chain.recvFromPrev();
        chain.sendToNext(m);
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
