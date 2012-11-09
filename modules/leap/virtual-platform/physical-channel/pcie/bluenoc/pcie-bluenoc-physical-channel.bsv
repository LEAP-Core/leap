//
// Copyright (C) 2008 Intel Corporation
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
import Connectable::*;
import FIFO::*;
import Clocks::*;
import MsgFormat::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/pcie_device.bsh"
`include "awb/provides/umf.bsh"


// ============== Physical Channel ===============

// interface
interface PHYSICAL_CHANNEL;
    method ActionValue#(UMF_CHUNK) read();
    method Action                  write(UMF_CHUNK chunk);
endinterface


// module
module mkPhysicalChannel#(PHYSICAL_DRIVERS drivers)
    // Interface
    (PHYSICAL_CHANNEL);
   
    //
    // The channel is written with the following assumptions:
    //
    if (valueOf(SizeOf#(UMF_PACKET_HEADER)) - valueOf(UMF_PACKET_HEADER_FILLER_BITS) > 32)
        errorM("UMF packet header must fit in 32 bits");
    if (valueOf(PCIE_BYTES_PER_BEAT) < 8)
        errorM("PCIE_BYTES_PER_BEAT must be at least 8");
    if (valueOf(PCIE_BYTES_PER_BEAT) * 8 != valueOf(UMF_CHUNK_BITS))
        errorM("PCIE_BYTES_PER_BEAT must be equal to the size of UMF chunks");

    let modelClk <- exposeCurrentClock();
    let modelRst <- exposeCurrentReset();

    // Maximum UMF payload chunks that fit in a BlueNoC packet
    Integer maxChunksPerPacket = (256 / valueOf(PCIE_BYTES_PER_BEAT)) - 1;

    let pcieDriver = drivers.pcieDriver;
    let pcieClk = pcieDriver.clock;
    let pcieRst = pcieDriver.reset;
    let pcieNOC = pcieDriver.noc;

    FifoMsgSink#(PCIE_BYTES_PER_BEAT)   beatsIn  <- mkFifoMsgSink(clocked_by pcieClk, reset_by pcieRst);
    FifoMsgSource#(PCIE_BYTES_PER_BEAT) beatsOut <- mkFifoMsgSource(clocked_by pcieClk, reset_by pcieRst);
    mkConnection(pcieNOC, as_port(beatsOut.source, beatsIn.sink));

    // Transfer from model clock to PCIe clock
    SyncFIFOIfc#(UMF_CHUNK) fromHostSyncQ <- mkSyncFIFO(8, pcieClk, pcieRst, modelClk);
    SyncFIFOIfc#(UMF_CHUNK) toHostSyncQ <- mkSyncFIFO(8, modelClk, modelRst, pcieClk);

    //
    // Count cycles of inactivity before forcing a flush of the FPGA to host
    // output buffer.
    //
    Reg#(Bit#(11)) inactiveOutCnt <- mkReg(0, clocked_by pcieClk, reset_by pcieRst);
    Reg#(Bit#(11)) maxTimeout <- mkReg(0, clocked_by pcieClk, reset_by pcieRst);

    //
    // Wait for a single beat message from the host to know that the channel
    // is up.  No response is expected.
    //
    Reg#(Bool) initDone <- mkReg(False, clocked_by pcieClk, reset_by pcieRst);
    ReadOnly#(Bool) initDone_Model  <- mkNullCrossingWire(modelClk, initDone,
                                                          clocked_by pcieClk,
                                                          reset_by pcieRst);

    rule initFromHost (! beatsIn.empty && ! initDone);
        let beat = beatsIn.first();
        beatsIn.deq();
        initDone <= True;

        // We can't use a dynamic parameter to set maxTimeout because the
        // channel needs to be up to set a parameter.  Instead, the value
        // is passed in the initialization payload.
        maxTimeout <= beat[42:32];
    endrule


    // Remaining bytes in an incoming BlueNoC packet
    Reg#(UInt#(8)) remBytesIn <- mkReg(0, clocked_by pcieClk, reset_by pcieRst);

    //
    // processHeaderFromHost --
    //   Process a BlueNoC packet header arriving from the host.
    //
    rule processHeaderFromHost (! beatsIn.empty && initDone && (remBytesIn == 0));
        let beat = beatsIn.first();
        beatsIn.deq();
        
        // Number of payload bytes.  Some bytes of the payload are in the
        // remainder of this beat, so subtract them from the count.
        UInt#(8) rem_bytes_in = unpack(beat[23:16]);
        UInt#(8) header_data_bytes = fromInteger(valueOf(TSub#(PCIE_BYTES_PER_BEAT, 4)));
        if (rem_bytes_in > header_data_bytes)
        begin
            remBytesIn <= rem_bytes_in - header_data_bytes;
        end

        // The longest BlueNoC packets are shorter than the longest UMF
        // packet allowed.  For long UMF packets a BlueNoC header may arrive
        // with no corresponding UMF header.  This is signalled by setting
        // bit 31 in the BlueNoC header (OP bit 6) for continuation packets.
        Bool contains_umf_header = (beat[31] == 0);

        if (contains_umf_header)
        begin
            // Extract the UMF header from the remainder of the beat
            let umf_header = beat[63:32];
            fromHostSyncQ.enq(unpack(zeroExtend(umf_header)));
        end
    endrule

    //
    // fwdChunkFromHost --
    //   Forward one UMF chunk from the host to the FPGA.
    //
    rule fwdChunkFromHost (! beatsIn.empty && initDone && (remBytesIn != 0));
        let beat = beatsIn.first();
        beatsIn.deq();

        // The chunk fills the beat
        fromHostSyncQ.enq(unpack(beat));

        // Done with BlueNoC packet?
        if (remBytesIn > fromInteger(valueOf(PCIE_BYTES_PER_BEAT)))
        begin
            // No.  Continue streaming.
            remBytesIn <= remBytesIn - fromInteger(valueOf(PCIE_BYTES_PER_BEAT));
        end
        else
        begin
            // Yes.  Wait for a header.
            remBytesIn <= 0;
        end
    endrule


    // Number of bytes remaining in current BlueNoC packet
    Reg#(UInt#(8)) remBytesOut <- mkReg(0, clocked_by pcieClk, reset_by pcieRst);
    // Number of chunks remaining in current UMF packet
    Reg#(UMF_MSG_LENGTH) remChunksOut <- mkReg(0, clocked_by pcieClk, reset_by pcieRst);

    //
    // startBlueNoCPacketToHost --
    //   Begin a new BlueNoC packet.  This may be the continuation of a
    //   UMF packet or the start of a new UMF packet.
    //
    rule startBlueNoCPacketToHost (initDone && (remBytesOut == 0));
        let chunk = toHostSyncQ.first();

        Bit#(8) flags = 0;
        // Continuation of UMF chunk?
        Bool is_umf_start = (remChunksOut == 0);
        flags[7] = pack(! is_umf_start);

        // Generate the UMF header value unconditionally to simplify hardware.
        // The receiver will look at flag bit 7 to know whether a header
        // exists.  When no header is needed the remainder of the beat
        // will be ignored, allowing the stream of chunks to be chunk-aligned.
        UMF_PACKET_HEADER umf_header = unpack(pack(chunk));

        //
        // Compute the length of the BlueNoC packet.  If the UMF packet
        // fits in a BlueNoC packet then set the BlueNoC packet length
        // to end when the UMF packet ends.  Otherwise, send a full
        // BlueNoC packet.
        //

        UInt#(8) rem_bytes_out;
        Bool last_bn_packet;

        if (is_umf_start)
        begin
            toHostSyncQ.deq();

            // One BlueNoC packet or multiple packets?
            last_bn_packet = (umf_header.numChunks <= fromInteger(maxChunksPerPacket));
            rem_bytes_out =
                fromInteger(valueOf(PCIE_BYTES_PER_BEAT)) *
                (last_bn_packet ? resize(umf_header.numChunks) :
                                  fromInteger(maxChunksPerPacket));

            remChunksOut <= umf_header.numChunks;
        end
        else
        begin
            // Same computation as header above but with what's left of
            // the continued UMF packet.
            last_bn_packet = (remChunksOut <= fromInteger(maxChunksPerPacket));
            rem_bytes_out =
                fromInteger(valueOf(PCIE_BYTES_PER_BEAT)) *
                (last_bn_packet ? resize(remChunksOut) :
                                  fromInteger(maxChunksPerPacket));
        end

        remBytesOut <= rem_bytes_out;

        // Set don't wait (send immediately) flag if this is the last
        // BlueNoC packet for the UMF packet and maxTimeout is 0.
        inactiveOutCnt <= maxTimeout;
        if (maxTimeout == 0)
        begin
            flags[0] = pack(last_bn_packet);
        end

        let len = rem_bytes_out +
                  fromInteger(valueOf(TSub#(PCIE_BYTES_PER_BEAT, 4)));

        Bit#(64) beat = { pack(umf_header)[31:0],
                          flags,
                          pack(len),                 // Length
                          8'd4,                      // Source
                          8'd0 };                    // Destination

        beatsOut.enq(zeroExtend(beat));
    endrule

    //
    // fwdChunkToHost --
    //   The continuation of both BlueNoC and UMF packets.
    //
    rule fwdChunkToHost (remBytesOut != 0);
        let chunk = toHostSyncQ.first();
        toHostSyncQ.deq();

        beatsOut.enq(pack(chunk));

        remChunksOut <= remChunksOut - 1;
        inactiveOutCnt <= maxTimeout;

        // Done with BlueNoC packet?
        if (remBytesOut > fromInteger(valueOf(PCIE_BYTES_PER_BEAT)))
        begin
            // No.  Continue streaming.
            remBytesOut <= remBytesOut - fromInteger(valueOf(PCIE_BYTES_PER_BEAT));
        end
        else
        begin
            // Yes.  Start a new BlueNoC packet.
            remBytesOut <= 0;
        end
    endrule

    //
    // triggerTimeout --
    //   Flush the FPGA->host data if it appears no more packets are coming.
    //   This rule never fires in the middle of a packet.
    //
    rule triggerTimeout ((inactiveOutCnt != 0) &&
                         (remChunksOut == 0) &&
                         ! toHostSyncQ.notEmpty);
        if (inactiveOutCnt == 1)
        begin
            Bit#(32) beat = { 8'd1,       // Don't wait
                              8'd0,       // Length
                              8'd4,       // Source
                              8'd0 };     // Destination
            beatsOut.enq(zeroExtend(beat));
        end

        inactiveOutCnt <= inactiveOutCnt - 1;
    endrule


    method Action write(UMF_CHUNK data) if (initDone_Model);
        toHostSyncQ.enq(data);
    endmethod
   
    method ActionValue#(UMF_CHUNK) read();
        let c = fromHostSyncQ.first();
        fromHostSyncQ.deq();

        return c;
    endmethod

endmodule
