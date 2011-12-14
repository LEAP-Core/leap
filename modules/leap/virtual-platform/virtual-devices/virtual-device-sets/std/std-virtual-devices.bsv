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
`include "awb/provides/shared_memory.bsh"
`include "asim/provides/local_memory_device.bsh"
`include "awb/provides/starter_device.bsh"
`include "awb/provides/common_utility_devices.bsh"
`include "awb/provides/soft_connections.bsh"

interface VIRTUAL_DEVICES;

    interface FRONT_PANEL frontPanel;
    interface SHARED_MEMORY sharedMemory;
    interface STARTER starter;
    interface COMMON_UTILITY_DEVICES commonUtilities;

endinterface

module [CONNECTED_MODULE] mkVirtualDevices#(LowLevelPlatformInterface llpint)
    // interface:
        (VIRTUAL_DEVICES);

    let fp  <- mkFrontPanel(llpint);
    // TODO: use the new Stats device for real stats
    let sh  <- mkSharedMemory(llpint);

    // mkLocalMemory() exports only soft connections, so will not be returned
    // as part of the VIRTUAL_DEVICES interface.
    let lm  <- mkLocalMemory(llpint);

    let st  <- mkStarter(llpint);
    let com <- mkCommonUtilityDevices(llpint);

    interface frontPanel = fp;
    interface sharedMemory = sh;
    interface starter = st;
    interface commonUtilities = com;

endmodule
