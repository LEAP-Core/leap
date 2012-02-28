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

//
// @file dynamic-paramters.bsv
// @brief Dynamic parameters.  The size of the parameter is an argument to
//        the declaration.  Parameters may be at most 64 bits.
//
// @author Michael Adler
//

// This should match what the device wants

typedef Bit#(32) PARAMS_DICT_TYPE;


//
// PARAMETER_NODE
//
// Interface to mkDynamicParameterNode.  Individual parameters constantly
// snoop to see whether their value has arrived on the ring.  They must
// look every cycle since the ring stop guarantees to export a value for only
// a cycle before a new ID might arrive.
//
interface PARAMETER_NODE;
    
endinterface


//
// Param
//
// Interface to a single parameter.  The read method blocks until the parameter
// is initialized by the controller.
//
interface Param#(numeric type bits);

    method Bit#(bits) _read();

endinterface


//
// mkDynamicParameterNode --
//
// Every module with dynamic parameters must allocate at least one node to
// receive values.  The node is just a temporary holding point as values
// pass through.  Each individual parameter (see mkDynamicParameter below)
// connects to a ring stop and snoops for incoming updates.
//
module mkDynamicParameterNode
    //interface:
        (PARAMETER_NODE);

endmodule


//
// mkDynamicParameter --
//
// Object for an individual parameter.
//
module mkDynamicParameter#(PARAMS_DICT_TYPE myID, PARAMETER_NODE paramNode)
    //interface:
        (Param#(bits)) provisos (Add#(a__, bits, 64));

    method Bit#(bits) _read() = 0;

endmodule
