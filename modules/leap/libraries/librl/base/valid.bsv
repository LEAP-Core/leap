//
// Copyright (C) 2014 Intel Corporation
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
// Convenience functions for dealing with Maybe types.
//


//
// toValid --
//   Return a valid instance of the value.
//
function Maybe#(t_TYPE) toValid(t_TYPE v) = tagged Valid v;


//
// toValidM --
//   Monadic version of toValid.  Evaluate and return a valid instance of the
//   object.
//
function m#(Maybe#(t_TYPE)) toValidM(m#(t_TYPE) obj)
    provisos (Monad#(m));
actionvalue
    t_TYPE _o <- obj;
    return tagged Valid _o;
endactionvalue
endfunction    
