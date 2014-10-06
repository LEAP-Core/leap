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


// ========================================================================
//
// Cache statistics.
//
// ========================================================================

//
// Statistics wires for caches so individual caches can have their hit rates logged.
// When a line becomes true the coresponding statistic should be incremented.
//
interface RL_CACHE_STATS;
    method Bool readHit();
    method Bool readMiss();
    method Bool readRecentLineHit();     // Caches may have internal recent line
                                         // caches to optimize repeat accesses
                                         // to the same line.
    method Bool writeHit();
    method Bool writeMiss();
    method Bool newMRU();                // MRU line changed
    method Bool invalEntry();            // Invalidate due to capacity
    method Bool dirtyEntryFlush();
    method Bool forceInvalLine();        // Invalidate forced by external request
endinterface: RL_CACHE_STATS

module mkNullRLCacheStats (RL_CACHE_STATS);
  return ?;
endmodule

