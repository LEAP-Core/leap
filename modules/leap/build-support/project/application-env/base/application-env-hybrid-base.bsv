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

`include "awb/provides/virtual_platform.bsh"
`include "awb/provides/hybrid_application.bsh"

//
// mkApplicationEnv --
//
// Instantiate an application that does not use soft services.  Most
// applications will use the soft services version of application_env and
// not this one.  This environment without soft connections using direct
// access to the virtual platform is typically used by small models 
// used to debug the platform.
//
module mkApplicationEnv#(VIRTUAL_PLATFORM vp)
    // interface:
        ();
        
    let app <- mkApplication(vp);

endmodule
