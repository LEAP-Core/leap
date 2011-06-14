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

////////////////////////////////////////////////////////////////////////////////
// Filename      : pcie-passthrough-physical-channel.h
// Brief         : physical channel between channel IO and PCIe device
// Author        : rfadeev
// Mailto        : roman.fadeev@intel.com

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
