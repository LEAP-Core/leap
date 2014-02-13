//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

//
// Hacks for defining type aliases within a module to work around lack of
// "typedef" inside module scope.
//
typeclass Alias#(type a, type b)
    dependencies (a determines b);
endtypeclass

instance Alias#(a,a);
endinstance

typeclass NumAlias#(numeric type a, numeric type b)
    dependencies (a determines b, b determines a);
endtypeclass

instance NumAlias#(a,a);
endinstance



//
// NumTypeParam is useful for passing a numeric type as a parameter to a
// module when the type is not part of the module's interface.  Ideally,
// Bluespec would permit type parameters to modules.  This is an
// intermediate step.
//
// Usage:
//
//   module mkMod0#(NumTypeParam#(n_ENTRIES) p) (BASE);
//       Vector#(n_ENTRIES, Bit#(1)) v = ?;
//   endmodule
//
//   module mkMod1 ();
//       NumTypeParam#(1024) p = ?;
//       BASE b <- mkMod0(p);
//   endmodule
//

typedef Bit#(n) NumTypeParam#(numeric type n);


// ========================================================================
//
// It would be nice if Bluespec provided numeric type comparison functions.
// These may be needed in complex operations on polymorphic types, where
// the algorithm may depend on the size of the type.
//
// On input, all operators treat 0 as False and non-zero as True.
// 
// All operators return 0 for False and 1 for True.
//
// These are made more difficult since Bluespec types don't work when
// the value falls below 0.
//
// ========================================================================

// TBool: 0 if A == 0, otherwise 1
typedef TMin#(a, 1)
    TBool#(numeric type a);

//
// TNot: 1 if A == 0, otherwise 0
//                         A ? 2 : 1
//               /                           \
typedef TSub#(2, TMax#(1, TAdd#(TBool#(a), 1)))
    TNot#(numeric type a);

//
// TAnd: A && B
typedef TBool#(TMin#(a, b))
    TAnd#(numeric type a, numeric type b);

//
// TOr: A || B
typedef TBool#(TMax#(a, b))
    TOr#(numeric type a, numeric type b);

//
// TGT: A > B
//                      1 or 0
//      /                                       \
//                  Either B + 1 or B
//            /                             \
//                      At most B + 1
//                  /                   \
typedef TSub#(TMax#(TMin#(a, TAdd#(b, 1)), b), b)
    TGT#(numeric type a, numeric type b);

//
// TGE: A >= B
//
typedef TGT#(TAdd#(a, 1), b)
    TGE#(numeric type a, numeric type b);

//
// TNE: A != B
//              0 if equal, otherwise nonzero
//            /                              \
typedef TBool#(TSub#(TMax#(a, b), TMin#(a, b)))
    TNE#(numeric type a, numeric type b);

// TEq: A == B
typedef TNot#(TNE#(a, b))
    TEq#(numeric type a, numeric type b);

// TSelect: A ? B : C
typedef TAdd#(TMul#(TBool#(a), b), TMul#(TNot#(a), c))
    TSelect#(numeric type a, numeric type b, numeric type c);



// ========================================================================
//
// Useful logical tests.
//
// ========================================================================

// True (1) iff A is a power of 2
typedef TEq#(a, TExp#(TLog#(a))) IS_POWER_OF_2#(type a);


// ========================================================================
//
// Bluespec ought to have included the following for HList.
//
// ========================================================================

//
// HLast --
//   Find the last type in an HList, when used as a proviso.  The "hLast()"
//   function returns the value of the last element in an HList.
//
typeclass HLast#(type t_HLIST, type t_LAST)
    dependencies (t_HLIST determines t_LAST);
    function t_LAST hLast(t_HLIST lst);
endtypeclass

instance HLast#(HNil, HNil);
    function hLast(lst) = ?;
endinstance

instance HLast#(HCons#(t_HEAD, HNil), t_HEAD);
    function hLast(lst) = hHead(lst);
endinstance

instance HLast#(HCons#(t_HEAD, t_TAIL), t_LAST)
    provisos (HLast#(t_TAIL, t_LAST));
    function hLast(lst) = hLast(hTail(lst));
endinstance


//
// Map an HList to Bits.  All the types in the list must also belong
// to Bits.
//
instance Bits#(HNil, 0);
    function pack(x) = 0;
    function unpack(x) = hNil;
endinstance

instance Bits#(HCons#(t_HEAD, HNil), t_SZ)
    provisos (Bits#(t_HEAD, t_SZ));
    function pack(x) = pack(hHead(x));
    function unpack(x) = hList1(unpack(x));
endinstance

instance Bits#(HCons#(t_HEAD, t_TAIL), t_SZ)
    provisos (Bits#(t_HEAD, t_HEAD_SZ),
              Bits#(t_TAIL, t_TAIL_SZ),
              Add#(t_HEAD_SZ, t_TAIL_SZ, t_SZ));
    function pack(x) = { pack(hHead(x)), pack(hTail(x)) };
    function unpack(x);
        t_HEAD h = unpack(x[valueOf(t_SZ)-1 : valueOf(t_TAIL_SZ)]);
        t_TAIL t = unpack(x[valueOf(t_TAIL_SZ)-1 : 0]);
        return hCons(h, t);
    endfunction
endinstance
