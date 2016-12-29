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

import Vector::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"

// ========================================================================
//
// Shared memory interface definitions. 
//
// ========================================================================

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

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    // Test and set request 
    method Action testAndSetReq(t_ADDR addr, t_DATA val);
    // Test and set response
    method ActionValue#(t_DATA) testAndSetRsp();
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    // Insert a memory fence. All requests issued earlier should
    // be processed before the fence request gets processed.
    method Action fence();
    // Insert a memory wrtie fence. Write requests issued earlier should
    // be processed before the fence request gets processed.
    method Action writeFence();
    // Insert a memory wrtie fence. Read requests issued earlier should
    // be processed before the fence request gets processed.
    method Action readFence();
`endif

    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface

//
// Memory with one writer and multiple readers.
// Memory fence is supported. 
//
interface MEMORY_MULTI_READ_WITH_FENCE_IFC#(numeric type n_READERS, type t_ADDR, type t_DATA);
    interface Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPorts;

    method Action write(t_ADDR addr, t_DATA val);
    method Bool writeNotFull();
    
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    // Test and set request 
    method Action testAndSetReq(t_ADDR addr, t_DATA val);
    // Test and set response
    method ActionValue#(t_DATA) testAndSetRsp();
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    // Insert a memory fence. All requests issued earlier should
    // be processed before the fence request gets processed.
    method Action fence();
    // Insert a memory wrtie fence. Write requests issued earlier should
    // be processed before the fence request gets processed.
    method Action writeFence();
    // Insert a memory wrtie fence. Read requests issued earlier should
    // be processed before the fence request gets processed.
    method Action readFence();
`endif

    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
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
    
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    // Test and set request 
    method Action testAndSetReq(t_ADDR addr, t_DATA val, t_MASK mask);
    // Test and set response
    method ActionValue#(t_DATA) testAndSetRsp();
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    // Insert a memory fence. All requests issued earlier should
    // be processed before the fence request gets processed.
    method Action fence();
    // Insert a memory wrtie fence. Write requests issued earlier should
    // be processed before the fence request gets processed.
    method Action writeFence();
    // Insert a memory wrtie fence. Read requests issued earlier should
    // be processed before the fence request gets processed.
    method Action readFence();
`endif

    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface

//
// Shared memory interface (normal memory interface + fence + flush/invalidate)
//
interface SHARED_MEMORY_IFC#(type t_ADDR, type t_DATA);
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
    // Flush or invalidate requests
    method Action flush(t_ADDR addr);
    method Action inval(t_ADDR addr);
    method Bool invalOrFlushPending();
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    // Test and set request 
    method Action testAndSetReq(t_ADDR addr, t_DATA val);
    // Test and set response
    method ActionValue#(t_DATA) testAndSetRsp();
`endif
`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    // Insert a memory fence. All requests issued earlier should
    // be processed before the fence request gets processed.
    method Action fence();
    // Insert a memory wrtie fence. Write requests issued earlier should
    // be processed before the fence request gets processed.
    method Action writeFence();
    // Insert a memory wrtie fence. Read requests issued earlier should
    // be processed before the fence request gets processed.
    method Action readFence();
`endif
    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface

//
// Shared memory with one writer and multiple readers.
//
interface SHARED_MEMORY_MULTI_READ_IFC#(numeric type n_READERS, type t_ADDR, type t_DATA);
    interface Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPorts;
    method Action write(t_ADDR addr, t_DATA val);
    method Bool writeNotFull();
    
    // Flush or invalidate requests
    method Action flush(t_ADDR addr);
    method Action inval(t_ADDR addr);
    method Bool invalOrFlushPending();
    
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    // Test and set request 
    method Action testAndSetReq(t_ADDR addr, t_DATA val);
    // Test and set response
    method ActionValue#(t_DATA) testAndSetRsp();
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    // Insert a memory fence. All requests issued earlier should
    // be processed before the fence request gets processed.
    method Action fence();
    // Insert a memory wrtie fence. Write requests issued earlier should
    // be processed before the fence request gets processed.
    method Action writeFence();
    // Insert a memory wrtie fence. Read requests issued earlier should
    // be processed before the fence request gets processed.
    method Action readFence();
