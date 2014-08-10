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

import Vector::*;
import FIFOF::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv.bsh"
`include "awb/provides/fpga_components.bsh"

`include "awb/dict/ASSERTIONS.bsh"

// Assertions

// A way to report to the outside world when something has gone wrong.


// ASSERTION_SEVERITY

// The severity of an assertion. This could be used to filter things out.

typedef enum
{
    ASSERT_NONE,
    ASSERT_MESSAGE,
    ASSERT_WARNING,
    ASSERT_ERROR
}
ASSERTION_SEVERITY 
    deriving (Eq, Bits);

instance Ord#(ASSERTION_SEVERITY);
    function Bool \< (ASSERTION_SEVERITY x, ASSERTION_SEVERITY y) = pack(x) < pack(y);
    function Bool \> (ASSERTION_SEVERITY x, ASSERTION_SEVERITY y) = pack(x) > pack(y);
    function Bool \<= (ASSERTION_SEVERITY x, ASSERTION_SEVERITY y) = pack(x) <= pack(y);
    function Bool \>= (ASSERTION_SEVERITY x, ASSERTION_SEVERITY y) = pack(x) >= pack(y);
endinstance




// ============================================================================
//
//  Assertions that trigger only in simulation.
//
// ============================================================================

module [CONNECTED_MODULE] mkAssertionSimOnly#(String str,
                                              ASSERTION_SEVERITY mySeverity)
    // interface:
    (ASSERTION);

    // Check the boolean expression and enqueue a pass/fail.
    function Action assert_function(Bool b);
    action
        // Check the boolean expression
        if (!b && (mySeverity != ASSERT_NONE))
        begin   // Failed. The system is sad. :(
            $display(str);

            if (mySeverity == ASSERT_ERROR)
            begin
                $finish();
            end
        end
    endaction
    endfunction
  
    return assert_function;
endmodule

module [CONNECTED_MODULE] mkAssertionSimOnlyWithMsg#(String str,
                                                     ASSERTION_SEVERITY mySeverity)
    // interface:
    (ASSERTION_WITH_MSG);

    // Check the boolean expression and enqueue a pass/fail.
    function Action assert_function(Bool b, Fmt msg);
    action
        // Check the boolean expression
        if (!b && (mySeverity != ASSERT_NONE))
        begin   // Failed. The system is sad. :(
            $display(str);
            $display(msg);

            if (mySeverity == ASSERT_ERROR)
            begin
                $finish();
            end
        end
    endaction
    endfunction
  
    return assert_function;
endmodule


// ============================================================================
//
//  Assertions that trigger even in synthesized hardware.
//
// ============================================================================

interface ASSERTION_STR_CLIENT;
    method Action raiseAssertion(GLOBAL_STRING_HANDLE str,
                                 ASSERTION_SEVERITY mySeverity);
endinterface

// A way to report to the outside world when something has gone wrong.
typedef function Action checkAssert(Bool b) ASSERTION;

// An assertion with more control simulator control.
typedef function Action checkAssert(Bool b, Fmt msg)
    ASSERTION_WITH_MSG;

//
// mkAssertionStrPvtChecker --
//    Simple wrapper for allocating both a function to check and raise an
//    assertion and the node to connect the checker to the assertions
//    service.
//
//    For checking multiple assertions in the same module, consider
//    mkAssertionStrChecker() below instead.
//
//    Usage:
//        let checker <- mkAssertionStrPvtChecker("error string", ASSERT_ERROR);
//
//        rule r;
//           ...
//           checker(<predicate>);
//           ...
//        endrule
//
module [CONNECTED_MODULE] mkAssertionStrPvtChecker#(String str,
                                                    ASSERTION_SEVERITY mySeverity)
    // interface:
    (ASSERTION);

    let h <- getGlobalStringHandle(str);
    let node <- mkAssertionStrClient();

    // Check the boolean expression and enqueue a pass/fail.
    function Action assert_function(Bool b);
    action
        if (!b) // Check the boolean expression
        begin   // Failed. The system is sad. :(
            node.raiseAssertion(h, mySeverity);
        end
    endaction
    endfunction
  
    return assert_function;
endmodule


//
// mkAssertionStrChecker --
//    Similar to mkAssertionStrChecker, but the caller must provide a port
//    to connect to the assertions service.  The port should be allocated
//    with mkAssertionStrClientVec().
//
module [CONNECTED_MODULE] mkAssertionStrChecker#(String str,
                                                 ASSERTION_SEVERITY mySeverity,
                                                 ASSERTION_STR_CLIENT node)
    // interface:
    (ASSERTION);

    let h <- getGlobalStringHandle(str);

    // Check the boolean expression and enqueue a pass/fail.
    function Action assert_function(Bool b);
    action
        if (!b) // Check the boolean expression
        begin   // Failed. The system is sad. :(
            node.raiseAssertion(h, mySeverity);
        end
    endaction
    endfunction
  
    return assert_function;
