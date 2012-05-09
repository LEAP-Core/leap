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

// Library imports.

import Vector::*;
import RWire::*;

`include "awb/provides/fpga_components.bsh"
`include "awb/provides/librl_bsv_base.bsh"


//
// Counting filters can be used to determine whether an entry is present in
// a set.  All counting filters have both test(), set() and remove() methods.
// This module provides multiple implementations for sets of varying sizes.
// Smaller sets can use direct decode filters.  Larger sets can use Bloom
// filters, which have more logic to deal with hashes but have good false
// positive rates with relatively small filter vector sizes.
//
// For automatic selection of a reasonable filter, use the mkCountingFilter
// module.  It picks decode filters for smaller sets and Bloom filters for
// larger sets.
//
// t_OPAQUE is used internally by counting filter implementations to pass
// state from test() to set().  The type may vary for different implementations.
// Each implementation must provide a typedef for defining t_OPAQUE.
//
interface COUNTING_FILTER_IFC#(type t_ENTRY, type t_OPAQUE);
    // Test whether a new entry may be added to the current state.
    // Returns Valid when the entry may be added along with some internal,
    // implementation-dependent, state to pass to the set() method.
    // Multiple test() calls may be scheduled in parallel (though this
    // may have high hardware costs).  However, set() may be called
    // for only one successful test() and once set() is called all
    // earlier test() results must be considered invalid.
    method Maybe#(t_OPAQUE) test(t_ENTRY newEntry);

    // When test() has said an element may be added, request addition of
    // the element by passing the result of the test() call.  Implementations
    // don't necessarily re-confirm that the element may be added, so
    // clients must be careful only to call set() for legal additions.
    // As noted for test(), once set() is called clients must not use the
    // results of any earlier test() responses.
    method Action set(t_OPAQUE stateUpdate);

    // Remove an entry from the filter.
    method Action remove(t_ENTRY oldEntry);

    // Test whether entry is busy
    method Bool notSet(t_ENTRY entry);

    // Clear filter
    method Action reset();
endinterface


// ========================================================================
//
//   Generic counting filter implementation.  mkCountingFilter tailors
//   the algorithm to the size of the set, picking counting Bloom filters
//   for large sets and decode filters for small sets.
//
// ========================================================================

// Private types used to compute the type of filter to employ in the
// standard implementation of mkCountingFilter.  Static elaboration using
// ifs would be preferable, but types are needed in order to set the size
// of t_OPAQUE.
//
// tF_OPAQUE stores the state passed between the test() and set() methods
// in order to avoid recomputing logic required by both methods.
//

// Use couting Bloom filter when the entry size is larger than 10 bits.
typedef TGT#(SizeOf#(t_ENTRY), 10) CF_USE_BLOOM#(type t_ENTRY);

// State of the appropriate filter for the t_ENTRY size
typedef Bit#(TSelect#(TAnd#(CF_USE_BLOOM#(t_ENTRY), permitComplexFilter),
                      SizeOf#(BLOOM_FILTER_STATE#(128)),
                      SizeOf#(DECODE_FILTER_STATE#(t_ENTRY))))
    CF_OPAQUE#(type t_ENTRY, numeric type permitComplexFilter);


//
// COUNTING_FILTER is the interface of a mkCountingFilter, derived from
// COUNTING_FILTER_IFC.
//
typedef COUNTING_FILTER_IFC#(t_ENTRY, CF_OPAQUE#(t_ENTRY, permitComplexFilter))
    COUNTING_FILTER#(type t_ENTRY, numeric type permitComplexFilter);

