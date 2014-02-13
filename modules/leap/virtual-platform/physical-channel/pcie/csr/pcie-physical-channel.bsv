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

import FIFOF::*;

`include "awb/provides/physical_platform.bsh"
`include "awb/provides/pci_express_device.bsh"
`include "awb/provides/led_device.bsh"
`include "awb/provides/umf.bsh"

// types
typedef enum
{
    CHANNEL_STATE_idle,
    CHANNEL_STATE_init,
    CHANNEL_STATE_active
}
CHANNEL_STATE
    deriving (Bits, Eq);

typedef enum
{
    READ_STATE_ready,
    READ_STATE_busy_data,
    READ_STATE_busy_f2hHead,
    READ_STATE_busy_h2fTail
}
READ_STATE
    deriving (Bits, Eq);

// ============== Physical Channel ===============

// interface
interface PHYSICAL_CHANNEL;
    
    method ActionValue#(UMF_CHUNK) read();
    method Action                  write(UMF_CHUNK chunk);
        
endinterface

// module
module mkPhysicalChannel#(PHYSICAL_DRIVERS drivers)
    // interface
        (PHYSICAL_CHANNEL);
    
    // ============= State ==============

    // buffers
    FIFOF#(PCIE_CSR_DATA) readBuffer  <- mkFIFOF();
    FIFOF#(PCIE_CSR_DATA) writeBuffer <- mkFIFOF();

    // states
    Reg#(READ_STATE)    readState    <- mkReg(READ_STATE_ready);
    Reg#(Bit#(4))       initStage    <- mkReg(0);
    Reg#(Bit#(8))       lastIID      <- mkReg(0);
    Reg#(CHANNEL_STATE) channelState <- mkReg(CHANNEL_STATE_idle);

    // pointers
    Reg#(PCIE_CSR_INDEX) f2hHead <- mkReg(`CSR_F2H_BUF_START);
    Reg#(PCIE_CSR_INDEX) f2hTail <- mkReg(`CSR_F2H_BUF_START);
    Reg#(PCIE_CSR_INDEX) h2fHead <- mkReg(`CSR_H2F_BUF_START);
    Reg#(PCIE_CSR_INDEX) h2fTail <- mkReg(`CSR_H2F_BUF_START);

    // dirty/valid bits
    Reg#(Bool) h2fHeadDirty <- mkReg(False);
    Reg#(Bool) h2fTailValid <- mkReg(True);
    Reg#(Bool) f2hHeadValid <- mkReg(True);
    Reg#(Bool) f2hTailDirty <- mkReg(False);

    // =========== Helper Wires =========

    PCIE_CSR_INDEX f2hHeadPlusOne = (f2hHead == `CSR_F2H_BUF_END) ? `CSR_F2H_BUF_START : (f2hHead + 1);
    PCIE_CSR_INDEX f2hTailPlusOne = (f2hTail == `CSR_F2H_BUF_END) ? `CSR_F2H_BUF_START : (f2hTail + 1);
    PCIE_CSR_INDEX h2fHeadPlusOne = (h2fHead == `CSR_H2F_BUF_END) ? `CSR_H2F_BUF_START : (h2fHead + 1);
    PCIE_CSR_INDEX h2fTailPlusOne = (h2fTail == `CSR_H2F_BUF_END) ? `CSR_H2F_BUF_START : (h2fTail + 1);

    Bool f2hEmpty = (f2hHead == f2hTail);
    Bool f2hFull  = (f2hHead == f2hTailPlusOne);
    Bool h2fEmpty = (h2fHead == h2fTail);
    Bool h2fFull  = (h2fHead == h2fTailPlusOne);

    Bool channelActive = (channelState == CHANNEL_STATE_active);
    
    // shortcut to drivers
    PCI_EXPRESS_DRIVER pciExpressDriver = drivers.pciExpressDriver;

    // ============== Rules =============
    
    // Control state machine

    // 32-bit control instruction format:
    //
    // field:   [IID]  [RESERVED] [OPCODE]  [INDEX] [IMMEDIATE]
    // bits :   31-24    23-20     19-16     15-8      7-0

    // process a new instruction
    rule process_inst (channelState != CHANNEL_STATE_init);
        
        // read current instruction and decode partially
        Bit#(8)        iid    = pciExpressDriver.systemCSR[31:24];
        Bit#(4)        opcode = pciExpressDriver.systemCSR[19:16];
        PCIE_CSR_INDEX index  = pciExpressDriver.systemCSR[15:8];
        
        // make sure this is a new instruction
        if (iid != lastIID)
        begin

            lastIID <= iid;

            case (opcode)
                
                // NOP
                `OP_NOP            : noAction;
                
                // start
                `OP_START          : if (channelState == CHANNEL_STATE_idle)
                                         channelState <= CHANNEL_STATE_init;
                
                // update H2F tail
                `OP_UPDATE_H2FTAIL : begin
                                         h2fTail <= index;
                                         h2fTailValid <= True;
                                     end
                
                // update F2H head
                `OP_UPDATE_F2HHEAD : begin
                                         f2hHead <= index;
                                         f2hHeadValid <= True;
                                     end

                default: noAction;

            endcase

        end

    endrule

    // === initialization sequence ===

    rule do_channel_init (channelState == CHANNEL_STATE_init);

        case (initStage)
            
            // nothing (FIXME)
            0: noAction;

            // write indices that we control
            1: pciExpressDriver.commonCSRs.write(`CSR_F2H_TAIL, zeroExtend(f2hTail));
            
            // write indices that we control
            2: pciExpressDriver.commonCSRs.write(`CSR_H2F_HEAD, zeroExtend(h2fHead));
            
            // give green signal to software
            3: pciExpressDriver.systemCSR <= `SIGNAL_GREEN;

            // all set, activate channel
            4: channelState <= CHANNEL_STATE_active;

        endcase
        
        initStage <= initStage + 1;
        
    endrule

    // === pointer updates: WRITE ===

    // NOTE: all write rules are gated by READ_STATE_ready (obsolete. debug only. FIXME)

    // write f2hTail state
    rule make_f2hTail_write_req (channelActive && f2hTailDirty && readState == READ_STATE_ready);

        pciExpressDriver.commonCSRs.write(`CSR_F2H_TAIL, zeroExtend(f2hTail));
        f2hTailDirty <= False;

    endrule

    // write h2fHead state
    rule make_h2fHead_write_req (channelActive && h2fHeadDirty && readState == READ_STATE_ready);
        
        pciExpressDriver.commonCSRs.write(`CSR_H2F_HEAD, zeroExtend(h2fHead));
        h2fHeadDirty <= False;
        
    endrule

    // === data ===

    // send data read request
    rule make_data_read_req (channelActive && h2fTailValid && !h2fEmpty && readState == READ_STATE_ready);

        pciExpressDriver.commonCSRs.readRequest(h2fHead);
        readState <= READ_STATE_busy_data;

    endrule

    // receive read response from CSR
    rule recv_read_resp (channelActive && readState == READ_STATE_busy_data);
        
        PCIE_CSR_DATA data <- pciExpressDriver.commonCSRs.readResponse();
        readBuffer.enq(data);

        // advance head
        h2fHead <= h2fHeadPlusOne;
        h2fHeadDirty <= True;

        readState <= READ_STATE_ready;
        
    endrule

    // send data write request
    rule make_data_write_req (channelActive && f2hHeadValid && !f2hFull && readState == READ_STATE_ready);
        
        PCIE_CSR_DATA data = writeBuffer.first();
        writeBuffer.deq();
        pciExpressDriver.commonCSRs.write(f2hTail, data);

        // advance tail
        f2hTail <= f2hTailPlusOne;
        f2hTailDirty <= True;
        
    endrule

    // ============= Methods =============

    // read
    method ActionValue#(UMF_CHUNK) read() if (channelActive);
        
        PCIE_CSR_DATA data = readBuffer.first();
        readBuffer.deq();
        UMF_CHUNK chunk = truncate(data);
        return chunk;
        
    endmethod

    // write
    method Action write(UMF_CHUNK chunk) if (channelActive);
        
        PCIE_CSR_DATA data = zeroExtend(chunk);
        writeBuffer.enq(data);
        
    endmethod

endmodule
