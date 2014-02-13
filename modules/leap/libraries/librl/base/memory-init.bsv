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
