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

//
// @file std-virtual-platform.bsv
// @author Michael Pellauer
// @brief Standard virtual platform interface
//

import Vector::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/platform_services.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/clocks_device.bsh"
`include "awb/provides/platform_services.bsh"

// pick up definition of INSTANTIATE_ROUTERS_Z
`include "awb/provides/model_params.bsh"
`ifndef INSTANTIATE_ROUTERS_Z
`include "multifpga_routing.bsh"
`endif

`include "awb/rrr/server_connections.bsh"
`include "awb/rrr/client_connections.bsh"

interface VIRTUAL_PLATFORM;

    interface PHYSICAL_DRIVERS          physicalDrivers;
    interface TOP_LEVEL_WIRES           topLevelWires;
    
endinterface


// Helper function used to extract clock and reset from virtual platform.
// Ultimately this function will not be needed, since it should be possible
// to derive clock and reset from those interfaces which use them. 
function Tuple2#(Clock, Reset) extractClocks(VIRTUAL_PLATFORM vp);
    return tuple2(vp.physicalDrivers.clocksDriver.clock, vp.physicalDrivers.clocksDriver.reset);
endfunction

module [CONNECTED_MODULE] mkVirtualPlatform
    // interface:
        (VIRTUAL_PLATFORM);

    let llpi <- mkLowLevelPlatformInterface();

    Clock clk = llpi.physicalDrivers.clocksDriver.clock;
    Reset rst = llpi.physicalDrivers.clocksDriver.reset;

    let vdevs  <- mkVirtualDevices(llpi, clocked_by clk, reset_by rst);

    //
    // Platform services are layered on the virtual platform.  These services
    // are typically device independent and must expose their interfaces as
    // soft connections.
    //
    let spi <- mkPlatformServices(clocked_by clk, reset_by rst);

    let platformID <- getSynthesisBoundaryPlatformID();
    //
    // auto-generated submodules for RRR connections.  Export them as soft
    // connections, but only on the master FPGA.
    //
    if(platformID == 0)
    begin
        let rrrServerLinks <- mkServerConnections(llpi.rrrServer, clocked_by clk, reset_by rst);
        let rrrClientLinks <- mkClientConnections(llpi.rrrClient, clocked_by clk, reset_by rst);
    end



    // We use a hackish means of obtaining information about the width of 
    // the platform interconnects -- we generate a stub router service which 
    // exports them.  Virtual platforms instantiate this stub service so
    // that the lim compilation gets the information. No hardware is instantiated.
`ifndef INSTANTIATE_ROUTERS_Z
    let routes <-  mkCommunicationModule(llpi.physicalDrivers, clocked_by clk, reset_by rst);
`endif


    interface physicalDrivers = llpi.physicalDrivers;
    interface topLevelWires = llpi.topLevelWires;

endmodule
