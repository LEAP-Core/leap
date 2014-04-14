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

//
// Scratchpad memory.
//
// This service manages multiple, independent, scratchpad memory regions.
// All storage is accessed as fixed-size chunks.  The clients are responsible
// for mapping the fixed-size chunks to their own data structures.
//

#include <stdio.h>
#include <unistd.h>
#include <strings.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <error.h>

#include "awb/provides/model.h"
#include "awb/provides/scratchpad_memory.h"
#include "awb/rrr/service_ids.h"

// service instantiation
SCRATCHPAD_MEMORY_SERVER_CLASS SCRATCHPAD_MEMORY_SERVER_CLASS::instance;

#ifdef PSEUDO_DMA_ENABLED

static bool PseudoDMA(
    int methodID,
    int length,
    const void *msg,
    NALLATECH_EDGE_PHYSICAL_CHANNEL_CLASS::PSEUDO_DMA_READ_RESP &resp);

#endif

// constructor
SCRATCHPAD_MEMORY_SERVER_CLASS::SCRATCHPAD_MEMORY_SERVER_CLASS()
{
    SetTraceableName("scratchpad_memory");

    // instantiate stubs
    serverStub = new SCRATCHPAD_MEMORY_SERVER_STUB_CLASS(this);

    for (UINT32 r = 0; r < nRegions(); r++)
    {
        regionBase[r] = NULL;
        regionWords[r] = 0;
        regionSize[r] = 0;
    }

    char fmt[16];

    sprintf(fmt, "0%dx", sizeof(SCRATCHPAD_MEMORY_ADDR) * 2);
    fmt_addr = Format("0x", fmt);

    fmt_mask = fmt_addr;

    sprintf(fmt, "0%dx", sizeof(SCRATCHPAD_MEMORY_WORD) * 2);
    fmt_data = Format("0x", fmt);

#ifdef PSEUDO_DMA_ENABLED
    NALLATECH_EDGE_PHYSICAL_CHANNEL_CLASS::RegisterPseudoDMAHandler(0,
                                                                    SCRATCHPAD_MEMORY_SERVICE_ID,
                                                                    &PseudoDMA);
#endif
}

// destructor
SCRATCHPAD_MEMORY_SERVER_CLASS::~SCRATCHPAD_MEMORY_SERVER_CLASS()
{
    //
    // Unmap all the scratchpad regions.
    //
    for (UINT32 r = 0; r < nRegions(); r++)
    {
        if (regionBase[r] != NULL)
        {
            munmap(regionBase[r], regionSize[r]);
        }
    }

    Cleanup();
}


void
SCRATCHPAD_MEMORY_SERVER_CLASS::Init(PLATFORMS_MODULE p)
{
    // chain
    PLATFORMS_MODULE_CLASS::Init(p);
}

// uninit: override
void
SCRATCHPAD_MEMORY_SERVER_CLASS::Uninit()
{
    // cleanup
    Cleanup();
    
    // chain
    PLATFORMS_MODULE_CLASS::Uninit();
}

// cleanup
void
SCRATCHPAD_MEMORY_SERVER_CLASS::Cleanup()
{
}


inline bool
SCRATCHPAD_MEMORY_SERVER_CLASS::IsTracing(int level)
{
    return TRACING(level);
}


//
// RRR requests
//

