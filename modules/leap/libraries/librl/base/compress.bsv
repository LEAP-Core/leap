//
// Copyright (C) 2012 Intel Corporation
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

import List::*;
import SpecialFIFOs::*;
import GetPut::*;
import HList::*;

//
// Instances of the "Compress" typeclass provide modules for converting
// types to compressed form.  Modules may implement whatever compression is
// appropriate, ranging from simple optimization of Maybe#() to stateful
// run-length encoding.
//
// Given an input t_DATA type, an instance of Compress provides the t_ENC_DATA
// encoded data and a minimal type on the receiver side used to determine how
// many bits are needed to decode a message (t_DECODER).
//
// The standard t_ENC_DATA type is an HList describing the positions
// and sizes of "fields" in the compressed data.  A sender/receiver
// pair may take advantage of these chunks to optimize communication.
// For example, individual soft connections may be allocated for each
// chunk.  Messages would always be sent on the lowest position chunk
// but may no message may be needed sometimes when compressed data has
// no information in a chunk.
//
// When t_ENC_DATA is an HList, the first entry corresponds to the highest
// bit position.  The last entry corresponds to the chunk starting at bit 0.
// t_DECODER is typically at most the size of the last chunk.  Note that
// LEAP provides an HLast typeclass for finding the last entry in an HList.
// It also provides HList instances of Bits, making it easy to flatten
// and restore HLists from Bit types.  (See bluespec-def.bsv)
//
typeclass Compress#(type t_DATA,
                    type t_ENC_DATA,
                    type t_DECODER)
    dependencies (t_DATA determines (t_ENC_DATA, t_DECODER));

    // Encode the original data into compressed form.
    module mkCompressor (COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA));

    // Restore original data given a compressed value.
    module mkDecompressor (COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER));
endtypeclass


//
// CompressMC is the same as Compress, but a module type is specified to
// support module contexts and connected modules.
//
typeclass CompressMC#(type t_DATA,
                      type t_ENC_DATA,
                      type t_DECODER,
                      type t_MODULE)
    dependencies ((t_DATA, t_MODULE) determines (t_ENC_DATA, t_DECODER));

    // Encode the original data into compressed form.
    module [t_MODULE] mkCompressorMC (COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA));

    // Restore original data given a compressed value.
    module [t_MODULE] mkDecompressorMC (COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER));
endtypeclass


//
// The interface for a compressor.
//
interface COMPRESSION_ENCODER#(type t_DATA, type t_ENC_DATA);
    method Action enq(t_DATA val);
    method Action deq();
    // The first entry is the encoded data.  The second is the length
    // of the encoded data in bits, starting with the low bit.
    method Tuple2#(t_ENC_DATA, Integer) first();
    method Bool notFull();
    method Bool notEmpty();
endinterface

//
// The interface for a decompressor.
//
interface COMPRESSION_DECODER#(type t_DATA, type t_ENC_DATA, type t_DECODER);
    method Action enq(t_ENC_DATA cval);
    method Action deq();
    method t_DATA first();
    method Bool notFull();
    method Bool notEmpty();

    // Return the number of bits of valid data in an encoded message, based
    // on the low bits of the message.  enq() requires the returned number of
    // bits to decode a message properly.
    method Integer numInBits(t_DECODER partialVal);
endinterface


//
// CompressionMapping --
//     Construct a set of I/O channels to carry compressed data, based
//     on the size hints in a t_ENC_DATA.
//
typeclass CompressionMapping#(type t_ENC_DATA, type t_CHAN);
    module mkCompressedChannel#(t_ENC_DATA map,
                                String name,
                                Integer depth) (t_CHAN);
endtypeclass

//
// CompressionMappingMC is the same as CompressionMapping, but a module type
// is specified to support module contexts and connected modules.
//
typeclass CompressionMappingMC#(type t_ENC_DATA, type t_CHAN, type t_MODULE);
    module [t_MODULE] mkCompressedChannelMC#(t_ENC_DATA map,
                                             String name,
                                             Integer depth) (t_CHAN);
endtypeclass


