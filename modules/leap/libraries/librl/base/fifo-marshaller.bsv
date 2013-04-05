//
// Copyright (C) 2011 Massachusetts Institute of Technology
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

import Vector::*;
import GetPut::*;

//==========================================================================
// Marshallers stream wide data (t_DATA) over a narrow stream (t_FIFO_DATA).
// Demarshallers transform the narrow data stream back to the original width.
//==========================================================================


// Length (chunks) of a marshalled message
typedef TDiv#(SizeOf#(t_DATA), SizeOf#(t_FIFO_DATA))
    MARSHALLER_MSG_LEN#(type t_FIFO_DATA, type t_DATA);

// Chunk count (add 1 to message length in order to hold the value)
typedef Bit#(TLog#(TAdd#(1, MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA))))
    MARSHALLER_NUM_CHUNKS#(type t_FIFO_DATA, type t_DATA);

//
// MARSHALLER_N interface allows per-message specification of the number of
// chunks to send.  This may be useful when the actual amount of useful
// information in a t_DATA varies.
//
interface MARSHALLER#(t_FIFO_DATA, t_DATA);
    method Action enq(t_DATA inData);
    method Action deq();
    method t_FIFO_DATA first();
    method Bool notFull();
    method Bool notEmpty();
    method Bool isLast();     // Last chunk from the original enqueued data
endinterface

//
// MARSHALLER_N interface allows per-message specification of the number of
// chunks to send.  This may be useful when the actual amount of useful
// information in a t_DATA varies.
//
interface MARSHALLER_N#(t_FIFO_DATA, t_DATA);
    method Action enq(t_DATA inData,
                      MARSHALLER_NUM_CHUNKS#(t_FIFO_DATA, t_DATA) numChunks)
        provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
                  Bits#(t_DATA, t_DATA_SZ));

    method Action deq();
    method t_FIFO_DATA first();
    method Bool notFull();
    method Bool notEmpty();
    method Bool isLast();     // Last chunk from the original enqueued data
endinterface

interface DEMARSHALLER#(type t_FIFO_DATA, type t_DATA);
    method Action enq(t_FIFO_DATA fifoData);
    method Action deq();
    method t_DATA first();
    method Bool notFull();
    method Bool notEmpty();
endinterface


// some typeclass/conversion definitions

instance ToPut#(DEMARSHALLER#(fifo_type, data_type), fifo_type);
    function Put#(fifo_type) toPut(DEMARSHALLER#(fifo_type, data_type) demarshaller);
        Put#(fifo_type) f = interface Put#(fifo_type);
                                method Action put(fifo_type data);
                                    demarshaller.enq(data);
                                endmethod
                            endinterface;
        return f;
    endfunction
endinstance

instance ToGet#(DEMARSHALLER#(fifo_type, data_type), data_type);
    function Get#(data_type) toGet(DEMARSHALLER#(fifo_type, data_type) demarshaller);
        Get#(data_type) f = interface Get#(data_type);
                                 method ActionValue#(data_type) get();
                                     demarshaller.deq;
                                     return demarshaller.first;
                                 endmethod
                             endinterface;
        return f;
    endfunction
endinstance

instance ToPut#(MARSHALLER#(fifo_type, data_type), data_type);
    function Put#(data_type) toPut(MARSHALLER#(fifo_type, data_type) marshaller);
        Put#(data_type) f = interface Put#(data_type);
                                method Action put(data_type data);
                                    marshaller.enq(data);
                                endmethod
                            endinterface;
        return f;
    endfunction
endinstance

instance ToGet#(MARSHALLER#(fifo_type, data_type), fifo_type);
    function Get#(fifo_type) toGet(MARSHALLER#(fifo_type, data_type) marshaller);
        Get#(fifo_type) f = interface Get#(fifo_type);
                                method ActionValue#(fifo_type) get();
                                    marshaller.deq;
                                    return marshaller.first;
                                endmethod
                            endinterface;
        return f;
    endfunction
endinstance




//
// mkSimpleMarshaller --
//     Transmit t_DATA in a stream of smaller, t_FIFO_DATA, messages.
//     Send the low chunk first.
//
module mkSimpleMarshaller
    // Interface:
        (MARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA)));

    MARSHALLER_N#(t_FIFO_DATA, t_DATA) m <- mkSimpleMarshallerN(True);

    method Action enq(t_DATA inData) = m.enq(inData, fromInteger(valueOf(n)));
    method Action deq() = m.deq;
    method t_FIFO_DATA first() = m.first;
    method Bool notFull() = m.notFull;
    method Bool notEmpty() = m.notEmpty;
    method Bool isLast() = m.isLast;