endmodule


//
// mkAssertionStrCheckerWithMsg --
//    The same as mkAssertionStrChecker() except that a Fmt string object
//    is passed in.  The assertion will be raised in both simulation and on
//    FPGAs, but the Fmt string will be printed only in simulation.
//
module [CONNECTED_MODULE] mkAssertionStrCheckerWithMsg#(String str,
                                                        ASSERTION_SEVERITY mySeverity,
                                                        ASSERTION_STR_CLIENT node)
    // interface:
    (ASSERTION_WITH_MSG);

    let h <- getGlobalStringHandle(str);

    // Check the boolean expression and enqueue a pass/fail.
    function Action assert_function(Bool b, Fmt msg);
    action
        // Check the boolean expression
        if (!b && (mySeverity != ASSERT_NONE))
        begin   // Failed. The system is sad. :(
            $display(str);
            $display(msg);

            if (mySeverity == ASSERT_ERROR)
            begin
                $finish();
            end

            node.raiseAssertion(h, mySeverity);
        end
    endaction
    endfunction
  
    return assert_function;
endmodule




// Internal datatype for communicating with the assertions controller
typedef struct
{
    GLOBAL_STRING_UID suid;
    ASSERTION_SEVERITY severity;
}
ASSERTION_STR_DATA
    deriving (Eq, Bits);

// Marshalled data on the assertions ring
typedef Bit#(8) ASSERTION_STR_RING_DATA;


