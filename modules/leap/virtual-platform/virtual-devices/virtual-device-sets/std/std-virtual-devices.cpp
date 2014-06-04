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
 * @file std-virtual-devices.cpp
 * @author Michael Adler
 * @brief Standard virtual devices
 */
 
#include "asim/syntax.h"
#include "awb/provides/virtual_devices.h"
#include "awb/provides/starter_service.h"

VIRTUAL_DEVICES_CLASS::VIRTUAL_DEVICES_CLASS(LLPI llpi) :
    commonUtilities(new COMMON_UTILITY_DEVICES_CLASS()),
    commonServices(new COMMON_SERVICES_CLASS())
{
    return;
}

VIRTUAL_DEVICES_CLASS::~VIRTUAL_DEVICES_CLASS()
{
}

void
VIRTUAL_DEVICES_CLASS::Init()
{
    // Temporary hack to eliminate ACP startup hangs in multi-FPGA models until
    // we figure out the source of the hang.
    sleep(1);

    // Init our children.
    commonUtilities->Init();
    commonServices->Init();

    // Tell the HW to start running via the Starter.
    STARTER_SERVICE_CLASS::GetInstance()->Start();
}
