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

`include "awb/provides/physical_platform.bsh"
`include "awb/provides/physical_channel.bsh"
`include "awb/provides/umf.bsh"



// channelio interface
interface CHANNEL_IO#(type umf_packet);
    interface Vector#(`CIO_NUM_CHANNELS, CIOReadPort#(umf_packet))  readPorts;
    interface Vector#(`CIO_NUM_CHANNELS, CIOWritePort#(umf_packet)) writePorts;
endinterface

module mkChannelIO#(PHYSICAL_DRIVERS drivers) (CHANNEL_IO#(UMF_PACKET));
    PHYSICAL_CHANNEL physicalChannel <- mkPhysicalChannel(drivers);
    CHANNEL_VIRTUALIZER#(`CIO_NUM_CHANNELS, `CIO_NUM_CHANNELS, UMF_PACKET) channelVirtualizer <- mkChannelVirtualizer(physicalChannel.read,physicalChannel.write);
    interface  readPorts = channelVirtualizer.readPorts();   
    interface  writePorts = channelVirtualizer.writePorts();   
endmodule

