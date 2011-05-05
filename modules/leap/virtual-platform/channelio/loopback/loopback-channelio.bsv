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

import FIFOF::*;
import Vector::*;

`include "asim/provides/physical_platform.bsh"
`include "asim/provides/physical_channel.bsh"
`include "asim/provides/umf.bsh"

// read/write port interfaces
interface CIOReadPort;
    method ActionValue#(UMF_PACKET) read();
endinterface

interface CIOWritePort;
    method Action write(UMF_PACKET data);
endinterface

// channelio interface
interface CHANNEL_IO;
    interface Vector#(`CIO_NUM_CHANNELS, CIOReadPort)  readPorts;
    interface Vector#(`CIO_NUM_CHANNELS, CIOWritePort) writePorts;
endinterface

// channelio module
module mkChannelIO#(PHYSICAL_DRIVERS drivers) (CHANNEL_IO);

    // physical channel
    PHYSICAL_CHANNEL physicalChannel <- mkPhysicalChannel(drivers);

    // ==============================================================
    //                        Loopback logic
    // ==============================================================

    rule loopback;
      let chunk <- physicalChannel.read();
      $display("chunk %h", chunk);
      physicalChannel.write(chunk);
    endrule	 

    // ==============================================================
    //                        Set Interfaces
    // ==============================================================

    // since we are creating a loopback device, and don't care about
    // anything above us in the stack, set the interfaces to null

    interface readPorts = ?;
    interface writePorts = ?;

endmodule
