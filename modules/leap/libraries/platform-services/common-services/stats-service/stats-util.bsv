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

import FIFO::*;
import DReg::*;

//
// mkCounterHistogramStats --
//     Generate histogram stats for a given counter.
//
typedef 64 HISTOGRAM_STATS_NUM;

module [CONNECTED_MODULE] mkCounterHistogramStats#(String statTag,
                                                   String statDesc,
                                                   Bit#(t_COUNTER_SZ) counter,
                                                   Bool counterEn)
    // interface:
    ()
    provisos(NumAlias#(TLog#(HISTOGRAM_STATS_NUM), n_STATS_LOG),
             NumAlias#(TMax#(t_COUNTER_SZ, n_STATS_LOG), t_MAX_COUNTER_SZ));
    
    STAT_ID statID = statName(statTag, statDesc);
    STAT_VECTOR#(HISTOGRAM_STATS_NUM) counterSv  <- mkStatCounter_RAM(statID);
    
    UInt#(n_STATS_LOG) maxStatIdx = maxBound;
    Reg#(Bit#(n_STATS_LOG)) statIdx <- mkRegU;
    Reg#(Bool) statEn  <- mkReg(False);
    
    function Bit#(n_STATS_LOG) getStatIdx(UInt#(t_MAX_COUNTER_SZ) val);
        return (val >= unpack(zeroExtend(pack(maxStatIdx))))? pack(maxStatIdx) : truncate(pack(val));
    endfunction

    rule addPipeline (True);
        statIdx <= getStatIdx(unpack(zeroExtend(counter)));
        statEn  <= counterEn;
    endrule

    rule counterIncr (statEn);
        counterSv.incr(statIdx);
    endrule

endmodule

//
// mkQueueingStats --
//     Generate queueing delay and arrival rate histogram stats for a given FIFO. 
//
// Maximum queueing delay
typedef 256 QUEUEING_STATS_MAX_LATENCY;
typedef 128 QUEUEING_STATS_PERIOD;

module [CONNECTED_MODULE] mkQueueingStats#(String statTagPrefix,
                                           String statDescPrefix,
                                           Maybe#(Integer) fifoSz, 
                                           Bool enqEn, 
                                           Bool deqEn)
    // interface:
    ()
    provisos(NumAlias#(TLog#(HISTOGRAM_STATS_NUM), n_STATS_LOG),
             Alias#(Bit#(TAdd#(TLog#(QUEUEING_STATS_MAX_LATENCY), 1)), t_LATENCY),
             Alias#(Bit#(TLog#(QUEUEING_STATS_PERIOD)), t_COUNTER));


    UInt#(n_STATS_LOG) maxStatIdx = maxBound;
    
    // Tracking queueing delay
    
    Reg#(t_LATENCY) current <- mkReg(0);
    Reg#(t_LATENCY) latencyReg <- mkDReg(0);
    
    STAT_ID latencyStatID = statName(statTagPrefix + "_QUEUEING_DELAY", statDescPrefix + " queueing delay");
    STAT_VECTOR#(HISTOGRAM_STATS_NUM) latencySv  <- mkStatCounter_RAM(latencyStatID);
    
    Reg#(Bit#(n_STATS_LOG)) latencyStatIdx <- mkRegU;
    Reg#(Bool) latencyStatEn  <- mkReg(False);
    
    FIFO#(t_LATENCY) queue = ?;
    
    if (fifoSz matches tagged Valid .s)
    begin
        queue <- mkSizedFIFO(s);
    end
    else
    begin
        queue <- mkFIFO();
    end
    
    function Bit#(n_STATS_LOG) getStatIdx(t_LATENCY val);
        return (val >= zeroExtend(pack(maxStatIdx)))? pack(maxStatIdx) : truncate(val);
    endfunction

    // Tracking arrival rates

    Reg#(t_COUNTER) cycleCnt <- mkReg(0);
    Reg#(t_COUNTER) reqCnt <- mkReg(0);
    
    STAT_ID arrivalStatID = statName(statTagPrefix + "_QUEUE_ARRIVALS", statDescPrefix + " queue arrivals every " + integerToString(valueOf(QUEUEING_STATS_PERIOD)) + " cycles");
    STAT_VECTOR#(HISTOGRAM_STATS_NUM) arrivalSv  <- mkStatCounter_RAM(arrivalStatID);
    
    Reg#(Bit#(n_STATS_LOG)) arrivalStatIdx <- mkRegU;
    Reg#(Bool) arrivalStatEn  <- mkReg(False);

    // Tracking inter-arrival time
    Reg#(t_LATENCY) lastReqTime     <- mkReg(0);
    Reg#(t_LATENCY) interArrivalReg <- mkDReg(0);
    Reg#(Bool)      isFirstReq      <- mkReg(True);
    
    STAT_ID interArrivalStatID = statName(statTagPrefix + "_QUEUE_INTER_ARRIVAL_TIME", statDescPrefix + " queue inter-arrival time");
    STAT_VECTOR#(HISTOGRAM_STATS_NUM) interArrivalSv  <- mkStatCounter_RAM(interArrivalStatID);
    
    Reg#(Bit#(n_STATS_LOG)) interArrivalStatIdx <- mkRegU;
    Reg#(Bool) interArrivalStatEn  <- mkReg(False);

    (* fire_when_enabled, no_implicit_conditions *)
    rule tickCurrent;
        current <= current + 1;
        cycleCnt <= cycleCnt + 1;
    endrule

    (* fire_when_enabled *)
    rule enqueueTimeStamp(enqEn);
        queue.enq(current);
        if (!isFirstReq)
        begin
            interArrivalReg <= (current > lastReqTime)? (current - lastReqTime) : (maxBound - lastReqTime + current);
        end
        isFirstReq  <= False;
        lastReqTime <= current;
    endrule

    (* fire_when_enabled *)
    rule updateReqCnt(True);
        if (cycleCnt == maxBound)
        begin
            reqCnt <= 0;
        end
        else if (enqEn)
        begin
            reqCnt <= reqCnt + 1;
        end
    endrule

    (* fire_when_enabled *)
    rule dequeueTimeStamp(deqEn);
        let stamp = queue.first();
        queue.deq();
        latencyReg <= (current > stamp)? (current - stamp) : (maxBound - stamp + current);
    endrule
    
    (* fire_when_enabled *)
    rule addPipeline (True);
        latencyStatIdx      <= getStatIdx(latencyReg>>2);
        latencyStatEn       <= (latencyReg != 0);
        arrivalStatIdx      <= getStatIdx(zeroExtend(reqCnt));
        arrivalStatEn       <= (cycleCnt == maxBound);
        interArrivalStatIdx <= getStatIdx(interArrivalReg>>1);
        interArrivalStatEn  <= (interArrivalReg != 0);
    endrule

    rule latencyStatsIncr (latencyStatEn);
        latencySv.incr(latencyStatIdx);
    endrule
    
    rule arrivalStatsIncr (arrivalStatEn);
        arrivalSv.incr(arrivalStatIdx);
    endrule
    
    rule interArrivalStatsIncr (interArrivalStatEn);
        interArrivalSv.incr(interArrivalStatIdx);
    endrule

endmodule