`endif

    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface

//
// SHARED_MEMORY_MULTI_READ_MASKED_WRITE_IFC
// Shared memory with multiple readers and one writer with write mask.
//
interface SHARED_MEMORY_MULTI_READ_MASKED_WRITE_IFC#(numeric type n_READERS, type t_ADDR, type t_DATA, type t_MASK);
    interface Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPorts;
    method Action write(t_ADDR addr, t_DATA val, t_MASK mask);
    method Bool writeNotFull();
    
    // Flush or invalidate requests
    method Action flush(t_ADDR addr);
    method Action inval(t_ADDR addr);
    method Bool invalOrFlushPending();
    
`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    // Test and set request 
    method Action testAndSetReq(t_ADDR addr, t_DATA val, t_MASK mask);
    // Test and set response
    method ActionValue#(t_DATA) testAndSetRsp();
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    // Insert a memory fence. All requests issued earlier should
    // be processed before the fence request gets processed.
    method Action fence();
    // Insert a memory wrtie fence. Write requests issued earlier should
    // be processed before the fence request gets processed.
    method Action writeFence();
    // Insert a memory wrtie fence. Read requests issued earlier should
    // be processed before the fence request gets processed.
    method Action readFence();
`endif

    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface

//
// Shared memory interface without pipelined fence and test&set support
//
interface SHARED_MEMORY_SIMPLE_IFC#(type t_ADDR, type t_DATA);
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
    // Flush or invalidate requests
    method Action flush(t_ADDR addr);
    method Action inval(t_ADDR addr);
    method Bool invalOrFlushPending();
    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface

//
// Simple shared memory interface with one writer and multiple readers.
//
interface SHARED_MEMORY_SIMPLE_MULTI_READ_IFC#(numeric type n_READERS, type t_ADDR, type t_DATA);
    interface Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPorts;
    method Action write(t_ADDR addr, t_DATA val);
    method Bool writeNotFull();
    
    // Flush or invalidate requests
    method Action flush(t_ADDR addr);
    method Action inval(t_ADDR addr);
    method Bool invalOrFlushPending();
    
    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface

//
// SHARED_MEMORY_SIMPLE_MULTI_READ_MASKED_WRITE_IFC
// Simple shared memory interface with multiple readers and one writer 
// with write mask.
//
interface SHARED_MEMORY_SIMPLE_MULTI_READ_MASKED_WRITE_IFC#(numeric type n_READERS, type t_ADDR, type t_DATA, type t_MASK);
    interface Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) readPorts;
    method Action write(t_ADDR addr, t_DATA val, t_MASK mask);
    method Bool writeNotFull();
    
    // Flush or invalidate requests
    method Action flush(t_ADDR addr);
    method Action inval(t_ADDR addr);
    method Bool invalOrFlushPending();
    
    // Return true if there is at least one pending write request
    method Bool writePending();
    // Return true if there is at least one pending read request
    method Bool readPending();
endinterface



// ========================================================================
//
// Memory interface conversion
//
// ========================================================================

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
// mkSharedMemIfcToMemIfc -- 
//     Interface conversion from a SHARED_MEMORY_IFC to a basic MEMORY_IFC.    
// 
module mkSharedMemIfcToMemIfc#(SHARED_MEMORY_IFC#(t_ADDR, t_DATA) mem)
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
// mkMultiReadMemFenceIfcToMemFenceIfc --
//     Interface conversion from a MEMORY_MULTI_READ_WITH_FENCE_IFC with one port 
//     to a MEMORY_WITH_FENCE_IFC.  Useful for implementing a memory that supports 
//     an arbitrary number of ports without having to special case code for 
//     a single port.
//
module mkMultiReadMemFenceIfcToMemFenceIfc#(MEMORY_MULTI_READ_WITH_FENCE_IFC#(1, t_ADDR, t_DATA) multiMem)
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

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_ADDR addr, t_DATA val) = multiMem.testAndSetReq(addr, val);
    method ActionValue#(t_DATA) testAndSetRsp();
        let resp <- multiMem.testAndSetRsp();
        return resp;
    endmethod
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence() = multiMem.fence();
    method Action writeFence() = multiMem.writeFence();
    method Action readFence() = multiMem.readFence();
`endif

    method Bool writePending() = multiMem.writePending();
    method Bool readPending() = multiMem.readPending();
