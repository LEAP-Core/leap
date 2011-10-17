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


//
// This package provides a wrapper class that maps underlying indexed storage
// with a fixed word size to a new array of storage with a different word
// size.  Scratchpad memory, that is always presented as a system-wide
// fixed size can thus be marshalled into arbitrary-sized types.
//
// Note:  all type marshalling is in buckets with sizes that are powers of 2.
// While this may waste space it drastically simplifies addressing.
//


import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;


`include "awb/provides/librl_bsv_base.bsh"

//
// Number of slots in read state buffers.  This value controls the number
// of reads that may be in flight.  It is likely you want this value to be
// equal to (definitely not greater than) the number of scratchpad port ROB
// slots.
//
typedef 32 MEM_PACK_READ_SLOTS;


//
// Number of container read ports needed based on the number of user-visible
// read ports and the packing of objects to containers.  Because all mappings
// flow through mkMemPackMultiRead() below, there must be a single expression
// defining the relationship that works in all cases.
//

// Read port adder for many:1 mapping (0 when mapping is not many:1).
// many:1 mapping requires exactly 1 extra read port.
typedef TMin#(1, MEM_PACK_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ))
        MEM_PACK_SMALLER_INTERNAL_READ_PORTS#(numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);

// Read port multiplier for 1:many mapping (1 when mapping is not 1:many)
// 1:many mapping requires this many read ports per user-visible port.
typedef TDiv#(t_DATA_SZ, t_CONTAINER_DATA_SZ)
        MEM_PACK_LARGER_CHUNKS_PER_OBJ#(numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);

// Read ports for all mappings
typedef TMax#(TAdd#(n_READERS, MEM_PACK_SMALLER_INTERNAL_READ_PORTS#(t_DATA_SZ, t_CONTAINER_DATA_SZ)),
              TMul#(n_READERS, MEM_PACK_LARGER_CHUNKS_PER_OBJ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)))
        MEM_PACK_CONTAINER_READ_PORTS#(numeric type n_READERS, numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);


//
// Compute the number of objects of desired type that can fit inside a container
// type.  For a given data and container size, one of the two object index sizes
// will always be 0.  This becomes important in MEM_PACK_CONTAINER_ADDR!
//
// For many:1 mapping, the number of objects per container will always
// be a power of 2.  Other values would require a divide.
//
typedef TLog#(TDiv#(t_CONTAINER_DATA_SZ, TExp#(TLog#(t_DATA_SZ))))
        MEM_PACK_SMALLER_OBJ_IDX_SZ#(numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);

typedef TLog#(MEM_PACK_LARGER_CHUNKS_PER_OBJ#(t_DATA_SZ, t_CONTAINER_DATA_SZ))
        MEM_PACK_LARGER_OBJ_IDX_SZ#(numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);


// ************************************************************************
//
// KEY DATA TYPE:
//
// MEM_PACK_CONTAINER_ADDR is the address type of a container that will
// hold a vector of the desired quantity of the desired data.
//
// The computation works because at least one of MEM_PACK_SMALLER_OBJ_IDX_SZ
// and MEM_PACK_LARGER_OBJ_IDX_SZ must be 0.
//
// ************************************************************************

typedef Bit#(TAdd#(TSub#(t_ADDR_SZ,
                         MEM_PACK_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)),
                   MEM_PACK_LARGER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)))
        MEM_PACK_CONTAINER_ADDR#(numeric type t_ADDR_SZ, numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);


//
// mkMemPackMultiRead
//     The general wrapper to use for all allocations.  Map an array indexed
//     by t_ADDR_SZ bits of Bit#(t_DATA_SZ) objects onto backing storage
//     made up of objects of type Bit#(t_CONTAINDER_DATA_SZ).
//
//     This wrapper picks the right implementation module depending on whether
//     there is a 1:1 mapping of objects to containers or a more complicated
//     mapping.
//
module [m] mkMemPackMultiRead#(NumTypeParam#(t_CONTAINER_DATA_SZ) containerDataSz,
                               function m#(MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA)) containerMem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (IsModule#(m, a__),
              Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              NumAlias#(MEM_PACK_CONTAINER_READ_PORTS#(n_READERS, t_DATA_SZ, t_CONTAINER_DATA_SZ), n_CONTAINER_READERS),
              Alias#(MEM_PACK_CONTAINER_ADDR#(t_ADDR_SZ, t_DATA_SZ, t_CONTAINER_DATA_SZ), t_CONTAINER_ADDR),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ),
              Alias#(Bit#(t_CONTAINER_DATA_SZ), t_CONTAINER_DATA));

    //
    // Pick the appropriate packed memory module depending on the relative sizes
    // of the container and the target.
    //

    MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) pack_mem;
    if (valueOf(t_ADDR_SZ) == valueOf(t_CONTAINER_ADDR_SZ))
    begin
        // One object per container
        pack_mem <- mkMemPack1To1(containerDataSz, containerMem);
    end
    else if (valueOf(t_ADDR_SZ) > valueOf(t_CONTAINER_ADDR_SZ))
    begin
        // Multiple objects per container
        pack_mem <- mkMemPackManyTo1(containerDataSz, containerMem);
    end
    else
    begin
        // Object bigger than one container.  Use multiple containers for
        // each object.
        pack_mem <- mkMemPack1ToMany(containerDataSz, containerMem);
    end

    return pack_mem;
endmodule



// ========================================================================
//
// Internal modules.
//
// ========================================================================

//
// mkMemPack1To1 --
//     Map desired storage to a container for the case where one object
//     is stored per container.  The address spaces of the container and
//     and desired data are thus identical and the mapping is trivial.
//
module [m] mkMemPack1To1#(NumTypeParam#(t_CONTAINER_DATA_SZ) containerDataSz,
                          function m#(MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA)) containerMem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (IsModule#(m, a__),
              Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              NumAlias#(MEM_PACK_CONTAINER_READ_PORTS#(n_READERS, t_DATA_SZ, t_CONTAINER_DATA_SZ), n_CONTAINER_READERS),
              Alias#(MEM_PACK_CONTAINER_ADDR#(t_ADDR_SZ, t_DATA_SZ, t_CONTAINER_DATA_SZ), t_CONTAINER_ADDR),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ),
              Alias#(Bit#(t_CONTAINER_DATA_SZ), t_CONTAINER_DATA));

    // Instantiate the underlying memory.
    MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA) mem <- containerMem();

    //
    // Read ports
    //
    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr) = mem.readPorts[p].readReq(unpack(zeroExtendNP(pack(addr))));

                method ActionValue#(t_DATA) readRsp();
                    let v <- mem.readPorts[p].readRsp();
                    return unpack(truncateNP(pack(v)));
                endmethod

                method t_DATA peek() = unpack(truncateNP(pack(mem.readPorts[p].peek())));
                method Bool notEmpty() = mem.readPorts[p].notEmpty();
                method Bool notFull() = mem.readPorts[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    //
    // Write
    //
    method Action write(t_ADDR addr, t_DATA val);
        mem.write(unpack(zeroExtendNP(pack(addr))), unpack(zeroExtendNP(pack(val))));
    endmethod

    method Bool writeNotFull() = mem.writeNotFull();
endmodule



//
// mkMemPackManyTo1 --
//     Pack multiple objects into a single container object.
//
module [m] mkMemPackManyTo1#(NumTypeParam#(t_CONTAINER_DATA_SZ) containerDataSz,
                             function m#(MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA)) containerMem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (IsModule#(m, a__),
              Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              NumAlias#(MEM_PACK_CONTAINER_READ_PORTS#(n_READERS, t_DATA_SZ, t_CONTAINER_DATA_SZ), n_CONTAINER_READERS),
              Alias#(MEM_PACK_CONTAINER_ADDR#(t_ADDR_SZ, t_DATA_SZ, t_CONTAINER_DATA_SZ), t_CONTAINER_ADDR),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ),
              Alias#(Bit#(t_CONTAINER_DATA_SZ), t_CONTAINER_DATA),

              Alias#(Bit#(MEM_PACK_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)), t_OBJ_IDX),
              Bits#(t_OBJ_IDX, t_OBJ_IDX_SZ),

              // Arrangement of objects packed in a container.  Objects are evenly
              // spaced to make packed values easier to read while debugging.
              Alias#(Vector#(TExp#(t_OBJ_IDX_SZ), Bit#(TDiv#(t_CONTAINER_DATA_SZ, TExp#(t_OBJ_IDX_SZ)))), t_PACKED_CONTAINER));

    // Instantiate the underlying memory.
    MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA) mem <- containerMem();

    // Write state
    FIFOF#(t_ADDR) writeAddrQ <- mkFIFOF();
    FIFOF#(t_DATA) writeDataQ <- mkFIFOF();
    Reg#(Bool) writeActive <- mkReg(False);

    // Read request info holds the address of the requested data within the
    // container.
    Vector#(n_READERS, FIFO#(t_OBJ_IDX)) readReqInfoQ <- replicateM(mkSizedFIFO(valueOf(MEM_PACK_READ_SLOTS)));

    //
    // addrSplit --
    //     Split an incoming address into two components:  the container address
    //     and the index of the requested object within the container.
    //
    function Tuple2#(t_CONTAINER_ADDR, t_OBJ_IDX) addrSplit(t_ADDR addr);
        Bit#(t_ADDR_SZ) p_addr = pack(addr);
        return tuple2(unpack(p_addr[valueOf(t_ADDR_SZ)-1 : valueOf(t_OBJ_IDX_SZ)]), p_addr[valueOf(t_OBJ_IDX_SZ)-1 : 0]);
    endfunction


    //
    // startRMW --
    //     The beginning of a read-modify-write.
    //
    rule startRMW (! writeActive);
        let addr = writeAddrQ.first();
        match {.c_addr, .o_idx} = addrSplit(addr);

        // Read port 0 is reserved for RMW
        mem.readPorts[0].readReq(c_addr);
    
        writeActive <= True;
    endrule

    //
    // finishRMW --
    //     Process read response for a write.  Update the object within the
    //     container and write it back.
    //
    rule finishRMW (writeActive);
        let addr = writeAddrQ.first();
        writeAddrQ.deq();
        
        let val = writeDataQ.first();
        writeDataQ.deq();

        // Pack the current data into a vector of the number of objects
        // per container.
        let d <- mem.readPorts[0].readRsp();
        t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
        
        // Update the object in the container and write it back.
        match {.c_addr, .o_idx} = addrSplit(addr);
        pack_data[o_idx] = zeroExtendNP(pack(val));
        mem.write(c_addr, unpack(zeroExtendNP(pack(pack_data))));
        
        writeActive <= False;
    endrule


    //
    // Methods
    //
    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr) if (! writeAddrQ.notEmpty());
                    match {.c_addr, .o_idx} = addrSplit(addr);
                    // Port 0 is reserved for reads to service read-modify-write.
                    // The container memory has an extra read port, so shift
                    // all requests up 1.
                    mem.readPorts[p + 1].readReq(c_addr);

                    readReqInfoQ[p].enq(o_idx);
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let o_idx = readReqInfoQ[p].first();
                    readReqInfoQ[p].deq();

                    // Receive the data and return the desired object from the container.
                    let d <- mem.readPorts[p + 1].readRsp();
                    t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
                    return unpack(truncateNP(pack_data[o_idx]));
                endmethod

                method t_DATA peek();
                    let o_idx = readReqInfoQ[p].first();
    
                    // Receive the data and return the desired object from the container.
                    let d = mem.readPorts[p + 1].peek();
                    t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
                    return unpack(truncateNP(pack_data[o_idx]));
                endmethod

                method Bool notEmpty() = mem.readPorts[p + 1].notEmpty();
                method Bool notFull() = mem.readPorts[p + 1].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val);
        writeAddrQ.enq(addr);
        writeDataQ.enq(val);
    endmethod

    method Bool writeNotFull() = writeAddrQ.notFull();
endmodule


//
// mkMemPack1ToMany --
//     Spread one object across multiple container objects.
//
module [m] mkMemPack1ToMany#(NumTypeParam#(t_CONTAINER_DATA_SZ) containerDataSz,
                             function m#(MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA)) containerMem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (IsModule#(m, a__),
              Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              NumAlias#(MEM_PACK_CONTAINER_READ_PORTS#(n_READERS, t_DATA_SZ, t_CONTAINER_DATA_SZ), n_CONTAINER_READERS),
              Alias#(MEM_PACK_CONTAINER_ADDR#(t_ADDR_SZ, t_DATA_SZ, t_CONTAINER_DATA_SZ), t_CONTAINER_ADDR),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ),
              Alias#(Bit#(t_CONTAINER_DATA_SZ), t_CONTAINER_DATA),

              Alias#(Bit#(MEM_PACK_LARGER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)), t_OBJ_IDX),
       
              // Vector of multiple containers holding one object
              NumAlias#(MEM_PACK_LARGER_CHUNKS_PER_OBJ#(t_DATA_SZ, t_CONTAINER_DATA_SZ), n_CHUNKS_PER_OBJ),
              Alias#(Vector#(n_CHUNKS_PER_OBJ, t_CONTAINER_DATA), t_PACKED_CONTAINER));

    // Instantiate the underlying memory.  Extra read ports are allocated
    // to account for the mapping of data across multiple container elements.
    MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS,
                           t_CONTAINER_ADDR,
                           t_CONTAINER_DATA) mem <- containerMem();

    // Write state
    FIFOF#(Tuple2#(t_ADDR, t_PACKED_CONTAINER)) writeQ <- mkBypassFIFOF();
    Reg#(t_OBJ_IDX) reqIdx <- mkReg(0);

    let chunks_per_obj = valueOf(n_CHUNKS_PER_OBJ);

    //
    // Need multiple containers for a single object, so the container
    // address is a function of the incoming address and the number of
    // container objects per base object.
    //
    function t_CONTAINER_ADDR addrContainer(t_ADDR addr, t_OBJ_IDX objIdx);
        let c_addr = pack(addr) * fromInteger(chunks_per_obj) + zeroExtendNP(objIdx);
        return unpack(zeroExtendNP(c_addr));
    endfunction


    //
    // writeData --
    //     Break down an incoming write request into multiple writes to containers.
    //
    rule writeData (True);
        match {.addr, .data} = writeQ.first();

        let c_addr = addrContainer(addr, reqIdx);
        mem.write(c_addr, data[reqIdx]);

        if (reqIdx == fromInteger(valueOf(TSub#(n_CHUNKS_PER_OBJ, 1))))
        begin
            writeQ.deq();
            reqIdx <= 0;
        end
        else
        begin
            reqIdx <= reqIdx + 1;
        end
    endrule


    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                //
                // Only allowed to start a read if a write is not in progress.
                // This preserves read/write order.
                //
                method Action readReq(t_ADDR addr) if (! writeQ.notEmpty());
                    // Separate ports are allocated for each chunk associated with
                    // a read request.  Start all reads together.
                    for (Integer cp = 0; cp < chunks_per_obj; cp = cp + 1)
                    begin
                        mem.readPorts[p + cp].readReq(addrContainer(addr, fromInteger(cp)));
                    end
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    t_PACKED_CONTAINER v = newVector();
                    for (Integer cp = 0; cp < chunks_per_obj; cp = cp + 1)
                    begin
                        v[cp] <- mem.readPorts[p + cp].readRsp();
                    end

                    return unpack(truncateNP(pack(v)));
                endmethod

                method t_DATA peek();
                    t_PACKED_CONTAINER v = newVector();
                    for (Integer cp = 0; cp < chunks_per_obj; cp = cp + 1)
                    begin
                        v[cp] = mem.readPorts[p + cp].peek();
                    end

                    return unpack(truncateNP(pack(v)));
                endmethod

                method Bool notEmpty();
                    Bool not_empty = True;
                    for (Integer cp = 0; cp < chunks_per_obj; cp = cp + 1)
                    begin
                        not_empty = not_empty && mem.readPorts[p + cp].notEmpty();
                    end

                    return not_empty;
                endmethod

                method Bool notFull();
                    Bool not_full = ! writeQ.notEmpty();
                    for (Integer cp = 0; cp < chunks_per_obj; cp = cp + 1)
                    begin
                        not_full = not_full && mem.readPorts[p + cp].notFull();
                    end

                    return not_full;
                endmethod
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val);
        t_PACKED_CONTAINER write_data = unpack(zeroExtendNP(pack(val)));
        writeQ.enq(tuple2(addr, write_data));
    endmethod

    method Bool writeNotFull() = writeQ.notFull();
endmodule
