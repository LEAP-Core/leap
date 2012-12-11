///
// Copyright (C) 2010 Intel Corporation
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

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/stats_service.bsh"
`include "awb/provides/soft_connections.bsh"


// SCRATCHPAD_STATS_CONSTRUCTOR

// A function to instantiate a stat tracker. Passed to the multi-cached-memory
// modules below.

typedef function CONNECTED_MODULE#(Empty) f(RL_CACHE_STATS stats) SCRATCHPAD_STATS_CONSTRUCTOR;
typedef function CONNECTED_MODULE#(Empty) f(RL_PREFETCH_STATS stats) SCRATCHPAD_PREFETCH_STATS_CONSTRUCTOR;

//
// mkBasicScratchpadCacheStats --
//     Shim between an RL_CACHE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicScratchpadCacheStats#(String tagPrefix,
                                                       String descPrefix,
                                                       RL_CACHE_STATS stats)
    // interface:
    ();

    STAT_ID statIDs[4] = {
        statName(tagPrefix + "SCRATCH_LOAD_HIT",
                 descPrefix + "Scratchpad load hits"),
        statName(tagPrefix + "SCRATCH_LOAD_MISS",
                 descPrefix + "Scratchpad load misses"),
        statName(tagPrefix + "SCRATCH_STORE_HIT",
                 descPrefix + "Scratchpad store hits"),
        statName(tagPrefix + "SCRATCH_STORE_MISS",
                 descPrefix + "Scratchpad store misses")
    };
    STAT_VECTOR#(4) sv <- mkStatCounter_Vector(statIDs);
    
    rule readHit (stats.readHit());
        sv.incr(0);
    endrule

    rule readMiss (stats.readMiss());
        sv.incr(1);
    endrule

    rule writeHit (stats.writeHit());
        sv.incr(2);
    endrule

    rule writeMiss (stats.writeMiss());
        sv.incr(3);
    endrule
endmodule


module [CONNECTED_MODULE] mkNullScratchpadCacheStats#(RL_CACHE_STATS stats)
    // interface:
    ();
endmodule


//
// mkBasicScratchpadPrefetchStats --
//     Shim between an RL_CACHE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicScratchpadPrefetchStats#(String tagPrefix,
                                                          String descPrefix,
                                                          NumTypeParam#(n_LEARNERS) dummy,
                                                          RL_PREFETCH_STATS stats)
    // interface:
    ()
    provisos( NumAlias#(TMul#(n_LEARNERS, 4), n_STATS),
              Add#(TMax#(TLog#(n_STATS),1), extraBits, TLog#(`STATS_MAX_VECTOR_LEN)));
    
    STAT_ID prefetchStatIDs[9];
    STAT_ID learnerStatIDs[ valueOf(n_STATS) ];

    prefetchStatIDs[0] = statName(tagPrefix  + "SCRATCH_PREFETCH_HIT", 
                         descPrefix + "Scratchpad prefetch hits");
    prefetchStatIDs[1] = statName(tagPrefix  + "SCRATCH_PREFETCH_DROP_BUSY", 
                         descPrefix + "Scratchpad prefetch reqs dropped by busy");
    prefetchStatIDs[2] = statName(tagPrefix  + "SCRATCH_PREFETCH_DROP_HIT", 
                         descPrefix + "Scratchpad prefetch reqs dropped by hit");
    prefetchStatIDs[3] = statName(tagPrefix  + "SCRATCH_PREFETCH_LATE", 
                         descPrefix + "Scratchpad late prefetch reqs");
    prefetchStatIDs[4] = statName(tagPrefix  + "SCRATCH_PREFETCH_USELESS", 
                         descPrefix + "Scratchpad useless prefetch reqs");
    prefetchStatIDs[5] = statName(tagPrefix  + "SCRATCH_PREFETCH_ISSUE", 
                         descPrefix + "Scratchpad prefetch reqs issued");
    prefetchStatIDs[6] = statName(tagPrefix  + "SCRATCH_PREFETCH_LEARN", 
                         descPrefix + "Scratchpad prefetcher learns");
    prefetchStatIDs[7] = statName(tagPrefix  + "SCRATCH_PREFETCH_CONFLICT", 
                         descPrefix + "Scratchpad prefetch learner conflicts");
    prefetchStatIDs[8] = statName(tagPrefix  + "SCRATCH_PREFETCH_ILLEGAL", 
                         descPrefix + "Scratchpad uncacheable prefetch reqs");
    
    for (Integer i = 0; i < valueOf(n_LEARNERS); i = i+1)
    begin
        learnerStatIDs[0+4*i] = statName(tagPrefix  + "SCRATCH_PREFETCH_L"+integerToString(i)+"_HIT",
                                descPrefix + "Scratchpad prefetch learner "+integerToString(i)+" hits");
        learnerStatIDs[1+4*i] = statName(tagPrefix  + "SCRATCH_PREFETCH_L"+integerToString(i)+"_ISSUE", 
                                descPrefix + "Scratchpad prefetch reqs from learner "+integerToString(i));
        learnerStatIDs[2+4*i] = statName(tagPrefix  + "SCRATCH_PREFETCH_L"+integerToString(i)+"_STRIDE", 
                                descPrefix + "Scratchpad prefetch stride from learner "+integerToString(i));
        learnerStatIDs[3+4*i] = statName(tagPrefix  + "SCRATCH_PREFETCH_L"+integerToString(i)+"_LA_DIST", 
                                descPrefix + "Scratchpad prefetch lookahead dist from learner "+integerToString(i));
    end

    STAT_VECTOR#(9)       prefetchSv <- mkStatCounter_Vector(prefetchStatIDs);
    STAT_VECTOR#(n_STATS) learnerSv  <- mkStatCounter_Vector(learnerStatIDs);
    
    rule prefetchHit (stats.prefetchHit());
        prefetchSv.incr(0);
    endrule

    rule prefetchDroppedByBusy (stats.prefetchDroppedByBusy());
        prefetchSv.incr(1);
    endrule

    rule prefetchDroppedByHit (stats.prefetchDroppedByHit());
        prefetchSv.incr(2);
    endrule

    rule prefetchLate (stats.prefetchLate());
        prefetchSv.incr(3);
    endrule

    rule prefetchUseless (stats.prefetchUseless());
        prefetchSv.incr(4);
    endrule
    
    rule prefetchIssued (stats.prefetchIssued());
        prefetchSv.incr(5);
    endrule
    
    rule prefetchLearn (stats.prefetchLearn());
        prefetchSv.incr(6);
    endrule
    
    rule prefetchLearnerConflict (stats.prefetchLearnerConflict());
        prefetchSv.incr(7);
    endrule

    rule prefetchIllegalReq (stats.prefetchIllegalReq());
        prefetchSv.incr(8);
    endrule
    
    rule hitLearnerUpdate (stats.hitLearnerInfo() matches tagged Valid .s);
        learnerSv.incr(0+resize(s.idx)*4); //hitLeanerIdx
        if (s.isActive)                    //the learner is issuing prefetch request
        begin
            learnerSv.incr(1+resize(s.idx)*4);                         //activeLearnerIdx
            learnerSv.incrBy(2+resize(s.idx)*4, signExtend(s.stride)); //activeLearnerStride
            learnerSv.incrBy(3+resize(s.idx)*4, zeroExtend(s.laDist)); //activeLearnerLaDist
        end
    endrule

endmodule

module [CONNECTED_MODULE] mkNullScratchpadPrefetchStats#(RL_PREFETCH_STATS stats)
    // interface:
    ();
endmodule
