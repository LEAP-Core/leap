//
// Copyright (C) 2008 Massachusetts Institute of Technology
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

import Vector::*;

//
// Various statistics interfaces:
//

typedef 8 STAT_VECTOR_INDEX_SZ;
typedef Bit#(STAT_VECTOR_INDEX_SZ) STAT_VECTOR_INDEX;
typedef Bit#(`STATS_SIZE) STAT_VALUE;

// Single statistic
interface STAT;
    method Action incr();

    // Be careful with this method.  Incrementing by values too close to
    // the `STATS_SIZE bit counter can cause data to be lost if the counter
    // rises faster than it can be dumped to the host.
    method Action incrBy(STAT_VALUE amount);
endinterface: STAT

// Vector of multiple instances of the same statistics ID
interface STAT_VECTOR#(type ni);
    method Action incr(Bit#(TLog#(ni)) iid);

    // Be careful with this method.  Incrementing by values too close to
    // the `STATS_SIZE bit counter can cause data to be lost if the counter
    // rises faster than it can be dumped to the host.
    method Action incrBy(Bit#(TLog#(ni)) iid, STAT_VALUE amount);
endinterface

//
// mkStatCounter --
//     Public module for the STAT single statistic interface.  Implement it
//     using the code for the vector interface.
//
module mkStatCounter#(STATS_DICT_TYPE statID)
    // interface:
    (STAT);

    method Action incr() = noAction;
    method Action incrBy(STAT_VALUE amount) = noAction;

endmodule

//
// mkStatCounterArrayElement --
//     Public module for the STAT single statistic interface.  In this case,
//     the software is expected to combine multiple counters sharing a
//     single statID into an array.  The arrayIdx values must be unique
//     for a given statID.
//
module mkStatCounterArrayElement#(STATS_DICT_TYPE statID,
                                  STAT_VECTOR_INDEX arrayIdx)
    // interface:
    (STAT);

    method Action incr() = noAction;
    method Action incrBy(STAT_VALUE amount) = noAction;

endmodule


//
// mkStatCounter_MultiEntry --
//     Public module for the STAT_VECTOR with multiple instances of a single
//     IDs interface.  This is most likely used to store separate counters
//     for the same statistic across multiple instances.
//
//     *** This method is the only way to instantiate multiple buckets ***
//     *** for a single statistic ID.                                  ***
//
module mkStatCounter_MultiEntry#(STATS_DICT_TYPE statID)
    // interface:
    (STAT_VECTOR#(n_STATS))
    provisos (Add#(TLog#(n_STATS), k, STAT_VECTOR_INDEX_SZ));

    Vector#(n_STATS, STATS_DICT_TYPE) statID_vec = replicate(statID);
    let m <- mkStatCounterVec_Disabled(statID_vec);

    return m;
endmodule


// TBD - This needs to be implemented

//
// mkStatCounter_Vector --
//     Public module for the STAT_VECTOR multiple instance IDs interface.
//
//module mkStatCounter_Vector#(Vector#(n_STATS, STATS_DICT_TYPE) myIDs)
    // interface:
//    (STAT_VECTOR#(n_STATS))
//    provisos (Add#(TLog#(n_STATS), k, STAT_VECTOR_INDEX_SZ));

//    Vector#(n_STATS, STATS_DICT_TYPE) statID_vec = replicate(myIDs);
//    let m <- mkStatCounterVec_Disabled(statID_vec);

//   return m;
//endmodule


//
// mkStatCounterArray_Vector --
//     Same as mkStatCounter_Vector, but multiple of these will be
//     created in the hardware sharing a dictionary ID with unique
//     arrayIdx values.  The software will combine dictionary IDs from
//     separate counters into arrays.
//
//     Don't be too confused by the two vectors here.  The "vector"
//     is the collection of multiple, independent dictionary IDs in
//     a single statistics ring stop.  The "array" is the combination of
//     counters from independent ring stops into a logical array in
//     software.
//

// TBD - This needs to be implemented

//module mkStatCounterArray_Vector#(Vector#(n_STATS, STATS_DICT_TYPE) myIDs,
//                                                     STAT_VECTOR_INDEX arrayIdx)
    // interface:
//    (STAT_VECTOR#(n_STATS))
//    provisos (Add#(TLog#(n_STATS), k, STAT_VECTOR_INDEX_SZ));

//    Vector#(n_STATS, STATS_DICT_TYPE) statID_vec = replicate(myIDs);
//    let m <- mkStatCounterVec_Disabled(statID_vec);

//    return m;
//endmodule

// Internal

// ========================================================================
//
// Implementation -- internal modules.
//
// ========================================================================


module mkStatCounterVec_Disabled#(Vector#(n_STATS, STATS_DICT_TYPE) myIDs)
    // interface:
    (STAT_VECTOR#(n_STATS));

    method Action incr(Bit#(TLog#(n_STATS)) idx);
        noAction;
    endmethod

    method Action incrBy(Bit#(TLog#(n_STATS)) idx, STAT_VALUE amount);
        noAction;
    endmethod
endmodule

