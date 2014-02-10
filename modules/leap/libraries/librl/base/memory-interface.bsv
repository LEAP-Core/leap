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

import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import Connectable::*;
import Arbiter::*;


// ========================================================================
//
// Memory interface definition
//
// ========================================================================

//
// This is a general interface to a multi-cycle memory.  By making it common we
// hope that code can switch between different memories changing only the
// call to a module constructor.
//

interface MEMORY_IFC#(type t_ADDR, type t_DATA);
    method Action readReq(t_ADDR addr);
    method ActionValue#(t_DATA) readRsp();

    // Look at the read response value without popping it
    method t_DATA peek();

    // Read response ready
    method Bool notEmpty();

    // Read request possible?
    method Bool notFull();


    method Action write(t_ADDR addr, t_DATA val);
    
    // Write request possible?
    method Bool writeNotFull();
endinterface

//
// Memory interface with memory fence supported. 
//
interface MEMORY_WITH_FENCE_IFC#(type t_ADDR, type t_DATA);
    method Action readReq(t_ADDR addr);
    method ActionValue#(t_DATA) readRsp();

    // Look at the read response value without popping it
    method t_DATA peek();

    // Read response ready
    method Bool notEmpty();

    // Read request possible?
    method Bool notFull();

    method Action write(t_ADDR addr, t_DATA val);
    
    // Write request possible?
    method Bool writeNotFull();

    // Test and set request 
    method Action testAndSetReq(t_ADDR addr, t_DATA val);
    // Test and set response
    method ActionValue#(t_DATA) testAndSetRsp();

    // Insert a memory fence. All requests issued earlier should
    // be processed before the fence request gets processed.
    method Action fence();
    // Insert a memory wrtie fence. Write requests issued earlier should
    // be processed before the fence request gets processed.
    method Action writeFence();
    // Insert a memory wrtie fence. Read requests issued earlier should
    // be processed before the fence request gets processed.
    method Action readFence();

    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface

//
// Single reader interface
//
interface MEMORY_READER_IFC#(type t_ADDR, type t_DATA);
    method Action readReq(t_ADDR addr);
    method ActionValue#(t_DATA) readRsp();
    method t_DATA peek();
    method Bool notEmpty();
    method Bool notFull();
endinterface

//
// Single writer interface
// This might initially seem counter-intuitive, but we'll use this function
// to manipulate vectorized interfaces later.
//
interface MEMORY_WRITER_IFC#(type t_ADDR, type t_DATA);
    method Action write(t_ADDR addr, t_DATA val);
    // Write request possible?
    method Bool writeNotFull();
endinterface

//
// Memory with one writer and multiple readers.
//
interface MEMORY_MULTI_READ_IFC#(numeric type n_READERS, type t_ADDR, type t_DATA);
    interface Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPorts;

    method Action write(t_ADDR addr, t_DATA val);
    method Bool writeNotFull();
endinterface

//
// Memory with one writer and multiple readers.
// Memory fence is supported. 
//
interface MEMORY_MULTI_READ_WITH_FENCE_IFC#(numeric type n_READERS, type t_ADDR, type t_DATA);
    interface Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPorts;

    method Action write(t_ADDR addr, t_DATA val);
    method Bool writeNotFull();
    
    // Test and set request 
    method Action testAndSetReq(t_ADDR addr, t_DATA val);
    // Test and set response
    method ActionValue#(t_DATA) testAndSetRsp();

    // Insert a memory fence. All requests issued earlier should
    // be processed before the fence request gets processed.
    method Action fence();
    // Insert a memory wrtie fence. Write requests issued earlier should
    // be processed before the fence request gets processed.
    method Action writeFence();
    // Insert a memory wrtie fence. Read requests issued earlier should
    // be processed before the fence request gets processed.
    method Action readFence();
    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface

//
// MEMORY_MULTI_READ_MASKED_WRITE_IFC
// Memory with multiple readers and one writer with write mask.
//
interface MEMORY_MULTI_READ_MASKED_WRITE_IFC#(numeric type n_READERS, type t_ADDR, type t_DATA, type t_MASK);
    interface Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPorts;

    method Action write(t_ADDR addr, t_DATA val, t_MASK mask);
    method Bool writeNotFull();
endinterface

