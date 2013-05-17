//
// Copyright (C) 2013 Intel Corporation
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
