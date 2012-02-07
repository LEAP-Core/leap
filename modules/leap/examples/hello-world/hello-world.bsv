//
// Copyright (C) 2008 Intel Corporation
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

import Vector::*;
import List::*;

`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/librl_bsv.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

typedef enum 
{
    STATE_start,
    STATE_say_hello,
    STATE_exit,
    STATE_finish 
} 
STATE deriving (Bits, Eq);


module [CONNECTED_MODULE] mkConnectedApplication ();

    Connection_Receive#(Bool) linkStarterStartRun <- mkConnectionRecv("vdev_starter_start_run");
    Connection_Send#(Bit#(8)) linkStarterFinishRun <- mkConnectionSend("vdev_starter_finish_run");

    STDIO#(Bit#(32)) stdio <- mkStdIO();

    Reg#(STATE) state <- mkReg(STATE_start);

    let msg <- getGlobalStringUID("Hello, World! This is hardware speaking.\n");

    rule start (state == STATE_start);
    
        linkStarterStartRun.deq();
        state <= STATE_say_hello;

    endrule

    rule hello (state == STATE_say_hello);
  
        stdio.printf(msg, List::nil);
        state <= STATE_exit;

    endrule


    rule exit (state == STATE_exit);
    
        linkStarterFinishRun.send(0);
        state <= STATE_finish;

    endrule


    rule finish (state == STATE_finish);
        noAction;
    endrule

endmodule
