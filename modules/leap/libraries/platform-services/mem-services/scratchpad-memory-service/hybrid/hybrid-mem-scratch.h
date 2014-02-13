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

#ifndef __HYBRID_SCRATCHPAD_MEMORY__
#define __HYBRID_SCRATCHPAD_MEMORY__

#include "asim/syntax.h"
#include "asim/mesg.h"
#include "asim/trace.h"

#ifdef PSEUDO_DMA_ENABLED
    #include "awb/provides/physical_channel.h"
#endif

#include "awb/provides/soft_services_deps.h"
#include "awb/provides/rrr.h"
#include "awb/dict/VDEV.h"

#include "awb/rrr/client_stub_SCRATCHPAD_MEMORY.h"

// Get the data types from the scratchpad RRR definition
#define TYPES_ONLY
#include "awb/rrr/server_stub_SCRATCHPAD_MEMORY.h"
#undef TYPES_ONLY

// This hack deals with the case that no scratchpad regions are defined...
#ifndef __VDEV_SCRATCH_DICT_H__
#define VDEV_SCRATCH__NENTRIES 0
#endif

#define SCRATCHPAD_WORDS_PER_LINE 4

typedef UINT64 SCRATCHPAD_MEMORY_ADDR;
typedef UINT64 SCRATCHPAD_MEMORY_WORD;

typedef class SCRATCHPAD_MEMORY_SERVER_CLASS* SCRATCHPAD_MEMORY_SERVER;

class SCRATCHPAD_MEMORY_SERVER_CLASS: public RRR_SERVER_CLASS,
                                      public PLATFORMS_MODULE_CLASS,
                                      public TRACEABLE_CLASS
{
  public:

    // self-instantiation
    static SCRATCHPAD_MEMORY_SERVER_CLASS instance;

  private:

    // stubs
    RRR_SERVER_STUB serverStub;

    // internal data
    SCRATCHPAD_MEMORY_WORD *regionBase[VDEV_SCRATCH__NENTRIES + 1];
    SCRATCHPAD_MEMORY_ADDR regionWords[VDEV_SCRATCH__NENTRIES + 1];
    size_t regionSize[VDEV_SCRATCH__NENTRIES + 1];

    Format fmt_addr;
    Format fmt_mask;
    Format fmt_data;

    // internal methods
    UINT32 nRegions() const { return VDEV_SCRATCH__NENTRIES; };

    // Compute region ID given an incoming address
    UINT32 regionID(UINT64 addr) const { return addr >> SCRATCHPAD_MEMORY_ADDR_BITS; };

    // Compute region word offset given an incoming address
    SCRATCHPAD_MEMORY_ADDR regionOffset(UINT64 addr)
    {
        // Get just the region address bits (drop the region ID)
        return addr & ((SCRATCHPAD_MEMORY_ADDR(1) << SCRATCHPAD_MEMORY_ADDR_BITS) - 1);
    };

    UINT64 FullByteMask(UINT64 mask);

  public:

    SCRATCHPAD_MEMORY_SERVER_CLASS();
    ~SCRATCHPAD_MEMORY_SERVER_CLASS();

    // generic RRR methods
    void   Init(PLATFORMS_MODULE);
    void   Uninit();
    void   Cleanup();

    bool   IsTracing(int level);

    // RRR request methods
    void InitRegion(UINT32 regionID,
                    UINT64 regionEndIdx,
                    GLOBAL_STRING_UID initFilePath);

    void *GetMemPtr(SCRATCHPAD_MEMORY_ADDR addr);

    OUT_TYPE_LoadLine LoadLine(SCRATCHPAD_MEMORY_ADDR addr);

    void StoreLine(UINT64 byteMask,
                   SCRATCHPAD_MEMORY_ADDR addr,
                   SCRATCHPAD_MEMORY_WORD data3,
                   SCRATCHPAD_MEMORY_WORD data2,
                   SCRATCHPAD_MEMORY_WORD data1,
                   SCRATCHPAD_MEMORY_WORD data0);

    void StoreWord(UINT64 byteMask,
                   SCRATCHPAD_MEMORY_ADDR addr,
                   SCRATCHPAD_MEMORY_WORD data);

    void StoreLineUnmasked(SCRATCHPAD_MEMORY_ADDR addr,
                           const SCRATCHPAD_MEMORY_WORD *data);
};

// Now that the server class is defined the RRR wrapper can be loaded.
#include "awb/rrr/server_stub_SCRATCHPAD_MEMORY.h"

#endif
