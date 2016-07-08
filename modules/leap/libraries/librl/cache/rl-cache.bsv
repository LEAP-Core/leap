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

import DefaultValue::*;

// ========================================================================
//
// Memory subsystem global definitions.
//
// ========================================================================

//
// RL_CACHE_GLOBAL_READ_META --
//   Passed down and up the memory stack with each read request.  A
//   fixed data structures of globally meaningful values.  This is
//   passed in addition to the opaque, level-specific, read metadata.
//
typedef struct
{
    // Request comes from a prefetch somewhere internal to the memory
    // hierarchy.
    Bool isPrefetch;

    // Enforce order of independent fill/spill requests to different
    // addresses? When set, fill and spill requests will be generated
    // in the same order as their corresponding client read/write requests.
    // This is useful when fill requests have side effects or when 
    // synchronizing with host memory.
    Bool orderedSourceDataReqs;
}
RL_CACHE_GLOBAL_READ_META
    deriving (Eq, Bits);


instance DefaultValue#(RL_CACHE_GLOBAL_READ_META);
    defaultValue = RL_CACHE_GLOBAL_READ_META { isPrefetch: False,
                                               orderedSourceDataReqs: False };
endinstance


// RL_CACHE_STORE_TYPE --
//   Used to define the underlying store used by the cache.
//   There is no way to enforce that these definitions are consistent
//   with the definitions found in librl_bsv_cache.
typedef enum
{
    RL_CACHE_STORE_FLAT_BRAM = 0,
    RL_CACHE_STORE_BANKED_BRAM = 1,
    RL_CACHE_STORE_CLOCK_DIVIDED_BRAM = 2   
}
RL_CACHE_STORE_TYPE
    deriving (Eq, Bits);


// ========================================================================
//
// Cache statistics.
//
// ========================================================================

//
// Statistics wires for caches so individual caches can have their hit rates logged.
// For advanced monitoring, we allow the programmer to expose the cache request 
// metadata, which may be used by special cache stats collectors. 
//
interface RL_CACHE_STATS#(type t_CACHE_METADATA);
    method Maybe#(t_CACHE_METADATA) readHit();
    method Maybe#(t_CACHE_METADATA) readMiss();
    // Caches may have internal recent line
    // caches to optimize repeat accesses
    // to the same line.
    method Bool                     readRecentLineHit();
    method Maybe#(t_CACHE_METADATA) writeHit();
    method Maybe#(t_CACHE_METADATA) writeMiss();
    method Bool                     newMRU();                // MRU line changed
    method Bool                     invalEntry();            // Invalidate due to capacity
    method Bool                     dirtyEntryFlush();
    method Bool                     forceInvalLine();        // Invalidate forced by external request
    method Bool                     reqQueueBlocked();       // Request queue blocked due to dependency
    // Upon line eviction, returns number of accesses to a line before its eviction.   
    method Maybe#(UInt#(`RL_CACHE_LINE_ACCESS_TRACKER_WIDTH)) entryAccesses(); 
endinterface: RL_CACHE_STATS

module mkNullRLCacheStats (RL_CACHE_STATS#(t_CACHE_METADATA));
  return ?;
endmodule



       