//
// mkAssertionStrClientVec --
//   A vector of independent ports into the assertion service from which one
//   or more string-based assertions may be raised.  Separate ports (vector
//   entries) do not conflict in the rule schedule.  Attempts to write the
//   same port from different rules will cause scheduling conflicts.
//
//   The goal is to make the service light weight and it is assumed that
//   the firing of an assertion typically brings down the system.  The
//   internal buffering guarantees that the first firing of an
//   assertion will be delivered.  If multiple assertions fire in the same
//   cycle on different ports only one will be delivered.  Later firings
//   will be deliverd as long as a slot is available in the local buffer.
//   The service does not provide back pressure in order to avoid
//   affecting the schedules of rules that may raise assertions.
//
module [CONNECTED_MODULE] mkAssertionStrClientVec
    // interface:
    (Vector#(n_CLIENTS, ASSERTION_STR_CLIENT));

    // *********** Connections ***********

    // Connection to the assertions controller
    CONNECTION_CHAIN#(ASSERTION_STR_RING_DATA) chain <-
        mkConnectionChain("AssertStrRing");

    // *********** Rules ***********

    MARSHALLER#(ASSERTION_STR_RING_DATA, ASSERTION_STR_DATA) assertQ <-
        mkSimpleMarshaller();
    Vector#(n_CLIENTS, RWire#(ASSERTION_STR_DATA)) assertW <- replicateM(mkRWire());

    //
    // Cycle counter used for printing in simulation.  Will be optimized away
    // in hardware.
    //
    Reg#(Bit#(64)) cycle <- mkReg(0);

    rule countCycle (True);
        cycle <= cycle + 1;
    endrule

    //
    // processLocal --
    //     Send local assertions to the controller.
    //
    rule processLocal (assertQ.notEmpty());
        let a = assertQ.first();
        assertQ.deq();

        chain.sendToNext(a);
    endrule

    //
    // processCmd --
    //     Forward assertions from other nodes to the controller.
    //
    rule processCmd (! assertQ.notEmpty());
        let a <- chain.recvFromPrev();
        chain.sendToNext(a);
    endrule


    //
    // fillAssertQ --
    //     Transfer raised assertion (from wire) to the assertQ if space
    //     is available.  Drop the assertion if no space.  If multiple
    //     assertions fire in the same cycle only one will be raised.
    //
    function Bool assertFired(RWire#(t_WIRE_DATA) w) = isValid(w.wget);

    rule fillAssertQ (find(assertFired, assertW) matches tagged Valid .w);
        assertQ.enq(validValue(w.wget));
    endrule


    //
    // Construct and return a vector of ASSERTION_STR_CLIENT interfaces.
    // Each interface has a method to raise an assertion that can be
    // scheduled independently.
    //

    Vector#(n_CLIENTS, ASSERTION_STR_CLIENT) ifc = newVector();

    for (Integer i = 0; i < valueOf(n_CLIENTS); i = i + 1)
    begin
        ifc[i] =
            interface ASSERTION_STR_CLIENT;
                method Action raiseAssertion(GLOBAL_STRING_HANDLE str,
                                             ASSERTION_SEVERITY mySeverity);
                    assertW[i].wset(ASSERTION_STR_DATA { suid: pack(str),
                                                         severity: mySeverity });

                    String a_type = case (mySeverity)
                                        ASSERT_NONE: "NONE";
                                        ASSERT_MESSAGE: "MESSAGE";
                                        ASSERT_WARNING: "WARNING";
                                        ASSERT_ERROR: "ERROR";
                                    endcase;
                    $display("ASSERTION %s: cycle %0d, %s", a_type, cycle, str.str);
                endmethod
            endinterface;
    end

    return ifc;
endmodule


//
// mkAssertionStrClient --
//   Similar to mkAssertionStrClientVec but allocates a single interface.
//
module [CONNECTED_MODULE] mkAssertionStrClient
    // interface:
    (ASSERTION_STR_CLIENT);

    Vector#(1, ASSERTION_STR_CLIENT) a <- mkAssertionStrClientVec();
    return a[0];
endmodule


// ============================================================================
//
//  Legacy interface, using dictionaries.
//
// ============================================================================

interface ASSERTION_NODE;
    method Action raiseAssertion(ASSERTIONS_DICT_TYPE myID,
                                 ASSERTION_SEVERITY mySeverity);
endinterface


// Vector of severity values for assertions baseID + index
typedef Vector#(`ASSERTIONS_PER_NODE, ASSERTION_SEVERITY) ASSERTION_NODE_VECTOR;


// Internal datatype for communicating with the assertions controller
typedef struct
{
    ASSERTION_NODE_VECTOR assertions;
    ASSERTIONS_DICT_TYPE baseID;
}
ASSERTION_DATA
    deriving (Eq, Bits);


//
// mkAssertionNode --
//     An assertion node is a group of assertions sharing a node on the
//     assertion ring.  Each assertion must be a member of a node in order
//     to pass the assertion to software.  Up to ASSERTIONS_PER_NODE assertions
//     may be allocated for a given node.  These assertions must be numerically
//     related to the node by sharing the same base identifier.  This sharing
//     is managed automatically by the dictionary builder.  An assertion named
//     ASSERTIONS.FOO.BAR in the dictionary gets an ID ASSERTIONS_FOO_BAR and
//     belongs to node ID ASSERTIONS_FOO__BASE.
//
module [CONNECTED_MODULE] mkAssertionNode#(ASSERTIONS_DICT_TYPE baseID)
    // interface:
        (ASSERTION_NODE);

    // *********** Connections ***********

    // Connection to the assertions controller
    CONNECTION_CHAIN#(ASSERTION_DATA) chain <- mkConnectionChain("ASSERTS_DICT");

    // Wires & registers for individual assertions
    Vector#(`ASSERTIONS_PER_NODE, Wire#(ASSERTION_SEVERITY)) raiseWire <- replicateM(mkDWire(ASSERT_NONE));
    Vector#(`ASSERTIONS_PER_NODE, Reg#(ASSERTION_SEVERITY))  raiseReg  <- replicateM(mkReg(ASSERT_NONE));

    // Queue of assertions to raise.  When an assertion gets raised there are
    // 2 cycles of accurate assertion groupings.  If the FIFO fills, assertions
    // are held in a single register until they can be sent out.  Thus 3 firings
    // of an assertion are guaranteed. Beyond that, multiple firings may be
    // merged into a single firing.
    FIFOF#(ASSERTION_NODE_VECTOR) assertQ <- mkGFIFOF(True, False);
    Reg#(ASSERTION_NODE_VECTOR) pendingAsserts <- mkReg(replicate(ASSERT_NONE));

    // *********** Rules ***********

    //
    // Cycle counter used for printing in simulation.  Will be optimized away
    // in hardware.
    //
    Reg#(Bit#(64)) cycle <- mkReg(0);

    rule countCycle (True);
        cycle <= cycle + 1;
    endrule



    function Bool isSet(ASSERTION_SEVERITY a) = (a != ASSERT_NONE);

    //
    // detectLocal --
    //     For each local assertion record whether assertion was raised this
    //     cycle and store it in a register.  The incoming registers used to
    //     feed directly into the raiseLocal rule, but that became a timing
    //     critical path.
    //
    for (Integer e = 0; e < `ASSERTIONS_PER_NODE; e = e + 1)
    begin

        rule detectLocal (True);
            raiseReg[e] <= raiseWire[e];
        endrule

    end

    (* conflict_free = "raiseLocal, processLocal" *)

    //
    // raiseLocal --
    //     Detect assertions raised last cycle (stored in raiseReg vector
    //     by detectLocal rule).  If possible, queue the assertion(s) for delivery
    //     to the assertions controller.  If the queue is full store the
    //     assertion(s) for later delivery.
    //
    rule raiseLocal (True);

        //
        // Merge new assertions this cycle and any pending assertions not yet
        // queued.
        //
        ASSERTION_NODE_VECTOR a = ?;
        for (Integer e = 0; e < `ASSERTIONS_PER_NODE; e = e + 1)
        begin
            a[e] = unpack(pack(raiseReg[e]) | pack(pendingAsserts[e]));
        end
        
        if (any(isSet, a))
        begin
            if (assertQ.notFull())
            begin
                assertQ.enq(a);
                pendingAsserts <= replicate(ASSERT_NONE);
            end
            else
            begin
                pendingAsserts <= a;
            end
        end
        
    endrule


    //
    // processLocal --
    //     Send local assertions to the controller.
    //
    rule processLocal (assertQ.notEmpty());

        let a = assertQ.first();
        assertQ.deq();

        let ast = ASSERTION_DATA { assertions: a, baseID: baseID };
        chain.sendToNext(ast);

    endrule

    //
    // processCmd --
    //     Forward assertions from other nodes to the controller.
    //
    rule processCmd (! assertQ.notEmpty());

        ASSERTION_DATA ast <- chain.recvFromPrev();
        chain.sendToNext(ast);

    endrule


    // *********** Methods ***********

    method Action raiseAssertion(ASSERTIONS_DICT_TYPE myID, ASSERTION_SEVERITY mySeverity);

        raiseWire[myID - baseID] <= mySeverity;

        String a_type = case (mySeverity)
                            ASSERT_NONE: "NONE";
                            ASSERT_MESSAGE: "MESSAGE";
                            ASSERT_WARNING: "WARNING";
                            ASSERT_ERROR: "ERROR";
                        endcase;

        $display("ASSERTION %s: cycle %0d, %s", a_type, cycle, strASSERTIONS_DICT[myID]);

    endmethod

endmodule

            
//
// mkAssertionChecker --
//    Allocate a checker for a single assertion ID, connected to an assertion node.
//
module [CONNECTED_MODULE] mkAssertionChecker#(ASSERTIONS_DICT_TYPE myID, ASSERTION_SEVERITY mySeverity, ASSERTION_NODE myNode)
    // interface:
        (ASSERTION);

    // *********** Methods ***********
  
    // Check the boolean expression and enqueue a pass/fail.
  
    function Action assert_function(Bool b);
    action

        if (!b) // Check the boolean expression
        begin   // Failed. The system is sad. :(
            myNode.raiseAssertion(myID, mySeverity);
        end

    endaction
    endfunction
  
    return assert_function;

endmodule

            
//
// mkAssertionCheckerWithMsg --
//    Allocate a checker for a single assertion ID, connected to an assertion node.
//
module [CONNECTED_MODULE] mkAssertionCheckerWithMsg#(ASSERTIONS_DICT_TYPE myID,
                                                     ASSERTION_SEVERITY mySeverity,
                                                     ASSERTION_NODE myNode)
    // interface:
    (ASSERTION_WITH_MSG);

    // *********** Methods ***********
  
    // Check the boolean expression and enqueue a pass/fail.
    function Action assert_function(Bool b, Fmt msg);
    action
        // Check the boolean expression
        if (!b && (mySeverity != ASSERT_NONE))
        begin   // Failed. The system is sad. :(
            $display(msg);

            myNode.raiseAssertion(myID, mySeverity);
        end
    endaction
    endfunction
  
    return assert_function;

endmodule

module [CONNECTED_MODULE] mkAssertionCheckerError#(ASSERTIONS_DICT_TYPE myID, ASSERTION_NODE myNode)
    // interface:
        (ASSERTION);

    let as <- mkAssertionChecker(myID, ASSERT_ERROR, myNode);
    return as;

endmodule

module [CONNECTED_MODULE] mkAssertionCheckerWarning#(ASSERTIONS_DICT_TYPE myID, ASSERTION_NODE myNode)
    // interface:
        (ASSERTION);

    let as <- mkAssertionChecker(myID, ASSERT_WARNING, myNode);
    return as;

endmodule

module [CONNECTED_MODULE] mkAssertionCheckerMessage#(ASSERTIONS_DICT_TYPE myID, ASSERTION_NODE myNode)
    // interface:
        (ASSERTION);

    let as <- mkAssertionChecker(myID, ASSERT_MESSAGE, myNode);
    return as;

endmodule
