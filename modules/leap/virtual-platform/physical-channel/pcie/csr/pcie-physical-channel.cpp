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

#include "awb/provides/physical_channel.h"

using namespace std;

// ==============================================
//            WARNING WARNING WARNING
// This code is swarming with potential deadlocks
// ==============================================

// ============================================
//               Physical Channel              
// ============================================

// constructor: set up hardware partition
PHYSICAL_CHANNEL_CLASS::PHYSICAL_CHANNEL_CLASS(
    PLATFORMS_MODULE p,
    PHYSICAL_DEVICES d) :
        PLATFORMS_MODULE_CLASS(p)
{
    // cache links to useful physical devices
    pciExpressDevice = d->GetPCIExpressDevice();

    // initialize pointers
    f2hHead      = CSR_F2H_BUF_START;
    f2hTailCache = CSR_F2H_BUF_START;
    h2fHeadCache = CSR_H2F_BUF_START;
    h2fTail      = CSR_H2F_BUF_START;

    pthread_mutex_init(&channelLock, NULL);
}

// destructor
PHYSICAL_CHANNEL_CLASS::~PHYSICAL_CHANNEL_CLASS()
{
}

void
PHYSICAL_CHANNEL_CLASS::Init()
{
    pciExpressDevice->Init();

    CSR_DATA data;
    do
    {
        // other initialization
        iid = 0;

        // give green signal to FPGA
        pciExpressDevice->WriteSystemCSR(genIID() | (OP_START << 16));

        // wait for green signal from FPGA
        UINT32 trips = 0;
        do
        {
            data = pciExpressDevice->ReadSystemCSR();
            trips = trips + 1;
        }
        while ((data != SIGNAL_GREEN) && (trips < 1000000));

        if (data != SIGNAL_GREEN)
        {
            // Gave up on green.  Reset again and restart the sequence.
            pciExpressDevice->ResetFPGA();
        }
    }
    while (data != SIGNAL_GREEN);

    // update pointers
    pciExpressDevice->WriteSystemCSR(genIID() | (OP_UPDATE_F2HHEAD << 16) | (f2hHead << 8));
    pciExpressDevice->WriteSystemCSR(genIID() | (OP_UPDATE_H2FTAIL << 16) | (h2fTail << 8));
}

// blocking read
UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::Read()
{
    // blocking loop
    pthread_mutex_lock(&channelLock);
    while (true)
    {
        // check if message is ready
        if (incomingMessage && !incomingMessage->CanAppend())
        {
            // message is ready!
            UMF_MESSAGE msg = incomingMessage;
            incomingMessage = NULL;
            pthread_mutex_unlock(&channelLock);
            return msg;
        }

        // if CSRs are empty, then poll pointers till some data is available
        while (f2hHead == f2hTailCache)
        {
            f2hTailCache = pciExpressDevice->ReadCommonCSR(CSR_F2H_TAIL);
        }

        // read some data from CSRs
        readCSR();
    }

    // shouldn't be here
    return NULL;
}

// non-blocking read
UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::TryRead()
{
    pthread_mutex_lock(&channelLock);

    // if CSRs are empty, then poll pointers (OPTIONAL)
    if (f2hHead == f2hTailCache)
    {
        f2hTailCache = pciExpressDevice->ReadCommonCSR(CSR_F2H_TAIL);
    }

    // now attempt read 
    readCSR();

    // now see if we have a complete message
    if (incomingMessage && !incomingMessage->CanAppend())
    {
        UMF_MESSAGE msg = incomingMessage;
        incomingMessage = NULL;
        pthread_mutex_unlock(&channelLock);
        return msg;
    }

    // message not yet ready
    pthread_mutex_unlock(&channelLock);
    return NULL;
}

// write
void
PHYSICAL_CHANNEL_CLASS::Write(
    UMF_MESSAGE message)
{
    pthread_mutex_lock(&channelLock);

    // block until buffer has sufficient space
    CSR_INDEX h2fTailPlusOne = (h2fTail == CSR_H2F_BUF_END) ? CSR_H2F_BUF_START : (h2fTail + 1);
    while (h2fTailPlusOne == h2fHeadCache)
    {
        h2fHeadCache = pciExpressDevice->ReadCommonCSR(CSR_H2F_HEAD);
    }

    // construct header
    UMF_CHUNK header = message->EncodeHeader();
    CSR_DATA csr_data = CSR_DATA(header);

    // write header to physical channel
    pciExpressDevice->WriteCommonCSR(h2fTail, csr_data);
    h2fTail = h2fTailPlusOne;
    h2fTailPlusOne = (h2fTail == CSR_H2F_BUF_END) ? CSR_H2F_BUF_START : (h2fTail + 1);

    // write message data to physical channel
    // NOTE: hardware demarshaller expects chunk pattern to start from most
    //       significant chunk and end at least significant chunk, so we will
    //       send chunks in reverse order
    message->StartReverseExtract();
    while (message->CanReverseExtract())
    {
        // this gets ugly - we need to block until space is available
        while (h2fTailPlusOne == h2fHeadCache)
        {
            h2fHeadCache = pciExpressDevice->ReadCommonCSR(CSR_H2F_HEAD);
        }

        // space is available, write
        UMF_CHUNK chunk = message->ReverseExtractChunk();
        csr_data = CSR_DATA(chunk);

        pciExpressDevice->WriteCommonCSR(h2fTail, csr_data);
        h2fTail = h2fTailPlusOne;
        h2fTailPlusOne = (h2fTail == CSR_H2F_BUF_END) ? CSR_H2F_BUF_START : (h2fTail + 1);
    }

    // sync h2fTail pointer. It is OPTIONAL to do this immediately, but we will do it
    // since this is probably the response to a request the hardware might be blocked on
    pciExpressDevice->WriteSystemCSR(genIID() | (OP_UPDATE_H2FTAIL << 16) | (h2fTail << 8));

    pthread_mutex_unlock(&channelLock);

    // de-allocate message
    delete message;
}

// read one CSR's worth of unread data
void
PHYSICAL_CHANNEL_CLASS::readCSR()
{
    UMF_CHUNK chunk;
    CSR_DATA csr_data;

    // check cached pointers to see if we can actually read anything
    if (f2hHead == f2hTailCache)
    {
        return;
    }

    // read in one CSR
    csr_data = pciExpressDevice->ReadCommonCSR(f2hHead);
    chunk = UMF_CHUNK(csr_data);

    // update head pointer
    f2hHead = (f2hHead == CSR_F2H_BUF_END) ? CSR_F2H_BUF_START : (f2hHead + 1);

    // sync head pointer (OPTIONAL)
    pciExpressDevice->WriteSystemCSR(genIID() | (OP_UPDATE_F2HHEAD << 16) | (f2hHead << 8));

    // determine if we are starting a new message
    if (incomingMessage == NULL)
    {
        // new message
        incomingMessage = new UMF_MESSAGE_CLASS;
        incomingMessage->DecodeHeader(chunk);
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
        incomingMessage->AppendChunk(chunk);
    }
}

// generate a new Instruction ID
CSR_DATA
PHYSICAL_CHANNEL_CLASS::genIID()
{
    assert(sizeof(CSR_DATA) >= 4);
    iid = (iid + 1) % 256;
    return (iid << 24);
}
