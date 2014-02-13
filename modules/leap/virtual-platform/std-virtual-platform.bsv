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
