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

import ModuleContext::*;

`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/soft_connections_alg.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/platform_services.bsh"
`include "awb/provides/connected_application.bsh"

// mkWrappedApplication

// A wrapper which instantiates the Soft Platform Interface and 
// the application. All soft connections are connected above.

module [SOFT_SERVICES_MODULE] mkWrappedApplication#(VIRTUAL_PLATFORM vp)
    // interface:
        ();
    
    let spi <- mkPlatformServices(vp);
    let app <- mkConnectedApplication();

endmodule

// mkApplicationEnv

// The actual application env instantiates the wrapper.

module [Module] mkApplicationEnv#(VIRTUAL_PLATFORM vp)
    // interface:
        ();
    
    // Instantiate the wrapper and connect all soft connections.
    // Dangling connections are errors.
    instantiateWithConnections(mkWrappedApplication(vp));

endmodule
