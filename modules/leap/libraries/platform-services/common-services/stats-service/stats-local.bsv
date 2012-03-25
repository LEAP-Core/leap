//
// Copyright (C) 2008 Massachusetts Institute of Technology
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

import FIFO::*;
import Counter::*;
import Vector::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv.bsh"
`include "awb/provides/physical_platform_utils.bsh"
`include "awb/provides/fpga_components.bsh"


// =============================================================================
//
//  Statistics naming
//
// =============================================================================

//
// Statistics are named with a string identifier designed to be easy to parse
// and a descriptive string.
//
// NOTES ON STRING VALUES:
//
//   - The string identifier is, by convention, all upper case, no spaces,
//     with words separated by underscores, e.g.:
//          L1_DCACHE_READ_HIT
//
//   - Tilde (~) is used as a string delimeter and may not appear in either
//     string.
//
//

typedef struct
{
    String id;
    String desc;
}
STAT_ID;

function STAT_ID statName(String id, String desc);
    return STAT_ID { id: id, desc: desc };
endfunction


// =============================================================================
//
//  Interfaces
//
// =============================================================================

//
// Node with single statistic
//
interface STAT;
    method Action incr();

    // Be careful with this method.  Incrementing by values too close to
    // the `STATS_SIZE bit counter can cause data to be lost if the counter
    // rises faster than it can be dumped to the host.
    method Action incrBy(STAT_VALUE amount);
endinterface: STAT

