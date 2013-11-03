//
// Copyright (C) 2012 Intel Corporation
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

import ModuleContext::*;
import List::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_connections.bsh"


//
// Global string UIDs are comprised of two parts: the UID associated with
// the synthesis boundary and the local UID within the synthesis boundary.
// All strings within a synthesis boundary share the same synth UID.
// Within a synthesis boundary there is a 1:1 mapping between UIDs and strings.
// Because synthesis boundaries are compiled in parallel, a given string may
// appear with separate UIDs in different synthesis regions.
//

// Don't need the separation of platform and synthesis boundary UID.
// Just combine them.
typedef TAdd#(`GLOBAL_STRING_PLATFORM_UID_SZ,
              `GLOBAL_STRING_SYNTH_UID_SZ) GLOBAL_STRING_SYNTH_UID_SZ;

typedef `GLOBAL_STRING_LOCAL_UID_SZ GLOBAL_STRING_LOCAL_UID_SZ;

// The full UID
typedef TAdd#(GLOBAL_STRING_SYNTH_UID_SZ,
              GLOBAL_STRING_LOCAL_UID_SZ) GLOBAL_STRING_UID_SZ;

typedef Bit#(GLOBAL_STRING_UID_SZ) GLOBAL_STRING_UID;

typedef Bit#(GLOBAL_STRING_SYNTH_UID_SZ) GLOBAL_STRING_SYNTH_UID;
typedef Bit#(GLOBAL_STRING_LOCAL_UID_SZ) GLOBAL_STRING_LOCAL_UID;


//
// A global string handle is the UID plus metadata that is not transmitted
// but is useful for compile-time and Bluesim debugging.
//
typedef struct
{
    GLOBAL_STRING_UID uid;
    String str;
}
GLOBAL_STRING_HANDLE
    deriving (Eq);

//
// Define mapping of GLOBAL_STRING_HANDLE to storage/wires.
//
instance Bits#(GLOBAL_STRING_HANDLE, GLOBAL_STRING_UID_SZ);
    function GLOBAL_STRING_UID pack(GLOBAL_STRING_HANDLE str) = str.uid;

    function GLOBAL_STRING_HANDLE unpack(GLOBAL_STRING_UID uid);
        // Return handle holding the correct UID but without the text string.
        // This affects only compile-time printing and Bluesim debugging.
        return GLOBAL_STRING_HANDLE { uid: uid, str: "" };
    endfunction
endinstance

//
// Extract synth and local portions of UID from full UID
//

function GLOBAL_STRING_SYNTH_UID getGlobalStringSynthUID(GLOBAL_STRING_UID uid);
    Tuple2#(GLOBAL_STRING_SYNTH_UID, GLOBAL_STRING_LOCAL_UID) t = unpack(pack(uid));
    return tpl_1(t);
endfunction

function GLOBAL_STRING_LOCAL_UID getGlobalStringLocalUID(GLOBAL_STRING_UID uid);
    Tuple2#(GLOBAL_STRING_SYNTH_UID, GLOBAL_STRING_LOCAL_UID) t = unpack(pack(uid));
    return tpl_2(t);
endfunction


//
// getGlobalStringHandle --
//     Get a UID for a string and return a handle.  The handle contains the
//     UID, which can be transmitted on wires.  It also contains the original
//     string, which can not.  The original string is mostly useful for
//     printing messages at compile time and in Bluesim.
//
module [t_CONTEXT] getGlobalStringHandle#(String str) (GLOBAL_STRING_HANDLE)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let uid <- getGlobalStringUID(str);
    return GLOBAL_STRING_HANDLE { uid: uid, str: str };
endmodule


//
// getGlobalStringUID --
//     Get a UID for a string.  If the string is already present in the global
//     table then return the old UID.
//
module [t_CONTEXT] getGlobalStringUID#(String str) (GLOBAL_STRING_UID)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    GLOBAL_STRING_UID str_uid;

    let str_table <- getGlobalStrings();

    GLOBAL_STRING_TABLE_IDX idx = ctHash(str);
    let bucket = str_table.buckets.tbl[idx];

    if (List::lookup(str, bucket) matches tagged Valid .entry)
    begin
        str_uid = fromInteger(entry.uid);
    end
    else
    begin
        // String not yet in the table.  Add it.
        Integer local_uid = str_table.nEntries;

        //
        // The UID must fit in 32 bits.  We allocate some to the platform ID,
        // some to the synthesis boundary ID within the platform, and some to
        // the strings within a synthesis boundary.
        //
        // This code and error checking would be cleaner if we used Bit#()
        // fields instead of Integer.  Unfortunately, messageM() used to
        // emit the table takes only strings and integers can be converted
        // easily to strings.
        //
        let synth_plat_uid <- getSynthesisBoundaryPlatformID();
        let synth_local_uid <- getSynthesisBoundaryID();

        Integer shift_over_local_uid = 2 ** `GLOBAL_STRING_LOCAL_UID_SZ;
        Integer shift_over_synth_uid = 2 ** `GLOBAL_STRING_SYNTH_UID_SZ;
        Integer shift_over_plat_uid =  2 ** `GLOBAL_STRING_PLATFORM_UID_SZ;

        GLOBAL_STRING_INFO entry = ?;
        entry.uid = (synth_plat_uid * shift_over_local_uid * shift_over_synth_uid) +
                    (synth_local_uid * shift_over_local_uid) +
                    local_uid;

        if (synth_plat_uid >= shift_over_plat_uid)
            error("Platform UID doesn't fit in alloted space");
        if (synth_local_uid >= shift_over_synth_uid)
            error("Synthesis boundary UID doesn't fit in alloted space");
        if (local_uid >= shift_over_local_uid)
            error("Too many global strings");

        str_table.nEntries = str_table.nEntries + 1;
        str_table.buckets.tbl[idx] = List::cons(ctHashEntry(str, entry),
                                                str_table.buckets.tbl[idx]);

        putGlobalStrings(str_table);
        str_uid = fromInteger(entry.uid);
    end

    return str_uid;

endmodule


//
// lookupGlobalString --
//     Return an existing instance of string as a global string (if present).
//
module [t_CONTEXT] lookupGlobalString#(String str)
    (Maybe#(GLOBAL_STRING_UID))
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    Maybe#(GLOBAL_STRING_UID) str_uid = tagged Invalid;

    let str_table <- getGlobalStrings();
    if (ctHashTableLookup(str_table.buckets, str) matches tagged Valid .entry)
    begin
        str_uid = tagged Valid fromInteger(entry.uid);
    end

    return str_uid;
endmodule


// ========================================================================
//
// Access the string table structures stored in module context.
//
// ========================================================================

module [t_CONTEXT] getGlobalStrings (GLOBAL_STRING_TABLE)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    return ctxt.globalStrings;

endmodule


module [t_CONTEXT] printGlobalStrings (Empty)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    let m <- getGlobalStrings();
    printGlobStrings(m);

endmodule


module [t_CONTEXT] putGlobalStrings#(GLOBAL_STRING_TABLE new_strs) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.globalStrings = new_strs;
    putContext(ctxt);

endmodule
