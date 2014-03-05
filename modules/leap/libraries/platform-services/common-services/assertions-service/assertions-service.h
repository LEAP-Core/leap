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

#include <stdio.h>

#include "tbb/atomic.h"

#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/rrr.h"

// this module handles reporting assertion failures.

typedef class ASSERTIONS_SERVER_CLASS* ASSERTIONS_SERVER;
class ASSERTIONS_SERVER_CLASS: public RRR_SERVER_CLASS,
                     public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static ASSERTIONS_SERVER_CLASS instance;
    
    // stubs
    RRR_SERVER_STUB serverStub;

    class tbb::atomic<bool> uninitialized;

    // File for output until we use DRAL.
    FILE* assertionsFile;

  public:
    ASSERTIONS_SERVER_CLASS();
    ~ASSERTIONS_SERVER_CLASS();
    
    // static methods
    static ASSERTIONS_SERVER GetInstance() { return &instance; }
    
    // required RRR methods
    void Init(PLATFORMS_MODULE);
    void Uninit();

    // RRR service methods
    void AssertStr(UINT64 fpgaCC, UINT32 strUID, UINT8 severity);
    void AssertDict(UINT64 fpgaCC, UINT32 assertBase, UINT32 assertions);
};

// server stub
#include "awb/rrr/server_stub_ASSERTIONS.h"

// all functionalities of the assertions io are completely implemented
// by the ASSERTIONS_SERVER class
typedef ASSERTIONS_SERVER_CLASS ASSERTIONS_DEVICE_CLASS;
