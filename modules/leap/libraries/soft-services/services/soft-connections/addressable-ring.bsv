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
endinterface


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
// mkConnectionAddrRingNode --
//     Build a node on an addressable ring.  This implementation does not
//     enforce fairness.  For that, use the token ring below.  What this ring
//     offers is no extra overhead of passing around a token, which may be
//     important for rings that extend off a single FPGA.
//
module [CONNECTED_MODULE] mkConnectionAddrRingNode#(String chainId,
                                                    t_NODE_ID myID)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
       
              Alias#(Tuple2#(t_NODE_ID, t_MSG), t_RING_MSG),

              // Message fits in a ring?
              Bits#(t_RING_MSG, t_RING_MSG_SZ)
              /*Add#(t_RING_MSG_SZ, m__, CON_CHAIN_DATA_SZ)*/);

    // Allocate a node on the physical chain
    CONNECTION_CHAIN#(t_RING_MSG) chain <- mkConnectionChain(chainId);

    // Inbound & outbound FIFOs provide buffering, mostly useful to relax
    // timing constraints on potentially long wires between ring stops.
    FIFOF#(t_MSG) recvQ <- mkFIFOF();
    FIFOF#(Tuple2#(t_NODE_ID, t_MSG)) sendQ <- mkFIFOF();

    PulseWire localSentMsg <- mkPulseWire();


    //
    // newMsgIsForMe --
    //     Does incoming message on the ring have data for this node?
    //
    function Bool newMsgIsForMe() = (tpl_1(chain.peekFromPrev()) == myID);


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
    rule sendToRing (True);
        chain.sendToNext(sendQ.first());
        sendQ.deq();

        localSentMsg.send();
    endrule


    //
    // forwardOnRing --
    //     Local node did not send a message this cycle and message coming
    //     from ring is not for this node.  Is there a message to forward?
    //
    rule forwardOnRing (! localSentMsg && ! newMsgIsForMe());
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
endmodule



//
// mkConnectionTokenRingNode --
//     Build a node on a token ring.  The token enforces fairness.
//
//     WARNING:  there must be a node with a NODE_ID of 0.  The token starts
//               on this node.
//
module [CONNECTED_MODULE] mkConnectionTokenRingNode#(String chainId,
                                                     t_NODE_ID myID)
    // Interface:
    (CONNECTION_ADDR_RING#(t_NODE_ID, t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              Bits#(t_NODE_ID, t_NODE_ID_SZ),
              Eq#(t_NODE_ID),
       
              Alias#(TOKEN_RING_MSG#(t_NODE_ID, t_MSG), t_RING_MSG),

              // Message fits in a ring?
              Bits#(t_RING_MSG, t_RING_MSG_SZ)
              /*Add#(t_RING_MSG_SZ, m__, CON_CHAIN_DATA_SZ)*/);

    // Allocate a node on the physical chain
    CONNECTION_CHAIN#(t_RING_MSG) chain <- mkConnectionChain(chainId);

    // Inbound & outbound FIFOs
    FIFOF#(t_MSG) recvQ <- mkFIFOF();
    FIFOF#(Tuple2#(t_NODE_ID, t_MSG)) sendQ <- mkFIFOF();

    COUNTER#(1) sawToken <- mkLCounter((pack(myID) == 0) ? 1 : 0);
    COUNTER#(1) haveToken <- mkLCounter((pack(myID) == 0) ? 1 : 0);

    PulseWire localSentMsg <- mkPulseWire();
    PulseWire forwardMsg <- mkPulseWire();


    //
    // newMsgIsForMe --
    //     Does incoming message on the ring have data for this node?
    //
    function Bool newMsgIsForMe();
        if (chain.peekFromPrev().data matches tagged Valid {.tgt, .msg})
            return tgt == myID;
        else
            return False;
    endfunction


    //
    // recvFromRing --
    //     Receive a new message from the ring destined for this node.
    //
    rule recvFromRing (newMsgIsForMe());
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
    rule sendToRing ((sawToken.value() != 0) ||
                      ! chain.recvNotEmpty() ||
                      newMsgIsForMe());
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
    rule forwardOnRing (! localSentMsg && ! newMsgIsForMe());
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
    rule forwardTokenOnRing (! localSentMsg && ! forwardMsg &&
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
endmodule
