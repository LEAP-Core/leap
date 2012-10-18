//
// Copyright (C) 2010 Intel Corporation
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
