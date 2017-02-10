//
// Copyright (c) 2016, Intel Corporation
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
//  shuffle.bsv -
//    provides some generic functions for shuffling 
//


// Library imports.

import FIFO::*;
import Vector::*;
import List::*;
import LFSR::*;



//
// permute -
//   Applys a permutation vector to another vector, creating
//   a new, permuted vector. 
//
function Vector#(n_SIZE, t_DATA) permute(Vector#(n_SIZE, t_DATA) data, Vector#(n_SIZE, Integer) order);

   return map(select(data),order);
   
endfunction


//
// Perfect Shuffle -
//   Produces a set of indices representing a radix n perfect shuffle permutation on a deck of some n_SIZE.
//   Accepts a deck of indices, so that multiple shuffles can be performed.
//   Strategy is to chop the original deck into subdecks and then pick indicies in those subdecks.
//   Code makes no attempt to handle case when n_SIZE is not divisible by radix. 
//
function Vector#(n_SIZE, Integer) perfectShuffle(NumTypeParam#(n_RADIX) radixParam, NumTypeParam#(n_SIZE) n_SIZEParam) 
   provisos(Add#(n_SIZE, n_SIZE_extra, TMul#(n_RADIX, TDiv#(n_SIZE, n_RADIX))));
   Vector#(n_RADIX, Integer) subdecks = genVector();
   Vector#(TDiv#(n_SIZE,n_RADIX), Vector#(n_RADIX, Integer)) subdecksVectors = replicate(subdecks);
   Vector#(TMul#(n_RADIX, TDiv#(n_SIZE,n_RADIX)), Integer) subdeckSelectsExpanded = concat(subdecksVectors);
   Vector#(n_SIZE, Integer) subdeckSelects = take(subdeckSelectsExpanded);

   Vector#(TDiv#(n_SIZE,n_RADIX), Integer) indices = genVector();
   Vector#(TDiv#(n_SIZE,n_RADIX), Vector#(n_RADIX, Integer)) indexVectors = map(replicate, indices);
   Vector#(TMul#(n_RADIX, TDiv#(n_SIZE,n_RADIX)), Integer) indexSelectsExpanded = concat(indexVectors);
   Vector#(n_SIZE, Integer) indexSelects= take(indexSelectsExpanded);


   Vector#(n_SIZE, Integer) offsets = zipWith( \* , replicate(fromInteger(valueof(n_SIZE))/fromInteger(valueof(n_RADIX))), subdeckSelects);
   Vector#(n_SIZE, Integer) result = zipWith ( \+ , indexSelects, zipWith( \* , replicate(fromInteger(valueof(n_SIZE))/fromInteger(valueof(n_RADIX))), subdeckSelects));

   return result;
endfunction


