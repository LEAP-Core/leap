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

//=============================================================================
// Filename      : pcie-passthough-physical-channel.bsv
// Brief         : physical channel between channel IO and PCIe device
// Author        : rfadeev
// Mailto        : roman.fadeev@intel.com
// Description   : This module implements bypass calling of methods: calling of
//                 read/write methods of PHYSICAL_CHANNEL interface will call
//                 read/write methods of PCIE_DRIVER interface respectively.
//=============================================================================

//=============================================================================
// Notes :
// Revision history :
//=============================================================================


`include "physical_platform.bsh"
`include "pcie_device.bsh"
`include "umf.bsh"


//=============================================================================
// Interfaces
//=============================================================================

interface PHYSICAL_CHANNEL;

    method ActionValue#(UMF_CHUNK) read();
    method Action                  write(UMF_CHUNK chunk);

endinterface

//=============================================================================
// Modules
//=============================================================================

module mkPhysicalChannel#(PHYSICAL_DRIVERS drivers)(PHYSICAL_CHANNEL);

    PCIE_DRIVER pcieDriver = drivers.pcieDriver;

    let initialized = True;

    method ActionValue#(UMF_CHUNK) read() if (initialized);
        let x <- pcieDriver.read();
        return x;
    endmethod

    method Action write(UMF_CHUNK x) if (initialized);
        pcieDriver.write(x);
    endmethod

endmodule
