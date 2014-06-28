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
import Clocks::*;
import ModuleContext::*;

`include "awb/provides/model.bsh"
`include "awb/provides/application_env.bsh"
`include "awb/provides/fpgaenv.bsh"
`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/clocks_device.bsh"

`include "awb/provides/soft_connections_alg.bsh" 
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_connections_debug.bsh"
`include "awb/provides/soft_connections_latency.bsh"
`include "awb/provides/physical_platform_utils.bsh" 
`include "awb/provides/physical_platform_defs.bsh" 

`ifndef INSTANTIATE_ROUTERS_Z
`include "awb/provides/multifpga_router_service.bsh"
`endif

//
// Optionally pass in a set of top-level clocks and a reset.
//
// mkModel has no default clocks.  For many platforms a true clock is
// synthesized from a differential pair of raw clocks, so there is no
// top-level clock that would make sense as a default.
//

module [Module] mkModel

    // interface:
    (TOP_LEVEL_WIRES);

    // Instantiate the soft-connected system with new clock and reset

    let sys <- mkClockedSystem();

    // return top level wires interface
    return sys;
endmodule


//
// mkClockedSystem --
//
// A wrapper which instantiates the clocked system.
//
module [Module] mkClockedSystem
    // interface:
        (TOP_LEVEL_WIRES);

    let int_ctx1 <- initializeServiceContext();

    // Set some initial context.
    match {.int_ctx2, .int_name2} <- runWithContext(int_ctx1, putSynthesisBoundaryPlatform(fpgaPlatformName()));
    match {.int_ctx3, .int_name3} <- runWithContext(int_ctx2, putSynthesisBoundaryPlatformID(fpgaPlatformID()));
    match {.int_ctx4, .int_name4} <- runWithContext(int_ctx3, putSynthesisBoundaryID(fpgaPlatformID()));
    match {.int_ctx5, .int_name5} <- runWithContext(int_ctx4, putSynthesisBoundaryName(fpgaPlatformName()));
    match {.int_ctx6, .int_name6} <- runWithContext(int_ctx5, putExposeAllConnections(`EXPOSE_ALL_CONNECTIONS == 1));

   // Instantiate the soft-connected system
    let sys <- instantiateWithConnections(mkConnectedSystem, tagged Valid int_ctx6);

    return sys;

endmodule


//
// mkConnectedSystem --
//
// A wrapper which instantiates the Soft Platform Interface and 
// the application.
//
module [SOFT_SERVICES_MODULE] mkConnectedSystem
    // interface:
        (TOP_LEVEL_WIRES);
    
    // By convention, global string ID 0 (the first string) is the module name
    let platform_name <- getSynthesisBoundaryPlatform();
    let model_name <- getGlobalStringUID(platform_name + ":model");

    //
    // Virtual platform is the first connection between the low level platform
    // and the application.  Elements in the virtual platform are often simple
    // and may either expose their interface through the VIRTUAL_PLATFORM or
    // through soft connections.
    //
    let vp <- instantiatePlatform();

    Clock clk = vp.physicalDrivers.clocksDriver.clock;
    Reset rst = vp.physicalDrivers.clocksDriver.reset;

`ifndef INSTANTIATE_ROUTERS_Z
    let routes <- mkMultifpgaRouterServices(vp, clocked_by clk, reset_by rst);
`endif

    //
    // Instantiate the application.
    //
    let app <- mkApplicationEnv(clocked_by clk, reset_by rst);

    //
    // Instantiate all subordinate synthesis boundaries.  The method is
    // generated by the build manager and included in the compilation
    // automatically.
    //
    let syn <- instantiateAllSynthBoundaries(clocked_by clk, reset_by rst);

    //
    // Final step: generate the debug logic for soft connections.  This call
    // must be triggered outside the internal soft connection code to avoid
    // a dependence loop.  The debug info call generates ring stops and the
    // ring stop code depends on soft connections.  If not for that dependence
    // we could push the call down into instantiateWithConnections().
    //
    let dbg <- mkSoftConnectionDebugInfo(clocked_by clk, reset_by rst);

    //
    // Call latency test generation for the same reasons listed above
    // 
    let lat <- mkSoftConnectionLatencyInfo(clocked_by clk, reset_by rst);

    return vp.topLevelWires;
endmodule
