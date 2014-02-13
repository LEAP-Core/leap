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

/**
 * @file std-virtual-devices.h
 * @author Michael Adler
 * @brief Standard virtual devices
 */

#ifndef __STD_VIRTUAL_DEVICES_h__
#define __STD_VIRTUAL_DEVICES_h__

#include <pthread.h>

#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/starter_device.h"
#include "awb/provides/common_utility_devices.h"
#include "awb/provides/common_services.h"

typedef class VIRTUAL_DEVICES_CLASS *VIRTUAL_DEVICES;

class VIRTUAL_DEVICES_CLASS
{
  private:
    COMMON_UTILITY_DEVICES commonUtilities;
    COMMON_SERVICES commonServices;

  public:
    VIRTUAL_DEVICES_CLASS(LLPI llpint);
    ~VIRTUAL_DEVICES_CLASS();
    void Init();
};

#endif // __STD_VIRTUAL_DEVICES_h__
