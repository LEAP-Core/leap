//
// Copyright (C) 2011 Intel Corporation
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

import FIFO::*;
import FIFOF::*;

//
// Algorithms for mapping memory over varying address spaces.
//


//=========================================================================
//
// Banked memory.  Present a multi-read-port memory interface as a unified
// space but implement the underlying storage as multiple banks to reduce
// contention between read ports.
//
//=========================================================================

typedef enum
{
    MEM_BANK_SELECTOR_BITS_HIGH,
    MEM_BANK_SELECTOR_BITS_LOW
}
MEM_BANK_SELECTOR_BITS
    deriving (Eq, Bits);

//
// mkMultiReadBankedMemory --
//     Construct the requested address space using multiple banks.
//
//     Note: Memory constructors that take a function to initialize storage
//           won't work especially well here, since the mapping from the
//           full address space to the space within each bank requires
//           knowledge of the bank ID.
//
module [m] mkMultiReadBankedMemory#(NumTypeParam#(n_BANKS) p_banks,
                                    MEM_BANK_SELECTOR_BITS selectorBits,
                                    function m#(MEMORY_MULTI_READ_IFC#(t_NUM_READERS, t_BANK_ADDR, t_DATA)) memImpl)
    // interface:
    (MEMORY_MULTI_READ_IFC#(t_NUM_READERS, t_ADDR, t_DATA))
    provisos
        (IsModule#(m, a__),
         Bits#(t_ADDR, t_ADDR_SZ),
         Bits#(t_DATA, t_DATA_SZ),
         // Break t_ADDR into bank and address within the bank
         Alias#(Bit#(TLog#(n_BANKS)), t_BANK_IDX),
         Bits#(t_BANK_IDX, t_BANK_IDX_SZ),
         Alias#(Bit#(TSub#(t_ADDR_SZ, t_BANK_IDX_SZ)), t_BANK_ADDR));

    // Instantiate memory banks
    Vector#(n_BANKS,
            MEMORY_MULTI_READ_IFC#(t_NUM_READERS,
                                   t_BANK_ADDR,
                                   t_DATA)) memory <- replicateM(memImpl());
    
    Vector#(t_NUM_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) localPorts = newVector();

    // Record bank of requests in flight
    Vector#(t_NUM_READERS, FIFOF#(t_BANK_IDX)) reqQ <- replicateM(mkSizedFIFOF(8));

    //
    // Compute the bank and address within the bank.
    //
    function Tuple2#(t_BANK_IDX, t_BANK_ADDR) bankAndAddr(t_ADDR fullAddr);
        t_BANK_IDX idx;
        t_BANK_ADDR addr;

        // resize() below keeps Bluespec from requring more module provisos.
        if (selectorBits == MEM_BANK_SELECTOR_BITS_HIGH)
        begin
            {idx, addr} = resize(fullAddr);
        end
        else
        begin
            {addr, idx} = resize(fullAddr);
        end
    
        return tuple2(idx, addr);
    endfunction

    //
    // Read ports
    //
    for (Integer x = 0; x < valueof(t_NUM_READERS); x = x + 1)
    begin
        localPorts[x] = interface MEMORY_READER_IFC
                           method Action readReq(t_ADDR addr);
                               match {.bank, .bank_addr} = bankAndAddr(addr);
                               memory[bank].readPorts[x].readReq(bank_addr);
                               reqQ[x].enq(bank);
                           endmethod

                           method ActionValue#(t_DATA) readRsp();
                               let bank = reqQ[x].first();
                               reqQ[x].deq();

                               let rsp <- memory[bank].readPorts[x].readRsp();
                               return rsp;
                           endmethod

                           method t_DATA peek();
                               let bank = reqQ[x].first();
                               return memory[bank].readPorts[x].peek();
                           endmethod

                           method Bool notEmpty();
                               if (! reqQ[x].notEmpty())
                               begin
                                   // No request in flight
                                   return False;
                               end
                               else
                               begin
                                   let bank = reqQ[x].first();
                                   return memory[bank].readPorts[x].notEmpty();
                               end
                           endmethod

                           method Bool notFull();
                               if (! reqQ[x].notEmpty())
                               begin
                                   // No request in flight
                                   return True;
                               end
                               else
                               begin
                                   let bank = reqQ[x].first();
                                   return memory[bank].readPorts[x].notFull();
                               end
                           endmethod
                       endinterface;
    end

    interface readPorts = localPorts;

    // Write port
    method Action write(t_ADDR addr, t_DATA val);
        match {.bank, .bank_addr} = bankAndAddr(addr);
        memory[bank].write(bank_addr, val);
    endmethod
    
    method Bool writeNotFull();
        // Must be conservative since the bank isn't known
        function Bool wNotFull(MEMORY_MULTI_READ_IFC#(t_NUM_BANKS,
                                                      t_BANK_ADDR,
                                                      t_DATA) bank) = bank.writeNotFull();

        return all(wNotFull, memory);
    endmethod
endmodule
