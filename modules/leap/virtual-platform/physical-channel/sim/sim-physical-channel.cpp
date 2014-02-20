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
#include "tbb/concurrent_queue.h"

#include "awb/provides/physical_channel.h"


using namespace std;

// ============================================
//               Physical Channel              
// ============================================

// constructor
SIM_PHYSICAL_CHANNEL_CLASS::SIM_PHYSICAL_CHANNEL_CLASS(
    PLATFORMS_MODULE     p
    ) :
    PHYSICAL_CHANNEL_CLASS(p),
    writeQ(),
    uninitialized(),
    unixPipeDevice((PLATFORMS_MODULE) (PHYSICAL_CHANNEL) this)
    
{
    incomingMessage = NULL;
    umfFactory = new UMF_FACTORY_CLASS(); //Use a default umf factory, but allow an external device to set it later...

    uninitialized = 0;

    // Start up write thread
    void ** writerArgs = NULL;
    writerArgs = (void**) malloc(2*sizeof(void*));
    writerArgs[0] = &unixPipeDevice;
    writerArgs[1] = this;
    if (pthread_create(&writerThread,
		       NULL,
		       WriterThread,
		       writerArgs))
    {
        perror("pthread_create, outToFPGA0Thread:");
        exit(1);
    }
}

// destructor
SIM_PHYSICAL_CHANNEL_CLASS::~SIM_PHYSICAL_CHANNEL_CLASS()
{
    Uninit();
}

void SIM_PHYSICAL_CHANNEL_CLASS::Uninit()
{
    if (!uninitialized.fetch_and_store(1))
    {
        // Tear down writer thread
        writeQ.push(NULL); 
        pthread_join(writerThread, NULL);
    }
}

// blocking read
UMF_MESSAGE
SIM_PHYSICAL_CHANNEL_CLASS::Read()
{
    // blocking loop
    while (true)
    {
        // check if message is ready
        if (incomingMessage && !incomingMessage->CanAppend())
        {
            // message is ready!
            UMF_MESSAGE msg = incomingMessage;
            incomingMessage = NULL;
            return msg;
        }

        // block-read data from pipe
        readPipe();
    }

    // shouldn't be here
    return NULL;
}

// non-blocking read
UMF_MESSAGE
SIM_PHYSICAL_CHANNEL_CLASS::TryRead()
{

    // if there's fresh data on the pipe, update
    if (unixPipeDevice.Probe())
    {
        readPipe();
    }

    // now see if we have a complete message
    if (incomingMessage && !incomingMessage->CanAppend())
    {
        UMF_MESSAGE msg = incomingMessage;
        incomingMessage = NULL;
        return msg;
    }

    // message not yet ready
    return NULL;
}

// write
void
SIM_PHYSICAL_CHANNEL_CLASS::Write(
    UMF_MESSAGE message)
{
    writeQ.push(message);
}

// read un-processed data on the pipe
void
SIM_PHYSICAL_CHANNEL_CLASS::readPipe()
{
    // determine if we are starting a new message
    if (incomingMessage == NULL)
    {
        // new message: read header
        unsigned char header[UMF_CHUNK_BYTES];

        unixPipeDevice.Read(header, UMF_CHUNK_BYTES);

        // create a new message
        incomingMessage = umfFactory->createUMFMessage();
        incomingMessage->DecodeHeader(header);
    }
    else if (!incomingMessage->CanAppend())
    {
        // uh-oh.. we already have a full message, but it hasn't been
        // asked for yet. We will simply not read the pipe, but in
        // future, we might want to include a read buffer.
    }
    else
    {
        // read in some more bytes for the current message
        unsigned char buf[BLOCK_SIZE];
        int bytes_requested = BLOCK_SIZE;

        if (incomingMessage->BytesUnwritten() < BLOCK_SIZE)
        {
            bytes_requested = incomingMessage->BytesUnwritten();
        }

        unixPipeDevice.Read(buf, bytes_requested);

        // append read bytes into message
        incomingMessage->AppendBytes(bytes_requested, buf);
    }
}