//
// InitRegion --
//
void SCRATCHPAD_MEMORY_SERVER_CLASS::InitRegion(
    UINT32 regionID,
    UINT64 regionEndIdx,
    GLOBAL_STRING_UID initFilePath)
{
    UINT64 nWords = regionEndIdx + 1;

    const string* init_path =
        (initFilePath != 0) ? GLOBAL_STRINGS::Lookup(initFilePath) : NULL;

    if (init_path == NULL)
    {
        T1("\tSCRATCHPAD init region " << regionID << ": "
           << nWords << " words");
    }
    else
    {
        T1("\tSCRATCHPAD init region " << regionID << ": "
           << nWords << " words"
           << ", init file: '" << *init_path << "'");
    }

    VERIFY(regionBase[regionID] == NULL, "Scratchpad region " << regionID << " already initialized");
    VERIFY(nWords <= (regionOffset(~0) + 1),
           "Scratchpad region " << regionID << " too large for " << SCRATCHPAD_MEMORY_ADDR_BITS <<
           " bit address space (" << (regionOffset(~0) + 1) << " bytes)");

    regionWords[regionID] = nWords;
    // Size must be multiple of a page for mmap.
    regionSize[regionID] = (nWords * sizeof(SCRATCHPAD_MEMORY_WORD) + getpagesize() - 1) &
                           ~(getpagesize() - 1);
    
    if (init_path == NULL)
    {
        // Scratchpad initialized with zeroes.
        regionBase[regionID] = (SCRATCHPAD_MEMORY_WORD*)
                               mmap(NULL,
                                    regionSize[regionID],
                                    PROT_WRITE | PROT_READ,
                                    MAP_PRIVATE | MAP_ANONYMOUS,
                                    -1, 0);
        VERIFY(regionBase[regionID] != MAP_FAILED, "Scratchpad mmap failed: region " << regionID << " nWords " << nWords << " (errno " << errno << ")");
    }
    else
    {
        // Scratchpad initialized from a file. 
        int fd = open(init_path->c_str(), O_RDONLY);
        if (fd == -1)
        {
            error(1, errno, "Scratchpad initialization file '%s'", init_path->c_str());
        }

        // How big is the file?
        ssize_t count = regionSize[regionID];
        struct stat stat_buf;
        if (fstat(fd, &stat_buf) == -1)
        {
            error(1, errno, "Scratchpad initialization file '%s'", init_path->c_str());
        }
        if (stat_buf.st_size < count)
        {
            // File is smaller than region
            count = stat_buf.st_size;
        }

        // Round count up to a page size.  mmap() extends files to the next page
        // boundary by padding with 0.
        long page_size = sysconf(_SC_PAGESIZE);
        count = ((count + page_size - 1) / page_size) * page_size;

        // It appears that asking for regionSize[regionID] bytes guarantees
        // a contiguous region of memory this large even if the file is smaller.
        // The large region will be completed by an anonymous mmap() later.
        regionBase[regionID] = (SCRATCHPAD_MEMORY_WORD*)
                               mmap(NULL,
                                    regionSize[regionID],
                                    PROT_WRITE | PROT_READ,
                                    MAP_PRIVATE,
                                    fd, 0);
        VERIFY(regionBase[regionID] != MAP_FAILED, "Scratchpad mmap failed: region " << regionID << " nWords " << nWords << " (errno " << errno << ")");

        // Is the file smaller than the scratchpad?  If yes, extend the mapping.
        if (count < regionSize[regionID])
        {
            // Size of missing region
            ssize_t extra = regionSize[regionID] - count;
            // count is already page aligned
            void *start_addr = (UINT8*)regionBase[regionID] + count;

            T1("\t\tSCRATCHPAD init region " << regionID << ": Extending file by " << extra << " bytes");

            // Map anonymous (zero initialized) memory in the extended area.
            void *actual_addr;
            actual_addr = mmap(start_addr,
                               extra,
                               PROT_WRITE | PROT_READ,
                               MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED,
                               -1, 0);
            VERIFY(start_addr == actual_addr, "Scratchpad mmap extend failed: region " << regionID << " nWords " << nWords << " (errno " << errno << ")");
        }
    }

}


//
// GetMemPtr --
//     Return a pointer to the memory holding address.
//
void *
SCRATCHPAD_MEMORY_SERVER_CLASS::GetMemPtr(
    SCRATCHPAD_MEMORY_ADDR addr)
{
    // Burst the incoming address into a region ID and a pointer to the line.
    UINT32 region = regionID(addr);
    SCRATCHPAD_MEMORY_WORD* mem = regionBase[region] + regionOffset(addr);
    
    VERIFYX(regionBase[region] != NULL);
    VERIFYX(regionOffset(addr) < regionWords[region]);

    return mem;
}


