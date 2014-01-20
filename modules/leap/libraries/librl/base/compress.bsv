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
// run-length encoding.  Given an input t_DATA type, an instance of
// Compress provides the t_ENC_DATA encoded data.
//
// By convention, t_ENC_DATA is a tagged union.  The multi-FPGA router
// generator is capable of converting these tagged unions into multi-
// channel, variable size messages.
//
typeclass Compress#(type t_DATA, type t_ENC_DATA, type t_MODULE)
    dependencies ((t_DATA, t_MODULE) determines t_ENC_DATA);

    // Encode the original data into compressed form.
    module [t_MODULE] mkCompressor (COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA));

    // Restore original data given a compressed value.
    module [t_MODULE] mkDecompressor (COMPRESSION_DECODER#(t_DATA, t_ENC_DATA));
endtypeclass


//
// The interface for a compressor.
//
interface COMPRESSION_ENCODER#(type t_DATA, type t_ENC_DATA);
    method Action enq(t_DATA val);
    method Bool notFull();

    method t_ENC_DATA first();
    method Action deq();
    method Bool notEmpty();
endinterface

//
// The interface for a decompressor.
//
interface COMPRESSION_DECODER#(type t_DATA, type t_ENC_DATA);
    method Action enq(t_ENC_DATA cval);
    method Bool notFull();

    method t_DATA first();
    method Action deq();
    method Bool notEmpty();
endinterface


// ========================================================================
//
//   Convert encoded data to transmittable chunks.
//
// ========================================================================

//
// The standard t_ENC_DATA type is a tagged union.  The multi-FPGA router
// generator is capable of decomposing tagged unions into multi-channel
// messages, sending only the channels needed for a given tag.
//
// To perform similar compression directly within Bluespec more information
// is required.  The CompressionChunks typeclass maps a t_ENC_DATA tagged
// union into an HList.  A sender/receiver pair may take advantage of these
// chunks to optimize communication.  For example, individual soft
// connections may be allocated for each chunk.
//
typeclass CompressionChunks#(type t_ENC_DATA,
                             type t_ENC_CHUNKS)
    provisos (HList#(t_ENC_CHUNKS))
    dependencies (t_ENC_DATA determines t_ENC_CHUNKS);

    // Convert encoded data to chunks
    function t_ENC_CHUNKS encDataToChunks(t_ENC_DATA data);

    // Mask of chunks containing valid data
    function COMPRESSION_CHUNKS_MASK#(t_ENC_DATA) encDataToChunksMask(t_ENC_DATA data);


    // Restore encoded data from chunks
    function t_ENC_DATA chunksToEncData(t_ENC_CHUNKS chunks);

    // Return a mask of the chunks that must be read in order to determine
    // the true chunk mask for a message.  The mask returned here most likely
    // indicates the chunk with the tag.
    function COMPRESSION_CHUNKS_MASK#(t_ENC_DATA) decodeRequiredChunksMask();

    // Given the read value from set of chunks from decodeRequiredChunksMask(),
    // return a mask of chunks that must be read to decode the value.  Chunks
    // passed to the function that are not in decodeRequiredChunksMask() are
    // permitted to have undefined values.
    function COMPRESSION_CHUNKS_MASK#(t_ENC_DATA) chunksToEncDataMask(t_ENC_CHUNKS key);
endtypeclass


typedef List#(Bool) COMPRESSION_CHUNKS_MASK#(type t_ENC_DATA);


//
// CompressionChunksBits --
//     Compute the size of an encoded message.  t_ENC_CHUNKS_SZ is the
//     full size of all chunks in t_ENC_CHUNKS, combined.
//
typeclass CompressionChunksBits#(type t_ENC_CHUNKS, numeric type t_ENC_CHUNKS_SZ)
    dependencies (t_ENC_CHUNKS determines t_ENC_CHUNKS_SZ);

    // Return the sum of the sizes of all valid chunks in a given message.
    function Integer validChunksSize(t_ENC_CHUNKS msg, List#(Bool) validChunks);

    // Return the size of a message assuming the sender is obligated to
    // send all chunks to the right of the first active chunk.  "Right" means
    // lower bit positions and later in the chunks HList.  A serialized
    // transmission channel, such as a compressing marshaller, may use
    // this method.  Because of rMsgSize, CompressionChunks instances should
    // arrange chunks so frequently sent values are at the end of the
    // chunks list.
    function Integer rMsgSize(t_ENC_CHUNKS msg, List#(Bool) validChunks);
endtypeclass

instance CompressionChunksBits#(HNil, 0);
    function validChunksSize(msg, validChunks) = 0;
    function rMsgSize(msg, validChunks) = 0;
endinstance

// Terminal instance
instance CompressionChunksBits#(HCons#(t_HEAD, HNil), t_HEAD_SZ)
    provisos (Bits#(t_HEAD, t_HEAD_SZ));

    function validChunksSize(msg, validChunks);
        return List::head(validChunks) ? valueOf(t_HEAD_SZ) : 0;
    endfunction

    function rMsgSize(msg, validChunks);
        return List::head(validChunks) ? valueOf(t_HEAD_SZ) : 0;
    endfunction
endinstance

instance CompressionChunksBits#(HCons#(t_HEAD, t_TAIL), t_SZ)
    provisos (CompressionChunksBits#(t_TAIL, t_TAIL_SZ),
              Bits#(t_HEAD, t_HEAD_SZ),
              Add#(t_HEAD_SZ, t_TAIL_SZ, t_SZ));

    function validChunksSize(msg, validChunks);
        return validChunksSize(hTail(msg), List::tail(validChunks)) +
               (List::head(validChunks) ? valueOf(t_HEAD_SZ) : 0);
    endfunction

    function rMsgSize(msg, validChunks);
        return List::head(validChunks) ? valueOf(t_SZ) :
                                         rMsgSize(hTail(msg), List::tail(validChunks));
    endfunction
endinstance


//
// CompressionMapping --
//     A helper typeclass to recursively walk a t_ENC_CHUNKS HList of encoded
//     chunks and map them to a set of communication channels, such as
//     soft connections.
//
typeclass CompressionMapping#(type t_ENC_CHUNKS, type t_CHAN, type t_MODULE);
    module [t_MODULE] mkCompressedChannel#(t_ENC_CHUNKS map,
                                           String name,
                                           Integer depth) (t_CHAN);
endtypeclass


// Base case for a recursize parsing of a t_ENC_CHUNKS HList.
instance CompressionMapping#(HList::HNil, t_CHAN, t_MODULE)
    provisos (IsModule#(t_MODULE, m__));
    module [t_MODULE] mkCompressedChannel#(HList::HNil map,
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

instance ToGet#(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA), t_ENC_DATA);
    function Get#(t_ENC_DATA) toGet(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) recv);
        let get = interface Get;
                      method ActionValue#(t_ENC_DATA) get();
                          recv.deq;
                          return recv.first; 
                      endmethod
                  endinterface; 
        return get;
    endfunction
endinstance

instance Connectable#(Put#(t_DATA), COMPRESSION_DECODER#(t_DATA, t_ENC_DATA));
    module mkConnection#(Put#(t_DATA) client,
                         COMPRESSION_DECODER#(t_DATA, t_ENC_DATA) server) (Empty);
        rule connect;
            server.deq();
            client.put(server.first());
        endrule
    endmodule
endinstance

instance Connectable#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA), Put#(t_DATA));
    module mkConnection#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA) server,
                         Put#(t_DATA) client) (Empty);
        rule connect;
            server.deq();
            client.put(server.first());
        endrule
    endmodule
endinstance

instance ToGet#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA), t_DATA);
    function Get#(t_DATA) toGet(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA) recv);
        let get = interface Get;
                      method ActionValue#(t_DATA) get();
                          recv.deq;
                          return recv.first; 
                      endmethod
                  endinterface;  
        return get;
    endfunction
endinstance

instance ToPut#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA), t_ENC_DATA);
    function Put#(t_ENC_DATA) toPut(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA) send);
        let put = interface Put;
                      method Action put(t_ENC_DATA value);
                          send.enq(value);
                      endmethod
                  endinterface; 
        return put; 
    endfunction
endinstance


// ========================================================================
//
//   Compressor for Maybe#() types.
//
// ========================================================================

//
// Maybe#() is already a tagged union, so technically no compressor is
// required.  This typeclass merely guarantees that Maybe#() is a member
// of Compress.
//
instance Compress#(// Original type
                   Maybe#(t_DATA),
                   // Compressed container (maximum size)
                   Maybe#(t_DATA),
                   t_MODULE)
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Alias#(Maybe#(t_DATA), t_ENC_DATA),
              IsModule#(t_MODULE, m__));

    module [t_MODULE] mkCompressor
        // Interface:
        (COMPRESSION_ENCODER#(Maybe#(t_DATA), t_ENC_DATA));

        FIFOF#(Maybe#(t_DATA)) inQ <- mkBypassFIFOF();

        method enq(val) = inQ.enq(val);
        method deq() = inQ.deq();

        method first() = inQ.first();
        method notFull() = inQ.notFull();
        method notEmpty() = inQ.notEmpty();
    endmodule

    module [t_MODULE] mkDecompressor
        // Interface:
        (COMPRESSION_DECODER#(Maybe#(t_DATA), t_ENC_DATA));

        FIFOF#(t_ENC_DATA) inQ <- mkBypassFIFOF();

        method Action enq(cval) = inQ.enq(cval);
        method Action deq() = inQ.deq();

        method first() = inQ.first();
        method Bool notFull() = inQ.notFull();
        method Bool notEmpty() = inQ.notEmpty();
    endmodule
endinstance


//
// Chunker for Maybe#() tagged unions.  Rearrange the tag so it is in the low
// bits, making the chunks more suitable for passing through a compressing
// marshaller.
//
instance CompressionChunks#(Maybe#(t_MSG),
                            HList2#(t_MSG, Bool))
    provisos (Alias#(t_ENC_DATA, t_MSG),
              Alias#(t_ENC_CHUNKS, HList2#(t_MSG, Bool)),
              HList#(t_ENC_CHUNKS));

    // Map Maybe#() to chunks
    function encDataToChunks(data) = hList2(validValue(data), isValid(data));

    // Which chunks are valid?
    function encDataToChunksMask(data) = list(isValid(data), True);


    // Map chunks to Maybe#()
    function chunksToEncData(chunks);
        return hLast(chunks) ? tagged Valid hHead(chunks) :
                               tagged Invalid;
    endfunction

    // The tag chunk must be read to decode a chunk.
    function decodeRequiredChunksMask() = list(False, True);

    // Which chunks are valid?  The Bool chunk is always valid and the message
    // chunk is valid when the Bool chunk is True.
    function chunksToEncDataMask(key) = list(hLast(key), True);
endinstance

// ========================================================================
//
//   Unbalanced Maybe - if the tagged Invalid leg is even remotely common, 
//   run-length encoding is a win.  However, we distinguish this type from 
//   Maybe for the time being to give the programmer some level of control.
//
// ========================================================================

typedef union tagged {
    void   UnbalancedInvalid;
    t_DATA UnbalancedValid;
}
UNBALANCED_MAYBE#(type t_DATA)
    deriving (Bits,Eq);

function Maybe#(t_DATA) unbalancedToMaybe(UNBALANCED_MAYBE#(t_DATA) d);
    return (d matches tagged UnbalancedValid .v ? tagged Valid v :
                                                  tagged Invalid);
endfunction

function UNBALANCED_MAYBE#(t_DATA) maybeToUnbalanced(Maybe#(t_DATA) d);
    return (d matches tagged Valid .v ? tagged UnbalancedValid v :
                                        tagged UnbalancedInvalid);
endfunction

typedef union tagged {
    Bit#(3)   UnbalancedInvalid;
    t_DATA    UnbalancedValid;
}
COMPRESSED_UNBALANCED_MAYBE#(type t_DATA)
    deriving (Bits,Eq);

instance Compress#(// Original type
                   UNBALANCED_MAYBE#(t_DATA),
                   // Compressed container (maximum size)
                   COMPRESSED_UNBALANCED_MAYBE#(t_DATA),
                   t_MODULE)
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Alias#(COMPRESSED_UNBALANCED_MAYBE#(t_DATA), t_ENC_DATA),
              IsModule#(t_MODULE, m__));

    module mkCompressor (COMPRESSION_ENCODER#(UNBALANCED_MAYBE#(t_DATA), 
                                              COMPRESSED_UNBALANCED_MAYBE#(t_DATA)));
        FIFOF#(UNBALANCED_MAYBE#(t_DATA)) inQ <- mkBypassFIFOF();
        FIFOF#(COMPRESSED_UNBALANCED_MAYBE#(t_DATA)) outQ <- mkBypassFIFOF();
	Reg#(Bit#(3)) invalidCount <- mkReg(0);
	Reg#(Bit#(3)) flushCount <- mkReg(0);

	rule tickFlush;
	    flushCount <= flushCount + 1;
        endrule

	rule flush (flushCount == maxBound && invalidCount > 0 && ! inQ.notEmpty);
            outQ.enq(tagged UnbalancedInvalid invalidCount);
            invalidCount <= 0;
        endrule

        rule transfer (inQ.notEmpty);
            let val = inQ.first();

	    Bool send;
	    COMPRESSED_UNBALANCED_MAYBE#(t_DATA) compressedToken;

	    if (inQ.first matches tagged UnbalancedValid .payload)
            begin
                // New valid message to send.  Are there Invalids to send first?
                if (invalidCount == 0)
                begin
                    // No.  Send message.
		    compressedToken = tagged UnbalancedValid payload;
                    inQ.deq();
                end	
                else
                begin
                    // Have invalids to send first.
		    compressedToken = tagged UnbalancedInvalid invalidCount;
                end	

                send = True;
            end
            else 
            begin
                // New invalid.
	  	inQ.deq;
                
                // Send only if the counter will now be full.  Otherwise,
                // just collect invalids in the counter.
                send = (invalidCount == maxBound - 1);
                compressedToken = tagged UnbalancedInvalid maxBound;
            end

            if (send)
            begin 
	        flushCount <= 0;
                outQ.enq(compressedToken);

                // Either sending invalids or a message.  Either way, the
                // count is now zero.
		invalidCount <= 0;
            end
            else
            begin
                // Must be an invalid that is being collected in the counter.
	        invalidCount <= invalidCount + 1;
            end
        endrule

        method enq(val) = inQ.enq(val);
        method deq() = outQ.deq();

	method first = outQ.first();
        method notFull() = inQ.notFull();
        method notEmpty() = outQ.notEmpty();
    endmodule

    module mkDecompressor (COMPRESSION_DECODER#(UNBALANCED_MAYBE#(t_DATA), 
                                                COMPRESSED_UNBALANCED_MAYBE#(t_DATA)));
        FIFOF#(COMPRESSED_UNBALANCED_MAYBE#(t_DATA)) inQ <- mkBypassFIFOF();
        FIFOF#(UNBALANCED_MAYBE#(t_DATA)) outQ <- mkBypassFIFOF();
	Reg#(Bit#(3)) invalidCount <- mkReg(0);

	rule transferInvalid (invalidCount != 0);
	    invalidCount <= invalidCount - 1;
            outQ.enq(tagged UnbalancedInvalid);
	endrule

        rule transfer (invalidCount == 0);
	    inQ.deq();

            if (inQ.first matches tagged UnbalancedValid .data)
	    begin
                outQ.enq(tagged UnbalancedValid data);
	    end
            else if (inQ.first matches tagged UnbalancedInvalid .invalids)
	    begin
                outQ.enq(tagged UnbalancedInvalid);
                // Record remaining invalids from the compressed packet.
	        invalidCount <= invalids - 1;
            end
        endrule

        method Action enq(cval) = inQ.enq(cval);
        method Action deq() = outQ.deq();
	method first = outQ.first();
        method Bool notFull() = inQ.notFull();
        method Bool notEmpty() = inQ.notEmpty();
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
module [t_MODULE] mkCompressingMarshaller
    // Interface:
        (MARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Compress#(t_DATA, t_ENC_DATA, t_MODULE),
              CompressionChunks#(t_ENC_DATA, t_ENC_CHUNKS),
              CompressionChunksBits#(t_ENC_CHUNKS, t_ENC_CHUNKS_SZ),
              Bits#(t_ENC_CHUNKS, t_ENC_CHUNKS_SZ),
              Alias#(COMPRESSING_MARSHALLER_NUM_CHUNKS#(t_FIFO_DATA, Bit#(t_ENC_CHUNKS_SZ)), t_MSG_LEN),
              Bits#(t_MSG_LEN, t_MSG_LEN_SZ),
              IsModule#(t_MODULE, m__));

    // The message being transmitted is the combination of the original message
    // and the message's actual length (in t_FIFO_DATA chunks).
    MARSHALLER_N#(t_FIFO_DATA, Tuple2#(t_ENC_CHUNKS, t_MSG_LEN)) m <-
        mkSimpleMarshallerN(True);

    // The compressor
    COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) encoder <- mkCompressor();

    // Compute a message length in marshaller chunks given a length in bits.
    function t_MSG_LEN bitsToMarshallerChunks(Integer nBits);
        return fromInteger((valueOf(t_MSG_LEN_SZ) +
                            nBits +
                            valueOf(t_FIFO_DATA_SZ) - 1) / valueOf(t_FIFO_DATA_SZ));
    endfunction

    // Connect the encoder to the marshaller
    rule connect;
        let enc_data = encoder.first();
        encoder.deq();

        // Convert encoded tagged union to a list of chunks
        let enc_msg = encDataToChunks(enc_data);
        // Compute the size of the encoded message
        let enc_msg_sz = rMsgSize(enc_msg, encDataToChunksMask(enc_data));
        // Convert the size (bits) to marshaller chunks
        let mar_chunks = bitsToMarshallerChunks(enc_msg_sz);

        m.enq(tuple2(enc_msg, mar_chunks), truncateNP(mar_chunks));
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
module [t_MODULE] mkCompressingDemarshaller
    // Interface:
    (DEMARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Compress#(t_DATA, t_ENC_DATA, t_MODULE),
              CompressionChunks#(t_ENC_DATA, t_ENC_CHUNKS),
              CompressionChunksBits#(t_ENC_CHUNKS, t_ENC_CHUNKS_SZ),
              Bits#(t_ENC_CHUNKS, t_ENC_CHUNKS_SZ),
              Alias#(COMPRESSING_MARSHALLER_NUM_CHUNKS#(t_FIFO_DATA, Bit#(t_ENC_CHUNKS_SZ)), t_MSG_LEN),
              Bits#(t_MSG_LEN, t_MSG_LEN_SZ),
              IsModule#(t_MODULE, m__));

    // Compute the number of chunks actually transmitted for a message, given
    // the first chunk.  The demarshaller will automatically truncate the
    // returned value to the minimum size for representing the length, so
    // simply returning the entire chunk with the count in the LSBs is fine.
    function compressedLen(t_FIFO_DATA chunk0) = pack(chunk0);

    DEMARSHALLER#(t_FIFO_DATA, Tuple2#(t_ENC_CHUNKS, t_MSG_LEN)) dem <-
        mkSimpleDemarshallerN(compressedLen);

    // The decompressor
    COMPRESSION_DECODER#(t_DATA, t_ENC_DATA) decoder <- mkDecompressor();

    // Connect the demarshaller to the decoder
    rule connect;
        let msg = chunksToEncData(tpl_1(dem.first()));
        dem.deq();

        decoder.enq(msg);
    endrule

    method Action enq(t_FIFO_DATA fifoData) = dem.enq(fifoData);
    method Bool notFull() = dem.notFull;
    method Action clear() = dem.clear;

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