endmodule


//
// mkSimpleMarshallerHighToLow --
//     Transmit t_DATA in a stream of smaller, t_FIFO_DATA, messages.
//     Send the high chunk first.
//
module mkSimpleMarshallerHighToLow
    // Interface:
        (MARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA)));

    MARSHALLER_N#(t_FIFO_DATA, t_DATA) m <- mkSimpleMarshallerN(False);

    method Action enq(t_DATA inData) = m.enq(inData, fromInteger(valueOf(n)));
    method Action deq() = m.deq;
    method t_FIFO_DATA first() = m.first;
    method Bool notFull() = m.notFull;
    method Bool notEmpty() = m.notEmpty;
    method Bool isLast() = m.isLast;

endmodule


module mkSimpleMarshallerN#(Bool lowFirst)
    // Interface:
        (MARSHALLER_N#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA)));

    Reg#(Vector#(TSub#(n, 1), t_FIFO_DATA)) buffer <- mkRegU();
    Reg#(MARSHALLER_NUM_CHUNKS#(t_FIFO_DATA, t_DATA)) count <- mkReg(0);
    Reg#(Bool) empty <- mkReg(True);

    RWire#(Tuple2#(Vector#(MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA), t_FIFO_DATA),
                   MARSHALLER_NUM_CHUNKS#(t_FIFO_DATA, t_DATA))) incomingData <- mkRWire();
    FIFOF#(Tuple2#(t_FIFO_DATA, Bool)) outQ <- mkUGLFIFOF();


    //
    // nextChunk --
    //     Given some state emit the next chunk and update local state.
    //     The input state is either a new message or the internal
    //     state of a partially transmitted message.
    //
    function Action nextChunk(Vector#(n, t_FIFO_DATA) inData,
                              MARSHALLER_NUM_CHUNKS#(t_FIFO_DATA, t_DATA) nChunks);
    action
        Bool will_be_empty = (nChunks == 1);

        // Send the chunk and whether it is the last in the full message.
        outQ.enq(tuple2(inData[0], will_be_empty));

        buffer <= take(shiftInAtN(inData, ?));
        empty <= will_be_empty;
        count <= nChunks - 1;
    endaction
    endfunction


    //
    // Consume incoming full-size messages.  Uses a rule instead of embedding
    // in the enq() method to avoid Bluespec scheduler warnings.
    //
    (* fire_when_enabled, no_implicit_conditions *)
    rule incoming (empty &&& incomingData.wget() matches tagged Valid .d);
        match {.in_data, .num_chunks} = d;
        nextChunk(in_data, num_chunks);
    endrule


    //
    // Send out marshalled chunks.
    //
    rule marshaller (! empty && outQ.notFull);
        nextChunk(append(buffer, ?), count);
    endrule


    method Action enq(t_DATA inData,
                      MARSHALLER_NUM_CHUNKS#(t_FIFO_DATA, t_DATA) numChunks) if (empty && outQ.notFull);

        Vector#(MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA),
                t_FIFO_DATA) d = toChunks(inData);

        if (! lowFirst)
        begin
            d = reverse(d);
        end
    
        incomingData.wset(tuple2(d, numChunks));
    endmethod

    method Action deq() if (outQ.notEmpty);
        outQ.deq();
    endmethod

    method t_FIFO_DATA first() if (outQ.notEmpty);
        return tpl_1(outQ.first());
    endmethod

    method Bool notFull() = (empty && outQ.notFull);
    method Bool notEmpty() = outQ.notEmpty;

    method Bool isLast() if (outQ.notEmpty);
        return tpl_2(outQ.first());
    endmethod
endmodule


//
// mkSimpleDemarshallerBoth --
//     Basic demarshaller that maps a fixed size number of marshalled messages
//     back to an original type. Parameterized to handle either choice of 
//     marshaller endianess.
//
module mkSimpleDemarshallerBoth#(Bool highToLow)
    // Interface:
        (DEMARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA)));

    if (valueOf(n) <= 1)
    begin
        //
        // Trivial case where the marshalling container is at least as large
        // as the data.
        //

        FIFOF#(t_DATA) msgQ <- mkFIFOF();

        method Action enq(t_FIFO_DATA dat) = msgQ.enq(unpack(truncateNP(pack(dat))));
        method Action deq() = msgQ.deq;
        method t_DATA first() = msgQ.first;
        method Bool notFull() = msgQ.notFull;
        method Bool notEmpty() = msgQ.notEmpty;
    end
    else
    begin
        //
        // More interesting case: message is marshalled in multiple chunks.
        //

        // In order to avoid a pipeline bubble with a stream of multiple
        // messages the element in slot 0 is stored in a FIFO.  The rest
        // is stored in a register (buffer).
        FIFOF#(t_FIFO_DATA) entry0Q <- mkUGLFIFOF();
        Reg#(Vector#(TSub#(n, 1), t_FIFO_DATA)) buffer <- mkRegU();

        Reg#(Bit#(TLog#(n))) count <- mkReg(0);

        //
        // Full logic implemented as a rule to keep the scheduler happy
        //
        Reg#(Bool) full <- mkReg(False);
        PulseWire enqComplete <- mkPulseWire();
        PulseWire deqComplete <- mkPulseWire();

        (* fire_when_enabled, no_implicit_conditions *)
        rule updateFull (True);
            // - Set full when a full set of enqs are complete
            // - Clear full when deq happens
            // - Preserve full otherwise
            // deqComplete and enqComplete will never both be set.
            full <= unpack(pack(full) ^ pack(deqComplete)) || enqComplete;
        endrule


        method Action enq(t_FIFO_DATA dat) if (! full || entry0Q.notFull);
            if (count == 0)
            begin
                entry0Q.enq(dat);
            end
            else
            begin
                buffer <= shiftInAtN(buffer, dat);
            end

            let is_last = (count == fromInteger(valueof(TSub#(n, 1))));
            if (is_last)
            begin
                enqComplete.send();
            end

            count <= (is_last ? 0 : count + 1);
        endmethod

        method Action deq() if (full);
            entry0Q.deq();
            deqComplete.send();
        endmethod

        method t_DATA first() if (full);
            // Return an entire demarshalled message.
            t_DATA result = unpack(truncateNP({ pack(buffer), pack(entry0Q.first) })); 
            if(highToLow)
            begin
                result = unpack(truncateNP({pack(entry0Q.first), pack(reverse(buffer))})); 
            end
            return result;
        endmethod

        method Bool notFull() = (! full || entry0Q.notFull);
        method Bool notEmpty() = full;
    end
endmodule

//
// mkSimpleDemarshaller--
//     Basic demarshaller that maps a fixed size number of marshalled messages
//     back to an original type. Low-to-High endianess.
//
module mkSimpleDemarshaller
    // Interface:
        (DEMARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA)));
    let m <- mkSimpleDemarshallerBoth(False);
    return m;
endmodule


//
// mkSimpleDemarshallerHighToLow--
//     Basic demarshaller that maps a fixed size number of marshalled messages
//     back to an original type. High-to-low endianess.
//
module mkSimpleDemarshallerHighToLow
    // Interface:
        (DEMARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA)));
    let m <- mkSimpleDemarshallerBoth(True);
    return m;
