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
// ========================================================================
//
// Coherent cache statistics.
//
// ========================================================================
//
// Statistics wires for coherent caches so individual caches can have their hit rates logged.
// When a line becomes true the coresponding statistic should be incremented.
//
interface COH_CACHE_STATS;
    method Bool readHit();
    method Bool readMiss();
    
    method Bool writeHit();
    method Bool writeCacheMiss();         // Write miss due to cache-line miss
    method Bool writePermissionMissS();   // Write miss due to permission miss (cache line already exists)
    method Bool writePermissionMissO();   // Write miss due to permission miss (cache line already exists)

    method Bool invalEntry();             // Invalidate due to capacity
    method Bool dirtyEntryFlush();        // Dirty flush due to capacity
    method Bool cleanEntryFlush();        // Clean flush due to capacity

    method Bool coherenceInval();         // Invalidate due to coherence
    method Bool coherenceFlush();         // Flush due to coherence
    
    method Bool forceInvalLine();         // Invalidate forced by external request
    method Bool forceFlushlLine();        // Flush forced by external request

    method Bool mshrRetry();              // Retry read/write because mshr entry is not available
    method Bool getxRetry();              // GETX retry forced by other caches
    method Bool getsUncacheable();        // Uncacheable response for GETS
    method Bool imUpgrade();              // automatically upgrade from I to M
    method Bool ioUpgrade();              // automatically upgrade from I to O

endinterface: COH_CACHE_STATS

module mkNullCoherentCacheStats (COH_CACHE_STATS);
  return ?;
endmodule

