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
// Statistics wires for cache prefetchers so individual prefetchers can have their 
// hit rate, activity, and learners' statistics logged.
// When a line becomes true the coresponding statistic should be incremented.
//

interface RL_PREFETCH_STATS;
    method Bool prefetchHit();              // The prefetched data is accessed before it is invalidated from the cache
    method Bool prefetchDroppedByBusy();    // Dropped because the cache line/side buffer is busy (untimely prefetch)
    method Bool prefetchDroppedByHit();     // Dropped because the data is already in the cache
    method Bool prefetchLate();             // Prefetch is usable but late (cache request is shunt to the side buffer due to late prefetch)
    method Bool prefetchUseless();          // The prefetch data is replaced before being accessed
    method Bool prefetchIssued();           // Prefetch request is issued from the prefetcher
    method Bool prefetchLearn();            // Prefetcher is triggered for learning
    method Bool prefetchLearnerConflict();  // Prefetcher's learner conflicts (learner's tag mismatch)     
    method Bool prefetchIllegalReq();       // Prefetch request is uncacheable 
    method Maybe#(PREFETCH_LEARNER_STATS) hitLearnerInfo();
endinterface: RL_PREFETCH_STATS


