/*****************************************************************************
 * std-virtual-platform.h
 *
 * Copyright (C) 2008 Intel Corporation
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

/**
 * @file std-virtual-platform.bsv
 * @author Michael Pellauer
 * @brief Standard virtual platform interface
 */

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/physical_platform_utils.bsh"
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/clocks_device.bsh"

`include "awb/rrr/server_connections.bsh"
`include "awb/rrr/client_connections.bsh"

interface VIRTUAL_PLATFORM;

    interface LowLevelPlatformInterface llpint;
    interface VIRTUAL_DEVICES virtualDevices;

endinterface

module [CONNECTED_MODULE] mkVirtualPlatform#(LowLevelPlatformInterface llpi)
    // interface:
        (VIRTUAL_PLATFORM);

    let vdevs  <- mkVirtualDevices(llpi);
    
    //
    // auto-generated submodules for RRR connections.  Export them as soft
    // connections, but only on the master FPGA.
    //
    if (fpgaPlatformID() == 0)
    begin
        let rrrServerLinks <- mkServerConnections(llpi.rrrServer);
        let rrrClientLinks <- mkClientConnections(llpi.rrrClient);
    end

    interface llpint = llpi;
    interface virtualDevices = vdevs;

endmodule
