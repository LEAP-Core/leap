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

`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_connections.bsh"


// We define a specific size for the global string UID since it will be passed
// around as data at run time.
typedef UInt#(32) GLOBAL_STRING_UID;


//
// getGlobalStringUID --
//     Get a UID for a string.  If the string is already present in the global
//     table then return the old UID.
//
module [t_CONTEXT] getGlobalStringUID#(String str) (GLOBAL_STRING_UID)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    GLOBAL_STRING_TABLE_ENTRY entry = ?;

    let cur_strs <- getGlobalStrings();
    if (List::lookup(str, cur_strs) matches tagged Valid .info)
    begin
        // Already present
        entry = info;
    end
    else
    begin
        // String not yet in the table.  Add it.
        Integer local_uid = length(cur_strs) + 1;

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

        Integer shift_over_local_uid = 'hffff + 1;
        Integer shift_over_synth_uid = 'h3ff + 1;
        Integer shift_over_plat_uid = 'h3f + 1;

        entry.uid = (synth_plat_uid * shift_over_local_uid * shift_over_synth_uid) +
                    (synth_local_uid * shift_over_local_uid) +
                    local_uid;

        if (synth_plat_uid >= shift_over_plat_uid)
            error("Platform UID doesn't fit in alloted space");
        if (synth_local_uid >= shift_over_synth_uid)
            error("Synthesis boundary UID doesn't fit in alloted space");
        if (local_uid >= shift_over_local_uid)
            error("Too many global strings");

        putGlobalStrings(List::cons(tuple2(str, entry), cur_strs));
    end

    return fromInteger(entry.uid);

endmodule


// ========================================================================
//
// Access the string table structures stored in module context.
//
// ========================================================================

module [t_CONTEXT] getGlobalStrings (List#(GLOBAL_STRING_TABLE))
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


module [t_CONTEXT] putGlobalStrings#(List#(GLOBAL_STRING_TABLE) new_strs) ()
    provisos
        (Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    LOGICAL_CONNECTION_INFO ctxt <- getContext();
    ctxt.globalStrings = new_strs;
    putContext(ctxt);

endmodule
