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

`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_connections_common.bsh"
`include "awb/provides/librl_bsv_base.bsh"

import GetPut::*;
import Connectable::*;
import HList::*;
import FIFO::*;
import FIFOF::*;

//
// Compressed soft connections.  Provide the illusion of a single soft
// connection using a base data type.  Internally, the base type is
// compressed and sent over multiple soft connections, transmitting
// each message over the minimum number of connections to preserve the
// value.
//
// See compress.bsv in LibRL.
//

//
// mkCompressedConnectionSend --
//     Same interface as a mkConnectionSend, but instantiates multiple
//     soft connections as appropriate for compression of t_MSG.
//
module [CONNECTED_MODULE] mkCompressedConnectionSend#(String name)
    // Interface:
    (CONNECTION_SEND#(t_MSG))
    provisos (Compress#(t_MSG, t_ENC_DATA, CONNECTED_MODULE),
              CompressionChunks#(t_ENC_DATA, t_ENC_CHUNKS),
              Alias#(COMPRESSION_CHUNKS_MASK#(t_ENC_DATA), t_CHUNKS_MASK),
              CompressionMapping#(t_ENC_CHUNKS,
                                  COMPRESSED_CONNECTION_SEND#(t_ENC_CHUNKS,
                                                              t_CHUNKS_MASK),
                                  CONNECTED_MODULE));

    // The encoder transforms input messages to a compressed stream
    COMPRESSION_ENCODER#(t_MSG, t_ENC_DATA) encoder <- mkCompressor();

    // Instantiate the set of sender soft connections
    t_ENC_CHUNKS map = ?;    
    COMPRESSED_CONNECTION_SEND#(t_ENC_CHUNKS, t_CHUNKS_MASK) con <-
        mkCompressedChannel(map, name, 0);

    // Connect the compressing encoder to the outbound soft connections
    mkConnection(encoder, con);

    method Action send(t_MSG data) = encoder.enq(data);
    method Bool notFull() = encoder.notFull();
endmodule


//
// mkCompressedConnection_Receive --
//     Same interface as a mkConnectionRecv, but for messages sent
//     by mkCompressedConnection_Send.
//
module [CONNECTED_MODULE] mkCompressedConnectionRecv#(String name)
    // Interface:
    (CONNECTION_RECV#(t_MSG))
    provisos (Compress#(t_MSG, t_ENC_DATA, CONNECTED_MODULE),
              CompressionChunks#(t_ENC_DATA, t_ENC_CHUNKS),
              Alias#(COMPRESSION_CHUNKS_MASK#(t_ENC_DATA), t_CHUNKS_MASK),
              CompressionMapping#(t_ENC_CHUNKS,
                                  COMPRESSED_CONNECTION_RECV#(t_ENC_CHUNKS,
                                                              t_CHUNKS_MASK),
                                  CONNECTED_MODULE));

    // The decoder transforms received messages to an output decompressed stream
    COMPRESSION_DECODER#(t_MSG, t_ENC_DATA) decoder <- mkDecompressor();

    // Instantiate the set of receiver soft connections
    t_ENC_CHUNKS map = ?;    
    COMPRESSED_CONNECTION_RECV#(t_ENC_CHUNKS, t_CHUNKS_MASK) con <-
        mkCompressedChannel(map, name, 0);

    // Connect the inbound soft connections to the input of the decoder
    mkConnection(con, decoder);

    method Action deq() = decoder.deq();
    method Bool notEmpty() = decoder.notEmpty();
    method t_MSG receive() = decoder.first();
endmodule


//
// Internal interfaces for multi-soft-connection compressed streams.  The
// modules with CONNECTION_SEND/RECV interfaces above communicate with the
// actual soft connections instantiated below through these interfaces.
//

interface COMPRESSED_CONNECTION_SEND#(type t_ENC_CHUNKS, type t_CHUNKS_MASK);
    method Action send(t_ENC_CHUNKS data, t_CHUNKS_MASK toChunks);
    method Bool notFull(t_CHUNKS_MASK toChunks);
endinterface

interface COMPRESSED_CONNECTION_RECV#(type t_ENC_CHUNKS, type t_CHUNKS_MASK);
    method Action deq(t_CHUNKS_MASK fromChunks);
    method Bool notEmpty(t_CHUNKS_MASK fromChunks);
    method t_ENC_CHUNKS receive(t_CHUNKS_MASK fromChunks);