//
// Load --
//
OUT_TYPE_LoadLine
SCRATCHPAD_MEMORY_SERVER_CLASS::LoadLine(
    SCRATCHPAD_MEMORY_ADDR addr)
{
    // Burst the incoming address into a region ID and a pointer to the line.
    UINT32 region = regionID(addr);
    SCRATCHPAD_MEMORY_WORD* line = regionBase[region] + regionOffset(addr);
    
    VERIFYX(regionBase[region] != NULL);
    VERIFYX(regionOffset(addr) < regionWords[region]);

    if (TRACING(2))
    {
        T2("\tSCRATCHPAD load  region " << region << ": r_addr " << fmt_addr(regionOffset(addr)));

        for (UINT32 i = 0; i < SCRATCHPAD_WORDS_PER_LINE; i++)
        {
            T2("\t\tL " << i << ":\t" << fmt_data(*(line + i)));
        }
    }

    OUT_TYPE_LoadLine v;
    v.data0 = *(line + 0);
    v.data1 = *(line + 1);
    v.data2 = *(line + 2);
    v.data3 = *(line + 3);
    return v;
}


//
// Store --
//

// Vector type definitions...
//
// Older versions of the compiler appear to want 
// this typedef to be a signed char
#if (__GNUC__ >= 4) && (__GNUC_MINOR__ >= 3)
    typedef char V8QI __attribute__ ((vector_size (8)));
#else
    typedef signed char V8QI __attribute__ ((vector_size (8)));
#endif

typedef int V2SI __attribute__ ((vector_size (8)));


void
SCRATCHPAD_MEMORY_SERVER_CLASS::StoreLine(
    UINT64 byteMask,
    SCRATCHPAD_MEMORY_ADDR addr,
    SCRATCHPAD_MEMORY_WORD data3,
    SCRATCHPAD_MEMORY_WORD data2,
    SCRATCHPAD_MEMORY_WORD data1,
    SCRATCHPAD_MEMORY_WORD data0)
{
    // Burst the incoming address into a region ID and a pointer to the line.
    UINT32 region = regionID(addr);
    
    T1("\tSCRATCHPAD store line, region " << region
                                          << ": r_addr " << fmt_addr(regionOffset(addr))
                                          << ", mask " << fmt_mask(byteMask));

    VERIFYX(regionBase[region] != NULL);
    VERIFYX(regionOffset(addr) < regionWords[region]);

    SCRATCHPAD_MEMORY_WORD* store_line = regionBase[region] + regionOffset(addr);

    //
    // The mask has been arranged so it works well with the maskmovq instruction.
    // Masks for data0 are in the high bits of each byte.  Masks for data1
    // are 1 bit lower, so the mask is shifted left 1 bit for each word using
    // pslld.
    //

#if defined(__MMX__) && defined(__SSE__) && defined(ENABLE_SSE_FOR_SCRATCHPAD)

    //
    // Using SSE instructions seemed like a good idea, but they appear to be
    // slower than the non-SSE version below!  For now we keep the code
    // here but predicate it with ENABLE_SSE_FOR_SCRATCHPAD, which is not
    // defined.
    //

    #if (__GNUC__ >= 4) && (__GNUC_MINOR__ >= 4)
        #define SHIFT_BY_1 V2SI(1LLU)
    #else
        #define SHIFT_BY_1 1
    #endif

    V8QI mask = V8QI(byteMask);
    __builtin_ia32_maskmovq(V8QI(data0), mask, (char *)(store_line + 0));
    if (UINT64(mask) & 0x8080808080808080)
    {
        T2("\t\tS 0:\t" << fmt_data(*(store_line + 0)));
    }

    mask = V8QI(__builtin_ia32_pslld(V2SI(mask), SHIFT_BY_1));
    __builtin_ia32_maskmovq(V8QI(data1), mask, (char *)(store_line + 1));
    if (UINT64(mask) & 0x8080808080808080)
    {
        T2("\t\tS 1:\t" << fmt_data(*(store_line + 1)));
    }

    mask = V8QI(__builtin_ia32_pslld(V2SI(mask), SHIFT_BY_1));
    __builtin_ia32_maskmovq(V8QI(data2), mask, (char *)(store_line + 2));
    if (UINT64(mask) & 0x8080808080808080)
    {
        T2("\t\tS 2:\t" << fmt_data(*(store_line + 2)));
    }

    mask = V8QI(__builtin_ia32_pslld(V2SI(mask), SHIFT_BY_1));
    __builtin_ia32_maskmovq(V8QI(data3), mask, (char *)(store_line + 3));
    if (UINT64(mask) & 0x8080808080808080)
    {
        T2("\t\tS 3:\t" << fmt_data(*(store_line + 3)));
    }

#else

    UINT64 mask = FullByteMask(byteMask);
    *(store_line + 0) = (data0 & mask) | (*(store_line + 0) & ~mask);
    if (mask)
    {
        T2("\t\tS 0:\t" << fmt_data(*(store_line + 0)));
    }

    mask = FullByteMask(byteMask << 1);
    *(store_line + 1) = (data1 & mask) | (*(store_line + 1) & ~mask);
    if (mask)
    {
        T2("\t\tS 0:\t" << fmt_data(*(store_line + 1)));
    }

    mask = FullByteMask(byteMask << 2);
    *(store_line + 2) = (data2 & mask) | (*(store_line + 2) & ~mask);
    if (mask)
    {
        T2("\t\tS 0:\t" << fmt_data(*(store_line + 2)));
    }

    mask = FullByteMask(byteMask << 3);
    *(store_line + 3) = (data3 & mask) | (*(store_line + 3) & ~mask);
    if (mask)
    {
        T2("\t\tS 0:\t" << fmt_data(*(store_line + 3)));
    }

#endif
}


