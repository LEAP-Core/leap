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

import Vector::*;

`include "awb/provides/rrr.bsh"
`include "awb/provides/channelio.bsh"
`include "awb/provides/remote_memory.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/physical_platform_debugger.bsh"
`include "awb/provides/clocks_device.bsh"
`include "awb/provides/umf.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_connections.bsh"

//
// LowLevelPlatformInterface.
//
// A convenient bundle of all ways to interact with the outside world.
//
interface LowLevelPlatformInterface;
    interface RRR_CLIENT                rrrClient;
    interface RRR_SERVER                rrrServer;
    interface CHANNEL_IO#(UMF_PACKET)   channelIO;
    interface REMOTE_MEMORY             remoteMemory;
    interface PHYSICAL_DRIVERS          physicalDrivers;
    interface TOP_LEVEL_WIRES           topLevelWires;
endinterface

//
// mkLowLevelPlatformInterface
//
// Instantiate the subcomponents in one module.
//
module [CONNECTED_MODULE] mkLowLevelPlatformInterface
    // Interface:
    (LowLevelPlatformInterface);

    // instantiate physical platform
    
    PHYSICAL_PLATFORM phys_plat <- mkPhysicalPlatform();
    
    // LLPI is instantiated in a NULL clock domain, so first get some clocks
    // from the physical platform, which we'll pass down into the debugger
    // and virtual platform
    
    Clock clk = phys_plat.physicalDrivers.clocksDriver.clock;
    Reset rst = phys_plat.physicalDrivers.clocksDriver.reset;
    
    // instantiate physical platform debugger and obtain gated drivers from it
    PHYSICAL_DRIVERS  drivers   <- mkPhysicalPlatformDebugger(phys_plat.physicalDrivers, clocked_by clk, reset_by rst);
    
    // interfaces to the physical platform
    REMOTE_MEMORY remMem <- mkRemoteMemory(drivers, clocked_by clk, reset_by rst);
    CHANNEL_IO#(UMF_PACKET)    cio    <- mkChannelIO(drivers, clocked_by clk, reset_by rst);

    // RRR
    RRR_CLIENT rrrc <- mkRRRClient(cio, clocked_by clk, reset_by rst);
    RRR_SERVER rrrs <- mkRRRServer(cio, clocked_by clk, reset_by rst);

    // plumb interfaces

    interface rrrClient        = rrrc;
    interface rrrServer        = rrrs;
    interface channelIO        = cio;
    interface remoteMemory     = remMem;
    interface physicalDrivers  = drivers;
    interface topLevelWires    = phys_plat.topLevelWires;
endmodule
