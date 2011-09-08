import FIFOF::*;
import SpecialFIFOs::*;
import Clocks::*;
import Vector::*;

`include "awb/provides/physical_platform.bsh"
`include "awb/provides/physical_channel.bsh"
`include "awb/provides/umf.bsh"

// read/write port interfaces
interface CIOReadPort#(type umf_packet);
    method ActionValue#(umf_packet) read();
endinterface

interface CIOWritePort#(type umf_packet);
    method Action write(umf_packet data);
endinterface

// channelio interface
interface CHANNEL_IO#(type umf_packet);
    interface Vector#(`CIO_NUM_CHANNELS, CIOReadPort#(umf_packet))  readPorts;
    interface Vector#(`CIO_NUM_CHANNELS, CIOWritePort#(umf_packet)) writePorts;
endinterface

// channelio module
module mkChannelIO#(PHYSICAL_DRIVERS drivers, Clock model_clk, Reset model_rst) (CHANNEL_IO#(UMF_PACKET));

    Reg#(UMF_MSG_LENGTH) readChunksRemaining  <- mkReg(0);
    Reg#(UMF_MSG_LENGTH) writeChunksRemaining <- mkReg(0);

    Reg#(Bit#(8)) currentReadChannel  <- mkReg(0);
    Reg#(Bit#(8)) currentWriteChannel <- mkReg(0);

    // physical channel
    PHYSICAL_CHANNEL physicalChannel <- mkPhysicalChannel(drivers);

    // ==============================================================
    //                        Ports and Buffers
    // ==============================================================

    // create read/write buffers and link them to ports
    SyncFIFOIfc#(UMF_PACKET)                    readBuffers[`CIO_NUM_CHANNELS];
    Vector#(`CIO_NUM_CHANNELS, CIOReadPort#(UMF_PACKET))	rports = newVector();
    FIFOF#(UMF_CHUNK)				readBuffStage;

    SyncFIFOIfc#(UMF_PACKET)                    writeBuffers[`CIO_NUM_CHANNELS];
    Vector#(`CIO_NUM_CHANNELS, CIOWritePort#(UMF_PACKET))	wports = newVector();
    //staging reg to improve RAM to RAM timing - before SyncFIFO mux as 
    FIFOF#(UMF_PACKET)				writeBuffStage[`CIO_NUM_CHANNELS]; 

    readBuffStage <- mkPipelineFIFOF();

    for (Integer i = 0; i < `CIO_NUM_CHANNELS; i = i+1)
    begin
        readBuffers[i] <- mkSyncFIFOFromCC(16, model_clk);
        writeBuffers[i] <- mkSyncFIFOToCC(16, model_clk, model_rst);
        writeBuffStage[i] <- mkPipelineFIFOF();

        // create a new read port and link it to the FIFO
        rports[i] = interface CIOReadPort
                        method ActionValue#(UMF_PACKET) read();
                            UMF_PACKET val = readBuffers[i].first();
                            readBuffers[i].deq();
`ifdef DEBUG
			    $display("CIOReadPort[%d]: %h", i, val);
`endif
                            return val;
                        endmethod
                    endinterface;

        // create a new write port and link it to the FIFO
        wports[i] = interface CIOWritePort
                        method Action write(UMF_PACKET data);
                            writeBuffers[i].enq(data);
                        endmethod
                    endinterface;
    end

    // ==============================================================
    //                          Read rules
    // ==============================================================

    rule stage_read_channel;
        UMF_CHUNK chunk <- physicalChannel.read();
`ifdef DEBUG
	$display("%t:stage_read_channel:H>F: %h", $time, chunk);
`endif
	readBuffStage.enq(chunk);
    endrule

    // probe physical channel for incoming new message header
    rule read_physical_channel_newmsg (readChunksRemaining == 0);

	UMF_CHUNK chunk = readBuffStage.first();
	readBuffStage.deq();

        // create new header packet
        UMF_PACKET packet = tagged UMF_PACKET_header unpack(chunk);

        // enqueue the new header into the channel's FIFO
        readBuffers[packet.UMF_PACKET_header.channelID].enq(packet);

        // setup channel for remaining chunks
        readChunksRemaining <= packet.UMF_PACKET_header.numChunks;
        currentReadChannel  <= zeroExtend(packet.UMF_PACKET_header.channelID);
`ifdef DEBUG
	$display("%t:read_physical_channel_newmsg:H>F: %h -> channel id: %d, chunks: %d", $time, packet, packet.UMF_PACKET_header.channelID, packet.UMF_PACKET_header.numChunks);
`endif

    endrule

    // probe physical channel for incoming read data (continuing old message)
    rule read_physical_channel_contmsg (readChunksRemaining != 0);

        UMF_CHUNK chunk = readBuffStage.first();
	readBuffStage.deq();

        UMF_PACKET packet = tagged UMF_PACKET_dataChunk chunk;

        readBuffers[currentReadChannel].enq(packet);
`ifdef DEBUG
	$display("%t:read_physical_channel_contmsg: %h", $time, chunk);
`endif
        // increment chunks read
        readChunksRemaining <= readChunksRemaining - 1;

    endrule

    // ==============================================================
    //                          Write rules
    // ==============================================================

    Bool request[`CIO_NUM_CHANNELS];
    Bool higher_priority_request[`CIO_NUM_CHANNELS];
    Bool grant[`CIO_NUM_CHANNELS];

    // static loop for all write channels
    for (Integer i = 0; i < `CIO_NUM_CHANNELS; i = i + 1)
    begin
    
	rule stage_write_buffs;
	    // get the next packet from the write channel
	    UMF_PACKET packet = writeBuffers[i].first();
	    writeBuffers[i].deq();

	    // register FIFO RAM outputs
	    writeBuffStage[i].enq(packet);
`ifdef DEBUG
	    $display("stage_write_buffs:F>H[%d]: %h", i, packet);
`endif
	endrule

        // compute priority for this channel (static request/grant)
        // current algorithm involves a chain OR, which is fine for
        // a small number of channels

        request[i] = (writeChunksRemaining == 0) && (writeBuffStage[i].notEmpty());

        if (i == 0)
        begin
            grant[i] = request[i];
            higher_priority_request[i] = request[i];
        end
        else
        begin
            grant[i] = (!higher_priority_request[i-1]) && request[i];
            higher_priority_request[i] = higher_priority_request[i-1] || request[i];
        end
	
        // start writing new message
        rule write_phys_channel_newmsg (grant[i]);

            // get header packet
            UMF_PACKET packet = writeBuffStage[i].first();
            writeBuffStage[i].deq();

            // create and encode header chunk
            //   TODO: ideally, we should explicitly set channelID here. For
            //   now, assume upper layer is setting it correctly (upper layer
            //   has to know its virtual channelID anyway
            UMF_CHUNK headerChunk = pack(packet.UMF_PACKET_header);

            // send the header chunk to the physical channel
            physicalChannel.write(headerChunk);

            // setup remaining chunks
            writeChunksRemaining <= packet.UMF_PACKET_header.numChunks;
            currentWriteChannel <= fromInteger(i);
        endrule

    end // for

    // continue writing message
    rule write_phys_channel_body(writeChunksRemaining != 0);
	UMF_PACKET packet = writeBuffStage[currentWriteChannel].first();
	writeBuffStage[currentWriteChannel].deq();

	physicalChannel.write(packet.UMF_PACKET_dataChunk);

        // one more chunk processed
        writeChunksRemaining <= writeChunksRemaining - 1;
    endrule


    // ==============================================================
    //                        Set Interfaces
    // ==============================================================

    interface readPorts = rports;
    interface writePorts = wports;

endmodule
