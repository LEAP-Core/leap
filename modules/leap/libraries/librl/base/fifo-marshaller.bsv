//
// Copyright (C) 2011 Massachusetts Institute of Technology
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

import Vector::*;
import GetPut::*;

//
// Marshallers stream wide data (t_DATA) over a narrow stream (t_FIFO_DATA).
// Demarshallers transform the narrow data stream back to the original width.
//

interface MARSHALLER#(type t_FIFO_DATA, type t_DATA);
    method Action enq(t_DATA inData);
    method Action deq();
    method t_FIFO_DATA first();
    method Bool notFull();
    method Bool notEmpty();
    method Bool isLast();     // Last chunk from the original enqueued data
endinterface

interface DEMARSHALLER#(type t_FIFO_DATA, type t_DATA);
    method Action enq(t_FIFO_DATA fifoData);
    method Action deq();
    method t_DATA first();
    method Bool notFull();
    method Bool notEmpty();
endinterface


// Length (chunks) of a marshalled message
typedef TDiv#(t_DATA_SZ, t_FIFO_DATA_SZ)
    MARSHALLER_MSG_LEN#(numeric type t_FIFO_DATA_SZ, numeric type t_DATA_SZ);


// some typeclass/conversion definitions

instance ToPut#(DEMARSHALLER#(fifo_type, data_type), fifo_type);
    function Put#(fifo_type) toPut(DEMARSHALLER#(fifo_type, data_type) demarshaller);
        Put#(fifo_type) f = interface Put#(fifo_type);
                                method Action put(fifo_type data);
                                    demarshaller.enq(data);
                                endmethod
                            endinterface;
        return f;
    endfunction
endinstance

instance ToGet#(DEMARSHALLER#(fifo_type, data_type), data_type);
    function Get#(data_type) toGet(DEMARSHALLER#(fifo_type, data_type) demarshaller);
        Get#(data_type) f = interface Get#(data_type);
                                 method ActionValue#(data_type) get();
                                     demarshaller.deq;
                                     return demarshaller.first;
                                 endmethod
                             endinterface;
        return f;
    endfunction
endinstance

instance ToPut#(MARSHALLER#(fifo_type, data_type), data_type);
    function Put#(data_type) toPut(MARSHALLER#(fifo_type, data_type) marshaller);
        Put#(data_type) f = interface Put#(data_type);
                                method Action put(data_type data);
                                    marshaller.enq(data);
                                endmethod
                            endinterface;
        return f;
    endfunction
endinstance

instance ToGet#(MARSHALLER#(fifo_type, data_type), fifo_type);
    function Get#(fifo_type) toGet(MARSHALLER#(fifo_type, data_type) marshaller);
        Get#(fifo_type) f = interface Get#(fifo_type);
                                method ActionValue#(fifo_type) get();
                                    marshaller.deq;
                                    return marshaller.first;
                                endmethod
                            endinterface;
        return f;
    endfunction
endinstance




//
// mkSimpleMarshaller --
//     Transmit t_DATA in a stream of smaller, t_FIFO_DATA, messages.
//     Send the low chunk first.
//
module mkSimpleMarshaller
    // Interface:
        (MARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    let m <- mkSimpleMarshallerImpl(True);
    return m;

endmodule


//
// mkSimpleMarshallerHighToLow --
//     Transmit t_DATA in a stream of smaller, t_FIFO_DATA, messages.
//     Send the high chunk first.
//
module mkSimpleMarshallerHighToLow
    // Interface:
        (MARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    let m <- mkSimpleMarshallerImpl(False);
    return m;

endmodule


module mkSimpleMarshallerImpl#(Bool lowFirst)
    // Interface:
        (MARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA_SZ, t_DATA_SZ)));

    Reg#(Vector#(n, t_FIFO_DATA)) buffer <- mkRegU();
    Reg#(Bit#(TAdd#(1, TLog#(n)))) count <- mkReg(0);
    Reg#(Bool) empty <- mkReg(True);

    method Action enq(t_DATA inData) if (empty);
        empty <= False;
        count <= fromInteger(valueof(n));
        // Convert the message to a vector of the marshalled size.
        buffer <= toChunks(inData);
    endmethod

    method Action deq() if (! empty);
        t_FIFO_DATA dummy = ?;

        if (lowFirst)
            buffer <= shiftInAtN(buffer, dummy);
        else
            buffer <= shiftInAt0(buffer, dummy);

        empty <= (count == 1);
        count <= count - 1;
    endmethod

    method t_FIFO_DATA first() if (! empty);
        return buffer[lowFirst ? 0 : valueOf(n) - 1];
    endmethod

    method Bool notFull();
        return empty;
    endmethod

    method Bool notEmpty();
        return ! empty;
    endmethod

    method Bool isLast();
        return count == 1;
    endmethod
endmodule


module mkSimpleDemarshaller
    // Interface:
        (DEMARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA_SZ, t_DATA_SZ)));

    Reg#(Vector#(n, t_FIFO_DATA)) buffer <- mkRegU();
    Reg#(Bit#(TLog#(n))) count <- mkReg(0);
    Reg#(Bool) full <- mkReg(False);

    method Action enq(t_FIFO_DATA dat) if (! full);
        buffer <= shiftInAtN(buffer, dat);
        full <= (count == fromInteger(valueof(TSub#(n, 1))));
        count <= count + 1;
    endmethod

    method Action deq() if (full);
        full <= False;
        count <= 0;
    endmethod

    method t_DATA first() if (full);
        // Return an entire demarshalled message.
        return unpack(truncateNP(pack(buffer)));
    endmethod

    method Bool notFull();
        return ! full;
    endmethod

    method Bool notEmpty();
        return full;
    endmethod
endmodule
