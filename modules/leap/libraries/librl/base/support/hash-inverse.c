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
// Discover the inverse of a CRC-based hashing function using matrix
// operations.
//

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>



//
// Define the base hash function here.
//

#define nBits 7

void init(uint64_t *vec)
{
    uint64_t mask;
    uint64_t d[nBits], hash[nBits];
    int i;

    mask = 1;
    for (i = 0; i < nBits; i++)
    {
        d[i] = mask;
        mask <<= 1;
    }
    
    hash[0] = d[4] ^ d[0];
    hash[1] = d[5] ^ d[1];
    hash[2] = d[6] ^ d[2];
    hash[3] = d[4] ^ d[3] ^ d[0];
    hash[4] = d[5] ^ d[4] ^ d[1];
    hash[5] = d[6] ^ d[5] ^ d[2];
    hash[6] = d[6] ^ d[3];

    for (i = 0; i < nBits; i++)
    {
        vec[i] = hash[i];
    }
}



void convertToIdentity(uint64_t *vec)
{
    int i, j;
    uint64_t mask_i = 1;
    for (i = 0; i < nBits; i++)
    {
        if ((vec[i] & mask_i) == 0)
        {
            // Must find a 1 later in the matrix and swap
            for (j = i + 1; j < nBits; j++)
            {
                if (vec[j] & mask_i)
                {
                    uint64_t swap;
                    swap = vec[i];
                    vec[i] = vec[j];
                    vec[j] = swap;
                    break;
                }
            }
            if ((vec[i] & mask_i) == 0)
            {
                fprintf(stderr, "Failed to find row to swap, i=%d\n", i);
                exit(1);
            }
        }

        for (j = 0; j < nBits; j++)
        {
            if ((i != j) && (vec[j] & mask_i))
            {
                vec[j] ^= vec[i];
            }
        }

        mask_i <<= 1;
    }
}



//
// Append the identity matrix to the existing one.  The identity matrix will
// be transformed to the inverse hashing matrix.
//
// This code only works for hash sizes up to 32 bits.  The identity matrix
// is stored in the upper 32 bits of 64 bit words.
//
void appendIdentity(uint64_t *vec)
{
    int i;
    uint64_t bit = 1L << 32;
    for (i = 0; i < nBits; i++)
    {
        vec[i] |= bit;
        bit <<= 1;
    }
}


void dumpVec(uint64_t *vec)
{
    printf("Inverse hash (%d):\n", nBits);

    int i, j, n;
    for (i = 0; i < nBits; i++)
    {
        uint64_t mask = (1L << 31);
        n = 0;
        printf("    hash[%d] =", i);
        for (j = 31; j >= 0; j--)
        {
            if ((vec[i] >> 32) & mask)
            {
                if (n != 0)
                {
                    printf(" ^");
                    if ((n % 7) == 0)
                    {
                        printf("\n             ");
                        if (i > 9) printf(" ");
                    }
                }
                printf(" d[%d]", j);
                n += 1;
            }
            mask >>= 1;
        }
        printf(";\n");
    }
}


main()
{
    static uint64_t gVec[nBits];

    init(gVec);
    appendIdentity(gVec);
    convertToIdentity(gVec);

    dumpVec(gVec);
}
