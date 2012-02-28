//
// Copyright (C) 2009 Massachusetts Institute of Technology
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

`include "awb/provides/virtual_devices.bsh"

// This interface isn't correct because we really don't have a
// stats device to pass in. So nobody can even instantiate a
// null stats service.

// module [CONNECTED_MODULE] mkStatsService#(STATS statsDevice)

module [CONNECTED_MODULE] mkStatsService
    // interface:
    ();

endmodule
