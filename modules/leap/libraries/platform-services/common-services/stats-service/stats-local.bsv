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
import FIFOF::*;
import Vector::*;
import GetPut::*;
import Connectable::*;


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

    // Non-blocking methods are for use by callers involved in I/O
    // where blocking due to activity in the statistics code could cause
    // a deadlock (e.g. the multi-FPGA router).  These routines sacrifice
    // fidelity, dropping increment requests, when necessary.
    method Action incr_NB(Bit#(TMax#(1, TLog#(n_STATS))) idx);
    method Action incrBy_NB(Bit#(TMax#(1, TLog#(n_STATS))) idx, STAT_VALUE amount);
endinterface


// =============================================================================
//
//  Public modules
//
// =============================================================================

typedef TLog#(`STATS_MAX_VECTOR_LEN) STAT_VECTOR_INDEX_SZ;
typedef Bit#(STAT_VECTOR_INDEX_SZ) STAT_VECTOR_INDEX;
typedef Bit#(`STATS_SIZE) STAT_VALUE;
// Marshalled data size on the statistics ring.
typedef Bit#(16) STATS_MAR_CHAIN_DATA;


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
    provisos
        (NumAlias#(TMax#(TLog#(n_STATS), 1), t_STAT_IDX_SZ),
         Add#(t_STAT_IDX_SZ, k, STAT_VECTOR_INDEX_SZ));

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
    provisos
        (NumAlias#(TMax#(TLog#(n_STATS), 1), t_STAT_IDX_SZ),
         Add#(t_STAT_IDX_SZ, k, STAT_VECTOR_INDEX_SZ));

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
    provisos
        (NumAlias#(TMax#(TLog#(n_STATS), 1), t_STAT_IDX_SZ),
         Add#(t_STAT_IDX_SZ, k, STAT_VECTOR_INDEX_SZ));

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
    provisos
        (NumAlias#(TMax#(TLog#(n_STATS), 1), t_STAT_IDX_SZ),
         Add#(t_STAT_IDX_SZ, k, STAT_VECTOR_INDEX_SZ));

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
    STAT_DUMP,
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
        (NumAlias#(TMax#(TLog#(n_STATS), 1), t_STAT_IDX_SZ),
         Alias#(Bit#(t_STAT_IDX_SZ), t_STAT_IDX),
         Add#(t_STAT_IDX_SZ, k, STAT_VECTOR_INDEX_SZ));

    GP_MARSHALLED_CHAIN#(STATS_MAR_CHAIN_DATA, STAT_DATA) chainGP <-
        mkGPMarshalledConnectionChain("StatsRing");
    let chainGet = tpl_1(chainGP).get;
    let chainPut = tpl_2(chainGP).put;

    Vector#(n_STATS, Reg#(Bit#(`STATS_SIZE))) statPool <- replicateM(mkReg(0));
    Vector#(n_STATS,RWire#(STAT_VALUE)) incrWires <- replicateM(mkRWire);

    Reg#(STAT_STATE) state <- mkReg(STAT_RECORDING);
    Reg#(Bool) enabled <- mkReg(False);
    Reg#(Bool) dumpingForOverflow <- mkReg(False);
    Reg#(Bool) overflowDetected <- mkReg(False);

    Reg#(Maybe#(t_STAT_IDX)) curDumpIdx <- mkReg(tagged Invalid);


    //
    // doInit --
    //     Complete initialization.
    //
    rule doInit (state == STAT_INIT);
        chainPut(tagged ST_INIT);
        state <= STAT_RECORDING;
    endrule


    //
    // dump --
    //     Dump one entry in the statistics vector.  The dump shifts all buckets
    //     from the vector one place for each entry dumped to avoid building
    //     a MUX for indexing the curDumpIdx.
    //
    rule dump (curDumpIdx matches tagged Valid .dump_idx &&& state == STAT_DUMP);
        if (statPool[0] != 0)
        begin
            chainPut(tagged ST_VAL { desc: desc,
                                     index: zeroExtend(dump_idx),
                                     value: statPool[0] });
        end

        // Shift all counters down, putting 0 at the top.  This will eventually
        // clear all the counters.
        for (Integer i = 0; i < valueOf(n_STATS) - 1; i = i + 1)
        begin
            statPool[i] <= statPool[i + 1];
        end
        statPool[valueOf(n_STATS) - 1] <= 0;

        // Done emitting all counters?
        if (dump_idx == fromInteger(valueOf(n_STATS) - 1))
        begin
            state <= STAT_FINISHING_DUMP;
            curDumpIdx <= tagged Invalid;
        end
        else
        begin
            curDumpIdx <= tagged Valid (dump_idx + 1);
        end
    endrule


    //
    // finishDump --
    //     Done dumping all entries in the statistics vector.
    //
    rule finishDump (state == STAT_FINISHING_DUMP);
        // Was this a host-initiated dump request?  If yes then forward the
        // command to the next node.
        if (! dumpingForOverflow)
        begin
            chainPut(tagged ST_DUMP);
        end

        dumpingForOverflow <= False;
        overflowDetected <= False;

        state <= STAT_RECORDING;
    endrule


    //
    // receiveCmd --
    //     Receive a command on the statistics ring.
    //
    (* conservative_implicit_conditions *)
    rule receiveCmd (state == STAT_RECORDING);
        STAT_DATA st <- chainGet();

        case (st) matches 
            tagged ST_ENABLE:
            begin
                enabled <= True;
                chainPut(st);
            end

            tagged ST_DISABLE:
            begin
                enabled <= False;
                chainPut(st);
            end

            tagged ST_INIT:
            begin
                // Tell software about this node
                chainPut(tagged ST_INIT_RSP desc);
                state <= STAT_INIT;
            end

            tagged ST_DUMP:
            begin
                curDumpIdx <= tagged Valid 0;
                state <= STAT_DUMP;
            end

            default: chainPut(st);
        endcase
    endrule


    //
    // checkOverflow --
    //     Monitor counters and signal the need to dump counters when there
    //     is danger of overflow.  The increment methods below signal on
    //     the overflow wires when a counter needs to be dumped to software.
    //
    //     The two phase transition from checkOverflow through handleOverflow
    //     is needed to keep the Bluespec scheduler's dependence analysis
    //     from complaining about updates of statPool in the methods below
    //     and internal rules.
    //
    (* fire_when_enabled, no_implicit_conditions *)    
    rule checkOverflow (! overflowDetected && (state == STAT_RECORDING));
        // Check the MSBs of all counters.
        Vector#(n_STATS, Bool) ovfl = newVector();
        for (Integer i = 0; i < valueOf(n_STATS); i = i + 1)
        begin
            ovfl[i] = (msb(statPool[i]) == 1);
        end

        // Trigger overflow state If any MSB is set.
        overflowDetected <= (pack(ovfl) != 0);
    endrule

    (* descending_urgency = "receiveCmd, handleOverflow" *)
    rule handleOverflow (overflowDetected && (state == STAT_RECORDING));
        // Some counter's MSB is set.  Write out all counters.  (Writing
        // out just one counter would require a MUX instead of the shifting
        // scheme used above during dumping.)
        curDumpIdx <= tagged Valid 0;
        dumpingForOverflow <= True;
        state <= STAT_DUMP;
    endrule

    for(Integer i = 0; i < valueof(n_STATS); i = i + 1)
    begin
        rule nbUpdate(incrWires[i].wget matches tagged Valid .value &&& enabled &&& (state == STAT_RECORDING));          
            statPool[i] <= statPool[i] + value;    
        endrule
    end

    method Action incr(t_STAT_IDX idx) if (state == STAT_RECORDING);
        if (enabled)
        begin
            statPool[idx] <= statPool[idx] + 1;
        end
    endmethod


    method Action incrBy(t_STAT_IDX idx, STAT_VALUE amount) if (state == STAT_RECORDING);
        if (enabled)
        begin
            statPool[idx] <= statPool[idx] + amount;
        end
    endmethod

    // We need the RWire indirection here to ensure that these methods can _never_ block
    // this is because STAT_DUMPING state can last an arbitrary amount time, which seems
    // to overwhelm buffers in the multiFPGA routers. 
    method Action incr_NB(t_STAT_IDX idx);
        incrWires[idx].wset(1);      
    endmethod

    method Action incrBy_NB(t_STAT_IDX idx, STAT_VALUE amount);
        incrWires[idx].wset(amount);        
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
        (NumAlias#(TMax#(TLog#(n_STATS), 1), t_STAT_IDX_SZ),
         Alias#(Bit#(t_STAT_IDX_SZ), t_STAT_IDX),
         Add#(t_STAT_IDX_SZ, k, STAT_VECTOR_INDEX_SZ));

    GP_MARSHALLED_CHAIN#(STATS_MAR_CHAIN_DATA, STAT_DATA) chainGP <-
        mkGPMarshalledConnectionChain("StatsRing");
    let chainGet = tpl_1(chainGP).get;
    let chainPut = tpl_2(chainGP).put;

    // Use multi-read interface to guarantee exactly 1 read port (in
    // case the compiler fails to merge all readers down to a single port).
    LUTRAM_MULTI_READ#(1, t_STAT_IDX, STAT_VALUE) statPool <- mkMultiReadLUTRAM(0);

    Reg#(STAT_STATE) state <- mkReg(STAT_RECORDING);
    Reg#(Bool) enabled <- mkReg(False);

    Reg#(t_STAT_IDX) curDumpIdx <- mkRegU();
    
    //
    // Overflow queue passes counter values that grow to large to software.
    // Low bandwidth is ok since passing the value to software will be slow.
    // Use a FIFO1 to reduce buffering.
    //
    // The unguarded FIFO is used to allow for precise scheduling control.
    //
    FIFOF#(Tuple2#(t_STAT_IDX, STAT_VALUE)) overflowQ <- mkUGFIFOF1();


    //
    // doInit --
    //     Complete initialization.
    //
    rule doInit (state == STAT_INIT);
        chainPut(tagged ST_INIT);
        state <= STAT_RECORDING;
    endrule


    //
    // dump --
    //     Done one entry in the statistics vector.
    //
    rule dump (state == STAT_DUMP);
        // Unlike the register vector case above (mkStatCounterVec_Enabled) the
        // value is always sent out in dumps, even when 0.  Here it is because
        // this dump code is only called when requested by software.  In the
        // other case, dump is also triggered by counter overflow, which is
        // more common and worth the logic to reduce I/O.
        chainPut(tagged ST_VAL { desc: desc,
                                 index: zeroExtend(curDumpIdx),
                                 value: statPool.readPorts[0].sub(curDumpIdx) });

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
        chainPut(tagged ST_DUMP);
        state <= STAT_RECORDING;
    endrule


    //
    // updateStat
    //     Increment a stat. Placed in a rule to make the scheduler's life easier.
    //
    Wire#(Tuple2#(t_STAT_IDX, STAT_VALUE)) incrW <- mkWire();
    
    (* fire_when_enabled *)
    rule updateStat (state == STAT_RECORDING && enabled);
        match {.idx, .amount} = incrW;

        STAT_VALUE val = statPool.readPorts[0].sub(idx) + amount;
        if (overflowQ.notFull && (msb(val) == 1))
        begin
            // Counter overflow!  Send the current value to software.
            overflowQ.enq(tuple2(idx, val));
            statPool.upd(idx, 0);
        end
        else
        begin
            // Normal case.  Just increment the counter.
            statPool.upd(idx, val);
        end
    endrule


    //
    // handleOverflow --
    //     Pass counter overflow data to software.
    //
    (* descending_urgency = "handleOverflow, doInit" *)
    (* descending_urgency = "handleOverflow, dump" *)
    (* descending_urgency = "handleOverflow, finishDump" *)
    rule handleOverflow (overflowQ.notEmpty);
        match {.idx, .val} = overflowQ.first();
        overflowQ.deq();
        
        chainPut(tagged ST_VAL { desc: desc,
                                 index: zeroExtend(idx),
                                 value: val });
    endrule


    //
    // receiveCmd --
    //     Receive a command on the statistics ring.
    //
    (* conservative_implicit_conditions *)
    rule receiveCmd ((state == STAT_RECORDING) && ! overflowQ.notEmpty);
        STAT_DATA st <- chainGet();

        case (st) matches 
            tagged ST_ENABLE:
            begin
                enabled <= True;
                chainPut(st);
            end

            tagged ST_DISABLE:
            begin
                enabled <= False;
                chainPut(st);
            end

            tagged ST_INIT:
            begin
                // Tell software about this node
                chainPut(tagged ST_INIT_RSP desc);
                state <= STAT_INIT;
            end

            tagged ST_DUMP:
            begin
                curDumpIdx <= 0;
                state <= STAT_DUMP;
            end

            default: chainPut(st);
        endcase
    endrule


    method Action incr(t_STAT_IDX idx) if ((state == STAT_RECORDING) && overflowQ.notFull);
        incrW <= tuple2(idx, 1);
    endmethod

    method Action incrBy(t_STAT_IDX idx, STAT_VALUE amount) if ((state == STAT_RECORDING) && overflowQ.notFull);
        incrW <= tuple2(idx, amount);
    endmethod

    method Action incr_NB(t_STAT_IDX idx);
        incrW <= tuple2(idx, 1);
    endmethod

    method Action incrBy_NB(t_STAT_IDX idx, STAT_VALUE amount);
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

    method Action incr_NB(Bit#(TMax#(1, TLog#(n_STATS))) idx);
        noAction;
    endmethod

    method Action incrBy_NB(Bit#(TMax#(1, TLog#(n_STATS))) idx, STAT_VALUE amount);
        noAction;
    endmethod
endmodule
