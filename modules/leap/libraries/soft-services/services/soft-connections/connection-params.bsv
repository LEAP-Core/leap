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

import DefaultValue::*;

//
// Parameters for soft connections.
//

typedef struct
{
    // Error if no match found?
    Bool optional;

    // Number of entries in internal buffer.  May be 0 but this violates
    // the LI property that a channel has at least one buffer slot.  Clients
    // are most likely to request no slots when a FIFO feeds directly into a
    // connection.  Even when 0 the compiler may insert buffers, as the
    // channel remains latency insensitive.  Buffer insertion is most likely
    // for off-chip connections.
    Integer nBufferSlots;

    // Experimental feature to simulate latency in a channel.
    Bool enableLatency;

    // Guard physical sends?  If the user asks for a guard we add it here.
    // Currently all our implementations ask for the guard. However a
    // "power user" can get unguarded connection.
    Bool guarded;

    Bool enableDebug;
}
CONNECTION_SEND_PARAM;

instance DefaultValue#(CONNECTION_SEND_PARAM);
    defaultValue = CONNECTION_SEND_PARAM {
        optional: False,
        nBufferSlots: `CON_BUFFERING,
        enableLatency: (`CON_LATENCY_ENABLE > 0),
        guarded: True,
        enableDebug: True };
endinstance


typedef struct
{
    // Error if no match found?
    Bool optional;

    // Guard physical receiver?  If the user asks for a guard we add it here.
    // Currently all our implementations ask for the guard. However a
    // "power user" can get unguarded connection.
    Bool guarded;

    // Only senders have buffers in the current implementation.  Hence the
    // lack of buffer control options.
}
CONNECTION_RECV_PARAM;

instance DefaultValue#(CONNECTION_RECV_PARAM);
    defaultValue = CONNECTION_RECV_PARAM {
        optional: False,
        guarded: True };
endinstance


//
// Service connection network type
//
typedef enum
{
   // Non token ring
   CONNECTION_NON_TOKEN_RING,
   // Token ring
   CONNECTION_TOKEN_RING,
   // Compiler generated network
   CONNECTION_COMPILER_GEN
}
CONNECTION_SERVICE_NETWORK_TYPE
    deriving (Bits, Eq);

typedef struct
{
    // Network type
    CONNECTION_SERVICE_NETWORK_TYPE networkType;
}
CONNECTION_SERVICE_PARAM;

instance DefaultValue#(CONNECTION_SERVICE_PARAM);
    defaultValue = CONNECTION_SERVICE_PARAM 
    {
        networkType: CONNECTION_NON_TOKEN_RING
    };
endinstance


