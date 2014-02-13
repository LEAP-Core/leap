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

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/local_mem.bsh"

//
// Copy the definitions from the soft connected local memory so that clients
// see a standard interface.
//
typedef union tagged
{
    LOCAL_MEM_ADDR LM_READ_WORD;
    LOCAL_MEM_ADDR LM_READ_LINE;

    LOCAL_MEM_ADDR LM_WRITE_WORD;
    LOCAL_MEM_ADDR LM_WRITE_LINE;

    LOCAL_MEM_ADDR LM_WRITE_WORD_MASKED;
    LOCAL_MEM_ADDR LM_WRITE_LINE_MASKED;
}
LOCAL_MEM_CMD
    deriving (Eq, Bits);

typedef union tagged
{
    LOCAL_MEM_WORD LM_READ_WORD_DATA;
    LOCAL_MEM_LINE LM_READ_LINE_DATA;
}
LOCAL_MEM_READ_DATA
    deriving (Eq, Bits);


module [CONNECTED_MODULE] mkLocalMemory#(LowLevelPlatformInterface llpi)
    // Interface:
    ();
    
    //
    // Mimic the soft connections of the true implementation.
    //
    CONNECTION_SERVER#(LOCAL_MEM_CMD, LOCAL_MEM_READ_DATA) lms
        <- mkConnectionServerOptional("local_memory_device");
    CONNECTION_RECV#(Tuple2#(LOCAL_MEM_LINE, LOCAL_MEM_LINE_MASK)) lmWriteData
        <- mkConnectionRecvOptional("local_memory_device_wdata");

endmodule
