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

// some useful modules
interface MARSHALLER#(numeric type n, type data);
    method Action enq(Vector#(n,data) vec);
    method Action deq();
    method data first();
    method Bool notFull();
    method Bool notEmpty();
endinterface

interface DEMARSHALLER#(numeric type n, type data);
    method Action enq(data dat);
    method Action deq();
    method Vector#(n,data) first();
    method Bool notEmpty();
endinterface

module mkSimpleMarshaller (MARSHALLER#(n,data))
    provisos(Bits#(data, data_sz));

    Reg#(Vector#(n,data)) buffer <- mkRegU();
    Reg#(Bit#(TAdd#(1,TLog#(n)))) count <- mkReg(0);

    method Action enq(Vector#(n,data) vec) if(count == 0);
        count <= fromInteger(valueof(n));
        buffer <= vec; 
    endmethod

    method Action deq() if(count > 0);
        Vector#(1,data) dummy = newVector();
        buffer <= takeTail(append(buffer,dummy));
        count <= count - 1;
    endmethod

    method data first() if(count > 0);
        return buffer[0];
    endmethod

    method Bool notFull();
        return count == 0;
    endmethod

    method Bool notEmpty();
        return count != 0;
    endmethod
endmodule

module mkSimpleDemarshaller (DEMARSHALLER#(n,data))
    provisos(Bits#(data, data_sz));

    Reg#(Vector#(n,data)) buffer <- mkRegU();
    Reg#(Bit#(TAdd#(1,TLog#(n)))) count <- mkReg(0);

    method Action enq(data dat) if(count != fromInteger(valueof(n)));
        Vector#(1,data) highVal = replicate(dat);
        count <= count + 1;
        buffer <= takeTail(append(buffer,highVal));
    endmethod

    method Action deq() if(count == fromInteger(valueof(n)));
        count <= 0;
    endmethod

    method Vector#(n,data) first() if(count == fromInteger(valueof(n)));
       return buffer;
    endmethod

    method Bool notEmpty();
        return count == fromInteger(valueof(n));
    endmethod
endmodule

