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

import FIFO::*;
import Vector::*;
import GetPut::*;


// ========================================================================
//
// Memory initialization
//
// ========================================================================

//
// mkMultiMemInitializedWith --
//     Initializes a memory using an FSM and provide a memory interface to
//     the initialized storage.  The memory cannot be accessed until the
//     FSM is done.   Uses an ADDR->VAL function to determine the
//     initial values.
//
module mkMultiMemInitializedWith#(MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) mem,
                                  function t_DATA initFunc(t_ADDR x))
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    // The current adddress we're updating.
    Reg#(Bit#(t_ADDR_SZ)) cur <- mkReg(0);
    
    // Are we initializing?
    Reg#(Bool) initializing <- mkReg(True);


    // initialize --
    //     When:   After a reset until every value is initialized.
    //     Effect: Update the RAM with the user-provided initial value.
    //
    rule initialize (initializing);
        t_ADDR cur_a = unpack(cur);
        mem.write(cur_a, initFunc(cur_a));
        cur <= cur + 1;

        if (cur == maxBound)
        begin
            initializing <= False;
        end
    endrule


    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();
    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr) if (!initializing);
                    mem.readPorts[p].readReq(addr);
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let v <- mem.readPorts[p].readRsp();
                    return v;
                endmethod

                method t_DATA peek() if (!initializing);
                    return mem.readPorts[p].peek();
                endmethod

                method Bool notEmpty() = mem.readPorts[p].notEmpty();

                method Bool notFull();
                    return !initializing && mem.readPorts[p].notFull();
                endmethod
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR a, t_DATA d) if (!initializing);
        mem.write(a, d);
    endmethod

    method Bool writeNotFull();
        return !initializing && mem.writeNotFull();
    endmethod
endmodule



//
// mkMultiMemInitializedWithGet --
//     Memory initialized with a Get source.
//
//     initFunc returns a stream of initialization values, followed by a single
//     Invalid to indicate the end of the stream.  The module can cope with
//     streams shorter than the size of memory (initializes the rest with 0)
//     and streams longer than the size of memory (consumes the full stream
//     and drops extra entries.)
//
//     This is identical to mkMultiMemInitializedWith except for initialization.
//
module mkMultiMemInitializedWithGet#(MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) mem,
                                     function Get#(Maybe#(t_DATA)) initFunc)

    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    // Are we initializing?
    Reg#(Bool) initialized_m <- mkReg(False);
    Reg#(Bool) finishInit <- mkReg(False);
    Reg#(Bool) sinkInit <- mkReg(False);
    Reg#(Bit#(t_ADDR_SZ)) init_idx <- mkReg(0);

    // initializing --
    //     When:   After a reset until every value is initialized.
    //     Effect: Update the RAM with the user-provided initial value.
    //
    rule initializing (! initialized_m && ! finishInit);
        let m_val <- initFunc.get;

        if (m_val matches tagged Valid .v)
        begin
            t_ADDR init_idx_a = unpack(init_idx);
            mem.write(init_idx_a, v);

            if (init_idx == maxBound)
            begin
                initialized_m <= True;
                sinkInit <= True;
            end

            init_idx <= init_idx + 1;
        end
        else
        begin
            finishInit <= True;
        end
    endrule

    //
    // zeroRemainder --
    //     If init stream ends before the full memory is initialized then
    //     complete initialization by writing 0 to the remainder.
    //
    rule zeroRemainder (! initialized_m && finishInit);
        t_ADDR init_idx_a = unpack(init_idx);
        mem.write(init_idx_a, unpack(0));

        if (init_idx == maxBound)
        begin
            initialized_m <= True;
            finishInit <= False;
        end

        init_idx <= init_idx + 1;
    endrule

    //
    // Sink any remaining initialization data, which is beyond the address
    // space.
    //
    rule sink (initialized_m && sinkInit);
        let m_val <- initFunc.get;
        sinkInit <= ! isValid(m_val);
    endrule


    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();
    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr) if (initialized_m);
                    mem.readPorts[p].readReq(addr);
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let v <- mem.readPorts[p].readRsp();
                    return v;
                endmethod

                method t_DATA peek() if (initialized_m);
                    return mem.readPorts[p].peek();
                endmethod

                method Bool notEmpty() = mem.readPorts[p].notEmpty();

                method Bool notFull();
                    return initialized_m && mem.readPorts[p].notFull();
                endmethod
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR a, t_DATA d) if (initialized_m);
        mem.write(a, d);
    endmethod

    method Bool writeNotFull();
        return initialized_m && mem.writeNotFull();
    endmethod
endmodule


//
// mkMultiMemInitialized --
//     A convenience-wrapper of mkMultiMemInitializedWith where the value is
//     constant.
//
module mkMultiMemInitialized#(MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) mem,
                              t_DATA initVal)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    // Wrap the data value in a dummy function.
    function t_DATA initFunc(t_ADDR a);
        return initVal;
    endfunction

    MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) m <- mkMultiMemInitializedWith(mem, initFunc);

    return m;
endmodule


//
// mkMemInitializedWith --
//     Initializes a memory using an FSM and provide a memory interface to
//     the initialized storage.  The memory cannot be accessed until the
//     FSM is done.   Uses an ADDR->VAL function to determine the
//     initial values.
//
module mkMemInitializedWith#(MEMORY_IFC#(t_ADDR, t_DATA) mem,
                             function t_DATA initFunc(t_ADDR x))
    // interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    // Convert to a multi-reader interface and use the initialization module.
    MEMORY_MULTI_READ_IFC#(1, t_ADDR, t_DATA) multi_m <- mkMemIfcToMultiMemIfc(mem);
    MEMORY_MULTI_READ_IFC#(1, t_ADDR, t_DATA) init_m <- mkMultiMemInitializedWith(multi_m, initFunc);

    // Convert back to single reader interface.
    MEMORY_IFC#(t_ADDR, t_DATA) m <- mkMultiMemIfcToMemIfc(init_m);

    return m;
endmodule


//
// mkMemInitialized --
//     A convenience-wrapper of mkMemInitializedWith where the value is
//     constant.
//
module mkMemInitialized#(MEMORY_IFC#(t_ADDR, t_DATA) mem,
                         t_DATA initVal)
    // interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    // Wrap the data value in a dummy function.
    function t_DATA initFunc(t_ADDR a);
        return initVal;
    endfunction

    MEMORY_IFC#(t_ADDR, t_DATA) m <- mkMemInitializedWith(mem, initFunc);

    return m;
endmodule


//
// mkMemInitializedWithGet --
//     Memory initialized with a Get source.
//
//     The Bool passed at the end of the initFunc, if true, indicates
//     initialization is complete even if all values have not been written.
//
//     This is identical to mkMemInitializedWith except for initialization.
//
module mkMemInitializedWithGet#(MEMORY_IFC#(t_ADDR, t_DATA) mem,
                                function Get#(Maybe#(t_DATA)) initFunc)
    // interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    // Convert to a multi-reader interface and use the initialization module.
    MEMORY_MULTI_READ_IFC#(1, t_ADDR, t_DATA) multi_m <- mkMemIfcToMultiMemIfc(mem);
    MEMORY_MULTI_READ_IFC#(1, t_ADDR, t_DATA) init_m <- mkMultiMemInitializedWithGet(multi_m, initFunc);

    // Convert back to single reader interface.
    MEMORY_IFC#(t_ADDR, t_DATA) m <- mkMultiMemIfcToMemIfc(init_m);

    return m;
endmodule
