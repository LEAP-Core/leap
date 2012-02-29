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
`include "awb/provides/front_panel.bsh"
`include "awb/provides/starter_device.bsh"

interface VIRTUAL_DEVICES;

    interface FRONT_PANEL frontPanel;
    interface STARTER starter;

endinterface

module mkVirtualDevices#(LowLevelPlatformInterface llpint)
    // interface:
        (VIRTUAL_DEVICES);

    let fp  <- mkFrontPanel(llpint);
    // TODO: use the new Stats device for real stats
    let st  <- mkStarter(llpint);

    interface frontPanel = fp;
    interface starter = st;

endmodule
