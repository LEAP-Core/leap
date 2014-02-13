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

#ifndef __SHARED_MEMORY__
#define __SHARED_MEMORY__

#include "platforms-module.h"
#include "awb/provides/low_level_platform_interface.h"

#include "awb/rrr/client_stub_SHARED_MEMORY.h"

typedef UINT64 SHARED_MEMORY_DATA;

typedef class SHARED_MEMORY_CLASS* SHARED_MEMORY;
class SHARED_MEMORY_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:

    SHARED_MEMORY_CLIENT_STUB clientStub;    

    // link to remote memory device
    REMOTE_MEMORY remoteMemory;

  public:

    SHARED_MEMORY_CLASS(PLATFORMS_MODULE p, LLPI llpi);
    ~SHARED_MEMORY_CLASS();

    // standard infrastructure methods
    void Cleanup();

    // get pointer to shared region
    SHARED_MEMORY_DATA* Allocate();
    void DeAllocate(SHARED_MEMORY_DATA* mem);
};

#endif