//
// MEMORY_MULTI_READ_MASKED_WRITE_WITH_FENCE_IFC
// Memory with multiple readers and one writer with write mask.
// Memory fence is supported. 
//
interface MEMORY_MULTI_READ_MASKED_WRITE_WITH_FENCE_IFC#(numeric type n_READERS, type t_ADDR, type t_DATA, type t_MASK);
    interface Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPorts;

    method Action write(t_ADDR addr, t_DATA val, t_MASK mask);
    method Bool writeNotFull();
    
    // Test and set request 
    method Action testAndSetReq(t_ADDR addr, t_DATA val, t_MASK mask);
    // Test and set response
    method ActionValue#(t_DATA) testAndSetRsp();

    // Insert a memory fence. All requests issued earlier should
    // be processed before the fence request gets processed.
    method Action fence();
    // Insert a memory wrtie fence. Write requests issued earlier should
    // be processed before the fence request gets processed.
    method Action writeFence();
    // Insert a memory wrtie fence. Read requests issued earlier should
    // be processed before the fence request gets processed.
    method Action readFence();
    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface

// ========================================================================
//
// Burst Memory interface
//
// ========================================================================

//
// This is a general interface to a multi-cycle memory, which may also 
// support burst requests. MEMORY_IFC can be expressed in terms of this 
// interface.  That would be a good excercise for some lazy Friday.
//

typedef struct
{
    t_ADDR addr;
    Bit#(TAdd#(1,TLog#(n_MAX_BURST))) size;
}
BURST_COMMAND#(type t_ADDR, numeric type n_MAX_BURST)
    deriving(Bits, Eq);

typedef union tagged
{
    BURST_COMMAND#(t_ADDR,n_MAX_BURST) ReadReq;
    BURST_COMMAND#(t_ADDR,n_MAX_BURST) WriteReq;
}
BURST_REQUEST#(type t_ADDR, numeric type n_MAX_BURST)
    deriving(Bits, Eq);