endmodule

//
// mkMultiReadSharedMemIfcToSharedMemIfc --
//     Interface conversion from a SHARED_MEMORY_MULTI_READ_IFC with one port 
//     to a SHARED_MEMORY_IFC.  Useful for implementing a memory that supports 
//     an arbitrary number of ports without having to special case code for 
//     a single port.
//
module mkMultiReadSharedMemIfcToSharedMemIfc#(SHARED_MEMORY_MULTI_READ_IFC#(1, t_ADDR, t_DATA) multiMem)
    // interface:
    (SHARED_MEMORY_IFC#(t_ADDR, t_DATA))
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
    
    method Action flush(t_ADDR addr) = multiMem.flush(addr);
    method Action inval(t_ADDR addr) = multiMem.inval(addr);
    method Bool invalOrFlushPending() = multiMem.invalOrFlushPending();

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_ADDR addr, t_DATA val) = multiMem.testAndSetReq(addr, val);
    method ActionValue#(t_DATA) testAndSetRsp();
        let resp <- multiMem.testAndSetRsp();
        return resp;
    endmethod
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence() = multiMem.fence();
    method Action writeFence() = multiMem.writeFence();
    method Action readFence() = multiMem.readFence();
`endif

    method Bool writePending() = multiMem.writePending();
    method Bool readPending() = multiMem.readPending();
endmodule

//
// mkMemFenceIfcToSharedMemIfc --
//     Interface conversion from a MEMORY_WITH_FENCE_IFC to a SHARED_MEMORY_IFC.
//
module mkMemFenceIfcToSharedMemIfc#(MEMORY_WITH_FENCE_IFC#(t_ADDR, t_DATA) mem)
    // interface:
    (SHARED_MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    method Action readReq(t_ADDR addr) = mem.readReq(addr);
    method ActionValue#(t_DATA) readRsp();
        let r <- mem.readRsp();
        return r;
    endmethod
    method t_DATA peek() = mem.peek();
    method Bool notEmpty() = mem.notEmpty();
    method Bool notFull() = mem.notFull();

    method Action write(t_ADDR addr, t_DATA val) = mem.write(addr, val);
    method Bool writeNotFull() = mem.writeNotFull();
    
    method Action flush(t_ADDR addr);
        noAction;
    endmethod

    method Action inval(t_ADDR addr);
        noAction;
    endmethod

    method Bool invalOrFlushPending();
        return False;
    endmethod

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_ADDR addr, t_DATA val) = mem.testAndSetReq(addr, val);
    method ActionValue#(t_DATA) testAndSetRsp();
        let resp <- mem.testAndSetRsp();
        return resp;
    endmethod
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence() = mem.fence();
    method Action writeFence() = mem.writeFence();
    method Action readFence() = mem.readFence();
`endif

    method Bool writePending() = mem.writePending();
    method Bool readPending() = mem.readPending();
endmodule

