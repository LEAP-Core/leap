//
// Copyright (C) 2008 Massachusetts Institute of Technology
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

`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/rrr.bsh"

`include "awb/provides/soft_connections.bsh"

`include "awb/provides/front_panel_service.bsh"
`include "awb/provides/starter_service.bsh"
`include "awb/provides/mem_services.bsh"
`include "awb/provides/common_services.bsh"

`include "awb/provides/aurora_service.bsh"

//
// mkPlatformInterface: Wrap the LLPI and virtual devices in soft connections.
//

module [CONNECTED_MODULE] mkPlatformServices#(VIRTUAL_PLATFORM virtualPlatform)
    // interface
        ();

    // Get a link to the LLPI.
    VIRTUAL_DEVICES vdevs = virtualPlatform.virtualDevices;

		let physicalDrivers = virtualPlatform.llpint.physicalDrivers;
		let auroraService <- mkAuroraService(physicalDrivers);

    // Instantiate soft interfaces to the virtual devices
    let starterService  <- mkStarterService(vdevs);
    let fpService       <- mkFrontPanelService(vdevs);
    let memServices     <- mkMemServices();
    let commonServices  <- mkCommonServices();

endmodule

/*

*/
