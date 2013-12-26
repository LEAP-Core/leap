//
// Copyright (C) 2009 Intel Corporation
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
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

//
// Statistics wires for coherent caches so individual caches can have their hit rates logged.
// When a line becomes true the coresponding statistic should be incremented.
//
interface RL_COH_CACHE_STATS;
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
endinterface: RL_COH_CACHE_STATS

module mkNullRLCoherentCacheStats (RL_COH_CACHE_STATS);
  return ?;
endmodule