// Base case for a recursize parsing of a t_ENC_DATA HList.
instance CompressionMapping#(HList::HNil, t_CHAN);
    module mkCompressedChannel#(HList::HNil map,
                                String name,
                                Integer depth) (t_CHAN);
        return ?;
    endmodule
endinstance


// ========================================================================
//
//   Helper functions (GetPut).
//
// ========================================================================

instance Connectable#(Get#(t_DATA), COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA));
    module mkConnection#(Get#(t_DATA) client,
                         COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) server) (Empty);
        rule connect;
            let data <- client.get();
            server.enq(data);
        endrule
    endmodule
endinstance

instance Connectable#(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA), Get#(t_DATA));
    module mkConnection#(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) server,
                         Get#(t_DATA) client) (Empty);
        rule connect;
            let data <- client.get();
            server.enq(data);
        endrule
    endmodule
endinstance

instance ToPut#(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA), t_DATA);
    function Put#(t_DATA) toPut(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) send);
        let put = interface Put;
                      method Action put(t_DATA value);
                          send.enq(value);
                      endmethod
                  endinterface; 
        return put; 
    endfunction
endinstance

instance Connectable#(Put#(t_DATA), COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER));
    module mkConnection#(Put#(t_DATA) client,
                         COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER) server) (Empty);
        rule connect;
            server.deq();
            client.put(server.first());
        endrule
    endmodule
endinstance

instance Connectable#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER), Put#(t_DATA));
    module mkConnection#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER) server,
                         Put#(t_DATA) client) (Empty);
        rule connect;
            server.deq();
            client.put(server.first());
        endrule
    endmodule
endinstance

instance ToGet#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER), t_DATA);
    function Get#(t_DATA) toGet(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER) recv);
        let get = interface Get;
                      method ActionValue#(t_DATA) get();
                          recv.deq;
                          return recv.first; 
                      endmethod
                  endinterface;  
        return get;
    endfunction
endinstance


// ========================================================================
//
//   Compressor for Maybe#() types.
//
// ========================================================================

