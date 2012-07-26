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

import GetPut::*;
import Connectable::*;
import HList::*;

//
// Compressed soft connections.  Provide the illusion of a single soft
// connection using a base data type.  Internally, the base type is
// compressed and sent over multiple soft connections, transmitting
// each message over the minimum number of connections to preserve the
// value.
//
// See compress.bsv in LibRL.
//

// Base case for a recursize parsing of a t_MAPPING HList.
instance CompressionMappingMC#(HList::HNil, t_CHAN, CONNECTED_MODULE);
    module [CONNECTED_MODULE] mkCompressedChannelMC#(HList::HNil map,
                                                     String name,
                                                     Integer depth) (t_CHAN);
        return ?;
    endmodule
endinstance


//
// mkCompressedConnectionSend --
//     Same interface as a mkConnectionSend, but instantiates multiple
//     soft connections as appropriate for compression of t_MSG.
//
module [CONNECTED_MODULE] mkCompressedConnectionSend#(String name)
    // Interface:
    (CONNECTION_SEND#(t_MSG))
    provisos (Bits#(t_MSG, t_MSG_SZ),
              CompressMC#(t_MSG, t_ENC_DATA, t_DECODER, CONNECTED_MODULE),
              Bits#(t_ENC_DATA, t_ENC_DATA_SZ),
              CompressionMappingMC#(t_ENC_DATA,
                                    COMPRESSED_CONNECTION_SEND#(t_ENC_DATA),
                                    CONNECTED_MODULE));

    // The encoder transforms input messages to a compressed stream
    COMPRESSION_ENCODER#(t_MSG, t_ENC_DATA) encoder <- mkCompressorMC();

    // Instantiate the set of sender soft connections
    t_ENC_DATA map = ?;    
    COMPRESSED_CONNECTION_SEND#(t_ENC_DATA) con <-
        mkCompressedChannelMC(map, name, 0);

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
    provisos (Bits#(t_MSG, t_MSG_SZ),
              CompressMC#(t_MSG, t_ENC_DATA, t_DECODER, CONNECTED_MODULE),
              Bits#(t_ENC_DATA, t_ENC_DATA_SZ),
              Bits#(t_DECODER, t_DECODER_SZ),    
              CompressionMappingMC#(t_ENC_DATA,
                                    COMPRESSED_CONNECTION_RECV#(t_ENC_DATA),
                                    CONNECTED_MODULE));

    // The decoder transforms received messages to an output decompressed stream
    COMPRESSION_DECODER#(t_MSG, t_ENC_DATA, t_DECODER) decoder <-
        mkDecompressorMC();

    // Instantiate the set of receiver soft connections
    t_ENC_DATA map = ?;    
    COMPRESSED_CONNECTION_RECV#(t_ENC_DATA) con <-
        mkCompressedChannelMC(map, name, 0);

    // Connect the inbound soft connections to the input of the decoder
    mkConnection(con, decoder);

    method Action deq() = decoder.deq();
    method Bool notEmpty() = decoder.notEmpty();
    method t_MSG receive() = decoder.first();
endmodule


//
// Internal interfaces for multi-soft connection compressed streams.  The
// modules with CONNECTION_SEND/RECV interfaces above communicate with the
// actual soft connections instantiated below through these interfaces.
//

interface COMPRESSED_CONNECTION_SEND#(type t_MSG);
    method Action send(t_MSG data, Integer nValidBits);
    method Bool notFull();
endinterface

interface COMPRESSED_CONNECTION_RECV#(type t_MSG);
    method Action deq(Integer nBits);
    method Bool notEmpty();
    method t_MSG receive(Integer nBits);
endinterface


//
// Helper modules for connecting compressors to sets of compressed soft
// connections.
//

