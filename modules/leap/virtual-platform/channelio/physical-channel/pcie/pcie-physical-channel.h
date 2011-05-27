////////////////////////////////////////////////////////////////////////////////
// Filename      : pcie-physical-channel.h
// Brief         : physical channel between channel IO and PCIe device
// Author        : rfadeev
// Mailto        : roman.fadeev@intel.com
//
// Copyright (C) 2010 Intel Corporation
// THIS PROGRAM IS AN UNPUBLISHED WORK FULLY PROTECTED BY COPYRIGHT LAWS AND
// IS CONSIDERED A TRADE SECRET BELONGING TO THE INTEL CORPORATION.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Description   : IMPORTANT! It's just stub for correct hasim model build flow
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Notes :
// Revision history :
////////////////////////////////////////////////////////////////////////////////

#ifndef __PHYSICAL_CHANNEL__
#define __PHYSICAL_CHANNEL__

#include <stdio.h>

#include "asim/provides/umf.h"
#include "asim/provides/physical_platform.h"


// ============================================
//               Physical Channel
// ============================================

class PHYSICAL_CHANNEL_CLASS: public PLATFORMS_MODULE_CLASS
{

  private:

  public:

    PHYSICAL_CHANNEL_CLASS(PLATFORMS_MODULE, PHYSICAL_DEVICES);
    ~PHYSICAL_CHANNEL_CLASS();

    UMF_MESSAGE Read();
    UMF_MESSAGE TryRead();
    void        Write(UMF_MESSAGE);
};

#endif
