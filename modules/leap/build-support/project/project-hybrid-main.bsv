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

`include "asim/provides/model.bsh"
`include "asim/provides/application_env.bsh"
`include "asim/provides/fpgaenv.bsh"
`include "asim/provides/virtual_platform.bsh"
`include "asim/provides/low_level_platform_interface.bsh"
`include "asim/provides/physical_platform.bsh"
`include "asim/provides/clocks_device.bsh"

module [Module] mkModel
    // interface:
        (TOP_LEVEL_WIRES);

    // The Model is instantiated inside a NULL (noClock) clock domain,
    // so first instantiate the LLPI and get a clock and reset from it.

    // name must be pi_llpint --- explain!!!
    VIRTUAL_PLATFORM vp <- mkVirtualPlatform();

    Clock clk = vp.llpint.physicalDrivers.clocksDriver.clock;
    Reset rst = vp.llpint.physicalDrivers.clocksDriver.reset;
    
    // instantiate application environment with new clock and reset
    let appEnv <- mkApplicationEnv(vp, clocked_by clk, reset_by rst);
    
    // return top level wires interface
    return vp.llpint.topLevelWires;

endmodule
