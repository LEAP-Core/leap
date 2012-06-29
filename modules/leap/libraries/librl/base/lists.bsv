//
// Copyright (C) 2012 Intel Corporation
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

import List::*;

//
// An easier way of building lists, similar to tuple().
//

function List#(t_DATA) list1(t_DATA a0) = List::cons(a0, List::nil);
function List#(t_DATA) list2(t_DATA a0, t_DATA a1) = List::cons(a0, List::cons(a1, List::nil));
function List#(t_DATA) list3(t_DATA a0, t_DATA a1, t_DATA a2) = List::cons(a0, List::cons(a1, List::cons(a2, List::nil)));
function List#(t_DATA) list4(t_DATA a0, t_DATA a1, t_DATA a2, t_DATA a3) = List::cons(a0, List::cons(a1, List::cons(a2, List::cons(a3, List::nil))));
function List#(t_DATA) list5(t_DATA a0, t_DATA a1, t_DATA a2, t_DATA a3, t_DATA a4) = List::cons(a0, List::cons(a1, List::cons(a2, List::cons(a3, List::cons(a4, List::nil)))));
function List#(t_DATA) list6(t_DATA a0, t_DATA a1, t_DATA a2, t_DATA a3, t_DATA a4, t_DATA a5) = List::cons(a0, List::cons(a1, List::cons(a2, List::cons(a3, List::cons(a4, List::cons(a5, List::nil))))));
function List#(t_DATA) list7(t_DATA a0, t_DATA a1, t_DATA a2, t_DATA a3, t_DATA a4, t_DATA a5, t_DATA a6) = List::cons(a0, List::cons(a1, List::cons(a2, List::cons(a3, List::cons(a4, List::cons(a5, List::cons(a6, List::nil)))))));
function List#(t_DATA) list8(t_DATA a0, t_DATA a1, t_DATA a2, t_DATA a3, t_DATA a4, t_DATA a5, t_DATA a6, t_DATA a7) = List::cons(a0, List::cons(a1, List::cons(a2, List::cons(a3, List::cons(a4, List::cons(a5, List::cons(a6, List::cons(a7, List::nil))))))));
    
    
//
// Provided by Bluespec -- method of generating arbitrary length lists
// using just list(a, b, ...).
//

// A type class used to implement a list construction function
// which can take any number of arguments (>0).
// The type a is the type of list elements.  The type r is the
// remainder of the curried type.
// So with 3 arguments, there would be three instance matches
// used for BuildList:
//   one with r equal to List#(a)
//   one with r equal to function List#(a) f(a x)
//   one with r equal to function (function List#(a) f1(a x)) f2(a x)

// The type class definition
typeclass BuildList#(type a, type r)
    dependencies (r determines a);
    function r buildList_(List#(a) l, a x);
endtypeclass

// This is the base case (building a list from the final argument)
instance BuildList#(a,List#(a));
    function List#(a) buildList_(List#(a) l, a x);
        return List::reverse(List::cons(x,l));
    endfunction
endinstance

// This is the recursive case (building a list from non-final
// arguments)
// Note: this plays the trick of moving a function
// application from the return type into the argument list -- the
// overall type of buildList_ is the same, but it is written in a way
// that allows us to manipulate the curried argument.
instance BuildList#(a,function r f(a x)) provisos(BuildList#(a,r));
    function r buildList_(List#(a) l, a x, a y);
        return buildList_(List::cons(x,l),y);
    endfunction
endinstance

// This is the user-visible List constructor function
function r list(a x) provisos(BuildList#(a,r));
    return buildList_(List::nil,x);
endfunction
