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

`include "asim/provides/soft_connections.bsh"
`include "asim/provides/streams_device.bsh"

`include "asim/dict/RINGID.bsh"


module [CONNECTED_MODULE] mkStreamsService#(STREAMS streams)
    // interface:
    ();
    
    // Communication link to the streams clients
    Connection_Chain#(STREAMS_REQUEST) chain <- mkConnection_Chain(`RINGID_STREAMS);

    //
    // fwdStreamsMsg --
    //     Forward a message from the internal ring to the host.
    //
    rule fwdStreamsMsg (True);
        let msg <- chain.recvFromPrev();

        streams.makeRequest(msg.streamID,
                            msg.stringID,
                            msg.payload0,
                            msg.payload1);
    endrule
endmodule
