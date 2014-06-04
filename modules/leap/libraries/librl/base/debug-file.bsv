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

`include "awb/provides/model_params.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/fpga_components_params.bsh"

// All debug output files go in a subdirectory
function String debugPath(String fname) = `LEAP_DEBUG_PATH + "/" + fname;


// ========================================================================
//
//   Basic debug file.  No model cycle, no thread context.
//
// ========================================================================

//
// A wrapper for a simulation debugging file.
//
interface DEBUG_FILE;

    method Action record(Fmt fmt);

endinterface


//
// mkDebugFileNull --
//     Null debug file, will drop everything on the floor. 
//
module mkDebugFileNull#(String fname)
    // interface:
    (DEBUG_FILE);
    method record = ?;
endmodule


//
// mkDebugFile --
//     Standard simulation debugging file.
//
module mkDebugFile#(String fname)
    // interface:
    (DEBUG_FILE);

`ifdef SYNTH_Z

    COUNTER#(32) fpga_cycle <- mkLCounter(0);

    Reg#(File) debugLog <- mkReg(InvalidFile);
    Reg#(Bool) initialized <- mkReg(False);

    rule open (initialized == False);
        let fd <- $fopen(debugPath(fname), "w");
        if (fd == InvalidFile)
        begin
            $display("Error opening debugging logfile " + debugPath(fname));
            $finish(1);
        end

        debugLog <= fd;
        initialized <= True;
    endrule

    rule inc (True);
        fpga_cycle.up();
    endrule

    method Action record(Fmt fmt) if (initialized);
        $fdisplay(debugLog, $format("[%d]: ", fpga_cycle.value()) + fmt);
        $fflush(debugLog);
    endmethod

`else

    // No point in wasting space on debug file for synthesized build.  Xst
    // doesn't get rid of it all.
    DEBUG_FILE n <- mkDebugFileNull(fname);
    return n;

`endif

endmodule
