//
// Copyright (C) 2009 Intel Corporation
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


`include "awb/rrr/server_stub_DEBUG_SCAN.bsh"
`include "awb/rrr/client_stub_DEBUG_SCAN.bsh"


module [CONNECTED_MODULE] mkDebugScanService
    // interface:
    ();

    // ****** State Elements ******

    // Communication to/from our SW via RRR
    ClientStub_DEBUG_SCAN clientStub <- mkClientStub_DEBUG_SCAN();
    ServerStub_DEBUG_SCAN serverStub <- mkServerStub_DEBUG_SCAN();

    // Communication link to the Stats themselves
    Connection_Chain#(DEBUG_SCAN_DATA) chain <- mkConnection_Chain(`RINGID_DEBUG_SCAN);
    

    // ****** Rules ******
  
    //
    // processReq --
    //     Receive a command requesting a scan dump.
    //
    rule processReq (True);
        let dummy <- serverStub.acceptRequest_Scan();

        // There is only one command:  start a scan
        chain.sendToNext(tagged DS_DUMP);
    endrule

    //
    // Done fires when software confirms all dump data has been received.
    // At that point it is safe to return from the Scan() request.
    //
    rule done (True);
        let dummy <- clientStub.getResponse_Done();
        serverStub.sendResponse_Scan(0);
    endrule

    //
    // processResp --
    //
    // Process a response from an individual scan node.
    //  
    rule processResp (True);
        let ds <- chain.recvFromPrev();

        case (ds) matches
            // A value to dump
            tagged DS_VAL .v:
            begin
                clientStub.makeRequest_Send(v, 0);
            end

            tagged DS_VAL_LAST .v:
            begin
                clientStub.makeRequest_Send(v, 1);
            end

            // Command came all the way around the loop.  Done dumping.
            tagged DS_DUMP:
            begin
                clientStub.makeRequest_Done(?);
            end
        endcase
    endrule
endmodule
