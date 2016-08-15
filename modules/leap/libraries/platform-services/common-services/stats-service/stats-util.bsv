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
import SpecialFIFOs::*;

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
// Statistics wires for queues 
//
interface QUEUE_STATS;
    // Tracking queueing delay
    method Maybe#(Bit#(TLog#(HISTOGRAM_STATS_NUM))) latencyStatInfo();
    // Tracking arrival rates
    method Maybe#(Tuple2#(Bit#(TLog#(HISTOGRAM_STATS_NUM)), STAT_VALUE)) arrivalStatInfo();
    // Tracking inter-arrival time
    method Maybe#(Bit#(TLog#(HISTOGRAM_STATS_NUM))) interArrivalStatInfo();
    // Tracking idle/busy cycles
    method Maybe#(STAT_VALUE) idleCycleStatInfo();
    method Bool queueBusy();
endinterface: QUEUE_STATS

//
// mkQueueingStatsMonitor --
//     Monitor queueing delay and arrival rate histogram stats for a given FIFO
// and return the statistics wires.
//
// Maximum queueing delay
typedef 2048 QUEUEING_STATS_MAX_LATENCY;
typedef 128  QUEUEING_STATS_PERIOD;

module [CONNECTED_MODULE] mkQueueingStatsMonitor#(Maybe#(Integer) fifoSz, 
                                                  Bool enqEn, 
                                                  Bool deqEn, 
                                                  Bool useBypassFIFO, 
                                                  DEBUG_FILE debugLog)
    // interface:
    (QUEUE_STATS)
    provisos(NumAlias#(TLog#(HISTOGRAM_STATS_NUM), n_STATS_LOG),
             Alias#(Bit#(TAdd#(TLog#(QUEUEING_STATS_MAX_LATENCY), 1)), t_LATENCY),
             Alias#(Bit#(TLog#(QUEUEING_STATS_PERIOD)), t_COUNTER));

    UInt#(n_STATS_LOG) maxStatIdx = maxBound;
   
    //
    // Tracking queueing delay
    //
    Reg#(t_LATENCY)                current <- mkReg(0);
    Reg#(Maybe#(t_LATENCY))     latencyReg <- mkDReg(tagged Invalid);
    Reg#(Bit#(n_STATS_LOG)) latencyStatIdx <- mkRegU;
    Reg#(Bool)               latencyStatEn <- mkReg(False);
    
    FIFOF#(t_LATENCY) queue = ?;
    
    if (fifoSz matches tagged Valid .s)
    begin
        if (s == 1)
        begin
            queue <- mkBypassFIFOF();
        end 
        else if (useBypassFIFO)
        begin
            queue <- mkSizedBypassFIFOF(s);
        end
        else
        begin
            queue <- mkSizedFIFOF(s);
        end
    end
    else if (useBypassFIFO)
    begin
        queue <- mkBypassFIFOF();
    end
    else
    begin
        queue <- mkFIFOF();
    end
    
    function Bit#(n_STATS_LOG) getStatIdx(t_LATENCY val);
        return (val >= zeroExtend(pack(maxStatIdx)))? pack(maxStatIdx) : truncate(val);
    endfunction

    //
    // Tracking arrival rates
    //
    Reg#(t_COUNTER) cycleCnt <- mkReg(0);
    Reg#(t_COUNTER) reqCnt  <- mkReg(0);
    Reg#(Bit#(n_STATS_LOG)) arrivalStatIdx <- mkRegU;
    Reg#(Bool) arrivalStatEn  <- mkReg(False);
    Reg#(Bit#(16)) zeroArrivalCnt <- mkReg(0);
    Reg#(Bool)  zeroArrivalStatEn <- mkReg(False);
    Reg#(Bit#(16)) zeroArrivalStatValue <- mkRegU; 
    
    //
    // Tracking inter-arrival time
    //
    Reg#(t_LATENCY)             lastReqTime <- mkReg(0);
    Reg#(Maybe#(t_LATENCY)) interArrivalReg <- mkDReg(tagged Invalid);
    Reg#(Bool)                   isFirstReq <- mkReg(True);
    
    Reg#(Bit#(n_STATS_LOG)) interArrivalStatIdx <- mkRegU;
    Reg#(Bool) interArrivalStatEn  <- mkReg(False);

    //
    // Tracking idle cycles
    //
    Reg#(Bit#(16)) idleCycleCnt <- mkReg(0);

    (* fire_when_enabled, no_implicit_conditions *)
    rule tickCurrent;
        current  <= current + 1;
        cycleCnt <= cycleCnt + 1;
    endrule
    
    (* fire_when_enabled *)
    rule updIdleCycleCnt(True);
        idleCycleCnt <= (enqEn || queue.notEmpty)? 0 : idleCycleCnt + 1;
    endrule

    (* fire_when_enabled *)
    rule enqueueTimeStamp(enqEn);
        queue.enq(current);
        if (!isFirstReq)
        begin
            let inter_arr = (current > lastReqTime)? (current - lastReqTime) : (maxBound - lastReqTime + current);
            if (inter_arr > 0)
            begin
                interArrivalReg <= tagged Valid inter_arr;
            end
            debugLog.record($format("enqueueTimeStamp: current=%0d, interArrival=%0d, reqCnt=%0d", 
                            current, inter_arr, reqCnt));
        end
        else
        begin
            debugLog.record($format("enqueueTimeStamp: current=%0d, reqCnt=%0d", 
                            current, reqCnt));
        end
        isFirstReq  <= False;
        lastReqTime <= current;
    endrule

    (* fire_when_enabled *)
    rule updateReqCnt(cycleCnt == maxBound || enqEn);
        let new_req_cnt = (cycleCnt == maxBound)? zeroExtend(pack(enqEn)) : (reqCnt + zeroExtend(pack(enqEn)));
        reqCnt <= new_req_cnt;
    endrule

    (* fire_when_enabled *)
    rule updateZeroArrivalCnt(True);
        let zero_arr_en = False;
        if ((enqEn || reqCnt > 0) && zeroArrivalCnt > 0)
        begin
            zero_arr_en = True;
            let zero_arr_value = zeroArrivalCnt + zeroExtend(pack(cycleCnt == maxBound && !isFirstReq && reqCnt == 0));
            zeroArrivalCnt <= 0;
            zeroArrivalStatValue <= zero_arr_value;
        end
        else if (cycleCnt == maxBound && !isFirstReq && reqCnt == 0)
        begin
            zeroArrivalCnt    <= zeroArrivalCnt + 1;
            debugLog.record($format("zeroArrivalCnt: zero_arr=%0d", zeroArrivalCnt+1));
        end
        zeroArrivalStatEn <= zero_arr_en;
    endrule

    (* fire_when_enabled *)
    rule dequeueTimeStamp(deqEn);
        let stamp = queue.first();
        queue.deq();
        let latency = (current >= stamp)? (current - stamp) : (maxBound - stamp + current);
        latencyReg <= tagged Valid latency;
        debugLog.record($format("dequeueTimeStamp: latency=%0d", latency));
    endrule
    
    (* fire_when_enabled *)
    rule addPipeline (True);
        let latency = (fromMaybe(0,latencyReg) == 0)? 0 : ((fromMaybe(0,latencyReg) - 1) >> 2) + 1;
        let inter_arr = (fromMaybe(0,interArrivalReg) == 0)? 0 : ((fromMaybe(0,interArrivalReg) - 1) >> 1) + 1;
        latencyStatIdx      <= getStatIdx(latency);
        latencyStatEn       <= isValid(latencyReg);
        arrivalStatIdx      <= getStatIdx(zeroExtend(reqCnt));
        arrivalStatEn       <= (cycleCnt == maxBound && !isFirstReq && reqCnt > 0);
        interArrivalStatIdx <= getStatIdx(inter_arr);
        interArrivalStatEn  <= isValid(interArrivalReg);
    endrule

    method Maybe#(Bit#(n_STATS_LOG)) latencyStatInfo();
        let info = (latencyStatEn)? tagged Valid latencyStatIdx : tagged Invalid;
        return info;
    endmethod

    method Maybe#(Tuple2#(Bit#(n_STATS_LOG), STAT_VALUE)) arrivalStatInfo();
        let info = ?;
        if (zeroArrivalStatEn)
        begin
            info = tagged Valid tuple2(0, zeroExtend(zeroArrivalStatValue));
        end
        else if (arrivalStatEn)
        begin
            info = tagged Valid tuple2(arrivalStatIdx, 1);
        end
        else
        begin    
            info = tagged Invalid;
        end
        return info;
    endmethod
    
    method Maybe#(Bit#(n_STATS_LOG)) interArrivalStatInfo();
        let info = (interArrivalStatEn)? tagged Valid interArrivalStatIdx : tagged Invalid;
        return info;
    endmethod
    
    method Maybe#(STAT_VALUE) idleCycleStatInfo();
        let info = (enqEn && !isFirstReq && idleCycleCnt != 0)? tagged Valid zeroExtend(idleCycleCnt) : tagged Invalid;
        return info;
    endmethod
    
    method Bool queueBusy();
        return enqEn || deqEn || queue.notEmpty();
    endmethod

endmodule


//
// mkQueueingStats --
//     Generate queueing delay and arrival rate histogram stats for a given FIFO. 
//
module [CONNECTED_MODULE] mkQueueingStats#(String statTagPrefix,
                                           String statDescPrefix,
                                           Maybe#(Integer) fifoSz, 
                                           Bool enqEn, 
                                           Bool deqEn, 
                                           Bool useBypassFIFO, 
                                           Bool reducedAreaEn)
    // interface:
    ();
        
    DEBUG_FILE debugLog <- mkDebugFile(statTagPrefix + "_stats.out");
    // DEBUG_FILE debugLog <- mkDebugFileNull(""); 

    // Instantiate stats monitor
    QUEUE_STATS monitor <- mkQueueingStatsMonitor(fifoSz, enqEn, deqEn, useBypassFIFO, debugLog);

    // Tracking queueing delay
    STAT_ID latencyStatID = statName(statTagPrefix + "_QUEUEING_DELAY", statDescPrefix + " queueing delay (unit: 4 cycles)");
    STAT_VECTOR#(HISTOGRAM_STATS_NUM) latencySv  <- mkStatCounter_RAM(latencyStatID);
    rule latencyStatsIncr (monitor.latencyStatInfo matches tagged Valid .s);
        latencySv.incr(s);
        debugLog.record($format("latencyStatsIncr: idx=%0d", s));
    endrule

    // Tracking arrival rates
    STAT_ID arrivalStatID = statName(statTagPrefix + "_QUEUE_ARRIVALS", statDescPrefix + " queue arrivals every " + integerToString(valueOf(QUEUEING_STATS_PERIOD)) + " cycles (unit: 1 request)");
    STAT_VECTOR#(HISTOGRAM_STATS_NUM) arrivalSv  <- mkStatCounter_RAM(arrivalStatID);
    rule arrivalStatsIncr (monitor.arrivalStatInfo matches tagged Valid .s);
        arrivalSv.incrBy(tpl_1(s), tpl_2(s));
        debugLog.record($format("arrivalStatsIncr: idx=%0d, incr=%0d", tpl_1(s), tpl_2(s)));
    endrule
    
    if (!reducedAreaEn)
    begin
        // Tracking inter-arrival time
        STAT_ID interArrivalStatID = statName(statTagPrefix + "_QUEUE_INTER_ARRIVAL_TIME", statDescPrefix + " queue inter-arrival time (unit: 2 cycles)");
        STAT_VECTOR#(HISTOGRAM_STATS_NUM) interArrivalSv  <- mkStatCounter_RAM(interArrivalStatID);
        rule interArrivalStatsIncr (monitor.interArrivalStatInfo matches tagged Valid .s);
            interArrivalSv.incr(s);
            debugLog.record($format("interArrivalStatsIncr: idx=%0d", s));
        endrule
        
        // Tracking idle cycles
        STAT_ID idleStatID = statName(statTagPrefix + "_QUEUE_IDLE_TIME", statDescPrefix + " queue idle time");
        STAT idleStat <- mkStatCounter(idleStatID); 
        rule idleStatsIncr (monitor.idleCycleStatInfo matches tagged Valid .s);
            idleStat.incrBy(s);
            debugLog.record($format("idleStatsIncr: incr=%0d", s));
        endrule
        
        // Tracking busy cycles
        STAT_ID busyStatID = statName(statTagPrefix + "_QUEUE_BUSY_TIME", statDescPrefix + " queue busy time");
        STAT busyStat <- mkStatCounter(busyStatID); 
        rule busyStatIncr (monitor.queueBusy);
            busyStat.incr();
        endrule
    end

endmodule

