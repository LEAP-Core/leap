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

`include "awb/provides/bsv_version_capabilities.bsh"

import DefaultValue::*;
import Vector::*;
import List::*;


//
// Support for building hash tables at compile time.  Some code here might
// be usable as hardware, also, but the primary purpose is to build internal
// data structures for use during compilation.
//

//
// COMPILE_TIME_HASH_TABLE --
//   The primary hash table data structure.  The long, somewhat awkward,
//   name is to avoid conflicts with other hash table implementations.
//

typedef Tuple2#(t_KEY, t_VALUE)
    COMPILE_TIME_HASH_ENTRY#(type t_KEY, type t_VALUE);

typedef struct
{
    Vector#(n_BUCKETS, List#(COMPILE_TIME_HASH_ENTRY#(t_KEY, t_VALUE))) tbl;
}
COMPILE_TIME_HASH_TABLE#(numeric type n_BUCKETS, type t_KEY, type t_VALUE);

instance DefaultValue#(COMPILE_TIME_HASH_TABLE#(n_BUCKETS, t_KEY, t_VALUE));
    defaultValue = COMPILE_TIME_HASH_TABLE { tbl: replicate(Nil) };
endinstance

//
// COMPILE_TIME_HASH_IDX --
//   Index into the hash table.
//
typedef UInt#(TLog#(n_BUCKETS)) COMPILE_TIME_HASH_IDX#(numeric type n_BUCKETS);


//
// ctHashEntry --
//   Return key/value pair as an entry type.  Using this and the functions
//   below allow us to change the underlying entry type.
//
function COMPILE_TIME_HASH_ENTRY#(t_KEY, t_VALUE) ctHashEntry(
    t_KEY key,
    t_VALUE value);

    return tuple2(key, value);
endfunction


//
// ctHashKey --
//   Extract the key from a hash table entry.
//
function t_KEY ctHashKey(COMPILE_TIME_HASH_ENTRY#(t_KEY, t_VALUE) entry);
    return tpl_1(entry);
endfunction

//
// ctHashValue --
//   Extract the value from a hash table entry.
//
function t_VALUE ctHashValue(COMPILE_TIME_HASH_ENTRY#(t_KEY, t_VALUE) entry);
    return tpl_2(entry);
endfunction


//
// ctHashTableToList --
//   Return the contents of a hash table as a single list.
//
function List#(Tuple2#(t_KEY, t_VALUE)) ctHashTableToList(
    COMPILE_TIME_HASH_TABLE#(n_BUCKETS, t_KEY, t_VALUE) t);

    return List::concat(toList(t.tbl));
endfunction


//
// CTHashable --
//   A series of functions that operate on the hash table will be defined
//   below.  Each of the functions needs a method of computed a hash based
//   on an entry.  Entries must be members of CTHashable in order to define
//   the hash function.
//
typeclass CTHashable#(type t_IDX, type t_KEY);
    function t_IDX ctHash(t_KEY key);
endtypeclass


//
// The hash of an entry is the hash of the key.
//
instance CTHashable#(t_HASH, COMPILE_TIME_HASH_ENTRY#(t_KEY, t_VALUE))
    provisos (CTHashable#(t_HASH, t_KEY));

    function t_HASH ctHash(COMPILE_TIME_HASH_ENTRY#(t_KEY, t_VALUE) entry);
        return ctHash(ctHashKey(entry));
    endfunction
endinstance


//
// ctHashTableInsert --
//   Insert a new entry into the table.
//
function COMPILE_TIME_HASH_TABLE#(n_BUCKETS, t_KEY, t_VALUE) ctHashTableInsert(
    COMPILE_TIME_HASH_TABLE#(n_BUCKETS, t_KEY, t_VALUE) t,
    t_KEY key,
    t_VALUE val)
    provisos (CTHashable#(COMPILE_TIME_HASH_IDX#(n_BUCKETS), t_KEY));
    
    // Which bucket holds the new entry?
    COMPILE_TIME_HASH_IDX#(n_BUCKETS) idx = ctHash(key);
    
    // Add new entry to the bucket
    t.tbl[idx] = List::cons(tuple2(key, val), t.tbl[idx]);
    return t;
endfunction


//
// ctHashTableLookup --
//   Find an instance of the value associated with key in the table.  If
//   there are multiple instances only the first is returned.
//
function Maybe#(t_VALUE) ctHashTableLookup(
    COMPILE_TIME_HASH_TABLE#(n_BUCKETS, t_KEY, t_VALUE) t,
    t_KEY key)
    provisos (CTHashable#(COMPILE_TIME_HASH_IDX#(n_BUCKETS), t_KEY),
              Eq#(t_KEY));
    
    // Which bucket holds the new entry?
    COMPILE_TIME_HASH_IDX#(n_BUCKETS) idx = ctHash(key);
    
    return List::lookup(key, t.tbl[idx]);
endfunction


//
// hashStringToInteger --
//   Hash a String into an Integer.
//
function Integer hashStringToInteger(String str);
    let n_chars = stringLength(str);

    Integer hash = 0;

    // The ability to convert String to Char was introduced in May 2013.
    // Always return 0 for the hash on old compilers.
`ifdef BSV_VER_CAP_CHAR
    while (str != "")
    begin
        Char c = stringHead(str);

        // sdbm string hash function
        hash = (hash * 65599 + charToInteger(c)) % 4294967296;

        str = stringTail(str);
    end
`endif

    return hash;
endfunction

instance CTHashable#(UInt#(n_IDX), String)
    provisos (Add#(n_IDX, a__, 32));

    function UInt#(n_IDX) ctHash(String key);
        UInt#(32) idx = fromInteger(hashStringToInteger(key));
        return truncate(idx);
    endfunction
endinstance
