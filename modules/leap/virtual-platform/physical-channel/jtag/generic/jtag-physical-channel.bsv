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

`include "awb/provides/physical_platform.bsh"
`include "awb/provides/jtag_device.bsh"
`include "awb/provides/umf.bsh"

// ============== Physical Channel ===============

// interface
interface PHYSICAL_CHANNEL;
    
    method ActionValue#(UMF_CHUNK) read();
    method Action                  write(UMF_CHUNK chunk);
        
endinterface

typedef Bit#(TLog#(TAdd#(TDiv#(SizeOf#(UMF_CHUNK),4),1))) UMF_COUNTER;

// module
module mkPhysicalChannel#(PHYSICAL_DRIVERS drivers)
    // interface
        (PHYSICAL_CHANNEL);
   
    // no. jtag words to assemble a umf chunk
    UMF_COUNTER no_jtag_words = fromInteger(valueof(SizeOf#(UMF_CHUNK))/4);

    JTAGWord password[8] = {97,98,99,100,101,102,103,104};
    JTAGWord counterword[8] = {65,66,67,68,69,70,71,72};

    Reg#(UMF_CHUNK)      jtagIncoming      <- mkReg(0);
    Reg#(UMF_COUNTER)    jtagIncomingCount <- mkReg(0); 
    Reg#(UMF_CHUNK)      jtagOutgoing      <- mkReg(0);
    Reg#(UMF_COUNTER)    jtagOutgoingCount <- mkReg(0);       
    Reg#(Bool)           init              <- mkReg(False);
    Reg#(Bool)           sent              <- mkReg(False);
    PulseWire            rxInit            <- mkPulseWire;   
    Reg#(Bit#(22))       timeout           <- mkReg(0);   

    rule countUp;
        timeout <= timeout + 1;
    endrule

    // send the first character
    rule sendInit (!init && !rxInit && (!sent));
        drivers.jtagDriver.send(password[jtagOutgoingCount]);
        sent <= True;  
    endrule


    rule recvInit (!init);
        let inVal <- drivers.jtagDriver.receive();
        rxInit.send;
        // drop spurious control signals
        if(inVal>40)
        begin  
            sent <= False;
        end
        if(inVal == counterword[jtagOutgoingCount])
        begin
            jtagOutgoingCount <= jtagOutgoingCount + 1;
            if (jtagOutgoingCount == no_jtag_words - 1)
            begin
                init <= True;
            end
        end
        // may need to drop some control signals...
        else if(inVal > 40)
        begin
            jtagOutgoingCount <= 0;
        end 
    endrule

    rule sendToJtag (init && jtagOutgoingCount != no_jtag_words);
        Bit#(4) x = truncate(jtagOutgoing);
        jtagOutgoing <= jtagOutgoing >> 4;
        JTAGWord jtag_x = zeroExtend(x) ^ 64;
        drivers.jtagDriver.send(jtag_x);
        jtagOutgoingCount <= jtagOutgoingCount + 1;
    endrule

    rule recvFromJtag (init && jtagIncomingCount != no_jtag_words);
        JTAGWord x <- drivers.jtagDriver.receive();
        if(x > 40)
        begin
            Bit#(4) truncated_x = truncate(x);
            jtagIncoming <= (jtagIncoming >> 4) ^ {truncated_x,0};
            jtagIncomingCount <= jtagIncomingCount + 1;
        end
    endrule

    method Action write(UMF_CHUNK data) if (jtagOutgoingCount == no_jtag_words && init);
        jtagOutgoing <= data;
        jtagOutgoingCount <= 0;
    endmethod

    method ActionValue#(UMF_CHUNK) read() if (jtagIncomingCount == no_jtag_words);
        jtagIncomingCount <= 0;
        return jtagIncoming;
    endmethod
   
endmodule