instance Compress#(// Original type
                   Maybe#(t_DATA),
                   // Compressed container (maximum size)
                   HList2#(t_DATA, Bool),
                   // Portion of container required to compute message size
                   Bool)
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Alias#(t_ENC_DATA, HList2#(t_DATA, Bool)),
              Bits#(t_ENC_DATA, t_ENC_DATA_SZ));

    module mkCompressor (COMPRESSION_ENCODER#(Maybe#(t_DATA), t_ENC_DATA));
        FIFOF#(Maybe#(t_DATA)) inQ <- mkBypassFIFOF();

        method enq(val) = inQ.enq(val);
        method deq() = inQ.deq();

        method first();
            let val = inQ.first();

            // Compute the compressed message length (in bits).
            Integer data_len = (isValid(val) ? valueOf(t_ENC_DATA_SZ) : 1);

            // The message is compressed by moving the tag to the low bit so it
            // will be next to the useful data.  The 2nd element in the returned
            // tuple is the compressed length.
            return tuple2(hList2(validValue(val), isValid(val)), data_len);
        endmethod

        method notFull() = inQ.notFull();
        method notEmpty() = inQ.notEmpty();
    endmodule

    module mkDecompressor (COMPRESSION_DECODER#(Maybe#(t_DATA), t_ENC_DATA, Bool));
        FIFOF#(t_ENC_DATA) inQ <- mkBypassFIFOF();

        method Action enq(cval) = inQ.enq(cval);
        method Action deq() = inQ.deq();

        method first();
            let cval = inQ.first();

            // Separate the tag and data
            Bool tag = hLast(cval);
            t_DATA data = hHead(cval);

            if (tag)
                return tagged Valid data;
            else
                return tagged Invalid;
        endmethod

        method Bool notFull() = inQ.notFull();
        method Bool notEmpty() = inQ.notEmpty();

        method Integer numInBits(tag);
            return tag ? valueOf(t_ENC_DATA_SZ) : 1;
        endmethod
    endmodule
endinstance


// ========================================================================
//
//   Compressing marshaller
//
// ========================================================================

//
// mkCompressingMarshaller --
//     Make a marshaller that accepts some input type and applies a compression
//     function to individual input messages before marshalling them through the
//     output type.
//
module mkCompressingMarshaller
    // Interface:
        (MARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Compress#(t_DATA, t_ENC_DATA, t_DECODER),
              Bits#(t_ENC_DATA, t_ENC_DATA_SZ),
              Alias#(COMPRESSING_MARSHALLER_NUM_CHUNKS#(t_FIFO_DATA, Bit#(t_ENC_DATA_SZ)), t_MSG_LEN),
              Bits#(t_MSG_LEN, t_MSG_LEN_SZ));

    // The message being transmitted is the combination of the original message
    // and the message's actual length (in t_FIFO_DATA chunks).
    MARSHALLER_N#(t_FIFO_DATA, Tuple2#(t_ENC_DATA, t_MSG_LEN)) m <-
        mkSimpleMarshallerN(True);

    // The compressor
    COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) encoder <- mkCompressor();

    // Compute a message length in chunks given a length in bits.
    function t_MSG_LEN bitsToChunks(Integer nBits);
        return fromInteger((valueOf(t_MSG_LEN_SZ) +
                            nBits +
                            valueOf(t_FIFO_DATA_SZ) - 1) / valueOf(t_FIFO_DATA_SZ));
    endfunction

    // Connect the encoder to the marshaller
    rule connect;
        match {.cval, .valid_bits} = encoder.first();
        encoder.deq();
        
        let chunks = bitsToChunks(valid_bits);
        m.enq(tuple2(cval, chunks), truncateNP(chunks));
    endrule

    method Action enq(t_DATA inData) = encoder.enq(inData);
    method Bool notFull() = encoder.notFull;

    method t_FIFO_DATA first() = m.first;
    method Action deq() = m.deq;
    method Bool notEmpty() = m.notEmpty;
    method Bool isLast() = m.isLast;
endmodule


//
// mkCompressingDemarshaller --
//     The receiving side of a mkCompressingMarshaller.
//
module mkCompressingDemarshaller
    // Interface:
        (DEMARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Compress#(t_DATA, t_ENC_DATA, t_DECODER),
              Bits#(t_ENC_DATA, t_ENC_DATA_SZ),
              Alias#(COMPRESSING_MARSHALLER_NUM_CHUNKS#(t_FIFO_DATA, Bit#(t_ENC_DATA_SZ)), t_MSG_LEN),
              Bits#(t_MSG_LEN, t_MSG_LEN_SZ));

    // Compute the number of chunks actually transmitted for a message, given
    // the first chunk.  The demarshaller will automatically truncate the
    // returned value to the minimum size for representing the length, so
    // simply returning the entire chunk with the count in the LSBs is fine.
    function compressedLen(t_FIFO_DATA chunk0) = pack(chunk0);

    DEMARSHALLER#(t_FIFO_DATA, Tuple2#(t_ENC_DATA, t_MSG_LEN)) dem <-
        mkSimpleDemarshallerN(compressedLen);

    // The decompressor
    COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER) decoder <- mkDecompressor();

    // Connect the demarshaller to the decoder
    rule connect;
        let v = tpl_1(dem.first());
        dem.deq();

        decoder.enq(v);
    endrule

    method Action enq(t_FIFO_DATA fifoData) = dem.enq(fifoData);
    method Bool notFull() = dem.notFull;

    method t_DATA first() = decoder.first;
    method Action deq() = decoder.deq;
    method Bool notEmpty() = decoder.notEmpty;
endmodule


// Chunk count passed in the message for a compressing marshaller.  Two is
// added to the length.  One to make the value the true number of chunks
// and one to leave space for the count itself to be stored in up to one chunk.
//
// One could make a case for using a 0 based counter so only 1 must be added,
// but that is more error prone and saves at most a bit.
typedef Bit#(TLog#(TAdd#(2, MARSHALLER_MSG_LEN#(t_FIFO_DATA, t_DATA))))
    COMPRESSING_MARSHALLER_NUM_CHUNKS#(type t_FIFO_DATA, type t_DATA);
