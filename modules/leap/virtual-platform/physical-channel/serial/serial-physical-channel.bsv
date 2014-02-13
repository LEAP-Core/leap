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
`include "awb/provides/serial_device.bsh"
`include "awb/provides/umf.bsh"

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
  
  // shortcut to drivers
  SERIAL_DRIVER serialDriver = drivers.serialDriver;

  let initialized = True;
  
//   Reg#(Bool)    initialized <- mkReg(False);
//   Reg#(Bit#(16)) count      <- mkReg(0);
  
//   //scheme is pos 0 "DEAD" HW -> SW
//   //          pos 1 "BEEF" SW -> HW
//   //          pos 2 "CAFE" HW -> SW
  
//   rule sendPulse(!initialized);
//     count <= count + 1;
//     if (count == 0)
//       begin
// 	serialDriver.send(32'h44454144);
//       end
//   endrule


//   rule getResp(!initialized);
//     let x<- serialDriver.receive();
//     if (x == 32'h42454546) // woo. A response Send a token and we're done 
//       begin
// 	serialDriver.send(32'h43414645);
// 	initialized <= True;
//       end
//      else
//        begin
// 	 serialDriver.send(x);	 
// 	 //serialDriver.send(32'h464F4F21);	 
// 	 //initialized <= True;
//        end   
//   endrule  
 
  method ActionValue#(UMF_CHUNK) read() if (initialized);
    let x <- serialDriver.receive();
    return x;
  endmethod

  method Action write(UMF_CHUNK x) if (initialized);
    serialDriver.send(x);
  endmethod
  
endmodule
