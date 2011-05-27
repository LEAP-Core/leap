////////////////////////////////////////////////////////////////////////////////
// Filename      : pcie-physical-channel.bsv
// Brief         : physical channel between channel IO and PCIe device
// Author        : rfadeev
// Mailto        : roman.fadeev@intel.com
//
// Copyright (C) 2010 Intel Corporation
// THIS PROGRAM IS AN UNPUBLISHED WORK FULLY PROTECTED BY COPYRIGHT LAWS AND
// IS CONSIDERED A TRADE SECRET BELONGING TO THE INTEL CORPORATION.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Description   : This module implements bypass calling of methods: calling of
//                 read/write methods of PHYSICAL_CHANNEL interface will call
//                 read/write methods of PCIE_DRIVER interface respectively.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Notes :
// Revision history :
////////////////////////////////////////////////////////////////////////////////


`include "physical_platform.bsh"
`include "pcie_device.bsh"
`include "umf.bsh"


////////////////////////////////////////////////////////////////////////////////
/// Interfaces
////////////////////////////////////////////////////////////////////////////////

interface PHYSICAL_CHANNEL;

    method ActionValue#(UMF_CHUNK) read();
    method Action                  write(UMF_CHUNK chunk);

endinterface

////////////////////////////////////////////////////////////////////////////////
/// Modules
////////////////////////////////////////////////////////////////////////////////

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
