//
// Copyright (c) 2015, Intel Corporation
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
// Direct mapped cache.  This cache is intended to be relatively simple and
// light weight, with fast hit times.
//

// Library imports.

import FIFO::*;
import SpecialFIFOs::*;

// Project foundation imports.

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/fpga_components.bsh"

// RL_MSHR_ENQ - 
//   Struct for containing the information pertaining to 
//   an MSHR enqueue operation.
typedef struct
{
    t_MSHR_INDEX index;
    t_MSHR_TAG   tag;
    t_MSHR_REQ   request;
}
RL_MSHR_ENQ#(type t_MSHR_INDEX, 
             type t_MSHR_TAG,
             type t_MSHR_REQ 
            )
    deriving (Eq, Bits);

// Turn on extra MSHR error checking.  This is disabled by default
// because it adds extra register file ports. 
Bool mshr_debug = True;

//
// MSHR interface.
//
// MSHRs consist of two components: allocation and queue management. This first attmept at an MSHR 
// implementation really only provides queue management.  Here, we provide a set of tagged queues
// each of which may store some number of requests. These queues are folded on top of a shared storage 
// for efficiency. One queue may be written and one queue may be dequeued per cycle.  It is possible to 
// read mutltiple queues in a cycle, though this may incur extra hardware overhead.  
//
interface RL_MSHR#(type t_MSHR_TAG, type t_MSHR_REQ, type t_MSHR_INDEX, numeric type n_ENTRIES);

   // enqMSHR --
   //    Enqueues a value into the index-th MSHR.  If a MSHR is empty, the MSHR tag will also
   //    be updated.  It is the responsibility of the caller to check the status of the 
   //    MSHR before enqueuing.     
   method Action     enqMSHR(t_MSHR_INDEX index, t_MSHR_TAG tag, t_MSHR_REQ request);

   // notEmpty/notFull --
   //    Check the state of the index-th MSHR.  Since the state depends on the value of tag, 
   //    caller must also supply a tag.  For example, a tag mismatch will make the MSHR 'full'.
   method Bool       notEmptyMSHR(t_MSHR_INDEX index, t_MSHR_TAG tag);
   method Bool       notFullMSHR(t_MSHR_INDEX index, t_MSHR_TAG tag);

   // deqMSHR/firstMSHR -- 
   //   Methods for manipulating the head of the index-th MSHR queue. 
   method Action     deqMSHR(t_MSHR_INDEX index);
   method t_MSHR_REQ firstMSHR(t_MSHR_INDEX index);
   method Bit#(TLog#(TAdd#(1, n_ENTRIES))) countMSHR(t_MSHR_INDEX index);

   // dump -- 
   //    A debug method, which dumps the state of the MSHR queues.
   method Action     dump();

endinterface


