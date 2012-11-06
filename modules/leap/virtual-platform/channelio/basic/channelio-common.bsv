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

import FIFOF::*;
import Vector::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/umf.bsh"

// read/write port interfaces
interface CIOReadPort#(type umf_packet);
    method ActionValue#(umf_packet) read();
endinterface

interface CIOWritePort#(type umf_packet);
    method Action write(umf_packet data);
endinterface

interface CHANNEL_VIRTUALIZER#(numeric type read_channels, numeric type write_channels, type umf_packet);
    interface Vector#(read_channels, CIOReadPort#(umf_packet))  readPorts;
    interface Vector#(write_channels, CIOWritePort#(umf_packet)) writePorts;
endinterface

// channelio module
module mkChannelVirtualizer#(function ActionValue#(umf_chunk) read(), function Action write(umf_chunk data)) (CHANNEL_VIRTUALIZER#(reads,writes, 
          GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk)))
       provisos (Bits#(umf_chunk, TAdd#(filler_bits, TAdd#(umf_phy_pvt,
                                  TAdd#(umf_channel_id, TAdd#(umf_service_id, 
                                                        TAdd#(umf_method_id,
                                                              umf_message_len)))))));

    Reg#(Bit#(umf_message_len)) readChunksRemaining  <- mkReg(0);
    Reg#(Bit#(umf_message_len)) writeChunksRemaining <- mkReg(0);

    Reg#(Bit#(umf_channel_id)) currentReadChannel  <- mkReg(0);
    Reg#(Bit#(umf_channel_id)) currentWriteChannel <- mkReg(0);


    // ==============================================================
    //                        Ports and Buffers
    // ==============================================================

    // create read/write buffers and link them to ports
    Vector#(reads, FIFOF#(GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk))) readBuffers = newVector();
    Vector#(reads, CIOReadPort#(GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk))) rports = newVector();

    Vector#(writes, FIFOF#(GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk))) writeBuffers = newVector();
    Vector#(writes, CIOWritePort#(GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk))) wports = newVector();

    for (Integer i = 0; i < valueof(reads); i = i+1)
    begin
        readBuffers[i] <- mkSizedFIFOF(4);


        // create a new read port and link it to the FIFO
        rports[i] = interface CIOReadPort#(GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk))
                        method ActionValue#(GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk)) read();

                            let val = readBuffers[i].first();
                            readBuffers[i].deq();
                            return val;

                        endmethod
                    endinterface;
    end		    

    for (Integer i = 0; i < valueof(writes); i = i+1)
    begin
        writeBuffers[i] <- mkSizedFIFOF(4);
        // create a new write port and link it to the FIFO
        wports[i] = interface CIOWritePort#(GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk))
                        method Action write(GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk) data);

                            writeBuffers[i].enq(data);

                        endmethod
                    endinterface;
    end

    // ==============================================================
    //                          Read rules
    // ==============================================================

    // probe physical channel for incoming new message header
    rule read_physical_channel_newmsg (readChunksRemaining == 0);

        umf_chunk chunk <- read();

        // create new header packet
        GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk) packet = 
            tagged UMF_PACKET_header unpack(pack(chunk));

        // enqueue the new header into the channel's FIFO
        readBuffers[packet.UMF_PACKET_header.channelID].enq(packet);

        // setup channel for remaining chunks
        readChunksRemaining <= packet.UMF_PACKET_header.numChunks;
        currentReadChannel  <= zeroExtend(packet.UMF_PACKET_header.channelID);

    endrule

    // probe physical channel for incoming read data (continuing old message)
    rule read_physical_channel_contmsg (readChunksRemaining != 0);

        umf_chunk chunk <- read();
        GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk) packet = tagged UMF_PACKET_dataChunk chunk;

        readBuffers[currentReadChannel].enq(packet);

        // increment chunks read
        readChunksRemaining <= readChunksRemaining - 1;

    endrule

    // ==============================================================
    //                          Write rules
    // ==============================================================

    //
    // Pick the next channel that may start a new message (assuming one isn't
    // already in flight.  Priority is static, with highest priority going
    // to the lowest numbered channel.
    //

    function Bool isNotEmpty(FIFOF#(t) f) = f.notEmpty();

    // start writing new message
    rule write_physical_channel_newmsg (writeChunksRemaining == 0 &&&
                                        findIndex(isNotEmpty, writeBuffers) matches tagged Valid .i);

        // get header packet
        GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                       umf_channel_id, umf_service_id,
                       umf_method_id,  umf_message_len,
                       umf_phy_pvt,    filler_bits), umf_chunk) packet = writeBuffers[i].first();
        writeBuffers[i].deq();

        // create and encode header chunk
        //   TODO: ideally, we should explicitly set channelID here. For
        //   now, assume upper layer is setting it correctly (upper layer
        //   has to know its virtual channelID anyway
        umf_chunk headerChunk = unpack(pack(packet.UMF_PACKET_header));

        // send the header chunk to the physical channel
        write(headerChunk);

        // setup remaining chunks
        writeChunksRemaining <= packet.UMF_PACKET_header.numChunks;
        currentWriteChannel <= zeroExtendNP(pack(i));

    endrule

    // continue writing message
    rule write_physical_channel_continue (writeChunksRemaining != 0);

        // get the next packet from the active write channel
        GENERIC_UMF_PACKET#(GENERIC_UMF_PACKET_HEADER#(
                           umf_channel_id, umf_service_id,
                           umf_method_id,  umf_message_len,
                           umf_phy_pvt,    filler_bits), umf_chunk) packet = writeBuffers[currentWriteChannel].first();
        writeBuffers[currentWriteChannel].deq();

        // send the data chunk to the physical channel
        write(packet.UMF_PACKET_dataChunk);

        // one more chunk processed
        writeChunksRemaining <= writeChunksRemaining - 1;

    endrule

    // ==============================================================
    //                        Set Interfaces
    // ==============================================================

    interface readPorts = rports;
    interface writePorts = wports;

endmodule
