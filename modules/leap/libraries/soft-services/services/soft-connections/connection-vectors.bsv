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
// Vectors of send/recv connections used for "chunking" up large message sizes.
// Note that for a shared connection with a station the vector will be 
// transmitted one element at a time. This could be improved because currently
// each element of the vector will take a separate line in the routing table.
// It may be more efficient to build more "packetizing" into the Station and
// thus keep its routing table smaller.
//
module [t_CONTEXT] mkConnectionSendVector#(String portname, Maybe#(STATION) m_station, Bool optional, String origtype)
    // interface:
        (PHYSICAL_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SZ),
         Div#(t_MSG_SZ, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    Vector#(t_NUM_PHYSICAL_CONNS, PHYSICAL_SEND#(Bit#(PHYSICAL_CONNECTION_SIZE))) v = newVector();

    for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
    begin
      v[x] <- mkPhysicalConnectionSend(portname + "_chunk_" + integerToString(x),
                                       m_station,
                                       optional,
                                       origtype,
                                       x == 0);
    end

    method Action send(t_MSG data);

        // This chunking is a bit ugly.
        Bit#(t_MSG_SZ) p = pack(data);
        Bit#(TMul#(t_NUM_PHYSICAL_CONNS, PHYSICAL_CONNECTION_SIZE)) p2 = zeroExtendNP(p);
        Vector#(t_NUM_PHYSICAL_CONNS, Bit#(PHYSICAL_CONNECTION_SIZE)) tmp = unpack(p2);

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          v[x].send(tmp[x]);
        end

    endmethod

    method Bool notFull();

        Bool res = True;
        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          res = res && v[x].notFull();
        end

        return res;

    endmethod

    method Bool dequeued();

        Bool res = True;
        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          res = res && v[x].dequeued();
        end

        return res;

    endmethod

endmodule


