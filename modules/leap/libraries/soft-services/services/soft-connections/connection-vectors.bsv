//
// Copyright (C) 2011 Intel Corporation
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

// Vectors of send/recv connections used for "chunking" up large message sizes.
// Note that for a shared connection with a station the vector will be 
// transmitted one element at a time. This could be improved because currently
// each element of the vector will take a separate line in the routing table.
// It may be more efficient to build more "packetizing" into the Station and
// thus keep its routing table smaller.

module [t_CONTEXT] mkConnectionSendVector#(String portname, Maybe#(STATION) m_station, Bool optional, String origtype)
    // interface:
        (CONNECTION_SEND#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SZ),
         Div#(t_MSG_SZ, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    Vector#(t_NUM_PHYSICAL_CONNS, CONNECTION_SEND#(Bit#(PHYSICAL_CONNECTION_SIZE))) v = newVector();

    for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
    begin
      v[x] <- mkPhysicalConnectionSend(portname + "_chunk_" + integerToString(x), m_station, optional, origtype);
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
        (CONNECTION_SEND_MULTI#(t_MSG))
    provisos
        (Bits#(t_MSG, t_MSG_SZ),
         Div#(t_MSG_SZ, PHYSICAL_CONNECTION_SIZE, t_NUM_PHYSICAL_CONNS),
         Context#(t_CONTEXT, LOGICAL_CONNECTION_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

    Vector#(t_NUM_PHYSICAL_CONNS, CONNECTION_SEND_MULTI#(Bit#(PHYSICAL_CONNECTION_SIZE))) v = newVector();

    for (Integer x = 0; x < valueof(t_NUM_PHYSICAL_CONNS); x = x + 1)
    begin
        v[x] <- mkPhysicalConnectionSendMulti(portname + "_chunk_" + integerToString(x), m_station, origtype);
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
