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

`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/physical_platform_utils.bsh"

`include "awb/provides/front_panel.bsh"
`include "asim/provides/local_memory_device.bsh"
`include "awb/provides/starter_device.bsh"
`include "awb/provides/soft_connections.bsh"

interface VIRTUAL_DEVICES;

    interface FRONT_PANEL frontPanel;
    interface STARTER starter;

endinterface

module [CONNECTED_MODULE] mkVirtualDevices#(LowLevelPlatformInterface llpint)
    // interface:
        (VIRTUAL_DEVICES);

    FRONT_PANEL fp = ?;
    STARTER st = ?;
 
    let platformID <- getSynthesisBoundaryPlatformID();
    
    //
    // Normal (master) platform and services are on platform ID 0.  Slaves are
    // on non-zero platform IDs.  Slave (multi-FPGA) platforms need the
    // definitions of the client connections to the services but don't
    // instantiate the services.  These are all rings, with the primary node
    // on the master FPGA.
    //
    if (platformID == 0)
    begin
        fp <- mkFrontPanel(llpint);
        st <- mkStarter(llpint);
    end

    // mkLocalMemory() exports only soft connections, so will not be returned
    // as part of the VIRTUAL_DEVICES interface.
    let lm  <- mkLocalMemory(llpint);

    interface frontPanel = fp;
    interface starter = st;

endmodule