endinterface


//
// Helper modules for connecting compressors to sets of compressed soft
// connections.
//

instance Connectable#(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA),
                      COMPRESSED_CONNECTION_SEND#(t_ENC_CHUNKS, t_CHUNKS_MASK))
    provisos (CompressionChunks#(t_ENC_DATA, t_ENC_CHUNKS),
              Alias#(COMPRESSION_CHUNKS_MASK#(t_ENC_DATA), t_CHUNKS_MASK));

    module mkConnection#(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) enc,
                         COMPRESSED_CONNECTION_SEND#(t_ENC_CHUNKS, t_CHUNKS_MASK) con)
    (Empty);

        rule connect;
            let cval = enc.first();
            enc.deq();
        
            con.send(encDataToChunks(cval), encDataToChunksMask(cval));
        endrule

    endmodule
endinstance

// Reverse argument order of above (same connection)
instance Connectable#(COMPRESSED_CONNECTION_SEND#(t_ENC_CHUNKS, t_CHUNKS_MASK),
                      COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA))
    provisos (CompressionChunks#(t_ENC_DATA, t_ENC_CHUNKS),
              Alias#(COMPRESSION_CHUNKS_MASK#(t_ENC_DATA), t_CHUNKS_MASK));

    module mkConnection#(COMPRESSED_CONNECTION_SEND#(t_ENC_CHUNKS, t_CHUNKS_MASK) con,
                         COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) enc)
    (Empty);

        let c <- mkConnection(enc, con);
        return c;

    endmodule
endinstance

