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

// Library imports.

`include "awb/provides/fpga_components.bsh"
`include "awb/provides/librl_bsv_base.bsh"


//
// Dual write implements an extension of the LUTRAM interface with two
// write ports.  It operates only on single bit or boolean types.
// Two writes may fire in parallel as long as the addresses are different.
// It is up to the client to avoid address conflicts.
//

interface LUTRAM_DUAL_WRITE#(type t_ADDR, type t_DATA);
    method Action upd(t_ADDR addr, t_DATA d);
    method Action updB(t_ADDR addr, t_DATA d);
    method t_DATA sub(t_ADDR addr);
endinterface

interface LUTRAM_DUAL_WRITE_MULTI_READ#(numeric type n_READERS, type t_ADDR, type t_DATA);
    method Action upd(t_ADDR addr, t_DATA d);
    method Action updB(t_ADDR addr, t_DATA d);
    interface Vector#(n_READERS, LUTRAM_READER_IFC#(t_ADDR, t_DATA)) readPorts;
endinterface


//
// mkDualWriteLUTRAM --
//     LUTRAM storing single bit values with a second write port (updB) added
//     to the standard interface.  In a cycle, the address passed to upd() must
//     not match the address passed to updB().
//
//     The LUTRAM implementation module is passed in as a function, allowing
//     the client to pick initialized or uninitialized storage.
//
module [m] mkDualWriteLUTRAM#(function m#(LUTRAM#(t_ADDR, t_DATA)) memImpl)
    // Interface:
    (LUTRAM_DUAL_WRITE#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, 1),
              IsModule#(m, m_TYPE));

    // Two write ports implemented with a pair of memories.  An index is
    // 1 if the value in each memory is different and 0 if the
    // values are the same.
    LUTRAM#(t_ADDR, t_DATA) memA <- memImpl();
    LUTRAM#(t_ADDR, t_DATA) memB <- memImpl();

    method Action upd(t_ADDR addr, t_DATA d);
        Bool b = unpack(pack(d));
        Bit#(1) x = pack(memB.sub(addr));
        if (b) x = ~ x;
        memA.upd(addr, unpack(x));
    endmethod

    method Action updB(t_ADDR addr, t_DATA d);
        Bool b = unpack(pack(d));
        Bit#(1) x = pack(memA.sub(addr));
        if (b) x = ~ x;
        memB.upd(addr, unpack(x));
    endmethod

    method t_DATA sub(t_ADDR addr);
        // Return 1 iff memA and memB are different
        return unpack(pack(pack(memA.sub(addr)) != pack(memB.sub(addr))));
    endmethod

endmodule


//
// mkDualWriteMultiReadLUTRAM --
//     Multi-read LUTRAM storing single bit values with a second write port (updB)
//     added to the standard interface.  In a cycle, the address passed to upd()
//     must not match the address passed to updB().
//
//     The internal implementation adds an extra read port to the number
//     requested by the client for use by the update methods.
//
module [m] mkDualWriteMultiReadLUTRAM#(function m#(LUTRAM_MULTI_READ#(n_TOTAL_READERS, t_ADDR, t_DATA)) memImpl)
    // Interface:
    (LUTRAM_DUAL_WRITE_MULTI_READ#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, 1),
              IsModule#(m, m_TYPE),
              Add#(n_READERS, 1, n_TOTAL_READERS));

    // Two write ports implemented with a pair of memories.  An index is
    // 1 if the value in each memory is different and 0 if the
    // values are the same.
    LUTRAM_MULTI_READ#(n_TOTAL_READERS, t_ADDR, t_DATA) memA <- memImpl();
    LUTRAM_MULTI_READ#(n_TOTAL_READERS, t_ADDR, t_DATA) memB <- memImpl();

    // Read port used by upd methods
    let loc_rd_port = valueOf(n_READERS);

    Vector#(n_READERS, LUTRAM_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();
    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface LUTRAM_READER_IFC#(t_ADDR, t_DATA);
                method t_DATA sub(t_ADDR addr);
                    return unpack(pack(pack(memA.readPorts[p].sub(addr)) !=
                                       pack(memB.readPorts[p].sub(addr))));
                endmethod
            endinterface;
    end

    method Action upd(t_ADDR addr, t_DATA d);
        Bool b = unpack(pack(d));
        Bit#(1) x = pack(memB.readPorts[loc_rd_port].sub(addr));
        if (b) x = ~ x;
        memA.upd(addr, unpack(x));
    endmethod

    method Action updB(t_ADDR addr, t_DATA d);
        Bool b = unpack(pack(d));
        Bit#(1) x = pack(memA.readPorts[loc_rd_port].sub(addr));
        if (b) x = ~ x;
        memB.upd(addr, unpack(x));
    endmethod

    interface readPorts = portsLocal;

endmodule
