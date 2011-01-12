//
// Copyright (C) 2008 Massachusetts Institute of Technology
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

import Clocks::*;

`include "asim/provides/model.bsh"
`include "asim/provides/application_env.bsh"

// TODO: better story on command line args
`include "asim/provides/command_switches.bsh"

module mkModel
    //interface:
        (TOP_LEVEL_WIRES);

    // instantiate application environment
    TOP_LEVEL_WIRES appEnv <- mkApplicationEnv();
    
    // return the app's wires as our own.
    return appEnv;
    
endmodule
