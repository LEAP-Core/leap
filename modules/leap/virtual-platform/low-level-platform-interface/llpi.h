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

#ifndef __LLPI__
#define __LLPI__

#include "platforms-module.h"
#include "awb/provides/physical_platform.h"
#include "awb/provides/remote_memory.h"
#include "awb/provides/channelio.h"
#include "awb/provides/rrr.h"
#include "awb/provides/physical_platform_debugger.h"

// Low Level Platform Interface

// A convenient bundle of all ways to interact with the outside world.
typedef class LLPI_CLASS* LLPI;
class LLPI_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:

    // LLPI stack layers
    PHYSICAL_DEVICES_CLASS           physicalDevices;
    PHYSICAL_PLATFORM_DEBUGGER_CLASS debugger;
    REMOTE_MEMORY_CLASS              remoteMemory;
    CHANNELIO_CLASS                  channelio;
    RRR_CLIENT_CLASS                 rrrClient;
    RRR_SERVER_MONITOR_CLASS         rrrServer;
    
    // Monitor thread ID for those who need it.
    pthread_t monitorThreadID;
    bool monitorAlive;

  public:

    // constructor - destructor
    LLPI_CLASS();
    ~LLPI_CLASS();

    // Main
    void Main();
    
    // Init - bring up the monitor thread
    void Init();
    void Uninit();
    
    // accessors
    PHYSICAL_DEVICES   GetPhysicalDevices() { return &physicalDevices; }
    REMOTE_MEMORY      GetRemoteMemory()    { return &remoteMemory; }
    CHANNELIO          GetChannelIO()       { return &channelio; }
    RRR_CLIENT         GetRRRClient()       { return &rrrClient; }
    RRR_SERVER_MONITOR GetRRRServer()       { return &rrrServer; }

    // misc
    void Poll();
    void StartMonitorThread();
    void KillMonitorThread();
};

#endif