void
SCRATCHPAD_MEMORY_SERVER_CLASS::StoreWord(
    UINT64 byteMask,
    SCRATCHPAD_MEMORY_ADDR addr,
    SCRATCHPAD_MEMORY_WORD data)
{
    // Burst the incoming address into a region ID and a pointer to the line.
    UINT32 region = regionID(addr);
    SCRATCHPAD_MEMORY_WORD *store_word = regionBase[region] + regionOffset(addr);
    
    T2("\tSCRATCHPAD store word, region " << region
                                          << ": r_addr " << fmt_addr(regionOffset(addr))
                                          << ", mask " << fmt_mask(byteMask));

    ASSERTX(regionBase[region] != NULL);
    ASSERTX(regionOffset(addr) < regionWords[region]);

#if defined(__MMX__) && defined(__SSE__) && defined(ENABLE_SSE_FOR_SCRATCHPAD)

    V8QI mask = V8QI(byteMask);
    __builtin_ia32_maskmovq(V8QI(data), mask, (char *)(store_word));
    if (UINT64(mask) & 0x8080808080808080)
    {
        T2("\t\tS 0:\t" << fmt_data(*store_word));
    }

#else

    UINT64 mask = FullByteMask(byteMask);
    *store_word = (data & mask) | (*store_word & ~mask);
    if (mask)
    {
        T2("\t\tS 0:\t" << fmt_data(*store_word));
    }

#endif
}