instance Connectable#(COMPRESSED_CONNECTION_RECV#(t_ENC_CHUNKS, t_CHUNKS_MASK),
                      COMPRESSION_DECODER#(t_DATA, t_ENC_DATA))
    provisos (CompressionChunks#(t_ENC_DATA, t_ENC_CHUNKS),
              Alias#(COMPRESSION_CHUNKS_MASK#(t_ENC_DATA), t_CHUNKS_MASK));

    module mkConnection#(COMPRESSED_CONNECTION_RECV#(t_ENC_CHUNKS, t_CHUNKS_MASK) con,
                         COMPRESSION_DECODER#(t_DATA, t_ENC_DATA) dec)
    (Empty);

        rule connect;
            // Compute the number of input chunks for the current message.
            COMPRESSION_CHUNKS_MASK#(t_ENC_DATA) mask = decodeRequiredChunksMask();
            let key = con.receive(mask);
            COMPRESSION_CHUNKS_MASK#(t_ENC_DATA) in_chunks = chunksToEncDataMask(key);

            // Read all required chunks
            let cval = con.receive(in_chunks);
            con.deq(in_chunks);

            dec.enq(chunksToEncData(cval));
        endrule

    endmodule
endinstance

// Reverse argument order of above (same connection)
instance Connectable#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA),
                      COMPRESSED_CONNECTION_RECV#(t_ENC_CHUNKS, t_CHUNKS_MASK))
    provisos (CompressionChunks#(t_ENC_DATA, t_ENC_CHUNKS),
              Alias#(COMPRESSION_CHUNKS_MASK#(t_ENC_DATA), t_CHUNKS_MASK));

    module mkConnection#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA) dec,
                         COMPRESSED_CONNECTION_RECV#(t_ENC_CHUNKS, t_CHUNKS_MASK) con)
    (Empty);

        let c <- mkConnection(con, dec);

    endmodule
endinstance


//
// Instance of soft-connection based compression mapping that allocates
// a group of soft connections for a compressed sender's channel.
//
instance CompressionMapping#(HCons#(t_HEAD, t_REM),
                             COMPRESSED_CONNECTION_SEND#(HCons#(t_HEAD, t_REM), List#(Bool)),
                             CONNECTED_MODULE)
    provisos (Alias#(t_ENC_CHUNKS, HCons#(t_HEAD, t_REM)),
              Bits#(t_HEAD, t_HEAD_SZ),
              // Prepare to map subordinate chunks
              CompressionMapping#(t_REM,
                                  COMPRESSED_CONNECTION_SEND#(t_REM, List#(Bool)),
                                  CONNECTED_MODULE));

    //
    // mkCompressedSendChannel --
    //     Recursive instantiation of send connections for current and all
    //     subordinate compression chunks.
    //
    module [CONNECTED_MODULE] mkCompressedChannel#(t_ENC_CHUNKS map,
                                                   String name,
                                                   Integer depth)
        // Interface:
        (COMPRESSED_CONNECTION_SEND#(t_ENC_CHUNKS, List#(Bool)));

        // Allocate the subordinate chunks
        COMPRESSED_CONNECTION_SEND#(t_REM, List#(Bool)) subChunks <-
            mkCompressedChannel(hTail(map), name, depth + 1);

        // Allocate an actual soft connection for the current chunk
        CONNECTION_SEND#(t_HEAD) thisChunk;
        if (valueOf(t_HEAD_SZ) != 0)
            thisChunk <- mkConnectionSend(name + "_cmpmap" + integerToString(depth));
        else
            thisChunk <- mkConnectionSendDummy(name + "_cmpmap" + integerToString(depth));

        method Action send(data, toChunks);
            // Send to subordinate chunks
            subChunks.send(hTail(data), List::tail(toChunks));

            // Is there compressed data to be sent for the current chunk?
            if (List::head(toChunks))
            begin
                thisChunk.send(hHead(data));
            end
        endmethod

        // notFull for masked set of chunks
        method Bool notFull(toChunks) = (thisChunk.notFull || ! List::head(toChunks)) &&
                                        subChunks.notFull(List::tail(toChunks));
    endmodule
endinstance


//
// Special case of compressed send channel for the bit 0 position (the
// end of the HList).
//
instance CompressionMapping#(HCons#(t_HEAD, HNil),
                             COMPRESSED_CONNECTION_SEND#(HCons#(t_HEAD, HNil), List#(Bool)),
                             CONNECTED_MODULE)
    provisos (Alias#(t_ENC_CHUNKS, HCons#(t_HEAD, HNil)),
              Bits#(t_HEAD, t_HEAD_SZ));

    module [CONNECTED_MODULE] mkCompressedChannel#(t_ENC_CHUNKS map,
                                                   String name,
                                                   Integer depth)
        // Interface:
        (COMPRESSED_CONNECTION_SEND#(t_ENC_CHUNKS, List#(Bool)));

        // Allocate an actual soft connection for the current chunk
        CONNECTION_SEND#(t_HEAD) thisChunk;
        if (valueOf(t_HEAD_SZ) != 0)
            thisChunk <- mkConnectionSend(name + "_cmpmap" + integerToString(depth));
        else
            thisChunk <- mkConnectionSendDummy(name + "_cmpmap" + integerToString(depth));

        method Action send(data, toChunks);
            // Is there compressed data to be sent for the current chunk?
            if (List::head(toChunks))
            begin
                thisChunk.send(hHead(data));
            end
        endmethod

        method Bool notFull(toChunks) = thisChunk.notFull() || ! List::head(toChunks);
    endmodule
endinstance


//
// Instance of soft-connection based compression mapping that allocates
// a group of soft connections for a compressed receiver's channel.
//
instance CompressionMapping#(HCons#(t_HEAD, t_REM),
                             COMPRESSED_CONNECTION_RECV#(HCons#(t_HEAD, t_REM), List#(Bool)),
                             CONNECTED_MODULE)
    provisos (Alias#(t_ENC_CHUNKS, HCons#(t_HEAD, t_REM)),
              Bits#(t_HEAD, t_HEAD_SZ),
              // Prepare to map subordinate chunks
              CompressionMapping#(t_REM,
                                  COMPRESSED_CONNECTION_RECV#(t_REM, List#(Bool)),
                                  CONNECTED_MODULE));

    module [CONNECTED_MODULE] mkCompressedChannel#(t_ENC_CHUNKS map,
                                                   String name,
                                                   Integer depth)
        // Interface:
        (COMPRESSED_CONNECTION_RECV#(t_ENC_CHUNKS, List#(Bool)));

        // Allocate the subordinate chunks
        COMPRESSED_CONNECTION_RECV#(t_REM, List#(Bool)) subChunks <-
            mkCompressedChannel(hTail(map), name, depth + 1);

        // Allocate an actual soft connection for the current chunk
        CONNECTION_RECV#(t_HEAD) thisChunk;
        if (valueOf(t_HEAD_SZ) != 0)
            thisChunk <- mkConnectionRecv(name + "_cmpmap" + integerToString(depth));
        else
            thisChunk <- mkConnectionRecvDummy(name + "_cmpmap" + integerToString(depth));

        method Action deq(fromChunks);
            //
            // The fromChunks mask is a list, corresponding to the list of chunks,
            // indicating which chunks held valid messages.
            //
            subChunks.deq(List::tail(fromChunks));
            if (List::head(fromChunks))
            begin
                thisChunk.deq();
            end
        endmethod

        method Bool notEmpty(fromChunks);
            return (thisChunk.notEmpty || ! List::head(fromChunks)) &&
                   subChunks.notEmpty(List::tail(fromChunks));
        endmethod

        method receive(fromChunks);
            //
            // Concatenate received chunks into a response, recursively
            // visiting all channels.  Only read channels corresponding
            // to requested chunks.
            //
            let sub_chunks = subChunks.receive(List::tail(fromChunks));
            if (List::head(fromChunks) && (valueOf(t_HEAD_SZ) != 0))
            begin
                return hCons(thisChunk.receive(), sub_chunks);
            end
            else
            begin
                return hCons(?, sub_chunks);
            end
        endmethod
    endmodule
endinstance


//
// Special case of compressed receive channel for the bit 0 position (the
// end of the HList).
//
instance CompressionMapping#(HCons#(t_HEAD, HNil),
                             COMPRESSED_CONNECTION_RECV#(HCons#(t_HEAD, HNil), List#(Bool)),
                             CONNECTED_MODULE)
    provisos (Alias#(t_ENC_CHUNKS, HCons#(t_HEAD, HNil)),
              Bits#(t_HEAD, t_HEAD_SZ));

    module [CONNECTED_MODULE] mkCompressedChannel#(t_ENC_CHUNKS map,
                                                   String name,
                                                   Integer depth)
        // Interface:
        (COMPRESSED_CONNECTION_RECV#(t_ENC_CHUNKS, List#(Bool)));

        // Allocate an actual soft connection for the current chunk
        CONNECTION_RECV#(t_HEAD) thisChunk;
        if (valueOf(t_HEAD_SZ) != 0)
            thisChunk <- mkConnectionRecv(name + "_cmpmap" + integerToString(depth));
        else
            thisChunk <- mkConnectionRecvDummy(name + "_cmpmap" + integerToString(depth));

        method Action deq(fromChunks) = thisChunk.deq();
        method Bool notEmpty(fromChunks) = thisChunk.notEmpty() || ! List::head(fromChunks);

        method receive(fromChunks);
            if (List::head(fromChunks) && (valueOf(t_HEAD_SZ) != 0))
            begin
                return hList1(thisChunk.receive());
            end
            else
            begin
                return hList1(?);
            end
        endmethod
    endmodule
endinstance


instance ToConnectionSend#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA), t_ENC_DATA);
    function CONNECTION_SEND#(t_ENC_DATA) toConnectionSend(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA) decoder);
        let send = interface CONNECTION_SEND;
                       method Action send(t_ENC_DATA data);
		           decoder.enq(data);
	               endmethod

                       method Bool notFull();
		           return decoder.notFull();
		       endmethod
                  endinterface;  
        return send;
    endfunction
endinstance

instance ToConnectionRecv#(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA), t_ENC_DATA);
    function CONNECTION_RECV#(t_ENC_DATA) toConnectionRecv(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) encoder);
        let recv = interface CONNECTION_RECV;

                       method Action deq();
		           encoder.deq();
		       endmethod

                       method Bool   notEmpty();
                           return encoder.notEmpty();
                       endmethod 

                       method t_ENC_DATA  receive();
		           return encoder.first();
                       endmethod 

                  endinterface; 
        return recv; 
    endfunction
endinstance



instance ToPhysicalSend#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA), t_ENC_DATA)
    provisos(Bits#(t_ENC_DATA, t_ENC_DATA_SZ));

    module mkPhysicalSend#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA) decoder) 
               (PHYSICAL_SEND#(t_ENC_DATA))
        provisos(Bits#(t_ENC_DATA, t_ENC_DATA_SZ));

	FIFOF#(t_ENC_DATA) fifo <- mkSizedFIFOF(`CON_BUFFERING);
	PulseWire dequeue <- mkPulseWire;

	rule transfer;
            dequeue.send;
            decoder.enq(fifo.first);
            fifo.deq;
        endrule

        method Action send(t_ENC_DATA data);
	    fifo.enq(data);
	endmethod

        method Bool notFull();
	    return fifo.notFull();
	endmethod

	method Bool dequeued();
            return dequeue;
        endmethod

    endmodule
endinstance
