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
// Support for using LFSRs.
//

import LFSR::*;


//
// mkLFSR --
//   Make an LFSR of arbitrary size, up to 39 bits.  The routine automatically
//   picks a polynomial appropriate for the size.
//
module mkLFSR
    // Interface:
    (LFSR#(Bit#(nBITS)));

    let n = valueOf(nBITS);

    Integer feed;
    if (n <= 4)
        feed = 'h9;
    else if (n == 5)
        feed = 'h12;
    else if (n == 6)
        feed = 'h21;
    else if (n == 7)
        feed = 'h41;
    else if (n == 8)
        feed = 'h8E;
    else if (n == 9)
        feed = 'h108;
    else if (n == 10)
        feed = 'h204;
    else if (n == 11)
        feed = 'h402;
    else if (n == 12)
        feed = 'h829;
    else if (n == 13)
        feed = 'h100D;
    else if (n == 14)
        feed = 'h2015;
    else if (n == 15)
        feed = 'h4001;
    else if (n == 16)
        feed = 'h8016;
    else if (n == 17)
        feed = 'h10004;
    else if (n == 18)
        feed = 'h20013;
    else if (n == 19)
        feed = 'h40013;
    else if (n == 20)
        feed = 'h80004;
    else if (n == 21)
        feed = 'h100002;
    else if (n == 22)
        feed = 'h200001;
    else if (n == 23)
        feed = 'h400010;
    else if (n == 24)
        feed = 'h80000D;
    else if (n == 25)
        feed = 'h1000004;
    else if (n == 26)
        feed = 'h2000023;
    else if (n == 27)
        feed = 'h4000013;
    else if (n == 28)
        feed = 'h8000004;
    else if (n == 29)
        feed = 'h10000002;
    else if (n == 30)
        feed = 'h20000029;
    else if (n == 31)
        feed = 'h40000004;
    else if (n == 32)
        feed = 'h80000057;
    else if (n == 33)
        feed = 'h100000029;
    else if (n == 34)
        feed = 'h200000073;
    else if (n == 35)
        feed = 'h400000002;
    else if (n == 36)
        feed = 'h80000003B;
    else if (n == 37)
        feed = 'h100000001F;
    else if (n == 38)
        feed = 'h2000000031;
    else if (n == 39)
        feed = 'h4000000008;
    else if (n != 64)
        error("Unsupported LFSR size");



    if (n == 64)
    begin
        // Special case for 64 bits, composed of 2 32 bit polynomials.
        LFSR#(Bit#(32)) l32a <- mkFeedLFSR(lfsr32FeedPolynomials(1));
        LFSR#(Bit#(32)) l32b <- mkFeedLFSR(lfsr32FeedPolynomials(2));

        method Bit#(nBits) value = truncateNP({ l32a.value, l32b.value });

        method Action next();
            l32a.next();
            l32b.next();
        endmethod

        method Action seed(Bit#(nBits) seedValue);
            l32a.seed(truncateNP(seedValue));
            l32b.seed(truncateNP(seedValue));
        endmethod
    end
    else if (n >= 4)
    begin
        // Simple: instantiate an LFSR at the requested size
        LFSR#(Bit#(nBITS)) lfsr <- mkFeedLFSR(fromInteger(feed));
        return lfsr;
    end
    else
    begin
        //
        // LFSR less than 4 bits requested.  Allocate a 4 bit LFSR and truncate
        // values.
        //
        LFSR#(Bit#(4)) lfsr <- mkFeedLFSR(fromInteger(feed));

        method Bit#(nBITS) value() = truncateNP(lfsr.value());
        method Action next() = lfsr.next();

        // May not make sense for < 4 bit LFSR...
        method Action seed(Bit#(nBITS) seed_value) = lfsr.seed(zeroExtendNP(seed_value));
    end
endmodule


//
// lfsr32FeedPolynomials --
//     Provide a set of optimal polynomials for generating random values using
//     an LFSR.  Each polynomial generates a different sequence.
//
//     These feedback terms were taken from the table at:
//         http://www.ece.cmu.edu/~koopman/lfsr/index.html
//
function Bit#(32) lfsr32FeedPolynomials(Integer n);
        Bit#(32) feed = case (n % 32)
                            0 : return 32'h80000057;
                            1 : return 32'h80000062;
                            2 : return 32'h8000007A;
                            3 : return 32'h80000092;
                            4 : return 32'h800000B9;
                            5 : return 32'h800000BA;
                            6 : return 32'h80000106;
                            7 : return 32'h80000114;
                            8 : return 32'h8000012D;
                            9 : return 32'h8000014E;
                           10 : return 32'h8000016C;
                           11 : return 32'h8000019F;
                           12 : return 32'h800001A6;
                           13 : return 32'h800001F3;
                           14 : return 32'h8000020F;
                           15 : return 32'h800002CC;
                           16 : return 32'h80000349;
                           17 : return 32'h80000370;
                           18 : return 32'h80000375;
                           19 : return 32'h80000392;
                           20 : return 32'h80000398;
                           21 : return 32'h800003BF;
                           22 : return 32'h800003D6;
                           23 : return 32'h800003DF;
                           24 : return 32'h800003E9;
                           25 : return 32'h80000412;
                           26 : return 32'h80000414;
                           27 : return 32'h80000417;
                           28 : return 32'h80000465;
                           29 : return 32'h8000046A;
                           30 : return 32'h80000478;
                           31 : return 32'h800004D4;
                        endcase;

    return feed;
endfunction
