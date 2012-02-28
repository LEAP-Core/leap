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

`include "awb/provides/soft_connections.bsh"

// These should match what the device actually expects - jse

typedef Bit#(32) ASSERTIONS_DICT_TYPE;
typedef Bit#(32) ASSERTION_SEVERITY;

// Assertions

// A way to report to the outside world when something has gone wrong.

typedef function Action checkAssert(Bool b) ASSERTION;
  
interface ASSERTION_NODE;
            
    method Action raiseAssertion(ASSERTIONS_DICT_TYPE myID, ASSERTION_SEVERITY mySeverity);
    
endinterface

//
// mkAssertionNode --
//     An assertion node is a group of assertions sharing a node on the
//     assertion ring.  Each assertion must be a member of a node in order
//     to pass the assertion to software.  Up to ASSERTIONS_PER_NODE assertions
//     may be allocated for a given node.  These assertions must be numerically
//     related to the node by sharing the same base identifier.  This sharing
//     is managed automatically by the dictionary builder.  An assertion named
//     ASSERTIONS.FOO.BAR in the dictionary gets an ID ASSERTIONS_FOO_BAR and
//     belongs to node ID ASSERTIONS_FOO__BASE.
//
module [CONNECTED_MODULE] mkAssertionNode#(ASSERTIONS_DICT_TYPE baseID)
    // interface:
        (ASSERTION_NODE);

endmodule
