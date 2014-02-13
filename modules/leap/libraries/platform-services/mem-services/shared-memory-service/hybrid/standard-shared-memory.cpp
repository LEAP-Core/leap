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

#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <sys/mman.h>

#include "awb/rrr/service_ids.h"
#include "awb/provides/command_switches.h"
#include "asim/ioformat.h"

#include "awb/provides/shared_memory.h"

using namespace std;

#define PAGE_OFFSET_BITS 12

// constructor
SHARED_MEMORY_CLASS::SHARED_MEMORY_CLASS(
    PLATFORMS_MODULE p,
    LLPI             llpi) :
        PLATFORMS_MODULE_CLASS(p)
{
    // instantiate stubs
    clientStub = new SHARED_MEMORY_CLIENT_STUB_CLASS(this);

    // store useful links from LLPI
    remoteMemory = llpi->GetRemoteMemory();
}

// destructor
SHARED_MEMORY_CLASS::~SHARED_MEMORY_CLASS()
{
    Cleanup();
}

// cleanup
void
SHARED_MEMORY_CLASS::Cleanup()
{
    delete clientStub;
}

// allocate a new shared memory region
SHARED_MEMORY_DATA*
SHARED_MEMORY_CLASS::Allocate()
{
    // allocate a page-sized, page-aligned region
    SHARED_MEMORY_DATA* mem;

    // find out system's page size
    UINT32 page_size = getpagesize();

    // sanity check for page size
    if (page_size != (UINT32(0x01) << PAGE_OFFSET_BITS))
    {
        ASIMERROR("page size mismatch");
        CallbackExit(1);
    }
 
    if (posix_memalign((void **)&mem, page_size, page_size) != 0)
    {
        perror("posix_memalign");
        CallbackExit(1);
    }

    // zero it out
    bzero((void *)mem, page_size);    

    // lock it down and get its physical address
    UINT64 pa = remoteMemory->TranslateAndLock((unsigned char *)mem, page_size);

    // update translation table that lives in software-side server
    SHARED_MEMORY_SERVER_CLASS::GetInstance()->UpdateTranslation(UINT64(mem), pa);

    // update translation in hardware
    UINT8 ack = clientStub->UpdateTranslation(pa);

    // TODO: we probably need more book-keeping

    return mem;
}

// de-allocate a previously-allocated region
void
SHARED_MEMORY_CLASS::DeAllocate(
    SHARED_MEMORY_DATA* mem)
{
    // TODO: book-keeping

/*    
    // ask server if this page is mapped

    // ask remote memory to unlock pages
    vector <REMOTE_MEMORY_PHYSICAL_ADDRESS> pa_vec;
    pa_vec[0] = REMOTE_MEMORY_PHYSICAL_ADDRESS(pa);
    remoteMemory->Unlock(&pa_vec);
*/

    // invalidate translation table (that lives in software-side server)
    SHARED_MEMORY_SERVER_CLASS::GetInstance()->InvalidateTranslation(UINT64(mem));

    // TODO: add RRR call to hardware to invalidate translation

    // free
    free(mem);
}
