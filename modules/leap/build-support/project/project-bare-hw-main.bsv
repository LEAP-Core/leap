//
// Copyright (C) 2012 Massachusetts Institute of Technology
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

//
// A very simple bare model for fast Bluesim-only builds.  Soft service stubs
// are present so that modules claiming to use soft services will compile
// (i.e. declared with the CONNECTED_MODULE ModuleContext).  Soft connections
// will not actually be connected.
//

import Clocks::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/hardware_system.bsh"

module [Module] mkModel
    // interface:
        (TOP_LEVEL_WIRES);

    // The Model is instantiated inside a NULL (noClock) clock domain,
    // so first instantiate a clock and reset.
    Clock clk <- mkAbsoluteClock(0, 100);
    Reset rst <- mkInitialReset(10, clocked_by clk);

    // Instantiate the system with new clock and reset
    let sys <- mkClockedSystem( clocked_by clk, reset_by rst);

endmodule


//
// mkClockedSystem --
//
// A wrapper which instantiates the clocked system.
//
module [Module] mkClockedSystem
    // interface:
        ();
    
    // Instantiate a dummy soft connections environment and invoke the system.
    match {.final_ctx, .m_final} <- runWithContext(?, mkConnectedSystem);

endmodule


//
// mkConnectedSystem --
//
// A wrapper which instantiates the Soft Platform Interface and 
// the application.
//
module [SOFT_SERVICES_MODULE] mkConnectedSystem
    // interface:
        ();
    
    let sys <- mkSystem();

endmodule
