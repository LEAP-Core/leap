//
// Copyright (C) 2013 Intel Corporation
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

`include "awb/provides/bsv_version_capabilities.bsh"


//
// hashStringToInteger --
//   Hash a String into an Integer.
//
function Integer hashStringToInteger(String str);
    let n_chars = stringLength(str);

    Integer hash = 0;

    // The ability to convert String to Char was introduced in May 2013.
    // Always return 0 for the hash on old compilers.
`ifdef BSV_VER_CAP_CHAR
    for (Integer i = 0; i < n_chars; i = i + 1)
    begin
        // sdbm string hash function
        hash = hash * 65599 + charToInteger(str[i]);
    end
`endif

    return hash;
endfunction