module [t_CONTEXT] mkConnectionRecvVector#(String portname, Maybe#(STATION) m_station, Bool optional, String origtype)
    //interface:
        (CONNECTION_RECV#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SZ),
         Div#(t_MSG_SZ, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    Vector#(t_NUM_PHYSICAL_CONNS, CONNECTION_RECV#(Bit#(PHYSICAL_CONNECTION_SIZE))) v = newVector();

    for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
    begin
      v[x] <- mkPhysicalConnectionRecv(portname + "_chunk_" + integerToString(x), m_station, optional, origtype);
    end

    // Reassemble the message.

    method t_MSG receive();

        Vector#(t_NUM_PHYSICAL_CONNS, Bit#(PHYSICAL_CONNECTION_SIZE)) tmp = newVector();

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          tmp[x] = v[x].receive();
        end

        Bit#(TMul#(t_NUM_PHYSICAL_CONNS, PHYSICAL_CONNECTION_SIZE)) p = pack(tmp);
        Bit#(t_MSG_SZ) p2 = truncateNP(p);
        return unpack(p2);

    endmethod

    method Bool notEmpty();
        
        Bool res = True;
        
        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          res = res && v[x].notEmpty();
        end
        
        return res;

    endmethod

    method Action deq();

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          v[x].deq();
        end

    endmethod

endmodule

// Vectors of multicast connections incur additional overhead because of tag duplication.

module [t_CONTEXT] mkConnectionSendMultiVector#(String portname, Maybe#(STATION) m_station, String origtype)
    // interface:
        (PHYSICAL_SEND_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SZ),
         Div#(t_MSG_SZ, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    Vector#(t_NUM_PHYSICAL_CONNS, PHYSICAL_SEND_MULTI#(Bit#(PHYSICAL_CONNECTION_SIZE))) v = newVector();

    for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
    begin
        v[x] <- mkPhysicalConnectionSendMulti(portname + "_chunk_" + integerToString(x),
                                              m_station,
                                              origtype,
                                              x == 0);
    end

    method Action broadcast(t_MSG data);

        // This chunking is a bit ugly.
        Bit#(t_MSG_SZ) p = pack(data);
        Bit#(TMul#(t_NUM_PHYSICAL_CONNS, PHYSICAL_CONNECTION_SIZE)) p2 = zeroExtendNP(p);
        Vector#(t_NUM_PHYSICAL_CONNS, Bit#(PHYSICAL_CONNECTION_SIZE)) tmp = unpack(p2);

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          v[x].broadcast(tmp[x]);
        end

    endmethod

    method Action sendTo(CONNECTION_IDX dst, t_MSG data);

        // This chunking is a bit ugly.
        Bit#(t_MSG_SZ) p = pack(data);
        Bit#(TMul#(t_NUM_PHYSICAL_CONNS, PHYSICAL_CONNECTION_SIZE)) p2 = zeroExtendNP(p);
        Vector#(t_NUM_PHYSICAL_CONNS, Bit#(PHYSICAL_CONNECTION_SIZE)) tmp = unpack(p2);

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          v[x].sendTo(dst, tmp[x]);
        end

    endmethod

    method Bool notFull();

        Bool res = True;
        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          res = res && v[x].notFull();
        end

        return res;

    endmethod

    method Bool dequeued();

        Bool res = True;
        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          res = res && v[x].dequeued();
        end

        return res;

    endmethod


endmodule



module [t_CONTEXT] mkConnectionRecvMultiVector#(String portname, Maybe#(STATION) m_station, String origtype)
    // interface:
        (CONNECTION_RECV_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SZ),
         Div#(t_MSG_SZ, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    Vector#(t_NUM_PHYSICAL_CONNS, CONNECTION_RECV_MULTI#(Bit#(PHYSICAL_CONNECTION_SIZE))) v = newVector();

    for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
    begin
      v[x] <- mkPhysicalConnectionRecvMulti(portname + "_chunk_" + integerToString(x), m_station, origtype);
    end

    // Reassemble the message.

    method Tuple2#(CONNECTION_IDX, t_MSG) receive();

        Vector#(t_NUM_PHYSICAL_CONNS, Bit#(PHYSICAL_CONNECTION_SIZE)) tmp = newVector();

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          tmp[x] = tpl_2(v[x].receive());
        end

        Bit#(TMul#(t_NUM_PHYSICAL_CONNS, PHYSICAL_CONNECTION_SIZE)) p = pack(tmp);
        Bit#(t_MSG_SZ) p2 = truncateNP(p);

        // Note that this just blindly returns the idx from connection zero.
        // It may be useful to add a sanity check that all indices are equal.
        return tuple2(tpl_1(v[0].receive()), unpack(p2));

    endmethod

    method Bool notEmpty();
        
        Bool res = True;
        
        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          res = res && v[x].notEmpty();
        end
        
        return res;

    endmethod

    method Action deq();

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          v[x].deq();
        end

    endmethod

endmodule

module [t_CONTEXT] mkConnectionChainVector#(String portname, String origtype)
    // interface:
        (CONNECTION_CHAIN#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SZ),
         Div#(t_MSG_SZ, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    Vector#(t_NUM_PHYSICAL_CONNS, CONNECTION_CHAIN#(Bit#(PHYSICAL_CONNECTION_SIZE))) v = newVector();

    for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
    begin
      v[x] <- mkPhysicalConnectionChain(portname + "_chunk_" + integerToString(x), origtype);
    end
  
    method t_MSG peekFromPrev();
        Vector#(t_NUM_PHYSICAL_CONNS, Bit#(PHYSICAL_CONNECTION_SIZE)) tmp = newVector();

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          tmp[x] = v[x].peekFromPrev();
        end

        Bit#(TMul#(t_NUM_PHYSICAL_CONNS, PHYSICAL_CONNECTION_SIZE)) p = pack(tmp);
        Bit#(t_MSG_SZ) p2 = truncateNP(p);
        return unpack(p2);

    endmethod

    method Bool recvNotEmpty();
        Bool res = True;

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          res = res && v[x].recvNotEmpty();
        end

        return res;

    endmethod
  
    method Bool sendNotFull;
        Bool res = True;
        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          res = res && v[x].sendNotFull();
        end

        return res;
    endmethod

    method Action sendToNext(t_MSG data);
        Bit#(t_MSG_SZ) p = pack(data);
        Bit#(TMul#(t_NUM_PHYSICAL_CONNS, PHYSICAL_CONNECTION_SIZE)) p2 = zeroExtendNP(p);
        Vector#(t_NUM_PHYSICAL_CONNS, Bit#(PHYSICAL_CONNECTION_SIZE)) tmp = unpack(p2);

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          v[x].sendToNext(tmp[x]);
        end

    endmethod

    method ActionValue#(t_MSG) recvFromPrev();

        Vector#(t_NUM_PHYSICAL_CONNS, Bit#(PHYSICAL_CONNECTION_SIZE)) tmp = newVector();

        for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
        begin
          tmp[x] <- v[x].recvFromPrev();
        end

        Bit#(TMul#(t_NUM_PHYSICAL_CONNS, PHYSICAL_CONNECTION_SIZE)) p = pack(tmp);
        Bit#(t_MSG_SZ) p2 = truncateNP(p);
        return unpack(p2);

    endmethod

endmodule
