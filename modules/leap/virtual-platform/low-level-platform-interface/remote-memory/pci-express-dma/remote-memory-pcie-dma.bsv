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

//
// Remote Memory via PCI Express DMA
//

import FIFOF::*;
import FIFOLevel::*;

`include "awb/provides/physical_platform.bsh"
`include "awb/provides/pci_express_device.bsh"

// types
typedef enum
{
    STATE_ready,
    STATE_reading_line,
    STATE_reading_burst,
    STATE_writing_line,
    STATE_writing_burst
}
STATE
    deriving (Bits, Eq);

typedef PCIE_PHYSICAL_ADDRESS REMOTE_MEMORY_PHYSICAL_ADDRESS;
typedef PCIE_DMA_DATA         REMOTE_MEMORY_DATA;
typedef PCIE_LENGTH           REMOTE_MEMORY_BURST_LENGTH;


// ============== REMOTE_MEMORY Interface ===============

// This interface is used to access host memory. The standard interface supports
// both Single-Word and Burst modes; however, one of these access modes could be
// emulated (and therefore inefficient) on top of the access mode that the
// underlying physical platform actually supports.
//
// The interface always uses Host Physical Addresses, and it is the user's
// responsibility to ensure that these addresses fall within a "safe" page that
// is pinned and that can be written from the FPGA side. The software-side
// interface for this module provides methods to setup a user page for FPGA access,
// and to obtain the physical address of a user page.

interface REMOTE_MEMORY;
    
    // line interface
    method Action                           readLineReq(REMOTE_MEMORY_PHYSICAL_ADDRESS addr);
    method ActionValue#(REMOTE_MEMORY_DATA) readLineResp();
    method Action                           writeLine(REMOTE_MEMORY_PHYSICAL_ADDRESS addr,
                                                      REMOTE_MEMORY_DATA data);
    
    // burst interface -- assumption here is that burst word size is the same as the
    //                    single word size
    method Action                           readBurstReq(REMOTE_MEMORY_PHYSICAL_ADDRESS addr,
                                                         REMOTE_MEMORY_BURST_LENGTH     len);
    method ActionValue#(REMOTE_MEMORY_DATA) readBurstResp();
    method Action                           writeBurstReq(REMOTE_MEMORY_PHYSICAL_ADDRESS addr,
                                                          REMOTE_MEMORY_BURST_LENGTH     len);
    method Action                           writeBurstData(REMOTE_MEMORY_DATA data);    
        
endinterface


// ============== mkRemoteMemory Module ===============

// This implementation of remote memory uses the PCI-Express DMA engine to
// provide host memory access. It currently allows only one in-flight read or
// write transaction.

module mkRemoteMemory#(PHYSICAL_DRIVERS drivers)
    // interface
        (REMOTE_MEMORY);
    
    PCI_EXPRESS_DRIVER pciExpressDriver = drivers.pciExpressDriver;

    Reg#(STATE) state <- mkReg(STATE_ready);
    
    Reg#(PCIE_LENGTH)  readWordsRemaining <- mkReg(0);
    Reg#(PCIE_LENGTH) writeWordsRemaining <- mkReg(0);

    // ============= Functions =============
    
    // start a Read request
    
    function Action readReq(REMOTE_MEMORY_PHYSICAL_ADDRESS addr,
                            REMOTE_MEMORY_BURST_LENGTH     nwords);
    action
        
        // PCI Express Driver needs transaction length in Bytes
        PCIE_LENGTH data_bytes = zeroExtend(nwords) << `PCIE_LOG_DMA_DATA_BYTES;
        pciExpressDriver.dmaDriver.startRead(addr, data_bytes);
        
    endaction
    endfunction
    
    // suck in Read data
    
    function ActionValue#(REMOTE_MEMORY_DATA) readResp();
    actionvalue
    
        PCIE_DMA_DATA data <- pciExpressDriver.dmaDriver.readData();        
        return data;
    
    endactionvalue
    endfunction
    
    // start a write request
    
    function Action writeReq(REMOTE_MEMORY_PHYSICAL_ADDRESS addr,
                             REMOTE_MEMORY_BURST_LENGTH     nwords);
    action    
        
        // PCI Express Driver needs transaction length in Bytes
        PCIE_LENGTH data_bytes  = zeroExtend(nwords) << `PCIE_LOG_DMA_DATA_BYTES;        
        pciExpressDriver.dmaDriver.startWrite(addr, data_bytes);
        
    endaction
    endfunction
    
    // send out write data
    
    function Action writeData(REMOTE_MEMORY_DATA data);
    action
        
        pciExpressDriver.dmaDriver.writeData(data);
        
    endaction
    endfunction
    

    // ============= Methods =============

    // line interface
    
    method Action readLineReq(REMOTE_MEMORY_PHYSICAL_ADDRESS addr) if (state == STATE_ready);
        
        readReq(addr, 1);
        readWordsRemaining <= 1;
        state <= STATE_reading_line;
        
    endmethod

    method ActionValue#(REMOTE_MEMORY_DATA) readLineResp() if (state == STATE_reading_line);
        
        let data <- readResp();
        readWordsRemaining <= 0;
        state <= STATE_ready;
        
        return data;
        
    endmethod
        
    method Action writeLine(REMOTE_MEMORY_PHYSICAL_ADDRESS addr,
                            REMOTE_MEMORY_DATA             data) if (state == STATE_ready);
        
        writeReq(addr, 1);
        writeData(data);
        
    endmethod
    
    // burst interface
    
    method Action readBurstReq(REMOTE_MEMORY_PHYSICAL_ADDRESS addr,
                               REMOTE_MEMORY_BURST_LENGTH     nwords) if (state == STATE_ready);

        readReq(addr, nwords);
        readWordsRemaining <= nwords;
        state <= STATE_reading_burst;
        
    endmethod

    method ActionValue#(REMOTE_MEMORY_DATA) readBurstResp() if (state == STATE_reading_burst);
        
        let data <- readResp();
        
        readWordsRemaining <= readWordsRemaining - 1;
        if (readWordsRemaining == 1)
        begin
            state <= STATE_ready;
        end
        
        return data;
        
    endmethod
    
    // for burst writes, the first data word can only be written in the cycle following
    // the initial write request. Probably easy to optimize this.
    
    method Action writeBurstReq(REMOTE_MEMORY_PHYSICAL_ADDRESS addr,
                                REMOTE_MEMORY_BURST_LENGTH     len) if (state == STATE_ready);
        
        writeReq(addr, len);
        writeWordsRemaining <= len;
        state <= STATE_writing_burst;
        
    endmethod
        
    method Action writeBurstData(REMOTE_MEMORY_DATA data) if (state == STATE_writing_burst);

        writeData(data);
        writeWordsRemaining <= writeWordsRemaining - 1;
        if (writeWordsRemaining == 1)
        begin
            state <= STATE_ready;
        end
        
    endmethod
        
endmodule
