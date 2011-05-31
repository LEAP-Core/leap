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

`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/virtual_devices.bsh"
`include "awb/provides/common_utility_devices.bsh"
`include "awb/provides/streams_device.bsh"
`include "awb/provides/starter_device.bsh"

`include "awb/dict/STREAMID.bsh"
`include "awb/dict/STREAMS.bsh"

typedef enum 
{
    STATE_start,
    STATE_say_hello,
    STATE_exit,
    STATE_finish 
} 
STATE deriving (Bits, Eq);


module mkApplication#(VIRTUAL_PLATFORM virtualPlatform)();

    STARTER starter = virtualPlatform.virtualDevices.starter;

    STREAMS streams = virtualPlatform.virtualDevices.commonUtilities.streams;
    

    Reg#(STATE) state <- mkReg(STATE_start);

    rule start (state == STATE_start);
    
       starter.acceptRequest_Start();

       state <= STATE_say_hello;

    endrule

    rule hello (state == STATE_say_hello);
  
       streams.makeRequest(`STREAMID_MESSAGE,
                           `STREAMS_MESSAGE_HELLO,
                           ?,
                           ?);

       state <= STATE_exit;

    endrule


    rule exit (state == STATE_exit);
    
       starter.makeRequest_End(0);

       state <= STATE_finish;

    endrule


    rule finish (state == STATE_finish);
       noAction;
    endrule

endmodule
