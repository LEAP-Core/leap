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

#include <stdio.h>
#include <unistd.h>
#include <strings.h>
#include <assert.h>
#include <stdlib.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>
#include <iostream>

#include "awb/provides/channelio.h"

using namespace std;

#define LOCK   { pthread_mutex_lock(&lock);   }
#define UNLOCK { pthread_mutex_unlock(&lock); }

// ============================================
//                 Channel I/O                 
// ============================================

// constructor
CHANNELIO_CLASS::CHANNELIO_CLASS(
    PLATFORMS_MODULE p,
    PHYSICAL_DEVICES d) :
        PLATFORMS_MODULE_CLASS(p)
{

}

// destructor
CHANNELIO_CLASS::~CHANNELIO_CLASS()
{
}

// register a station for message delivery
void
CHANNELIO_CLASS::RegisterForDelivery(
    int channel,
    CIO_DELIVERY_STATION module)
{

}

// non-blocking read
UMF_MESSAGE
CHANNELIO_CLASS::TryRead(
    int channel)
{
    fprintf(stderr, "You should not be trying to read this null channelio\n");
    fflush(stderr);
    return NULL;
}

// blocking read
UMF_MESSAGE
CHANNELIO_CLASS::Read(
    int channel)
{
    fprintf(stderr, "You should not be reading this null channelio\n");
    fflush(stderr);
    return NULL;
}

// write

void
CHANNELIO_CLASS::Write(
    int channel,
    UMF_MESSAGE message)
{
  // Drop it on the floor  
    fprintf(stderr, "You should not be writing this null channelio\n");
    fflush(stderr);
}

// poll
void
CHANNELIO_CLASS::Poll()
{ 
    fprintf(stderr, "You should not be writing this null channelio\n");
    fflush(stderr);
}