interface BURST_MEMORY_IFC#(type t_ADDR, type t_DATA, numeric type n_MAX_BURST);
    method ActionValue#(t_DATA) readRsp();

    // Look at the read response value without popping it
    method t_DATA peek();

    // Read response ready
    method Bool notEmpty();

    // Read request possible?
    method Bool notFull();

    // We must split the write request and response...
    method Action writeData(t_DATA data); 

    method Action burstReq(BURST_REQUEST#(t_ADDR, n_MAX_BURST) burstReq);
    
    // Write request possible?
    method Bool writeNotFull();
endinterface

//
// This is a complimentary interface to BURST_MEMORY_IFC and is intended to be connectable
//

interface BURST_MEMORY_CLIENT_IFC#(type t_ADDR, type t_DATA, numeric type n_MAX_BURST);
    method Action readRsp(t_DATA data);

    // Look at the read response value without popping it
    method Action peek(t_DATA value);

    // Read response ready
    method Action notEmpty(Bool value);

    // Read request possible?
    method Action notFull(Bool value);

    // We must split the write request and response...
    method ActionValue#(t_DATA) writeData(); 

    method ActionValue#(BURST_REQUEST#(t_ADDR, n_MAX_BURST)) burstReq();
    
    // Write request possible?
    method Action writeNotFull(Bool value);
endinterface


//
//  Connect a BURST_MEMORY_IFC to a BURST_MEMORY_CLIENT_IFC
//

instance Connectable#(BURST_MEMORY_IFC#(t_ADDR,t_DATA,n_MAX_BURST),
                      BURST_MEMORY_CLIENT_IFC#(t_ADDR,t_DATA,n_MAX_BURST));
  module mkConnection#(BURST_MEMORY_IFC#(t_ADDR,t_DATA,n_MAX_BURST) server,
                       BURST_MEMORY_CLIENT_IFC#(t_ADDR,t_DATA,n_MAX_BURST) client) (Empty);
    mkConnection(server.burstReq, client.burstReq);    
    mkConnection(client.readRsp, server.readRsp);    
    mkConnection(server.writeData, client.writeData);    
 
    rule peekRule;
      client.peek(server.peek);
    endrule

    rule notEmptyRule;
      client.notEmpty(server.notEmpty);
    endrule

    rule notFullRule;
      client.notFull(server.notFull);
    endrule

    rule writeNotFullRule;
      client.writeNotFull(server.writeNotFull);
    endrule

  endmodule
endinstance


// ========================================================================
//
// Memory interface conversion
//
// ========================================================================

//
//  mkMemIfcToMemReaderIfc
//  Converts a memory interface down into a reader
//

module mkMemIfcToMemReaderIfc#(MEMORY_IFC#(t_ADDR, t_DATA) memory)
    // interface:
    (MEMORY_READER_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    method Action readReq(t_ADDR addr) = memory.readReq(addr);

    method ActionValue#(t_DATA) readRsp();
        let v <- memory.readRsp();
        return v;
    endmethod

    method t_DATA peek() = memory.peek();
    method Bool notEmpty() = memory.notEmpty();
    method Bool notFull() = memory.notFull();
endmodule

//
//  mkMemIfcToMemWriterIfc
//  Converts a memory interface down into a writer
//
module mkMemIfcToMemWriterIfc#(MEMORY_IFC#(t_ADDR, t_DATA) memory)
    // interface:
    (MEMORY_WRITER_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));
    method Action write(t_ADDR addr, t_DATA val) = memory.write(addr, val);
    method Bool writeNotFull() = memory.writeNotFull();
endmodule

//
// mkMultiMemIfcToMemIfc --
//     Interface conversion from a MEMORY_MULTI_READ_IFC with one port to a
//     MEMORY_IFC.  Useful for implementing a memory that supports an arbitrary
//     number of ports without having to special case the code for a single port.
//
module mkMultiMemIfcToMemIfc#(MEMORY_MULTI_READ_IFC#(1, t_ADDR, t_DATA) multiMem)
    // interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    method Action readReq(t_ADDR addr) = multiMem.readPorts[0].readReq(addr);

    method ActionValue#(t_DATA) readRsp();
        let v <- multiMem.readPorts[0].readRsp();
        return v;
    endmethod

    method t_DATA peek() = multiMem.readPorts[0].peek();
    method Bool notEmpty() = multiMem.readPorts[0].notEmpty();
    method Bool notFull() = multiMem.readPorts[0].notFull();

    method Action write(t_ADDR addr, t_DATA val) = multiMem.write(addr, val);
    method Bool writeNotFull() = multiMem.writeNotFull();
endmodule

// 
// mkMemFenceIfcToMemIfc -- 
//     Interface conversion from a MEMORY_WITH_FENCE_IFC to a basic MEMORY_IFC.    
// 
module mkMemFenceIfcToMemIfc#(MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) mem)
    // interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    method Action readReq(t_ADDR addr) = mem.readReq(addr);

    method ActionValue#(t_DATA) readRsp();
        let v <- mem.readRsp();
        return v;
    endmethod

    method t_DATA peek() = mem.peek();
    method Bool notEmpty() = mem.notEmpty();
    method Bool notFull() = mem.notFull();

    method Action write(t_ADDR addr, t_DATA val) = mem.write(addr, val);
    method Bool writeNotFull() = mem.writeNotFull();
endmodule

//
// mkMultiMemFenceIfcToMemFenceIfc --
//     Interface conversion from a MEMORY_MULTI_READ_WITH_FENCE_IFC with one port 
//     to a MEMORY_WITH_FENCE_IFC.  Useful for implementing a memory that supports 
//     an arbitrary number of ports without having to special case the code for 
//     a single port.
//
module mkMultiMemFenceIfcToMemFenceIfc#(MEMORY_MULTI_READ_WITH_FENCE_IFC#(1, t_ADDR, t_DATA) multiMem)
    // interface:
    (MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    method Action readReq(t_ADDR addr) = multiMem.readPorts[0].readReq(addr);

    method ActionValue#(t_DATA) readRsp();
        let v <- multiMem.readPorts[0].readRsp();
        return v;
    endmethod

    method t_DATA peek() = multiMem.readPorts[0].peek();
    method Bool notEmpty() = multiMem.readPorts[0].notEmpty();
    method Bool notFull() = multiMem.readPorts[0].notFull();

    method Action write(t_ADDR addr, t_DATA val) = multiMem.write(addr, val);
    method Bool writeNotFull() = multiMem.writeNotFull();

    method Action testAndSetReq(t_ADDR addr, t_DATA val) = multiMem.testAndSetReq(addr, val);
    method ActionValue#(t_DATA) testAndSetRsp();
        let resp <- multiMem.testAndSetRsp();
        return resp;
    endmethod

    method Action fence() = multiMem.fence();
    method Action writeFence() = multiMem.writeFence();
    method Action readFence() = multiMem.readFence();
    method Bool writePending() = multiMem.writePending();
    method Bool readPending() = multiMem.readPending();
endmodule

//
// mkMultiReadMemToVectorMemIfc --
//     Converts a MEMORY_MULTI_READ_IFC to a Vector of MEMORY_IFC each of which 
//     share the write port.  Used to split up the memory interfaces in the multicache.

module mkMultiReadMemIfcToVectorMemIfc#(MEMORY_MULTI_READ_IFC#(n_Readers, 
                                                               t_ADDR, 
                                                               t_DATA) multiMem)
    (Vector#(n_Readers, MEMORY_IFC#(t_ADDR, t_DATA)))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));
    Vector#(n_Readers, MEMORY_IFC#(t_ADDR, t_DATA)) memories = newVector();
 
    for(Integer i = 0; i < valueof(n_Readers); i = i + 1) 
    begin
        MEMORY_IFC#(t_ADDR, t_DATA) memory = interface MEMORY_IFC
            method readReq = multiMem.readPorts[i].readReq;
            method readRsp =multiMem.readPorts[i].readRsp;
            method peek = multiMem.readPorts[i].peek;
            method notEmpty = multiMem.readPorts[i].notEmpty;
            method notFull = multiMem.readPorts[i].notFull;
            method write = multiMem.write;
            method writeNotFull = multiMem.writeNotFull;
        endinterface;
        memories[i] = memory;
    end

    return memories;
endmodule


//
//  mkVectorMemIfcToMultiReadMemIfc --
//     Converts a Vector of MEMORY_IFC to a each MEMORY_MULTI_READ_IFC.  
//     Each of the write functions are tied to the single write function of
//     the MEMORY_MULTI_READ_IFC. 

module mkVectorMemIfcToMultiReadMemIfc#(Vector#(n_Readers, MEMORY_IFC#(t_ADDR, t_DATA)) memories)
    (MEMORY_MULTI_READ_IFC#(n_Readers, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    Vector#(n_Readers, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPortsLocal = newVector();  
    
    for(Integer i = 0; i < valueof(n_Readers); i = i + 1) 
    begin
        MEMORY_READER_IFC#(t_ADDR, t_DATA) reader = interface MEMORY_READER_IFC
            method readReq = memories[i].readReq;
            method readRsp = memories[i].readRsp;
            method peek    = memories[i].peek;
            method notEmpty= memories[i].notEmpty;
            method notFull = memories[i].notFull;
        endinterface;
        readPortsLocal[i] = reader;
    end
    
    MEMORY_MULTI_READ_IFC#(n_Readers, t_ADDR, t_DATA) multiMem = interface MEMORY_MULTI_READ_IFC
        interface readPorts = readPortsLocal;    

        // One write to touch them all, one write to bind them.
        method Action write(t_ADDR addr, t_DATA data);
            for(Integer i = 0; i < valueof(n_Readers); i = i + 1) 
            begin            
              memories[i].write(addr,data);
            end
        endmethod

        // If any of the memories are full, they are all full.
        method Bool writeNotFull;
            Bool notFull = True;
            for(Integer i = 0; i < valueof(n_Readers); i = i + 1) 
            begin            
              notFull = notFull && memories[i].writeNotFull();
            end

            return notFull;
        endmethod
    endinterface;

    return multiMem;
endmodule

//
//  mkVectorMemIfcToMultiReadMemIfc --
//     Converts a Vector of MEMORY_IFC to a each MEMORY_MULTI_READ_IFC.  
//     Each of the write functions are tied to the single write function of
//     the MEMORY_MULTI_READ_IFC. 

module mkMemWriterAndVectorMemReaderIfcToMultiReadMemIfc#(
    MEMORY_WRITER_IFC#(t_ADDR, t_DATA) writer,
    Vector#(n_Readers, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readers)
    (MEMORY_MULTI_READ_IFC#(n_Readers, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    Vector#(n_Readers, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPortsLocal = newVector();  
    
    for(Integer i = 0; i < valueof(n_Readers); i = i + 1) 
    begin
        MEMORY_READER_IFC#(t_ADDR, t_DATA) reader = interface MEMORY_READER_IFC
            method readReq = readers[i].readReq;
            method readRsp = readers[i].readRsp;
            method peek    = readers[i].peek;
            method notEmpty= readers[i].notEmpty;
            method notFull = readers[i].notFull;
        endinterface;
        readPortsLocal[i] = reader;
    end
    
    MEMORY_MULTI_READ_IFC#(n_Readers, t_ADDR, t_DATA) multiMem = interface MEMORY_MULTI_READ_IFC
        interface readPorts = readPortsLocal;    
 
         // One write to touch them all, one write to bind them.
         method Action write(t_ADDR addr, t_DATA data);
             writer.write(addr,data);
         endmethod

         // If any of the memories are full, they are all full.
         method Bool writeNotFull;
             return writer.writeNotFull();
         endmethod
    endinterface;

    return multiMem;
endmodule


// ========================================================================
//
// Safe reader (output buffer credit management).
//
// ========================================================================

//
// mkSafeMemoryReader --
//     A wrapper for memory reader that guarantees output buffer space
//     before issuing a request to memory.  This helps in deadlock avoidance,
//     by guaranteeing that memory responses are drained, in the case that a 
//     memory is shared by several readers.
//
module mkSafeMemoryReader#(MEMORY_READER_IFC#(t_ADDR, t_DATA) unsafeReader) (MEMORY_READER_IFC#(t_ADDR, t_DATA))
    provisos(Bits#(t_DATA, t_DATA_SZ));
  
    // State elements.  Notice that bypass/loopy fifo usage preserves performance
    FIFOF#(Bit#(0)) tokenFIFO <- mkLFIFOF();
    FIFOF#(t_DATA) outputFIFO <- mkBypassFIFOF();
    
    rule response;
        t_DATA data <- unsafeReader.readRsp;
        outputFIFO.enq(data);
    endrule

    method Action readReq(t_ADDR addr);
        tokenFIFO.enq(0);
        unsafeReader.readReq(addr);
    endmethod

    method ActionValue#(t_DATA) readRsp();
        tokenFIFO.deq;
        outputFIFO.deq;
        return outputFIFO.first;
    endmethod

    method peek = outputFIFO.first;
    method notEmpty = outputFIFO.notEmpty;
    method notFull = tokenFIFO.notFull;

endmodule


//
// mkSizedSafeMemoryReader --
//     A wrapper for memory reader that guarantees output buffer space
//     before issuing a request to memory.  This helps in deadlock avoidance,
//     by guaranteeing that memory responses are drained, in the case that a 
//     memory is shared by several readers.  Unlike the preceding non-size module,
//     this one takes a size parameter, but doesn't have the LFIFOF. This might 
//     introduce some latency
//
module mkSafeSizedMemoryReader#(NumTypeParam#(n_ENTRIES) p, MEMORY_READER_IFC#(t_ADDR, t_DATA) unsafeReader) (MEMORY_READER_IFC#(t_ADDR, t_DATA))
    provisos(Bits#(t_DATA, t_DATA_SZ));
  
    // State elements.  Notice that bypass/loopy fifo usage preserves performance
    FIFOF#(Bit#(0)) tokenFIFO <- mkSizedFIFOF(valueof(n_ENTRIES));
    FIFOF#(t_DATA) outputFIFO <- mkSizedBypassFIFOF(valueof(n_ENTRIES));
    
    rule response;
        t_DATA data <- unsafeReader.readRsp;
        outputFIFO.enq(data);
    endrule

    method Action readReq(t_ADDR addr);
        tokenFIFO.enq(0);
        unsafeReader.readReq(addr);
    endmethod

    method ActionValue#(t_DATA) readRsp();
        tokenFIFO.deq;
        outputFIFO.deq;
        return outputFIFO.first;
    endmethod

    method peek = outputFIFO.first;
    method notEmpty = outputFIFO.notEmpty;
    method notFull = tokenFIFO.notFull;

endmodule


// ========================================================================
//
// Convert a single read port memory interface to a multi read port
// interface.  A number of modules are provided using a variety of
// strategies.
//
// ========================================================================

//
// mkMemIfcToMultiMemIfc --
//     Convert a standard MEMORY_IFC to a MEMORY_MULTI_READ_IFC with a
//     single read port.  This conversion is a simple interface method
//     mapping.
//
module mkMemIfcToMultiMemIfc#(MEMORY_IFC#(t_ADDR, t_DATA) mem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(1, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    Vector#(1, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();
    portsLocal[0] =
        interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
            method Action readReq(t_ADDR addr) = mem.readReq(addr);

            method ActionValue#(t_DATA) readRsp();
                let v <- mem.readRsp();
                return v;
            endmethod

            method t_DATA peek() = mem.peek();
            method Bool notEmpty() = mem.notEmpty();
            method Bool notFull() = mem.notFull();
        endinterface;

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val) = mem.write(addr, val);
    method Bool writeNotFull() = mem.writeNotFull();
endmodule


//
// mkMemIfcToPseudoMultiMemSyncWrites --
//     Provide the illusion of multiple read ports by multiplexing all
//     requests on a single physical read port.  Limited buffering is
//     provided for holding responses in order prevent one port from
//     blocking another.
//
//     In this implementation, writes are sequenced along with reads.
//     A write request arriving on the same cycle as a set of read
//     requests will be processed AFTER the read requests.  The write
//     will be processed BEFORE and subsequent read requests arriving
//     on later cycles.
//
module mkMemIfcToPseudoMultiMemSyncWrites#(MEMORY_IFC#(t_ADDR, t_DATA) mem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),

              // Compute minimum size for storing read port ID (must be at least
              // 1 bit).
              Log#(n_READERS, n_READERS_SZ),
              Max#(n_READERS_SZ, 1, n_READERS_SAFE_SZ));

    // Sort incoming requests.  One port for each read port and another for writes.
    MERGE_FIFOF#(TAdd#(n_READERS, 1), t_ADDR) incomingReqQ <- mkMergeBypassFIFOF();

    // Write data
    FIFO#(t_DATA) writeDataQ <- mkBypassFIFO();

    // Match requests to ports.  Add 1 to the number of readers to guarantee
    // we never try to allocate a Bit#(0).
    FIFO#(Bit#(n_READERS_SAFE_SZ)) noteReqQ <- mkFIFO();

    // How much buffering is available?  Buffering matches the depth of mkBRAM.
    Vector#(n_READERS, COUNTER#(2)) bufferingAvailable <- replicateM(mkLCounter(2));
    Vector#(n_READERS, FIFOF#(t_DATA)) buffer <- replicateM(mkSizedBypassFIFOF(2));

    //
    // processWriteReq --
    //     Send writes to the BRAM.  Write port is the last port in the
    //     request queue.
    //
    rule processWriteReq (incomingReqQ.firstPortID() == fromInteger(valueOf(n_READERS)));
        let addr = incomingReqQ.first();
        incomingReqQ.deq();

        let val = writeDataQ.first();
        writeDataQ.deq();
        
        mem.write(addr, val);
    endrule


    //
    // Read rules
    //
    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        //
        // processReadReq --
        //     Forward read requests to the memory.
        //
        rule processReadReq ((incomingReqQ.firstPortID() == fromInteger(p)) &&
                             (bufferingAvailable[p].value() > 0));
            let addr = incomingReqQ.first();
            incomingReqQ.deq();

            mem.readReq(addr);

            noteReqQ.enq(fromInteger(p));
            bufferingAvailable[p].down();
        endrule

        //
        // enqIntoFIFO --
        //     Forward BRAM response to read port's response buffer.
        //
        rule enqIntoFIFO (noteReqQ.first() == fromInteger(p));
            noteReqQ.deq();

            let data <- mem.readRsp();
            buffer[p].enq(data);
        endrule
    end
    

    //
    // readPorts
    //

    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR a);
                    incomingReqQ.ports[p].enq(a);
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    bufferingAvailable[p].up();

                    let v = buffer[p].first();
                    buffer[p].deq();

                    return v;
                endmethod

                method t_DATA peek() = buffer[p].first();
                method Bool notEmpty() = buffer[p].notEmpty();
                method Bool notFull() = incomingReqQ.ports[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val);
        // Write port is the last of the incomingReqQ ports.
        incomingReqQ.ports[valueOf(n_READERS)].enq(addr);
        writeDataQ.enq(val);
    endmethod

    method Bool writeNotFull = incomingReqQ.ports[valueOf(n_READERS)].notFull();
endmodule


//
// mkMemIfcToPseudoMultiMemAsyncWrites --
//     Provide the same buffering for mapping logical read ports to a single
//     physical read port as mkMemIfcToPseudoMultiMemSyncWrites above.
//
//     In this implementation, write sequencing is independent of reads.
//     Writes are emitted the cycle they arrive.  Reads may be buffered
//     and emitted later.  BE CAREFUL!  This implementation may have
//     better performance, but requires more attention to management of
//     read/write ordering.
//
module mkMemIfcToPseudoMultiMemAsyncWrites#(MEMORY_IFC#(t_ADDR, t_DATA) mem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),

              // Compute minimum size for storing read port ID (must be at least
              // 1 bit).
              Log#(n_READERS, n_READERS_SZ),
              Max#(n_READERS_SZ, 1, n_READERS_SAFE_SZ));

    // Sort incoming requests.  One port for each read port.
    Vector#(n_READERS, FIFOF#(t_ADDR)) incomingReqQ <- replicateM(mkBypassFIFOF);

    // Match requests to ports.  Add 1 to the number of readers to guarantee
    // we never try to allocate a Bit#(0).
    FIFO#(Bit#(n_READERS_SAFE_SZ)) noteReqQ <- mkFIFO();

    // How much buffering is available?  Buffering matches the depth of mkBRAM.
    Vector#(n_READERS, COUNTER#(2)) bufferingAvailable <- replicateM(mkLCounter(2));
    Vector#(n_READERS, FIFOF#(t_DATA)) buffer <- replicateM(mkSizedBypassFIFOF(2));
        
    // Arbiter (pick an input request to process)
    Arbiter_IFC#(n_READERS) arbiter <- mkArbiter(False);

    //
    // Read rules
    //
    Rules read_req = emptyRules();
    Rules enq_fifo = emptyRules();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        //
        // arbForReadReq --
        //     If read request has data and buffering is available for the
        //     output then send a request to the arbiter.
        //
        rule arbForReadReq (incomingReqQ[p].notEmpty &&
                            (bufferingAvailable[p].value() > 0));
            arbiter.clients[p].request();
        endrule

        //
        // processReadReq --
        //     Forward read requests to the memory.  Only one reader queue
        //     will have a chance to forward a request per cycle.
        //
        let rr =
        (rules
            rule processReadReq (arbiter.clients[p].grant);
                let addr = incomingReqQ[p].first();
                incomingReqQ[p].deq();

                mem.readReq(addr);

                noteReqQ.enq(fromInteger(p));
                bufferingAvailable[p].down();
            endrule
        endrules);
        read_req = rJoinMutuallyExclusive(read_req, rr);

        //
        // enqIntoFIFO --
        //     Forward BRAM response to read port's response buffer.
        //
        let enqf =
        (rules
            rule enqIntoFIFO (noteReqQ.first() == fromInteger(p));
                noteReqQ.deq();

                let data <- mem.readRsp();
                buffer[p].enq(data);
            endrule
        endrules);
        enq_fifo = rJoinMutuallyExclusive(enq_fifo, enqf);
    end
    
    addRules(read_req);
    addRules(enq_fifo);


    //
    // readPorts
    //

    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR a);
                    incomingReqQ[p].enq(a);
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    bufferingAvailable[p].up();

                    let v = buffer[p].first();
                    buffer[p].deq();

                    return v;
                endmethod

                method t_DATA peek() = buffer[p].first();
                method Bool notEmpty() = buffer[p].notEmpty();
                method Bool notFull() = incomingReqQ[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val);
        mem.write(addr, val);
    endmethod

    method Bool writeNotFull = True;
endmodule


// ========================================================================
//
// Other
//
// ========================================================================


//
// mkNullMemory --
//   Instantiate a memory with no storage.  Useful for maintaining
//   interface behavior but the storage isn't needed in some AWB
//   configuration.
//
module mkNullMemory
    // interface:
    (MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    method Action readReq(t_ADDR addr);
        noAction;
    endmethod

    method ActionValue#(t_DATA) readRsp() if (False);
        return ?;
    endmethod

    method t_DATA peek() = ?;
    method Bool notEmpty() = False;
    method Bool notFull() = True;

    method Action write(t_ADDR addr, t_DATA val);
        noAction;
    endmethod

    method Bool writeNotFull() = True;
endmodule