instance Connectable#(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA),
                      COMPRESSED_CONNECTION_SEND#(t_ENC_DATA))
    // We avoid associating t_ENC_DATA and t_END_DATA_SZ because it causes
    // a ripple of provisos up the chain.
    provisos (Bits#(t_ENC_DATA, a__));
    module mkConnection#(COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) enc,
                         COMPRESSED_CONNECTION_SEND#(t_ENC_DATA) con)
    (Empty);

        rule connect;
            match {.cval, .valid_bits} = enc.first();
            enc.deq();
        
            con.send(cval, valid_bits);
        endrule

    endmodule
endinstance

// Reverse argument order of above (same connection)
instance Connectable#(COMPRESSED_CONNECTION_SEND#(t_ENC_DATA),
                      COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA))
    provisos (Bits#(t_ENC_DATA, a__));
    module mkConnection#(COMPRESSED_CONNECTION_SEND#(t_ENC_DATA) con,
                         COMPRESSION_ENCODER#(t_DATA, t_ENC_DATA) enc)
    (Empty);

        let c <- mkConnection(enc, con);
        return c;

    endmodule
endinstance

instance Connectable#(COMPRESSED_CONNECTION_RECV#(t_ENC_DATA),
                      COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER))
    // We avoid associating t_ENC_DATA and t_END_DATA_SZ because it causes
    // a ripple of provisos up the chain.
    provisos (Bits#(t_ENC_DATA, a__),
              Bits#(t_DECODER, t_DECODER_SZ));
    module mkConnection#(COMPRESSED_CONNECTION_RECV#(t_ENC_DATA) con,
                         COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER) dec)
    (Empty);

        rule connect;
            // Compute the number of input bits for the current message by
            // first reading the number of decoder bits from the current message.
            let base_chunk_bits = con.receive(valueOf(t_DECODER_SZ));
            let in_bits = dec.numInBits(unpack(truncateNP(pack(base_chunk_bits))));

            let cval = con.receive(in_bits);
            con.deq(in_bits);

            dec.enq(cval);
        endrule

    endmodule
endinstance