//
// mkMultiReadMemFenceIfcToMultiReadSharedMemIfc --
//     Interface conversion from a MEMORY_MULTI_READ_WITH_FENCE_IFC to a
//     SHARED_MEMORY_MULTI_READ_IFC. 
//
module mkMultiReadMemFenceIfcToMultiReadSharedMemIfc#(MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA) mem)
    // interface:
    (SHARED_MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    interface readPorts = mem.readPorts;

    method Action write(t_ADDR addr, t_DATA val) = mem.write(addr, val);
    method Bool writeNotFull() = mem.writeNotFull();
    
    method Action flush(t_ADDR addr);
        noAction;
    endmethod

    method Action inval(t_ADDR addr);
        noAction;
    endmethod

    method Bool invalOrFlushPending();
        return False;
    endmethod

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_ADDR addr, t_DATA val) = mem.testAndSetReq(addr, val);
    method ActionValue#(t_DATA) testAndSetRsp();
        let resp <- mem.testAndSetRsp();
        return resp;
    endmethod
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence() = mem.fence();
    method Action writeFence() = mem.writeFence();
    method Action readFence() = mem.readFence();
`endif

    method Bool writePending() = mem.writePending();
    method Bool readPending() = mem.readPending();
endmodule

//
// mkSimpleSharedMemIfcToSharedMemIfc --
//     Interface conversion from a SHARED_MEMORY_SIMPLE_IFC to a SHARED_MEMORY_IFC.
//
module mkSimpleSharedMemIfcToSharedMemIfc#(SHARED_MEMORY_SIMPLE_IFC#(t_ADDR, t_DATA) mem)
    // interface:
    (SHARED_MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    method Action readReq(t_ADDR addr) = mem.readReq(addr);
    method ActionValue#(t_DATA) readRsp();
        let r <- mem.readRsp();
        return r;
    endmethod
    method t_DATA peek() = mem.peek();
    method Bool notEmpty() = mem.notEmpty();
    method Bool notFull() = mem.notFull();

    method Action write(t_ADDR addr, t_DATA val) = mem.write(addr, val);
    method Bool writeNotFull() = mem.writeNotFull();
    
    method Action flush(t_ADDR addr) = mem.flush(addr);
    method Action inval(t_ADDR addr) = mem.inval(addr);
    method Bool invalOrFlushPending() = mem.invalOrFlushPending();

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_ADDR addr, t_DATA val);
        noAction;
    endmethod
    method ActionValue#(t_DATA) testAndSetRsp();
        noAction;
        return ?;
    endmethod
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence();
        noAction;
    endmethod
    method Action writeFence();
        noAction;
    endmethod
    method Action readFence();
        noAction;
    endmethod
`endif

    method Bool writePending() = mem.writePending();
    method Bool readPending() = mem.readPending();
endmodule

//
// mkMultiReadSimpleSharedMemIfcToMultiReadSharedMemIfc --
//     Interface conversion from a MEMORY_MULTI_READ_WITH_FENCE_IFC to a
//     SHARED_MEMORY_MULTI_READ_IFC. 
//
module mkMultiReadSimpleSharedMemIfcToMultiReadSharedMemIfc#(SHARED_MEMORY_SIMPLE_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) mem)
    // interface:
    (SHARED_MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    interface readPorts = mem.readPorts;

    method Action write(t_ADDR addr, t_DATA val) = mem.write(addr, val);
    method Bool writeNotFull() = mem.writeNotFull();
    
    method Action flush(t_ADDR addr) = mem.flush(addr);
    method Action inval(t_ADDR addr) = mem.inval(addr);
    method Bool invalOrFlushPending() = mem.invalOrFlushPending();

`ifndef SHARED_SCRATCHPAD_TEST_AND_SET_ENABLE_Z
    method Action testAndSetReq(t_ADDR addr, t_DATA val);
        noAction;
    endmethod
    method ActionValue#(t_DATA) testAndSetRsp();
        noAction;
        return ?;
    endmethod
`endif

`ifndef SHARED_SCRATCHPAD_PIPELINED_FENCE_ENABLE_Z
    method Action fence();
        noAction;
    endmethod
    method Action writeFence();
        noAction;
    endmethod
    method Action readFence();
        noAction;
    endmethod
`endif

    method Bool writePending() = mem.writePending();
    method Bool readPending() = mem.readPending();
endmodule

