//
// Copyright (C) 2008 Intel Corporation
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
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
