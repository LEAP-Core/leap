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

import Vector::*;
import List::*;

//The interface of a module with Connections
interface WITH_CONNECTIONS#(parameter numeric type t_NUM_IN,
                            parameter numeric type t_NUM_OUT,
                            parameter numeric type t_NUM_IN_MULTI,
                            parameter numeric type t_NUM_OUT_MULTI,
                            parameter numeric type t_NUM_CHAINS);

  interface Vector#(t_NUM_IN, PHYSICAL_CONNECTION_IN)  incoming;
  interface Vector#(t_NUM_OUT, PHYSICAL_CONNECTION_OUT) outgoing;
  interface Vector#(t_NUM_IN_MULTI, PHYSICAL_CONNECTION_IN_MULTI)  incomingMultis;
  interface Vector#(t_NUM_OUT_MULTI, PHYSICAL_CONNECTION_OUT_MULTI) outgoingMultis;

  interface Vector#(t_NUM_CHAINS, PHYSICAL_CHAIN) chains;

endinterface

// Backwards compatability:
typedef WITH_CONNECTIONS#(nI, nO, 0, 0, nC) WithConnections#(parameter numeric type nI, parameter numeric type nO, parameter numeric type nC);


