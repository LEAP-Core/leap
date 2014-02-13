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

#include <iostream>

#include "awb/provides/rrr.h"
#include "awb/provides/model.h" // FIXME should be project

#define CHANNEL_ID  1

using namespace std;

// global link
RRR_CLIENT RRRClient;

// Hooks for the local client to re-direct to the global handler. 

UMF_MESSAGE RRR_CLIENT_STUB_CLASS::MakeRequest(UMF_MESSAGE msg)
{
    return RRRClient->MakeRequest(msg);
}

void RRR_CLIENT_STUB_CLASS::MakeRequestNoResponse(UMF_MESSAGE msg)
{
    RRRClient->MakeRequestNoResponse(msg);
}

// constructor
RRR_CLIENT_CLASS::RRR_CLIENT_CLASS(
    PLATFORMS_MODULE p,
    CHANNELIO    cio) :
        PLATFORMS_MODULE_CLASS(p),
        initialized (0)
{
    // set channelio link
    channelio = cio;

    // set up locks and CVs
    pthread_mutex_init(&bufferLock, NULL);
    pthread_cond_init(&bufferCond, NULL);
}

// destructor
RRR_CLIENT_CLASS::~RRR_CLIENT_CLASS()
{
}

// register a service
void
RRR_CLIENT_CLASS::RegisterClient(
    int             serviceID,
    RRR_CLIENT_STUB client)
{

}

// The monitor thread ID must be set before we start polling.
void
RRR_CLIENT_CLASS::SetMonitorThreadID(pthread_t mon)
{ 
    monitorThreadID = mon;
    initialized = 1;
    return;
}

// make request with response
UMF_MESSAGE
RRR_CLIENT_CLASS::MakeRequest(
    UMF_MESSAGE request)
{
    UMF_MESSAGE response;

    // get serviceID
    UINT32 serviceID = request->GetServiceID();

    // add channelID to request
    request->SetChannelID(CHANNEL_ID);

    // write request message to channel
    channelio->Write(CHANNEL_ID, request);

    //
    // read response (blocking read) from channelio
    // 
    // We need to handle the Monitor/Service thread and the
    // System thread differently.
    //

    if (pthread_self() != monitorThreadID)
    {
        //
        // System Thread: this thread is only allowed to look
        // at the system-thread-return-buffer. If the buffer is
        // empty, then the thread blocks on a condition variable.
        // The CV is global for all services since there is only
        // one System thread, which can be simultaneously blocked
        // on at most one service at any instant.
        //

        // sleep until buffer becomes non-empty
        pthread_mutex_lock(&bufferLock);
        while (systemThreadResponseBuffer.empty())
        {
            pthread_cond_wait(&bufferCond, &bufferLock);
        }
        
        // buffer is not empty, and we have the lock
        response = systemThreadResponseBuffer.front();
        systemThreadResponseBuffer.pop();

        // response is ready, unlock the buffers
        pthread_mutex_unlock(&bufferLock);

        // sanity check: the serviceID of the buffered message
        // MUST be what we are expecting
        ASSERTX(serviceID == response->GetServiceID());
    }
    else
    {
        //
        // Monitor/Service Thread: this thread directly reads
        // (blocking read) messages out of the channel, directs
        // messages for other services into their appropriate input
        // buffers, and triggers the condition variables. It is
        // guaranteed that a message expected by the Monitor/Service
        // thread will never be in an input buffer; it can only be
        // obtained by directly probing the channel.
        //

        // loop until we get a response for our request
        while (true)
        {
            // get a message from channelio
            response = channelio->Read(CHANNEL_ID);

            // check if this is a message for the service that
            // initiated the request
            if (serviceID == response->GetServiceID())
            {
                // we're all set, break out
                break;
            }

            // this message is for a different service, perhaps
            // (actually, most certainly) it is a response that
            // the System thread is blocked on. Enqueue it into
            // the response buffer of the service and release the
            // condition variable
            pthread_mutex_lock(&bufferLock);

            // sanity check: the current code structure guarantees
            // that there can be at most one outstanding message in
            // the response buffer
            ASSERTX(systemThreadResponseBuffer.empty());

            systemThreadResponseBuffer.push(response);

            pthread_cond_broadcast(&bufferCond);
            pthread_mutex_unlock(&bufferLock);
        }
    }

    return response;
}

// make request with no response
void
RRR_CLIENT_CLASS::MakeRequestNoResponse(
    UMF_MESSAGE request)
{
    // add channelID to request
    request->SetChannelID(CHANNEL_ID);

    // write request message to channelio
    channelio->Write(CHANNEL_ID, request);
}

// poll
void
RRR_CLIENT_CLASS::Poll()
{
    if (!initialized)
        return;

    // this method can only be called from the Monitor/Service thread
    ASSERTX(pthread_self() == monitorThreadID);

    // try to read a single message from channelio
    UMF_MESSAGE msg = channelio->TryRead(CHANNEL_ID);

    //
    // If channelio gives us a message, this means the message is a
    // response to a request that the System thread is currently
    // blocked on. It cannot be a response to a Monitor/Service request.
    //
    if (msg != NULL)
    {
        // lock the buffer
        pthread_mutex_lock(&bufferLock);

        // we cannot already have an outstanding response in the response
        // buffer, because the System thread is only allowed to have one
        // outstanding request
        ASSERTX(systemThreadResponseBuffer.empty());

        // put the message into the System thread's buffer
        systemThreadResponseBuffer.push(msg);

        // wake up the System thread and unlock the buffer
        pthread_cond_broadcast(&bufferCond);
        pthread_mutex_unlock(&bufferLock);
    }
}
