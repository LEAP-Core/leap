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

#include <signal.h>

#include "asim/syntax.h"
#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/umf.h"

//
// FIXME: Applications in which the client thread forces the monitor
//        thread to exit at the end of execution (WAIT_FOR_HW == 0)
//        segfault at the end, possibly because LLPI's submodules'
//        destructors are called before LLPI's destructor (which
//        cancels the Monitor thread). This means the Monitor thread
//        is still alive for a short duration after the submodules
//        cease to exist.
//
//        The problem has been patched locally in some implementations
//        of lower-level modules, but we need a more general solution.
//

// UGLY: maintain a global pointer to LLPI's instance
//       so that the signal handler can get access to it
static LLPI llpi_instance = NULL;

// *** trampolene function for LLPI's Main() ***
void * LLPI_Main(void *argv)
{
    LLPI instance = LLPI(argv);
    instance->Main();
    return NULL;
}

// *** signal handler for Ctrl-C ***
void LLPISignalHandler(int arg)
{
    llpi_instance->KillMonitorThread();
    llpi_instance->CallbackExit(0);
}

LLPI_CLASS::LLPI_CLASS() :
        PLATFORMS_MODULE_CLASS(NULL),
        physicalDevices(this),
        debugger(this, &physicalDevices),
        remoteMemory(this, &physicalDevices),
        channelio(this, &physicalDevices),
        rrrClient(this, &channelio),
        rrrServer(this, &channelio),
        monitorAlive(false)
{
    // set global link to RRR client
    // the service modules need this link since they
    // are statically instantiated
    RRRClient = &rrrClient;

    llpi_instance = this;
}

LLPI_CLASS::~LLPI_CLASS()
{
    KillMonitorThread();
}

void
LLPI_CLASS::Init()
{

    PLATFORMS_MODULE_CLASS::Init();

    // setup signal handler to catch SIGINT
    if (signal(SIGINT, LLPISignalHandler) == SIG_ERR)
    {
        perror("signal");
        CallbackExit(1);
    }

    // initialize UMF_ALLOCATOR (FIXME: could do this cleaner)
    // or earlier...
    UMF_ALLOCATOR_CLASS::GetInstance()->Init(this);
    
}


void
LLPI_CLASS::Uninit()
{
    //
    // This path is called only during an unexpected exit sequence, with
    // the normal destructor not being called.  Make sure the physical
    // channel is cleaned up properly.  Some hardware (e.g. ACP) needs
    // to be power cycled if not closed cleanly.
    //
    channelio.~CHANNELIO_CLASS();
    physicalDevices.~PHYSICAL_DEVICES_CLASS();
}


void LLPI_CLASS:: StartMonitorThread()
{
    // Spawn Monitor/Service thread which calls LLPI's Main()
    if (pthread_create(&monitorThreadID,
                       NULL,
                       LLPI_Main,
                       (void *)this) != 0)
    {
        perror("pthread_create");
        exit(1);
    }
    
    // RRR needs to know the monitor thread ID
    monitorAlive = true;
    rrrClient.SetMonitorThreadID(monitorThreadID);
}


// cleanup
void LLPI_CLASS::KillMonitorThread()
{
    if (! monitorAlive) return;

    if (pthread_self() == monitorThreadID)
    {
        ASIMERROR("llpi: Monitor thread trying to cancel itself!\n");
    }

    usleep(50); // Allow non-thread-safe printouts or calls to older stdlib implementations to finish.
    pthread_cancel(monitorThreadID);
    pthread_join(monitorThreadID, NULL);
    monitorAlive = false;
}

// main
void
LLPI_CLASS::Main()
{
    // infinite scheduler loop
    while (true)
    {
        pthread_testcancel(); // set cancelation point
        Poll();
    }
}

inline void
LLPI_CLASS::Poll()
{
    // Poll channelio and RRR server.  Favor channelio over other polling loops,
    // since it tends to have much more activity.
    static int m = 0;

    channelio.Poll();

    if ((++m & 15) == 0)
    {
        rrrServer.Poll();
        rrrClient.Poll();
    }
}