//
// Node with multiple statistics, either an array statistic with a single
// name and multiple buckets or a collection of many single-entry stats.
// The size of the iid argument guarantees it is never 0 bits, which is
// useful for multiplexed HAsim timing models where the CPU index is similarly
// defined.
//
interface STAT_VECTOR#(type n_STATS);
    method Action incr(Bit#(TMax#(1, TLog#(n_STATS))) idx);

    // Be careful with this method.  Incrementing by values too close to
    // the `STATS_SIZE bit counter can cause data to be lost if the counter
    // rises faster than it can be dumped to the host.
    method Action incrBy(Bit#(TMax#(1, TLog#(n_STATS))) idx, STAT_VALUE amount);
endinterface


// =============================================================================
//
//  Public modules
//
// =============================================================================

typedef 12 STAT_VECTOR_INDEX_SZ;
typedef Bit#(STAT_VECTOR_INDEX_SZ) STAT_VECTOR_INDEX;
typedef Bit#(`STATS_SIZE) STAT_VALUE;

//
// mkStatCounter --
//     Public module for the STAT single statistic interface.  Implement it
//     using the code for the vector interface.
//
module [CONNECTED_MODULE] mkStatCounter#(STAT_ID statID)
    // interface:
    (STAT);

    STAT_ID ids[1] = { statID };
    STAT_VECTOR#(1) m <- mkStatCounter_Vector(ids);
    
    method Action incr() = m.incr(0);
    method Action incrBy(STAT_VALUE amount) = m.incrBy(0, amount);
endmodule

//
// mkStatCounterDistributed --
//     Public module for the STAT single statistic interface.  In this case,
//     the software is expected to combine multiple counters sharing a
//     single statID into an array.  The arrayIdx values must be unique
//     for a given statID.
//
module [CONNECTED_MODULE] mkStatCounterDistributed#(STAT_ID statID,
                                                    Integer arrayIdx)
    // interface:
    (STAT);

    STAT_ID ids[1] = { statID };
    STAT_VECTOR#(1) m <- mkStatCounterDistributed_Vector(ids, arrayIdx);
    
    method Action incr() = m.incr(0);
    method Action incrBy(STAT_VALUE amount) = m.incrBy(0, amount);
endmodule


//
// mkStatCounter_MultiEntry --
//     Public module for the STAT_VECTOR with multiple instances of a single
//     IDs interface.  This is most likely used to store separate counters
//     for the same statistic across multiple instances.
//
//     *** This version is optimized for updating multiple entries in
//     *** the same cycle.  Each entry's counter is stored in a separate
//     *** register.  If only one entry will be updated in a cycle, consider
//     *** mkStatCounter_RAM below.
//
module [CONNECTED_MODULE] mkStatCounter_MultiEntry#(STAT_ID statID)
    // interface:
    (STAT_VECTOR#(n_STATS))
    provisos (Add#(TLog#(n_STATS), k, STAT_VECTOR_INDEX_SZ));

    let desc <- getGlobalStringUID("M" + integerToString(valueOf(n_STATS)) + "~" +
                                   statID.id + "~" + statID.desc);

    let m <- (`STATS_ENABLED) ? mkStatCounterVec_Enabled(desc) :
                                mkStatCounterVec_Disabled();
    return m;
endmodule


//
// mkStatCounter_RAM --
//     Similar to mkStatCounter_MultiEntry, but the counters are stored in
//     a dense RAM instead of individual registers.  This implementation
//     only allows one counter to be updated per cycle.  In exchange, the
//     storage is more efficient.
//
module [CONNECTED_MODULE] mkStatCounter_RAM#(STAT_ID statID)
    // interface:
    (STAT_VECTOR#(n_STATS))
    provisos (Add#(TLog#(n_STATS), k, STAT_VECTOR_INDEX_SZ));

    let desc <- getGlobalStringUID("M" + integerToString(valueOf(n_STATS)) + "~" +
                                   statID.id + "~" + statID.desc);

    let m <- (`STATS_ENABLED) ? mkStatCounterRAM_Enabled(desc) :
                                mkStatCounterVec_Disabled();
    return m;
endmodule


//
// mkStatCounter_Vector --
//     Public module for the STAT_VECTOR multiple instance IDs interface.
//
module [CONNECTED_MODULE] mkStatCounter_Vector#(STAT_ID myIDs[])
    // interface:
    (STAT_VECTOR#(n_STATS))
    provisos (Add#(TLog#(n_STATS), k, STAT_VECTOR_INDEX_SZ));

    String d = "V" + integerToString(valueOf(n_STATS));
    for (Integer i = 0; i < valueOf(n_STATS); i = i + 1)
    begin
        d = d + "~" + myIDs[i].id + "~" + myIDs[i].desc;
    end

    let desc <- getGlobalStringUID(d);

    let m <- (`STATS_ENABLED) ? mkStatCounterVec_Enabled(desc) :
                                mkStatCounterVec_Disabled();
    return m;
endmodule


//
// mkStatCounterDistributed_Vector --
//     Same as mkStatCounter_Vector, but the counters for an array of
//     values are distributed across more than one statistics node.
//     Multiple of these will be created in the hardware sharing a
//     dictionary ID with unique arrayIdx values.  The software will
//     combine dictionary IDs from separate counters into arrays.
//
//     Don't be too confused by the two vectors here.  The "vector"
//     is the collection of multiple, independent dictionary IDs in
//     a single statistics ring stop.  The "array" is the combination of
//     counters from independent ring stops into a logical array in
//     software.
//
module [CONNECTED_MODULE] mkStatCounterDistributed_Vector#(STAT_ID myIDs[],
                                                           Integer arrayIdx)
    // interface:
    (STAT_VECTOR#(n_STATS))
    provisos (Add#(TLog#(n_STATS), k, STAT_VECTOR_INDEX_SZ));

    String d = "D" + integerToString(valueOf(n_STATS)) +
               "~" + integerToString(arrayIdx);
    for (Integer i = 0; i < valueOf(n_STATS); i = i + 1)
    begin
        d = d + "~" + myIDs[i].id + "~" + myIDs[i].desc;
    end

    let desc <- getGlobalStringUID(d);

    let m <- (`STATS_ENABLED) ? mkStatCounterVec_Enabled(desc) :
                                mkStatCounterVec_Disabled();
    return m;
endmodule


// ========================================================================
//
//  Implementation -- internal modules.
//
// ========================================================================

typedef union tagged
{
    // Commands issued by host
    void ST_ENABLE;
    void ST_DISABLE;
    void ST_INIT;
    void ST_DUMP;

    // Responses from FPGA

    // Normal value response
    struct {
        GLOBAL_STRING_UID desc;       // Node's descriptor
        STAT_VECTOR_INDEX index;      // Statistic index within this node
        STAT_VALUE value;             // Current accumulator's value
    } ST_VAL;

    // Initialization response.  The descriptor encodes all the details of
    // the node.
    GLOBAL_STRING_UID ST_INIT_RSP;
}
STAT_DATA
    deriving (Eq, Bits);

typedef enum
{
    STAT_INIT,
    STAT_RECORDING,
    STAT_DUMPING,
    STAT_FINISHING_DUMP
}
STAT_STATE
    deriving (Eq, Bits);


//
// mkStatCounterVec_Enabled --
//     Vector of statistics counters.  Multiple statistics counters may
//     be updated in a single FPGA cycle.
//
//
module [CONNECTED_MODULE] mkStatCounterVec_Enabled#(GLOBAL_STRING_UID desc)
    // interface:
    (STAT_VECTOR#(n_STATS))
    provisos
        (Add#(TLog#(n_STATS), k, STAT_VECTOR_INDEX_SZ));

    CONNECTION_CHAIN#(STAT_DATA) chain <- mkConnectionChain("StatsRing");

    Vector#(n_STATS, COUNTER#(`STATS_SIZE)) statPool <- replicateM(mkLCounter(0));

    Reg#(STAT_STATE) state <- mkReg(STAT_RECORDING);
    Reg#(Bool) enabled <- mkReg(False);

    Reg#(STAT_VECTOR_INDEX) curDumpIdx <- mkRegU();


    //
    // doInit --
    //     Complete initialization.
    //
    rule doInit (state == STAT_INIT);
        chain.sendToNext(tagged ST_INIT);
        state <= STAT_RECORDING;
    endrule


    //
    // dump --
    //     Done one entry in the statistics vector.
    //
    rule dump (state == STAT_DUMPING);
        chain.sendToNext(tagged ST_VAL { desc: desc,
                                         index: curDumpIdx,
                                         value: statPool[curDumpIdx].value() });

        statPool[curDumpIdx].setC(0);

        if (curDumpIdx == fromInteger(valueOf(n_STATS) - 1))
            state <= STAT_FINISHING_DUMP;

        curDumpIdx <= curDumpIdx + 1;
    endrule


    //
    // finishDump --
    //     Done dumping all entries in the statistics vector.
    //
    rule finishDump (state == STAT_FINISHING_DUMP);
        chain.sendToNext(tagged ST_DUMP);
        state <= STAT_RECORDING;
    endrule


    //
    // receiveCmd --
    //     Receive a command on the statistics ring.
    //
    (* conservative_implicit_conditions *)
    rule receiveCmd (state == STAT_RECORDING);
        STAT_DATA st <- chain.recvFromPrev();

        case (st) matches 
            tagged ST_ENABLE:
            begin
                enabled <= True;
                chain.sendToNext(st);
            end

            tagged ST_DISABLE:
            begin
                enabled <= False;
                chain.sendToNext(st);
            end

            tagged ST_INIT:
            begin
                // Tell software about this node
                chain.sendToNext(tagged ST_INIT_RSP desc);
                state <= STAT_INIT;
            end

            tagged ST_DUMP:
            begin
                curDumpIdx <= 0;
                state <= STAT_DUMPING;
            end

            default: chain.sendToNext(st);
        endcase
    endrule


    //
    // dumpPartial --
    //     Monitor counters and forward values to software before a counter
    //     overflows.
    //
    Reg#(STAT_VECTOR_INDEX) curDumpPartialIdx <- mkReg(0);

    (* descending_urgency = "receiveCmd, dumpPartial" *)
    rule dumpPartial (state == STAT_RECORDING);
        // Is the most significant bit set?
        if (msb(statPool[curDumpPartialIdx].value()) == 1)
        begin
            chain.sendToNext(tagged ST_VAL { desc: desc,
                                             index: curDumpPartialIdx,
                                             value: statPool[curDumpPartialIdx].value() });

            statPool[curDumpPartialIdx].setC(0);
        end

        if (curDumpPartialIdx == fromInteger(valueOf(n_STATS) - 1))
            curDumpPartialIdx <= 0;
        else
            curDumpPartialIdx <= curDumpPartialIdx + 1;
    endrule


    method Action incr(Bit#(TMax#(1, TLog#(n_STATS))) idx);
        if (enabled)
        begin
            statPool[idx].up();
        end
    endmethod


    method Action incrBy(Bit#(TMax#(1, TLog#(n_STATS))) idx, STAT_VALUE amount);
        if (enabled)
        begin
            statPool[idx].upBy(amount);
        end
    endmethod
endmodule


//
// mkStatCounterRAM_Enabled --
//     Vector of statistics counters.  Unlike mkStatCounterVec_Enabled above,
//     only one statistics counter may be updated in a single FPGA cycle.
//     This constraint allows the counters to be stored in RAM instead
//     of registers.
//
module [CONNECTED_MODULE] mkStatCounterRAM_Enabled#(GLOBAL_STRING_UID desc)
    // interface:
    (STAT_VECTOR#(n_STATS))
    provisos
        (Alias#(Bit#(TMax#(TLog#(n_STATS), 1)), t_STAT_IDX),
         Add#(TLog#(n_STATS), k, STAT_VECTOR_INDEX_SZ));

    CONNECTION_CHAIN#(STAT_DATA) chain <- mkConnectionChain("StatsRing");

    LUTRAM#(t_STAT_IDX, STAT_VALUE) statPool <- mkLUTRAM(0);

    Reg#(STAT_STATE) state <- mkReg(STAT_RECORDING);
    Reg#(Bool) enabled <- mkReg(False);

    Reg#(t_STAT_IDX) curDumpIdx <- mkRegU();
    
    Wire#(Tuple2#(t_STAT_IDX, STAT_VALUE)) incrW <- mkWire();


    //
    // doInit --
    //     Complete initialization.
    //
    rule doInit (state == STAT_INIT);
        chain.sendToNext(tagged ST_INIT);
        state <= STAT_RECORDING;
    endrule


    //
    // dump --
    //     Done one entry in the statistics vector.
    //
    rule dump (state == STAT_DUMPING);
    
        chain.sendToNext(tagged ST_VAL { desc: desc,
                                         index: zeroExtendNP(curDumpIdx),
                                         value: statPool.sub(curDumpIdx) });

        statPool.upd(curDumpIdx, 0);

        if (curDumpIdx == fromInteger(valueOf(n_STATS) - 1))
            state <= STAT_FINISHING_DUMP;

        curDumpIdx <= curDumpIdx + 1;
    endrule


    //
    // finishDump --
    //     Done dumping all entries in the statistics vector.
    //
    rule finishDump (state == STAT_FINISHING_DUMP);
        chain.sendToNext(tagged ST_DUMP);
        state <= STAT_RECORDING;
    endrule


    //
    // updateStat
    //     Increment a stat. Placed in a rule to make the scheduler's life easier.
    
    (* fire_when_enabled *)
    rule updateStat (state == STAT_RECORDING && enabled);
        match {.idx, .amount} = incrW;
        let c = statPool.sub(idx);
        statPool.upd(idx, c + amount);
    endrule


    //
    // receiveCmd --
    //     Receive a command on the statistics ring.
    //
    (* conservative_implicit_conditions *)
    rule receiveCmd (state == STAT_RECORDING);
        STAT_DATA st <- chain.recvFromPrev();

        case (st) matches 
            tagged ST_ENABLE:
            begin
                enabled <= True;
                chain.sendToNext(st);
            end

            tagged ST_DISABLE:
            begin
                enabled <= False;
                chain.sendToNext(st);
            end

            tagged ST_INIT:
            begin
                // Tell software about this node
                chain.sendToNext(tagged ST_INIT_RSP desc);
                state <= STAT_INIT;
            end

            tagged ST_DUMP:
            begin
                curDumpIdx <= 0;
                state <= STAT_DUMPING;
            end

            default: chain.sendToNext(st);
        endcase
    endrule


    //
    // dumpPartial --
    //     Monitor counters and forward values to software before a counter
    //     overflows.
    //
    Reg#(t_STAT_IDX) curDumpPartialIdx <- mkReg(0);

    (* descending_urgency = "updateStat, receiveCmd, dumpPartial" *)
    rule dumpPartial (state == STAT_RECORDING);
    
        let stat = statPool.sub(curDumpPartialIdx);

        // Is the most significant bit set?
        if (msb(stat) == 1)
        begin
            chain.sendToNext(tagged ST_VAL { desc: desc,
                                             index: zeroExtendNP(curDumpPartialIdx),
                                             value: stat });

            statPool.upd(curDumpPartialIdx, 0);
        end

        if (curDumpPartialIdx == fromInteger(valueOf(n_STATS) - 1))
            curDumpPartialIdx <= 0;
        else
            curDumpPartialIdx <= curDumpPartialIdx + 1;
    endrule


    method Action incr(t_STAT_IDX idx);
        incrW <= tuple2(idx, 1);
    endmethod


    method Action incrBy(t_STAT_IDX idx, STAT_VALUE amount);
        incrW <= tuple2(idx, amount);
    endmethod

endmodule


module [CONNECTED_MODULE] mkStatCounterVec_Disabled
    // interface:
    (STAT_VECTOR#(n_STATS));

    method Action incr(Bit#(TMax#(1, TLog#(n_STATS))) idx);
        noAction;
    endmethod

    method Action incrBy(Bit#(TMax#(1, TLog#(n_STATS))) idx, STAT_VALUE amount);
        noAction;
    endmethod
endmodule
