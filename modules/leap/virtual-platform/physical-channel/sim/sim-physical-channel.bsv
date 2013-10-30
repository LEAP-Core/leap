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

`include "awb/provides/unix_pipe_device.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/umf.bsh"

// physical channel interface
interface PHYSICAL_CHANNEL;
    
    method ActionValue#(UMF_CHUNK) read();
    method Action                  write(UMF_CHUNK chunk);

    // this interface needed for LIM compiler.
    method UMF_CHUNK first();
    method Action    deq();
    method Bool      write_ready();

endinterface

// physical channel module
module mkPhysicalChannel#(PHYSICAL_DRIVERS drivers)
    // interface
                  (PHYSICAL_CHANNEL);
    
    method ActionValue#(UMF_CHUNK) read();
        
        drivers.unixPipeLIDriver.deq();
        UMF_PACKET_HEADER umf_header = unpack(drivers.unixPipeLIDriver.first);
        return drivers.unixPipeLIDriver.first;
        
    endmethod


    method deq = drivers.unixPipeLIDriver.deq;
    method first = drivers.unixPipeLIDriver.first;
    method write = drivers.unixPipeLIDriver.write;
    method write_ready = drivers.unixPipeLIDriver.write_ready;

endmodule
