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
`include "awb/provides/physical_platform_utils.bsh"

`include "awb/provides/streams_device.bsh"
`include "awb/provides/dynamic_parameters_device.bsh"
`include "awb/provides/assertions_device.bsh"
`include "awb/provides/stats_device.bsh"

// A set of useful IO services.

interface COMMON_UTILITY_DEVICES;

    interface STREAMS streams;
    interface DYNAMIC_PARAMETERS dynamicParameters;
    interface ASSERTIONS assertions;
    interface STATS stats;

endinterface

//
// mkCommonUtilityDevices --
//
// Instantiate useful IO utilities
//

module mkCommonUtilityDevices#(LowLevelPlatformInterface llpi)
    // interface:
    (COMMON_UTILITY_DEVICES);

    STREAMS str = ?;
    DYNAMIC_PARAMETERS dp = ?;
    ASSERTIONS as = ?;
    STATS st = ?;

    //
    // Normal (master) platform and services are on platform ID 0.  Slaves are
    // on non-zero platform IDs.  Slave (multi-FPGA) platforms need the
    // definitions of the client connections to the services but don't
    // instantiate the services.  These are all rings, with the primary node
    // on the master FPGA.
    //
    if (fpgaPlatformID() == 0)
    begin
        //
        // Normal (master) platform and services.
        //
        str <- mkStreamsDevice(llpi);
        dp  <- mkDynamicParametersDevice(llpi);
        as  <- mkAssertionsDevice(llpi);
        st  <- mkStatsDevice(llpi);
    end

    interface streams = str;
    interface dynamicParameters = dp;
    interface assertions = as;
    interface stats = st;

endmodule
