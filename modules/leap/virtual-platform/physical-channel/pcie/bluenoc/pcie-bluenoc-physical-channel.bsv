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

`include "awb/provides/physical_platform.bsh"
`include "awb/provides/pcie_device.bsh"
`include "awb/provides/umf.bsh"

// ============== Physical Channel ===============

// interface
interface PHYSICAL_CHANNEL;
    method ActionValue#(UMF_CHUNK) read();
    method Action                  write(UMF_CHUNK chunk);
endinterface

typedef Bit#(TLog#(TAdd#(TDiv#(SizeOf#(UMF_CHUNK),8),1))) UMF_COUNTER;


// module
module mkPhysicalChannel#(PHYSICAL_DRIVERS drivers)
    // Interface
    (PHYSICAL_CHANNEL);
   
    let modelClk <- exposeCurrentClock();
    let modelRst <- exposeCurrentReset();

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
    // For now we expect 4 byte UMF chunks and 8 byte PCIe beats.  Each chunk
    // is stored, quite inefficiently, in a single beat BlueNoC message.
    // The performance is terrible, but works.
    //

    rule fwdFromHost (! beatsIn.empty);
        let beat = beatsIn.first();
        beatsIn.deq();
        
        let chunk = beat[63:32];
        fromHostSyncQ.enq(chunk);
    endrule

    rule fwdToHost (True);
        let chunk = toHostSyncQ.first();
        toHostSyncQ.deq();
        Bit#(64) beat = { chunk,
                          8'd1,           // Don't wait
                          8'd4,           // Length
                          8'd4,           // Source
                          8'd0 };         // Destination

        beatsOut.enq(zeroExtend(beat));
    endrule


    method Action write(UMF_CHUNK data);
        toHostSyncQ.enq(data);
    endmethod
   
    method ActionValue#(UMF_CHUNK) read();
        let c = fromHostSyncQ.first();
        fromHostSyncQ.deq();

        return c;
    endmethod

endmodule
