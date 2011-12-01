//
// Copyright (C) 2009 Massachusetts Institute of Technology
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

import Clocks::*;

`include "awb/provides/model.bsh"
`include "awb/provides/application_env.bsh"
`include "awb/provides/fpgaenv.bsh"
`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/clocks_device.bsh"

`include "awb/provides/soft_connections_alg.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/platform_services.bsh"

module [Module] mkModel
    // interface:
        (TOP_LEVEL_WIRES);

    // The Model is instantiated inside a NULL (noClock) clock domain,
    // so first instantiate the LLPI and get a clock and reset from it.

    VIRTUAL_PLATFORM vp <- mkVirtualPlatform();

    Clock clk = vp.llpint.physicalDrivers.clocksDriver.clock;
    Reset rst = vp.llpint.physicalDrivers.clocksDriver.reset;
    
    // Instantiate the soft-connected system with new clock and reset
    let sys <- mkClockedSystem(vp, clocked_by clk, reset_by rst);
    
    // return top level wires interface
    return vp.llpint.topLevelWires;

endmodule


//
// mkClockedSystem --
//
// A wrapper which instantiates the clocked system.
//
module [Module] mkClockedSystem#(VIRTUAL_PLATFORM vp)
    // interface:
        ();
    
    // Instantiate the soft-connected system
    instantiateWithConnections(mkConnectedSystem(vp));

endmodule


//
// mkConnectedSystem --
//
// A wrapper which instantiates the Soft Platform Interface and 
// the application.
//
module [SOFT_SERVICES_MODULE] mkConnectedSystem#(VIRTUAL_PLATFORM vp)
    // interface:
        ();
    
    // Platform services are the exposed soft connections from the LEAP
    // virtual services.  They must be instantiated within the soft-connected
    // domain.
    let spi <- mkPlatformServices(vp);

    let app <- mkApplicationEnv(vp);

endmodule
