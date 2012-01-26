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

`include "awb/provides/low_level_platform_interface.bsh"

// Starter
interface STARTER;

    // server methods
    method Action acceptRequest_Start();

    // client methods
    method Action makeRequest_End(Bit#(8) exit_code);
    
    //
    // FPGA Heartbeat --
    //   Message the number of FPGA cycles passed.
    //   Useful for detecting deadlocks.
    //
    method Action makeRequest_Heartbeat(Bit#(64) fpga_cycles);

endinterface

// mkStarter
module mkStarter#(LowLevelPlatformInterface llpi)
    // interface:
        (STARTER);
    // ----------- server methods ------------

    // Run
    method Action acceptRequest_Start ();
    endmethod

    // ------------ client methods ------------

    // signal end of simulation
    method Action makeRequest_End(Bit#(8) exit_code);
    endmethod

    // Heartbeat
    method Action makeRequest_Heartbeat(Bit#(64) fpga_cycles);
    endmethod

endmodule