// Reverse argument order of above (same connection)
instance Connectable#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER),
                      COMPRESSED_CONNECTION_RECV#(t_ENC_DATA))
    provisos (Bits#(t_ENC_DATA, a__),
              Bits#(t_DECODER, t_DECODER_SZ));
    module mkConnection#(COMPRESSION_DECODER#(t_DATA, t_ENC_DATA, t_DECODER) dec,
                         COMPRESSED_CONNECTION_RECV#(t_ENC_DATA) con)
    (Empty);

        let c <- mkConnection(con, dec);

    endmodule
endinstance


//
// Instance of soft-connection based compression mapping that allocates
// a group of soft connections for a compressed sender's channel.
//
instance CompressionMappingMC#(HCons#(t_HEAD, t_REM),
                               COMPRESSED_CONNECTION_SEND#(HCons#(t_HEAD, t_REM)),
                               CONNECTED_MODULE)
    provisos (Alias#(t_ENC_DATA, HCons#(t_HEAD, t_REM)),
              Bits#(t_ENC_DATA, t_ENC_DATA_SZ),
              Bits#(t_HEAD, t_HEAD_SZ),
              Bits#(t_REM, t_REM_SZ),
              // Prepare to map subordinate chunks
              CompressionMappingMC#(t_REM,
                                    COMPRESSED_CONNECTION_SEND#(t_REM),
                                    CONNECTED_MODULE));

    //
    // mkCompressedSendChannel --
    //     Recursive instantiation of send connections for current and all
    //     subordinate compression chunks.
    //
    module [CONNECTED_MODULE] mkCompressedChannelMC#(t_ENC_DATA map,
                                                     String name,
                                                     Integer depth)
        // Interface:
        (COMPRESSED_CONNECTION_SEND#(t_ENC_DATA));

        // Is this the lowest (right-most) chunk?
        let isLowestChunk = (valueOf(t_REM_SZ) == 0);

        // Allocate the subordinate chunks
        COMPRESSED_CONNECTION_SEND#(t_REM) subChunks = ?;
        if (! isLowestChunk)
        begin
            subChunks <- mkCompressedChannelMC(hTail(map), name, depth + 1);
        end

        // Allocate an actual soft connection for the current chunk
        CONNECTION_SEND#(t_HEAD) thisChunk;
        if (valueOf(t_HEAD_SZ) != 0)
            thisChunk <- mkConnectionSend(name + "_cmpmap" + integerToString(depth));
        else
            thisChunk <- mkConnectionSendDummy(name + "_cmpmap" + integerToString(depth));

        method Action send(t_ENC_DATA data, Integer nValidBits);
            // If this is not the chunk for bit position 0 forward the send
            // request down the recursive chain.
            if (! isLowestChunk)
            begin
                subChunks.send(hTail(data), nValidBits);
            end

            // Is there compressed data to be sent for the current chunk?
            if (nValidBits > valueOf(t_REM_SZ))
            begin
                thisChunk.send(hHead(data));
            end
        endmethod

        // notFull requires that all chunks be notFull.
        method Bool notFull();
            Bool sub_state = (isLowestChunk ? True : subChunks.notFull());
            return sub_state && thisChunk.notFull();
        endmethod
    endmodule
endinstance


//
// Instance of soft-connection based compression mapping that allocates
// a group of soft connections for a compressed receiver's channel.
//
instance CompressionMappingMC#(HCons#(t_HEAD, t_REM),
                               COMPRESSED_CONNECTION_RECV#(HCons#(t_HEAD, t_REM)),
                               CONNECTED_MODULE)
    provisos (Alias#(t_ENC_DATA, HCons#(t_HEAD, t_REM)),
              Bits#(t_ENC_DATA, t_ENC_DATA_SZ),
              Bits#(t_HEAD, t_HEAD_SZ),
              Bits#(t_REM, t_REM_SZ),
              // Prepare to map subordinate chunks
              CompressionMappingMC#(t_REM,
                                    COMPRESSED_CONNECTION_RECV#(t_REM),
                                    CONNECTED_MODULE));

    module [CONNECTED_MODULE] mkCompressedChannelMC#(t_ENC_DATA map,
                                                     String name,
                                                     Integer depth)
        // Interface:
        (COMPRESSED_CONNECTION_RECV#(t_ENC_DATA));

        // Allocate the subordinate chunks
        COMPRESSED_CONNECTION_RECV#(t_REM) subChunks <-
            mkCompressedChannelMC(hTail(map), name, depth + 1);

        // Allocate an actual soft connection for the current chunk
        CONNECTION_RECV#(t_HEAD) thisChunk;
        if (valueOf(t_HEAD_SZ) != 0)
            thisChunk <- mkConnectionRecv(name + "_cmpmap" + integerToString(depth));
        else
            thisChunk <- mkConnectionRecvDummy(name + "_cmpmap" + integerToString(depth));

        method Action deq(nBits);
            //
            // The "nBits" argument to deq() indicates how many valid
            // bits were transmitted for the current message.  Only
            // channels with valid bits are dequeued.
            //
            subChunks.deq(nBits);
            if (nBits > valueOf(t_REM_SZ))
            begin
                thisChunk.deq();
            end
        endmethod

        //
        // For now, notEmpty() only indicates whether the lowest chunk is not
        // empty.  The only expected consumer of these channels is 
        // mkCompressedConnectionRecv, which doesn't care.
        //
        method Bool notEmpty();
            return subChunks.notEmpty();
        endmethod

        method receive(nBits);
            //
            // Concatenate received chunks into a response, recursively
            // visiting all channels.  Only read channels corresponding
            // to bit positions within the requested low nBits.
            //
            let sub_chunks = subChunks.receive(nBits);
            if ((nBits > valueOf(t_REM_SZ)) && (valueOf(t_HEAD_SZ) != 0))
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
instance CompressionMappingMC#(HCons#(t_HEAD, HNil),
                               COMPRESSED_CONNECTION_RECV#(HCons#(t_HEAD, HNil)),
                               CONNECTED_MODULE)
    provisos (Alias#(t_ENC_DATA, HCons#(t_HEAD, HNil)),
              Bits#(t_ENC_DATA, t_ENC_DATA_SZ),
              Bits#(t_HEAD, t_HEAD_SZ));

    module [CONNECTED_MODULE] mkCompressedChannelMC#(t_ENC_DATA map,
                                                     String name,
                                                     Integer depth)
        // Interface:
        (COMPRESSED_CONNECTION_RECV#(t_ENC_DATA));

        // Allocate an actual soft connection for the current chunk
        CONNECTION_RECV#(t_HEAD) thisChunk;
        if (valueOf(t_HEAD_SZ) != 0)
            thisChunk <- mkConnectionRecv(name + "_cmpmap" + integerToString(depth));
        else
            thisChunk <- mkConnectionRecvDummy(name + "_cmpmap" + integerToString(depth));

        method Action deq(nBits);
            thisChunk.deq();
        endmethod

        method Bool notEmpty();
            return thisChunk.notEmpty();
        endmethod

        method receive(nBits);
            return hList1(thisChunk.receive());
        endmethod
    endmodule
endinstance