endmodule


//
// mkSimpleDemarshallerN --
//     Demarshall a stream back to an original type.
//
//     The msgChunks function must compute the number of chunks for each
//     marshalled message based only on the first chunk received.  The
//     unnecessarily large return type of msgChunks is to avoid a dependence
//     loop for clients of mkSimpleDemarshallerN that need to add extra
//     state to a marshalled message in order to compute that message's
//     size.  The state adds more bits to the marshalled message, potentially
//     increasing the number of chunks in the encoded message.  We avoid
//     the loop by making the data type larger than needed.  This will
//     not affect generated hardware, as the true size will be truncated.
//
module mkSimpleDemarshallerN#(function Bit#(t_FIFO_DATA_SZ) msgChunks(t_FIFO_DATA head))
    // Interface:
        (DEMARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA)),
              Alias#(MARSHALLER_NUM_CHUNKS#(t_FIFO_DATA, t_DATA), t_NUM_CHUNKS),
              Bits#(t_NUM_CHUNKS, t_NUM_CHUNKS_SZ));

    if (valueOf(n) <= 1)
    begin
        //
        // Trivial case where the marshalling container is at least as large
        // as the data.
        //

        FIFOF#(t_DATA) msgQ <- mkFIFOF();

        method Action enq(t_FIFO_DATA dat) = msgQ.enq(unpack(truncateNP(pack(dat))));
        method Action deq() = msgQ.deq;
        method t_DATA first() = msgQ.first;
        method Bool notFull() = msgQ.notFull;
        method Bool notEmpty() = msgQ.notEmpty;
    end
    else if (valueOf(t_NUM_CHUNKS_SZ) > valueOf(t_FIFO_DATA_SZ))
    begin
        error("Demarshaller configuration error: chunk size too small to encode length in one chunk (" +
              integerToString(valueOf(t_NUM_CHUNKS_SZ)) + " vs. " +
              integerToString(valueOf(t_FIFO_DATA_SZ)) + ")");
        return ?;
    end
    else
    begin
        //
        // More interesting case: message is marshalled in multiple chunks.
        //

        // In order to avoid a pipeline bubble with a stream of multiple
        // messages the element in slot 0 is stored in a FIFO.  The rest
        // is stored in a register (buffer).
        FIFOF#(t_FIFO_DATA) entry0Q <- mkUGLFIFOF();
        Reg#(Vector#(TSub#(n, 1), t_FIFO_DATA)) buffer <- mkRegU();

        Reg#(t_NUM_CHUNKS) n_chunks_remaining <- mkReg(0);

        Reg#(Bool) skipChunks <- mkReg(False);
        Reg#(t_NUM_CHUNKS) n_chunks_skipped <- mkReg(0);
        // Avoid a scheduling warning between enq() method and handleUnsentChunks
        // with this hack.
        PulseWire schedCtrl <- mkPulseWire();

        //
        // Full logic implemented as a rule to keep the scheduler happy
        //
        Reg#(Bool) full <- mkReg(False);
        PulseWire enqComplete <- mkPulseWire();
        PulseWire deqComplete <- mkPulseWire();

        (* fire_when_enabled, no_implicit_conditions *)
        rule updateFull (True);
            // - Set full when a full set of enqs are complete
            // - Clear full when deq happens
            // - Preserve full otherwise
            // deqComplete and enqComplete will never both be set.
            full <= unpack(pack(full) ^ pack(deqComplete)) || enqComplete;
        endrule


        //
        // handleUnsentChunks --
        //     When the marshaller sends a fraction of the full message,
        //     the receive buffer holds the data in the wrong location.
        //     To avoid building a full MUX we use the same logic as normal
        //     data, adding bubble cycles to the receiver equal to the number
        //     of unsent chunks.
        //
        //     This remains useful in some cases:
        //       - The case of sending only 1 chunk remains optimized without
        //         delay slots because of special handling in the enq() method.
        //       - When multiple marshalled data streams share a single
        //         physical resource (e.g. an inter-FPGA link), reducing the
        //         traffic improves throughput even with this delay.
        //
        rule handleUnsentChunks ((n_chunks_skipped != 0) && skipChunks && ! schedCtrl);
            buffer <= shiftInAtN(buffer, ?);

            if (n_chunks_skipped == 1)
            begin
                // Last chunk in message
                enqComplete.send();
                skipChunks <= False;
            end

            n_chunks_skipped <= n_chunks_skipped - 1;
        endrule


        method Action enq(t_FIFO_DATA dat) if ((! full || entry0Q.notFull) && ! skipChunks);
            // Dummy dependence to avoid scheduling warning with handleUnsentChunks
            schedCtrl.send();

            t_NUM_CHUNKS cur_chunks_remaining = n_chunks_remaining;
            let cur_chunks_skipped = n_chunks_skipped;

            if (n_chunks_remaining == 0)
            begin
                // First chunk in a new message
                entry0Q.enq(dat);

                // msgChunks computes the total number of chunks in the encoded
                // message.
                cur_chunks_remaining = truncateNP(msgChunks(dat));

                // Compute the number of chunks that won't be sent, given the
                // maximum size of the message.  Sending only one chunk is a
                // special case since the first chunk is stored in entry0Q.
                cur_chunks_skipped = (cur_chunks_remaining == 1) ?
                                         0 :
                                         fromInteger(valueOf(n)) - cur_chunks_remaining;
                n_chunks_skipped <= cur_chunks_skipped;
            end
            else
            begin
                // Continue with current message
                buffer <= shiftInAtN(buffer, dat);
            end

            if (cur_chunks_remaining == 1)
            begin
                // Last chunk in message
                if (cur_chunks_skipped == 0)
                    enqComplete.send();
                else
                    skipChunks <= True;
            end

            n_chunks_remaining <= cur_chunks_remaining - 1;
        endmethod

        method Action deq() if (full);
            entry0Q.deq();
            deqComplete.send();
        endmethod

        method t_DATA first() if (full);
            // Return an entire demarshalled message.
            return unpack(truncateNP({ pack(buffer), pack(entry0Q.first) }));
        endmethod

        method Bool notFull() = (! full || entry0Q.notFull);
        method Bool notEmpty() = full;
    end
endmodule
