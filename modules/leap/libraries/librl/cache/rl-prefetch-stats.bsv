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
    method Maybe#(PREFETCH_LEARNER_STATS) hitLearnerInfo();
endinterface: RL_PREFETCH_STATS


