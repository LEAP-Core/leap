//
// Copyright (C) 2014 Intel Corporation
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


//
// CRCGEN --
//   Compute one round of CRC, consuming a chunk and updating the remainder.
//
interface CRCGEN#(numeric type t_REM_SZ, type t_CHUNK);
    method Bit#(t_REM_SZ) nextChunk(Bit#(t_REM_SZ) curCRC, t_CHUNK chunk);
endinterface


//
// Note that standard generators are defined at the end.
//


//
// mkCRCGen --
//   A CRC generator, with each round consuming one t_CHUNK and generating
//   a CRC of size t_REM_SZ.
//
//   The polynomial requested must correspond to the remainder size t_REM_SZ!
//   The polynomial bit order is the "normal" bit order, e.g. from the
//   table in http://en.wikipedia.org/wiki/Cyclic_redundancy_check.
//   For example, the polynomial for CRC-8-CCITT (ATM HEC) is 8'h7.
//
module mkCRCGen#(Bit#(t_REM_SZ) poly)
    // Interface:
    (CRCGEN#(t_REM_SZ, t_CHUNK))
    provisos (Bits#(t_CHUNK, t_CHUNK_SZ),
              // The chunk size must be >= the remainder size.
              Add#(t_REM_SZ, n_OFFSET, t_CHUNK_SZ));

    //
    // One step of the CRC.  Inject a single bit (bitIn) into the remainder.
    //
    function Bit#(t_REM_SZ) oneStep(Bit#(1) bitIn, Bit#(t_REM_SZ) rem);
        let multiple = ((bitIn ^ msb(rem)) == 1 ? poly : 0);
        return (rem << 1) ^ multiple;
    endfunction

    //
    // Pre-compute the bit masks that will turn the oneStep() above into a
    // simple set of XORs at run time.  This is accomplished by iterating
    // and generating the CRC with only a single bit set at each of the
    // input chunk positions.
    //
    Vector#(t_CHUNK_SZ, Vector#(t_REM_SZ, Bit#(1))) chunk_bit_masks = newVector();
    for (Integer c = 0; c < valueOf(t_CHUNK_SZ); c = c + 1)
    begin
        // Set only bit "c" in a chunk
        Vector#(t_CHUNK_SZ, Bit#(1)) bits_in = replicate(0);
        bits_in[c] = 1;

        // Compute the CRC of a chunk with just bit "c" set.
        chunk_bit_masks[c] = unpack(foldr(oneStep, 0, bits_in));
    end

    // The previous step computes an array indexed by chunks, with sub-arrays
    // of bit positions in the computed remainder.  What we really need is
    // an outer array indexed by bit position in the remainder.  For each
    // remainder bit we need a vector of bits in a chunk that are active
    // in the given remainder's bit position.  This is just the transposition
    // of chunk_bit_masks.
    Vector#(t_REM_SZ, Vector#(t_CHUNK_SZ, Bit#(1))) rem_bit_masks =
        transpose(chunk_bit_masks);

    //
    // Update CRC given curCRC and a new chunk.
    //
    method Bit#(t_REM_SZ) nextChunk(Bit#(t_REM_SZ) curCRC, t_CHUNK chunk);
        // Map curCRC and chunk to vectors of bits
        Vector#(t_CHUNK_SZ, Bit#(1)) chunk_bits = unpack(pack(chunk));
        Vector#(t_REM_SZ, Bit#(1)) curCRC_bits = unpack(pack(curCRC));

        //
        // The static steps during module construction have built rem_bit_masks,
        // a table of bit positions in "chunk" that must be XORed for each
        // resulting remainder bit position.
        //
        Bit#(t_REM_SZ) r = 0;
        for (Integer b = 0; b < valueOf(t_REM_SZ); b = b + 1)
        begin
            // Mask the bits relevant to remainder bit "b" by ANDing the
            // incoming chunk's bits with rem_bit_masks[b].
            let masked_chunk = map(uncurry(\& ), zip(chunk_bits, rem_bit_masks[b]));
            // XOR those relevant chunk bits, forming remainder bit "b".
            r[b] = foldr(\^ , 0, masked_chunk);

            // Include the existing (incoming) curCRC by performing the same
            // steps on it, and XORing into remainder bit "b".  The mask
            // is taken from the high bits of the same rem_bit_masks as the
            // previous step.
            let masked_cur_crc = map(uncurry(\& ),
                                     zip(curCRC_bits, takeTail(rem_bit_masks[b])));
            r[b] = foldr(\^ , r[b], masked_cur_crc);
        end

        return r;
    endmethod
endmodule


//
// mkCRCGen8 --
//   CRC-8-CCITT (ATM HEC).  Arbitrary chunk size.
//
module mkCRCGen8
    // Interface:
    (CRCGEN#(8, t_CHUNK))
    provisos (Bits#(t_CHUNK, t_CHUNK_SZ),
              Add#(8, n_OFFSET, t_CHUNK_SZ));

    let _c <- mkCRCGen(8'h7);
    return _c;
endmodule