module mkMSHR#(DEBUG_FILE debugLog) 
    // interface:
    (RL_MSHR#(t_MSHR_TAG, t_MSHR_REQ, t_MSHR_INDEX, n_ENTRIES))
    provisos (Bits#(t_MSHR_TAG, t_MSHR_TAG_SZ),
              Bits#(t_MSHR_REQ, t_MSHR_REQ_SZ),
              Bits#(t_MSHR_INDEX, t_MSHR_INDEX_SZ),
              Eq#(t_MSHR_TAG),
              Bounded#(t_MSHR_INDEX),
              Eq#(t_MSHR_INDEX),  
              Log#(TAdd#(1, n_ENTRIES), TLog#(TAdd#(n_ENTRIES, 1))),
              NumAlias#(TLog#(n_ENTRIES), n_ENTRIES_SZ)
             );

    // Declare state:
    //  | tag | requestsState | requests[0] | requests[1] | ... | requests[n_ENTRIES - 1] |
    //  We have 2 ^ |t_MSHR_INDEX| of these entries, which we manage as independent
    //  fifos, using the  requestsState.

    // Really, these should be folded into a single LUTRAM.  We are not taking advantage of the 
    // multiporting. 
//    Vector#(n_ENTRIES, LUTRAM#(t_MSHR_INDEX, t_MSHR_REQ))             requests       <- replicateM(mkLUTRAMU());
    LUTRAM#(Bit#(TAdd#(n_ENTRIES_SZ, t_MSHR_INDEX_SZ)), t_MSHR_REQ)     requests       <- mkLUTRAMU();
    Vector#(TExp#(t_MSHR_INDEX_SZ), Reg#(FUNC_FIFO_IDX#(n_ENTRIES)))  requestsState  <- replicateM(mkReg(funcFIFO_IDX_Init()));
    LUTRAM#(t_MSHR_INDEX, t_MSHR_TAG)                                 mshrTags       <- mkLUTRAMU();

    RWire#(RL_MSHR_ENQ#(t_MSHR_INDEX, t_MSHR_TAG, t_MSHR_REQ)) mshrEnqW <- mkRWire();
    RWire#(t_MSHR_INDEX)                                       mshrDeqW <- mkRWire();
    
    // We must update the MSHR in the same rule, in the case that we have a conflict 
    // between enq and deq.  In this case, the value we are placing into the queue 
    // must go in the same slot as the one that we are reading out. 
    rule updateMSHR;

        let enqState = ?;
        let requestsStateNext = readVReg(requestsState);
 

        // If I enqueue and dequeue this cycle, I actually need enqIndex - 1.
        if(mshrEnqW.wget matches tagged Valid .enqReq &&& mshrDeqW.wget matches tagged Valid .deqReq &&& 
           deqReq == enqReq.index)
        begin            
            enqState = funcFIFO_IDX_UGdeq(requestsState[pack(deqReq)]);
            debugLog.record($format("MSHR enq/deq idx=0x%x", enqReq.index));
        end
        // enqueue and dequeue are different. Do dequeue 
        else
        begin 
            if(mshrDeqW.wget matches tagged Valid .deqReq)
            begin
                debugLog.record($format("MSHR deq idx=0x%x", deqReq));
                requestsStateNext[pack(deqReq)] = funcFIFO_IDX_UGdeq(requestsState[pack(deqReq)]);      
            end
            
            if(mshrEnqW.wget matches tagged Valid .enqReq) 
            begin
                debugLog.record($format("MSHR enq idx=0x%x", enqReq.index));
                enqState = requestsState[pack(enqReq.index)];
            end

        end

        // Handle the back half of the enqueue.
        if(mshrEnqW.wget matches tagged Valid .enqReq) 
        begin 

            // If this is the first entry, then we allocate the MSHR.
            if(!funcFIFO_IDX_notEmpty(enqState))
            begin               
                debugLog.record($format("MSHR new tag idx=0x%x tag=0x%x", enqReq.index, enqReq.tag));
                mshrTags.upd(enqReq.index, enqReq.tag);
            end

            // Bad news -- we got a new tag, but the previous mshr was not empty.
            else if(mshr_debug)
            begin
                if(mshrTags.sub(enqReq.index) != enqReq.tag)
                begin
                    $display("MSHR attempted to enqueue into busy MSHR without tag match. Tag is %h, new tag is %h", mshrTags.sub(enqReq.index), enqReq.tag);
                    $finish;
                end 
            end

            // is the fifo full? 
            if(!funcFIFO_IDX_notFull(enqState))
            begin
                $display("MSHR attempted to enqueue into full MSHR: mshr %d was full", enqReq.index);
                $finish;
            end

            // Do the actual enqueue.
            match {.s, .dataIdx} = funcFIFO_IDX_UGenq(enqState);
                 
            requests.upd({pack(dataIdx),pack(enqReq.index)}, enqReq.request);
            requestsStateNext[pack(enqReq.index)] = s;
            debugLog.record($format("MSHR enq %d notFull %d notEmpty %d count %d", enqReq.index, 
                                                                               funcFIFO_IDX_notFull(s),
                                                                               funcFIFO_IDX_notEmpty(s),
                                                                               funcFIFO_IDX_numBusySlots(s)));

        end 
 
        writeVReg(requestsState, requestsStateNext);

    endrule   

    // Method interfaces. 
    method Action enqMSHR(t_MSHR_INDEX index, t_MSHR_TAG tag, t_MSHR_REQ request);
        mshrEnqW.wset(RL_MSHR_ENQ{index: index, tag: tag, request: request});
        debugLog.record($format("MSHR enq: idx=0x%x, tag=0x%x, request=0x%x ", index, tag, request));
    endmethod 

    method Bool notEmptyMSHR(t_MSHR_INDEX index, t_MSHR_TAG tag);
        // Is the MSHR being used?  If not, then it is notEmpty. 
        return funcFIFO_IDX_notEmpty(requestsState[pack(index)]);
    endmethod 

    // notFullMSHR is substantially more complicated than notEmpty, since it means 
    // cannot enqueue.   
    method Bool notFullMSHR(t_MSHR_INDEX index, t_MSHR_TAG tag);
        
        Bool returnValue = ?;
        // Is the MSHR being used?  If not, then it is notEmpty. 
        if(!funcFIFO_IDX_notEmpty(requestsState[pack(index)]))
        begin
            returnValue = True;
        end 
        else if(mshrTags.sub(index) == tag)
        begin
            returnValue =  funcFIFO_IDX_notFull(requestsState[pack(index)]);
        end
        // If there was no tag match, we declare this mshr full.
        else 
        begin
            returnValue = False;
        end

        return returnValue;

    endmethod

    method Bit#(TLog#(TAdd#(n_ENTRIES, 1))) countMSHR(t_MSHR_INDEX index);
        return funcFIFO_IDX_numBusySlots(requestsState[pack(index)]);
    endmethod 

    method Action deqMSHR(t_MSHR_INDEX index);
        mshrDeqW.wset(index);
        debugLog.record($format("MSHR deq: idx=0x%x", index));
    endmethod 

    method t_MSHR_REQ firstMSHR(t_MSHR_INDEX index);               
        return requests.sub({pack(funcFIFO_IDX_UGfirst(requestsState[pack(index)])),pack(index)});
    endmethod 

    method Action dump();
        debugLog.record($format("MSHR dump"));
        for( Integer i = 0; i < valueof(TExp#(t_MSHR_INDEX_SZ)); i = i + 1) 
        begin
            debugLog.record($format("MSHR %d notFull %d notEmpty %d count %d", i, 
                                                                               funcFIFO_IDX_notFull(requestsState[i]),
                                                                               funcFIFO_IDX_notEmpty(requestsState[i]),
                                                                               funcFIFO_IDX_numBusySlots(requestsState[i])));
        end
    endmethod
  
endmodule
