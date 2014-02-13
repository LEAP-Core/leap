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

#ifndef __SHARED_MEMORY_SERVER__
#define __SHARED_MEMORY_SERVER__

#include <map>

#include "awb/provides/rrr.h"

// Page Table entry

typedef map <UINT64, UINT64> PAGE_TABLE;

// Shared Memory software server

typedef class SHARED_MEMORY_SERVER_CLASS* SHARED_MEMORY_SERVER;
class SHARED_MEMORY_SERVER_CLASS: public RRR_SERVER_CLASS,
                                  public PLATFORMS_MODULE_CLASS
{
  private:

    // self-instantiation
    static SHARED_MEMORY_SERVER_CLASS instance;
    
    // stubs
    RRR_SERVER_STUB serverStub;

    // page table
    // PAGE_TABLE pageTable;
    UINT64 theOnlyPhysicalAddress;

  public:

    SHARED_MEMORY_SERVER_CLASS();
    ~SHARED_MEMORY_SERVER_CLASS();
    
    static SHARED_MEMORY_SERVER GetInstance() { return &instance; }

    // methods exposed to software client

    void UpdateTranslation(UINT64 va, UINT64 pa);
    void InvalidateTranslation(UINT64 va);

    // standard infrastructure methods

    void Init(PLATFORMS_MODULE);
    void Uninit();
    void Cleanup();

    // RRR methods

    UINT64 GetTranslation(UINT8 dummy);
};

#include "awb/rrr/server_stub_SHARED_MEMORY.h"

#endif
