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

`include "awb/provides/shared_scratchpad_memory_common.bsh"

// ========================================================================
//
// Uncached shared scratchpad common definitions. 
//
// ========================================================================

typedef struct
{
    SHARED_SCRATCH_CLIENT_META  clientMeta;
    RL_CACHE_GLOBAL_READ_META   globalReadMeta;
}
SHARED_SCRATCH_UNCACHED_READ_REQ_INFO
    deriving (Eq, Bits);

typedef struct
{
    t_DATA                       data;
}
SHARED_SCRATCH_UNCACHED_WRITE_REQ_INFO#(type t_DATA)
    deriving (Eq, Bits);

typedef union tagged 
{
    SHARED_SCRATCH_UNCACHED_READ_REQ_INFO            SHARED_SCRATCH_READ;
    SHARED_SCRATCH_UNCACHED_WRITE_REQ_INFO#(t_DATA)  SHARED_SCRATCH_WRITE;
}
SHARED_SCRATCH_UNCACHED_REQ_INFO#(type t_DATA)
    deriving (Eq, Bits);

typedef struct
{
    SHARED_SCRATCH_PORT_NUM                   requester;
    t_ADDR                                    addr;
    SHARED_SCRATCH_UNCACHED_REQ_INFO#(t_DATA) reqInfo;
}
SHARED_SCRATCH_UNCACHED_REQ#(type t_ADDR,
                             type t_DATA)
    deriving (Eq, Bits);

typedef struct
{
    t_DATA                      val;
    SHARED_SCRATCH_CLIENT_META  clientMeta;
    RL_CACHE_GLOBAL_READ_META   globalReadMeta;
}
SHARED_SCRATCH_UNCACHED_READ_RESP#(type t_DATA)
    deriving (Eq, Bits);

typedef union tagged 
{
    SHARED_SCRATCH_UNCACHED_READ_RESP#(t_DATA)  UNCACHED_READ_RESP;
    void                                        UNCACHED_WRITE_ACK;
}
SHARED_SCRATCH_UNCACHED_RESP#(type t_DATA)
    deriving (Eq, Bits);

typedef struct
{
    SHARED_SCRATCH_CTRLR_PORT_NUM                reqControllerId;
    SHARED_SCRATCH_UNCACHED_REQ#(t_ADDR, t_DATA) reqLocal;
}
SHARED_SCRATCH_CONTROLLERS_UNCACHED_REQ#(type t_ADDR,
                                         type t_DATA)
    deriving (Eq, Bits);

typedef struct
{
    SHARED_SCRATCH_PORT_NUM               clientId;
    SHARED_SCRATCH_UNCACHED_RESP#(t_DATA) resp;
}
SHARED_SCRATCH_CONTROLLERS_UNCACHED_RESP#(type t_DATA)
    deriving (Eq, Bits);
    
