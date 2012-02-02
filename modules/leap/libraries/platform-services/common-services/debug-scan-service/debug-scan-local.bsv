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


import List::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv.bsh"

`include "awb/dict/RINGID.bsh"

//
// Debug scan nodes accept any size data to scan out by breaking the data
// into chunks.  The addDebugScanField() module takes a function as input, with
// the expectation that the function will have no predicate and that it will
// have a meaningful value on any cycle.
//


// ========================================================================
//
//   Public interface and modules
//
// ========================================================================

//
// Sets of values to scan are collected in DEBUG_SCAN_FIELD_LISTs by
// adding them with module addDebugScanField.  For example:
//
//    DEBUG_SCAN_FIELD_LIST dbg_list = List::nil;
//    dbg_list <- addDebugScanField(dbg_list, "Read state", readState);
//    dbg_list <- addDebugScanField(dbg_list, "Write state", writeState);
//
// The list of fields must then be attached to a scan node:
//
//    let dbgNode <- mkDebugScanNode("My module's state", dbg_list);
//

interface DEBUG_SCAN_FIELD;
    method String name();
    method Integer size();
    method Bit#(64) value();
    method Bool isMaybe();
endinterface: DEBUG_SCAN_FIELD

typedef List#(DEBUG_SCAN_FIELD) DEBUG_SCAN_FIELD_LIST;

//
// addDebugScanField --
//     Insert a new field name and value into a list of monitored objects.
//
module addDebugScanField#(List#(DEBUG_SCAN_FIELD) curFields, 
                          String fieldName,
                          function t_DEBUG_DATA debugValue())
    // Interface:
    (List#(DEBUG_SCAN_FIELD))
    provisos (Bits#(t_DEBUG_DATA, t_DEBUG_DATA_SZ));

    let f <- mkDebugScanField(fieldName, debugValue, False);
    return List::cons(f, curFields);
endmodule

//
// addDebugScanMaybeField --
//     Insert a new field name and Maybe#(value) into a list of monitored
//     objects.
//
module addDebugScanMaybeField#(List#(DEBUG_SCAN_FIELD) curFields, 
                               String fieldName,
                               function t_DEBUG_DATA debugValue())
    // Interface:
    (List#(DEBUG_SCAN_FIELD))
    provisos (Bits#(t_DEBUG_DATA, t_DEBUG_DATA_SZ));

    let f <- mkDebugScanField(fieldName, debugValue, True);
    return List::cons(f, curFields);
endmodule


//
// mkDebugScanNode --
//     Instantiate a scan node for a set of fields.
//
module [CONNECTED_MODULE] mkDebugScanNode#(String nodeName,
                                           List#(DEBUG_SCAN_FIELD) allFields)
    // Interface:
    (Empty);

    mkDebugScanNodeFromList(nodeName, allFields, debugScanName, True);
endmodule


//
// mkDebugScanRaw --
//     Scan out raw (unformatted) data, printing only a header and numeric data.
//
module [CONNECTED_MODULE] mkDebugScanRaw#(String nodeName,
                                          function t_DEBUG_DATA debugValue())
    // interface:
    (Empty)
    provisos (Bits#(t_DEBUG_DATA, t_DEBUG_DATA_SZ));

    mkDebugScanNodeImpl(debugScanRawName(nodeName), debugValue);    
endmodule


//
// mkDebugScanSoftConnections --
//     Special hook used only by soft connections debugging code to dump
//     the state of a set of soft connections.
//
module [CONNECTED_MODULE] mkDebugScanSoftConnections#(String nodeName,
                                                      List#(DEBUG_SCAN_FIELD) allFields)
    // interface:
    (Empty);

    mkDebugScanNodeFromList(nodeName, allFields, debugScanSoftConnections, False);
endmodule


// ========================================================================
//
//   Internal implementation
//
// ========================================================================

//
// mkDebugScanField --
//     Create a descriptor for a single field in a debug scan record.
//     In order to make lists of these records, the scan field data type
//     is widened to 64 bits.  This is simply an internal artifact.  Hardware
//     will be generated only for the relevant bits.
//
module mkDebugScanField#(String fieldName,
                         function t_DEBUG_DATA debugValue(),
                         Bool isMaybeField)
    // Interface:
    (DEBUG_SCAN_FIELD)
    provisos (Bits#(t_DEBUG_DATA, t_DEBUG_DATA_SZ));
    
    if (valueOf(t_DEBUG_DATA_SZ) > 64)
        error("Debug scan field " + fieldName + " is larger than 64 bits");
    
    method String name = fieldName;
    method Integer size = valueOf(t_DEBUG_DATA_SZ);
    method Bit#(64) value = zeroExtendNP(pack(debugValue));
    method Bool isMaybe = isMaybeField;
endmodule


//
// Formatting of debug scan output is encoded in the string passed to the
// module.  The following functions construct the encoded string.  An
// encoded ID string begins with a name record and, in some cases, is
// followed by descriptions of data fields.
//
// WARNING:  The formatting parser is very simple!  Do not put a ~ in your string!
//

//
// debugScanName --
//     The name of a debug scan record.  The record will be printed as a
//     set of named fields.  Define fields by appending the result of
//     debugScanField to the returned string.
//
function String debugScanName(String name, Integer nEntries);
    return "N:" + name;
endfunction

//
// debugScanFieldName --
//     Describe one field in a debug scan record.  Mutiple fields may be defined
//     by concatenation.  Describe fields starting with the low bits.
//
function String debugScanFieldName(String field, Integer bits);
    return "~" + integerToString(bits) + "~" + field;
endfunction

//
// debugScanMaybeField --
//     Same as a debugScanField, but the value is wrapped by a Maybe#().  Do
//     not include the maybe bit in the size.
//
function String debugScanMaybeField(String field, Integer bits);
    return "~M" + integerToString(bits) + "~" + field;
endfunction


//
// debugScanRawName --
//     A raw heading prints a name for the data and emits the debug scan
//     value as a basic data stream.  No other strings should be appended to
//     the returned string.
//
function String debugScanRawName(String name);
    return "R:" + name;
endfunction


//
// debugScanSoftConnections --
//     Special heading used only by the soft connections state dumping code.
//
function String debugScanSoftConnections(String name, Integer nEntries);
    return "C:" + integerToString(nEntries);
endfunction



typedef 8 DEBUG_SCAN_VALUE_SZ;
typedef Bit#(DEBUG_SCAN_VALUE_SZ) DEBUG_SCAN_VALUE;

typedef union tagged
{
    void             DS_DUMP;
    DEBUG_SCAN_VALUE DS_VAL;        // One marshalled chunk (sent low to high)
    DEBUG_SCAN_VALUE DS_VAL_LAST;   // Last chunk of a value
}
DEBUG_SCAN_DATA
    deriving (Eq, Bits);


typedef enum
{
    DS_IDLE,
    DS_DUMPING
}
DEBUG_SCAN_STATE
    deriving (Eq, Bits);


//
// mkDebugScanNodeFromList --
//     Instantiate a scan node for a set of fields.  The format of the
//     fields depends on the genNodeName function, passed from one
//     of the public interface modules above.
//
module [CONNECTED_MODULE] mkDebugScanNodeFromList#(
        String nodeName,
        List#(DEBUG_SCAN_FIELD) allFields,
        function String genNodeName(String name, Integer nEntries),
        Bool emitFieldNames)
    // Interface:
    (Empty)
    provisos (NumAlias#(512, n_MAX_SIZE));

    // Reverse the fields list so that the first field printed is the first
    // field declared.
    List#(DEBUG_SCAN_FIELD) fields = List::reverse(allFields);

    String dbg_desc = "";
    Bit#(n_MAX_SIZE) dbg_data = 0;

    //
    // Bluespec doesn't provide a way to dynamically size the type of an object.
    // Instead, we will map the relevant portions of each field into a bit
    // vector and pick the optimal vector size using conditional logic.
    //
    // Input fields are mapped to the bit vector tedeously, bit by bit.  The
    // code looks bad but the resulting Verilog is fine.
    //

    // Loop over all fields
    Integer b = 0;
    Integer n_fields = 0;
    while (fields matches tagged Nil ? False : True)
    begin
        let fld = List::head(fields);

        // Is there room for the entire new field in the bit vector?
        if (b + fld.size > valueOf(n_MAX_SIZE))
        begin
            // No space!  Generate a debug node with the current state
            // and begin another one for the remainder.
            dbg_desc = genNodeName(nodeName, n_fields) + dbg_desc;
            mkDebugScanNodeImpl(dbg_desc, dbg_data);

            dbg_desc = "";
            dbg_data = 0;
            b = 0;
            n_fields = 0;
        end

        // Add the field details to the descriptor record
        if (emitFieldNames)
        begin
            dbg_desc = dbg_desc +
                       (! fld.isMaybe ? debugScanFieldName(fld.name, fld.size) :
                                        debugScanMaybeField(fld.name, fld.size - 1));
        end

        // Map input field to the scan output bit vector
        for (Integer i = 0; i < fld.size; i = i + 1)
        begin
            dbg_data[b] = fld.value[i];
            b = b + 1;
        end

        n_fields = n_fields + 1;
        fields = List::tail(fields);
    end

    dbg_desc = genNodeName(nodeName, n_fields) + dbg_desc;

    //
    // Pick a reasonable output buffer size.  Ugly!
    //
    if (b == 0) begin end
    else if (b <= 1)  begin Bit#(1)  d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 2)  begin Bit#(2)  d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 3)  begin Bit#(3)  d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 4)  begin Bit#(4)  d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 5)  begin Bit#(5)  d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 6)  begin Bit#(6)  d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 7)  begin Bit#(7)  d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 8)  begin Bit#(8)  d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 9)  begin Bit#(9)  d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 10) begin Bit#(10) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 11) begin Bit#(11) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 12) begin Bit#(12) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 13) begin Bit#(13) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 14) begin Bit#(14) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 15) begin Bit#(15) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 16) begin Bit#(16) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 17) begin Bit#(17) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 18) begin Bit#(18) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 19) begin Bit#(19) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 20) begin Bit#(20) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 21) begin Bit#(21) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 22) begin Bit#(22) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 23) begin Bit#(23) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 24) begin Bit#(24) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 25) begin Bit#(25) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 26) begin Bit#(26) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 27) begin Bit#(27) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 28) begin Bit#(28) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 29) begin Bit#(29) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 30) begin Bit#(30) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 31) begin Bit#(31) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 32) begin Bit#(32) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 34) begin Bit#(34) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 36) begin Bit#(36) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 38) begin Bit#(38) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 40) begin Bit#(40) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 42) begin Bit#(42) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 44) begin Bit#(44) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 46) begin Bit#(46) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 48) begin Bit#(48) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 50) begin Bit#(50) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 52) begin Bit#(52) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 54) begin Bit#(54) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 56) begin Bit#(56) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 58) begin Bit#(58) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 60) begin Bit#(60) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 62) begin Bit#(62) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 64) begin Bit#(64) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 68) begin Bit#(68) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 72) begin Bit#(72) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 76) begin Bit#(76) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 80) begin Bit#(80) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 84) begin Bit#(84) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 88) begin Bit#(88) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 92) begin Bit#(92) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 96) begin Bit#(96) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 100) begin Bit#(100) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 104) begin Bit#(104) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 108) begin Bit#(108) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 112) begin Bit#(112) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 116) begin Bit#(116) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 120) begin Bit#(120) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 124) begin Bit#(124) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 128) begin Bit#(128) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 136) begin Bit#(136) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 144) begin Bit#(144) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 152) begin Bit#(152) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 160) begin Bit#(160) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 168) begin Bit#(168) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 176) begin Bit#(176) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 184) begin Bit#(184) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 192) begin Bit#(192) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 200) begin Bit#(200) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 208) begin Bit#(208) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 216) begin Bit#(216) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 224) begin Bit#(224) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 232) begin Bit#(232) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 240) begin Bit#(240) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 248) begin Bit#(248) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 256) begin Bit#(256) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 272) begin Bit#(272) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 288) begin Bit#(288) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 304) begin Bit#(304) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 320) begin Bit#(320) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 336) begin Bit#(336) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 352) begin Bit#(352) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 368) begin Bit#(368) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 384) begin Bit#(384) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 400) begin Bit#(400) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 416) begin Bit#(416) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 432) begin Bit#(432) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 448) begin Bit#(448) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 464) begin Bit#(464) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 480) begin Bit#(480) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else if (b <= 496) begin Bit#(496) d = truncate(dbg_data); mkDebugScanNodeImpl(dbg_desc, d); end
    else mkDebugScanNodeImpl(dbg_desc, dbg_data);
endmodule


//
// mkDebugScanNodeImpl --
//
//   Scan out the data coming in on wire debugValue.  To avoid deadlocks
//   during scan the value should have no predicates.
//
//   Construct the "myID" argument using the functions above.
// 
module [CONNECTED_MODULE] mkDebugScanNodeImpl#(String myID,
                                               function t_DEBUG_DATA debugValue())
    // interface:
    (Empty)
    provisos (Bits#(t_DEBUG_DATA, t_DEBUG_DATA_SZ));

    Connection_Chain#(DEBUG_SCAN_DATA) chain <- mkConnection_Chain(`RINGID_DEBUG_SCAN);

    Reg#(DEBUG_SCAN_STATE) state <- mkReg(DS_IDLE);

    let id <- getGlobalStringUID(myID);

    // Marshall the debug data to the message size.
    MARSHALLER#(DEBUG_SCAN_VALUE,
                Tuple2#(t_DEBUG_DATA, GLOBAL_STRING_UID)) mar <- mkSimpleMarshaller();

    //
    // sendDumpData --
    //     Forward dump data and token around the ring.
    //
    rule sendDumpData (state == DS_DUMPING);
        if (mar.notEmpty)
        begin
            // More data remains for this node
            if (! mar.isLast())
                chain.sendToNext(tagged DS_VAL mar.first());
            else
                chain.sendToNext(tagged DS_VAL_LAST mar.first());

            mar.deq();
        end
        else
        begin
            // Done with this node's data
            chain.sendToNext(tagged DS_DUMP);
            state <= DS_IDLE;
        end
    endrule


    //
    // receiveCmd --
    //     Receive a command on the ring.
    //
    (* conservative_implicit_conditions *)
    rule receiveCmd (state == DS_IDLE);
        let ds <- chain.recvFromPrev();

        case (ds) matches 
            tagged DS_DUMP:
            begin
                mar.enq(tuple2(debugValue, id));
                state <= DS_DUMPING;
            end

            default: chain.sendToNext(ds);
        endcase
    endrule
endmodule
