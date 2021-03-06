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
        readReq(false),
        PLATFORMS_MODULE_CLASS(p)
{
    physicalChannel = d->GetLegacyPhysicalChannel();

    // set up stations
    for (int i = 0; i < CIO_NUM_CHANNELS; i++)
    {
        // default station type is READ
        stations[i].type = CIO_STATION_TYPE_READ;
        stations[i].module = NULL;
    }

    // initialize mutexes (mutices?)
    pthread_mutex_init(&bufferLock, NULL);
    pthread_mutex_init(&channelLock, NULL);
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
    stations[channel].type = CIO_STATION_TYPE_DELIVERY;
    stations[channel].module = module;
}

// non-blocking read
UMF_MESSAGE
CHANNELIO_CLASS::TryRead(
    int channel)
{
    UMF_MESSAGE msg = NULL;

    // check if a message is already enqueued in read buffer
    pthread_mutex_lock(&bufferLock);
    if (stations[channel].readBuffer.empty() == false)
    {
        msg = stations[channel].readBuffer.front();
        stations[channel].readBuffer.pop();
    }
    pthread_mutex_unlock(&bufferLock);
    
    return msg;
}

// blocking read
UMF_MESSAGE
CHANNELIO_CLASS::Read(
    int channel)
{
    //
    // We will use two locks to implement this functionality.
    // The first lock called channelLock simply guards access to
    // the physical channel layer (and can possibly be transferred
    // to the physical channel code). The second lock, called
    // bufferLock is a fine-grained lock that we use to control
    // access to our internal per-channel buffers.
    //
    // I am NOT convinced that these two locks are sufficient to
    // guarantee correct atomic behavior of channelio under all
    // circumstances. Using a global lock around the Read and Write
    // methods is much safer and easier to reason about, but
    // unfortunately leads to a deadlock situation because of
    // Delivery-type stations (the lock is still held while
    // DeliverMessage is called, which in turn might call Write
    // on us). I think we should get rid of the entire Delivery idea
    // and require all stations to poll us for messages, although
    // this would reduce performance somewhat.
    //

    UMF_MESSAGE msg = NULL;

    // first check if a message is already enqueued in read buffer
    pthread_mutex_lock(&bufferLock);
    if (stations[channel].readBuffer.empty() == false)
    {
        msg = stations[channel].readBuffer.front();
        stations[channel].readBuffer.pop();
    }
    pthread_mutex_unlock(&bufferLock);

    // return if we found a message
    if (msg)
    {
        return msg;
    }

    // loop until we get what we are looking for
    while (true)
    {
        // block-read a message from physical channel
        readReq = true;
        pthread_mutex_lock(&channelLock);
        readReq = false;
        msg = physicalChannel->Read();
        pthread_mutex_unlock(&channelLock);

        // get virtual channel ID of incoming message
        int inchannel = msg->GetChannelID();

        // if this message is for the channel we want, then return it
        if (inchannel == channel)
        {
            return msg;
        }

        // message is for another channel, check type of station
        if (stations[inchannel].type == CIO_STATION_TYPE_READ)
        {
            // enqueue in read buffer
            pthread_mutex_lock(&bufferLock);
            stations[inchannel].readBuffer.push(msg);
            pthread_mutex_unlock(&bufferLock);
        }
        else
        {
            // deliver message to station module
            stations[inchannel].module->DeliverMessage(msg);
        }
    }

    // shouldn't be here
    return NULL;
}

// write
void
CHANNELIO_CLASS::Write(
    int channel,
    UMF_MESSAGE message)
{
    //
    // We do NOT lock the channel here, under the assumption that parallel
    // reads and writes are permitted in many channel implementations.
    //
    // Channels that do not support parallel reads and writes must provide
    // their own locking.
    //

    // attach channelID to message
    message->SetChannelID(channel);

    // send to physical channel
    physicalChannel->Write(message);
}

// poll
void
CHANNELIO_CLASS::Poll()
{
    // Yield if a read or write request is trying to get the lock.  On multi-core
    // machines the pool loop can effectively hold the lock and never give it
    // up without this.
    if (readReq) return;

    // check if physical channel has a new message
    pthread_mutex_lock(&channelLock);
    UMF_MESSAGE msg = physicalChannel->TryRead();
    pthread_mutex_unlock(&channelLock);

    if (msg != NULL)
    {
        // get virtual channel ID
        int channelID = msg->GetChannelID();

        // if this message is for a read-type station, then enqueue it
        if (stations[channelID].type == CIO_STATION_TYPE_READ)
        {
            pthread_mutex_lock(&bufferLock);
            stations[channelID].readBuffer.push(msg);
            pthread_mutex_unlock(&bufferLock);
        }
        else
        {
            // deliver message to station module immediately
            stations[channelID].module->DeliverMessage(msg);
        }
    }
}
