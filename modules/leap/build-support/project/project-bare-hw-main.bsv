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