void
SCRATCHPAD_MEMORY_SERVER_CLASS::StoreLineUnmasked(
    SCRATCHPAD_MEMORY_ADDR addr,
    const SCRATCHPAD_MEMORY_WORD *data)
{
    // Burst the incoming address into a region ID and a pointer to the line.
    UINT32 region = regionID(addr);
    SCRATCHPAD_MEMORY_WORD *store_line = regionBase[region] + regionOffset(addr);
    
    ASSERTX(regionBase[region] != NULL);
    ASSERTX(regionOffset(addr) < regionWords[region]);

    memcpy(store_line, data, sizeof(SCRATCHPAD_MEMORY_WORD) * 4);

    if (TRACING(2))
    {
        T2("\tSCRATCHPAD store line, region " << region
                                              << ": r_addr " << fmt_addr(regionOffset(addr)));

        for (UINT32 i = 0; i < SCRATCHPAD_WORDS_PER_LINE; i++)
        {
            T2("\t\tS 0:\t" << fmt_data(*(store_line + i)));
        }
    }
}


//
// Convert a bit mask appropriate for maskmovq (high bit of each byte)
// to a full mask for each byte.
//
inline UINT64
SCRATCHPAD_MEMORY_SERVER_CLASS::FullByteMask(
    UINT64 in_mask)
{
    UINT64 pos_mask = in_mask & 0x8080808080808080;
    UINT64 mask = pos_mask | (pos_mask >> 7) ^ 0x0101010101010101;
    mask -= 0x0101010101010101;
    mask |= pos_mask;
    return mask;
}




// ========================================================================
//
// Some low level channel I/O drivers that do not support real DMA allow
// the scratchpad code to register a pseudo-DMA path.  (E.g. The Nallatech
// ACP driver.)  This path is significantly faster as it bypasses the
// channel I/O and RRR stacks.
//
// ========================================================================

#ifdef PSEUDO_DMA_ENABLED

static bool
PseudoDMA(
    int methodID,
    int length,
    const void *msg,
    NALLATECH_EDGE_PHYSICAL_CHANNEL_CLASS::PSEUDO_DMA_READ_RESP &resp)
{
    const UINT64 *u64msg = (const UINT64*) msg;
    const SCRATCHPAD_MEMORY_SERVER instance = &SCRATCHPAD_MEMORY_SERVER_CLASS::instance;

    resp = NULL;

    switch (methodID)
    {
      case SCRATCHPAD_MEMORY_METHOD_ID_StoreWord:
      {
        instance->StoreWord(u64msg[2], u64msg[1], u64msg[0]);
        return true;
      }
      case SCRATCHPAD_MEMORY_METHOD_ID_StoreLine:
      {
        UINT64 byteMask = u64msg[5];

        if ((byteMask & 0xf0f0f0f0f0f0f0f0) == 0xf0f0f0f0f0f0f0f0)
        {
            // All bytes written.  Use fast path.
            instance->StoreLineUnmasked(u64msg[4], u64msg);
        }
        else
        {
            // Partial (masked) write.  Slow path.
            instance->StoreLine(byteMask, u64msg[4], u64msg[3],
                                u64msg[2], u64msg[1], u64msg[0]);
        }

        return true;
      }
      case SCRATCHPAD_MEMORY_METHOD_ID_LoadLine:
      {
        static NALLATECH_EDGE_PHYSICAL_CHANNEL_CLASS::PSEUDO_DMA_READ_RESP_CLASS r;
        static bool did_init = false;
        static UMF_MESSAGE_CLASS m;

        // Initialize the constant portions of the response on the first pass
        if (! did_init)
        {
            did_init = true;

            m.Clear();
            m.SetLength(32);
            m.SetServiceID(SCRATCHPAD_MEMORY_SERVICE_ID);
            m.SetMethodID(SCRATCHPAD_MEMORY_METHOD_ID_LoadLine);

            // UMF header components
            r.header = m.EncodeHeader();
            r.msgBytes = 32;
        }

        // Pointer to the requested memory
        r.msg = instance->GetMemPtr(u64msg[0]);

        resp = &r;

        // Only handle reads here when tracing is off.  When tracing is on
        // the RRR method will be called.
        return ! instance->IsTracing(1);
        }
    }

    // Request not handled by pseudoDMA
    return false;
}

#endif