//
// mkCountingFilter --
//   Pick a reasonable filter based on the entry set size.  Uses a Bloom filter
//   for large sets and a simple decode filter for smaller sets.
//
module mkCountingFilter#(DEBUG_FILE debugLog)
    // interface:
    (COUNTING_FILTER#(t_ENTRY, permitComplexFilter))
    provisos (Bits#(t_ENTRY, t_ENTRY_SZ));

    if (valueOf(TAnd#(CF_USE_BLOOM#(t_ENTRY), permitComplexFilter)) != 0)
    begin
        // Large sets use Bloom filters
        COUNTING_BLOOM_FILTER#(t_ENTRY, 128, 2) filter <- mkCountingBloomFilter(debugLog);

        method Maybe#(CF_OPAQUE#(t_ENTRY, permitComplexFilter)) test(t_ENTRY newEntry) = sameSizeNP(filter.test(newEntry));
        method Action set(CF_OPAQUE#(t_ENTRY, permitComplexFilter) stateUpdate) = filter.set(sameSizeNP(stateUpdate));
        method Action remove(t_ENTRY oldEntry) = filter.remove(oldEntry);
        method Bool notSet(t_ENTRY entry) = filter.notSet(entry);
        method Action reset() = filter.reset;
    end
    else
    begin
        // Smaller sets use decode filters
        let filter = ?;

        if (valueOf(t_ENTRY_SZ) > 7)
        begin
            // Medium sized sets share 2 bits per entry
            DECODE_FILTER#(t_ENTRY, TDiv#(TExp#(t_ENTRY_SZ), 2)) decodeFilterL <- mkSizedDecodeFilter(debugLog);
            filter = decodeFilterL;
        end
        else
        begin
            // Small sets get unique bit per entry
            DECODE_FILTER#(t_ENTRY, TExp#(t_ENTRY_SZ)) decodeFilterS <- mkSizedDecodeFilter(debugLog);
            filter = decodeFilterS;
        end

        method Maybe#(CF_OPAQUE#(t_ENTRY, permitComplexFilter)) test(t_ENTRY newEntry) = sameSizeNP(filter.test(newEntry));
        method Action set(CF_OPAQUE#(t_ENTRY, permitComplexFilter) stateUpdate) = filter.set(sameSizeNP(stateUpdate));
        method Action remove(t_ENTRY oldEntry) = filter.remove(oldEntry);
        method Bool notSet(t_ENTRY entry) = filter.notSet(entry);
        method Action reset() = filter.reset;
    end
endmodule


// ========================================================================
//
// Decode Filter
//
// ========================================================================

// nFilterBits should be a power of 2!
typedef COUNTING_FILTER_IFC#(t_ENTRY, DECODE_FILTER_STATE#(t_ENTRY))
    DECODE_FILTER#(type t_ENTRY, numeric type nFilterBits);

// State passed from test() to set() methods.
typedef Bit#(SizeOf#(t_ENTRY)) DECODE_FILTER_STATE#(type t_ENTRY);

//
// Decode filter with one bit corresponding to one or more entries.
// Insert and remove methods may both be called in the same cycle.
//
module mkSizedDecodeFilter#(DEBUG_FILE debugLog)
    // interface:
    (DECODE_FILTER#(t_ENTRY, nFilterBits))
    provisos (Bits#(t_ENTRY, t_ENTRY_SZ),
              Alias#(Bit#(TLog#(nFilterBits)), t_FILTER_IDX));

    if (valueOf(t_ENTRY_SZ) < valueOf(TLog#(nFilterBits)))
    begin
        t_ENTRY dummy = ?;
        error("mkSizedDecodeFilter:  filter is larger than needed: " +
              integerToString(valueOf(nFilterBits)) + " entries for a " +
              printType(typeOf(dummy)));
    end

    // The filter is implemented as a pair of bit vectors.  Bits in the "in"
    // vector are toggled when an entry is added to the active set.  Bits in
    // the "out" vector are toggled when an entry is removed from the active
    // set.  An entry is active when an in bit differs from an out bit.
    LUTRAM#(Bit#(TLog#(nFilterBits)), Bit#(1)) fvIn <- mkLUTRAMU();
    LUTRAM#(Bit#(TLog#(nFilterBits)), Bit#(1)) fvOut <- mkLUTRAMU();

    Reg#(Bool) ready <- mkReg(False);
    Reg#(Bit#(TLog#(nFilterBits))) initIdx <- mkReg(0);
    
    rule init (! ready);
        fvIn.upd(initIdx, 0);
        fvOut.upd(initIdx, 0);

        ready <= (initIdx == maxBound);
        initIdx <= initIdx + 1;
    endrule


    RWire#(t_FILTER_IDX) insertId <- mkRWire();
    RWire#(t_FILTER_IDX) removeId <- mkRWire();


    function t_FILTER_IDX filterIdx(t_ENTRY e);
        return truncateNP(pack(e));
    endfunction

    (* fire_when_enabled, no_implicit_conditions *)
    rule updateInFilter (ready &&& insertId.wget() matches tagged Valid .id);
        fvIn.upd(id, fvIn.sub(id) ^ 1);
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule updateOutFilter (ready &&& removeId.wget() matches tagged Valid .id);
        fvOut.upd(id, fvOut.sub(id) ^ 1);
    endrule


    method Maybe#(DECODE_FILTER_STATE#(t_ENTRY)) test(t_ENTRY newEntry) if (ready);
        let id = filterIdx(newEntry);
        return (fvIn.sub(id) == fvOut.sub(id)) ? tagged Valid pack(newEntry) :
                                                 tagged Invalid;
    endmethod

    method Action set(DECODE_FILTER_STATE#(t_ENTRY) newEntry) if (ready);
        let id = filterIdx(unpack(newEntry));

        insertId.wset(id);
        debugLog.record($format("    Decode filter SET %0d OK, idx=%0d", newEntry, id));
    endmethod

    method Action remove(t_ENTRY oldEntry) if (ready);
        let id = filterIdx(oldEntry);
        removeId.wset(id);
        debugLog.record($format("    Decode filter REMOVE %0d, idx=%0d", oldEntry, id));
    endmethod

    method Bool notSet(t_ENTRY entry) if (ready);
        let id = filterIdx(entry);
        return (fvIn.sub(id) == fvOut.sub(id));
    endmethod

    method Action reset() if (ready);
        ready <= False;
        initIdx <= 0;
    endmethod
endmodule



// ========================================================================
//
// Counting Bloom Filter
//
// ========================================================================


typedef COUNTING_FILTER_IFC#(t_ENTRY, BLOOM_FILTER_STATE#(nFilterBits))
    COUNTING_BLOOM_FILTER#(type t_ENTRY,
                           numeric type nFilterBits,
                           numeric type nCounterBits);

typedef Vector#(nFilterBits, Bool)
    BLOOM_FILTER_HASH_MASK#(numeric type nFilterBits);

// State passed from test() to set() methods.
typedef BLOOM_FILTER_HASH_MASK#(nFilterBits)
    BLOOM_FILTER_STATE#(numeric type nFilterBits);

//
// Counting Bloom filter up to 256 bits.
//
module mkCountingBloomFilter#(DEBUG_FILE debugLog)
    // interface:
    (COUNTING_BLOOM_FILTER#(t_ENTRY, nFilterBits, nCounterBits))
    provisos (Bits#(t_ENTRY, t_ENTRY_SZ),
              Alias#(Bit#(TLog#(nFilterBits)), t_FILTER_IDX),

              // nFilterBits must be <= 256 and a power of 2.
              Add#(TLog#(nFilterBits), a__, 8),
              Add#(nFilterBits, 0, TExp#(TLog#(nFilterBits))),

              Alias#(BLOOM_FILTER_HASH_MASK#(nFilterBits), t_HASH_MASK),
              Alias#(BLOOM_FILTER_STATE#(nFilterBits), t_FILTER_STATE));
    
    // Filter bits (counters)
    Reg#(Vector#(nFilterBits, Bit#(nCounterBits))) bf <- mkReg(replicate(0));

    // Insert and remove requests are passed on wires to a single rule so
    // both methods may be called in the same cycle.
    RWire#(t_HASH_MASK) insertVec <- mkRWire();
    RWire#(t_ENTRY) removeId <- mkRWire();
    Wire#(Tuple2#(t_HASH_MASK, t_HASH_MASK)) updateBits <- mkBypassWire();

    //
    // computeHashMask --
    //     Calculate the mask of positions in the filter for the entry.
    //
    function t_HASH_MASK computeHashMask(t_ENTRY entryId);
        //
        // Map however many entry bits there are to 32 bits.  This hash function
        // is a compromise for FPGA area.  It works well for current functional
        // memory set sizes.  We may need to revisit it later.
        //
        Vector#(TDiv#(32, t_ENTRY_SZ), t_ENTRY) entry_rep = replicate(entryId);
        Bit#(32) idx32 = truncateNP(pack(entry_rep));

        // Get four 8 bit hashes.  The optimal number is probably 5 or 6 but
        // the FPGA area required is too large.
        Vector#(4, t_FILTER_IDX) hash = newVector();
        hash[0] = truncate(hash8(idx32[7:0]));
        hash[1] = truncate(hash8a(idx32[15:8]));
        hash[2] = truncate(hash8b(idx32[23:16]));
        hash[3] = truncate(hash8c(idx32[31:24]));
    
        Vector#(4, t_HASH_MASK) masks = replicate(replicate(False));
        masks[0][hash[0]] = True;
        masks[1][hash[1]] = True;
        masks[2][hash[2]] = True;
        masks[3][hash[3]] = True;

        return unpack(pack(masks[0]) | pack(masks[1]) |
                      pack(masks[2]) | pack(masks[3]));
    endfunction


    //
    // updateFilter --
    //
    //     Two part, single cycle rule to update the Bloom filter.  The
    //     first rule consumes this cycle's insert and remove calls and constructs
    //     a pair of vectors of filter positions that will change.  The second
    //     rule consumes those vectors as wires and updates the Bloom filter.
    //
    //     While these rules are logically a single rule, combining them causes
    //     the Bluespec optimizer to attempt to figure out exactly which bits
    //     changed and the combinatorics grow quite large.
    //
    (* fire_when_enabled, no_implicit_conditions *)
    rule updateFilter1 (True);
        //
        // Construct a vector of filter positions to increment.
        //
        t_HASH_MASK bf_incr_mask = newVector();
        if (insertVec.wget() matches tagged Valid .mask)
        begin
            bf_incr_mask = mask;
        end
        else
        begin
            bf_incr_mask = replicate(False);
        end

        //
        // Construct a vector of filter positions to decrement.
        //
        // Removal request comes in as the index to the filter instead of a
        // set of hash buckets.  This puts the computation of hashes in a single
        // rule.  We would do this for the test method, too, except that
        // the test method returns a response that is a function of the hashes.
        //
        t_HASH_MASK bf_decr_mask = newVector();
        if (removeId.wget() matches tagged Valid .remId)
        begin
            bf_decr_mask = computeHashMask(remId);
        end
        else
        begin
            bf_decr_mask = replicate(False);
        end

        // Pass the update vectors to the next rule (same cycle)
        updateBits <= tuple2(bf_incr_mask, bf_decr_mask);
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule updateFilter2 (True);
        //
        // Consume the result of updateFilter1 and update the Bloom filter.
        //
        match {.bf_incr_mask, .bf_decr_mask} = updateBits;

        // Update function invoked below to change the state of one counter
        function Bit#(nCounterBits) updateCounter(Bit#(nCounterBits) cur,
                                                  Bool req_incr,
                                                  Bool req_decr);
            // No change if the increment and decrement request states are
            // the same.
            if (req_incr == req_decr)
                return cur;
            else
                return cur + (req_incr ? 1 : -1);
        endfunction

        bf <= zipWith3(updateCounter, bf, bf_incr_mask, bf_decr_mask);
    endrule


    //
    // Is any counter zero in the set?  If yes then the entry is not
    // currently active in the filter.
    //
    function Bool counterInSetIsClear(Bool inSet, Bit#(nCounterBits) counter);
        return inSet && (counter == 0);
    endfunction
    
    //
    // Is any counter in the set at its maximum?  If so, the entry can't
    // be added to the filter even if it isn't currently present.
    //
    function Bool wouldOverflow(Bool inSet, Bit#(nCounterBits) counter);
        return inSet && (counter == maxBound);
    endfunction

    function Bool isTrue(Bool b) = b;


    method Maybe#(t_FILTER_STATE) test(t_ENTRY newEntry);
        let mask = computeHashMask(newEntry);

        //
        // Compute properties of the current counter states given a mask
        // of counters in the entry's set.
        //
        t_HASH_MASK not_all_set = zipWith(counterInSetIsClear, mask, bf);
        t_HASH_MASK overflow = zipWith(wouldOverflow, mask, bf);

        if (any(isTrue, not_all_set) && ! any(isTrue, overflow))
        begin
            // May insert
            return tagged Valid mask;
        end
        else
        begin
            // Can't insert.
            return tagged Invalid;
        end
    endmethod

    method Action set(t_FILTER_STATE stateUpdate);
        t_HASH_MASK mask = stateUpdate;

        debugLog.record($format("    Bloom filter SET, mask=0x%h", mask));
        insertVec.wset(mask);
    endmethod

    method Action remove(t_ENTRY oldEntry);
        debugLog.record($format("    Bloom filter REMOVE %0d", oldEntry));
        removeId.wset(oldEntry);
    endmethod

    method Bool notSet(t_ENTRY entry);
        let mask = computeHashMask(entry);
        t_HASH_MASK not_all_set = zipWith(counterInSetIsClear, mask, bf);
        return any(isTrue, not_all_set);
    endmethod

    method Action reset();
        bf <= replicate(0);
    endmethod
endmodule
