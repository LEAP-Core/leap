//
// Copyright (C) 2011 Intel Corporation
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
