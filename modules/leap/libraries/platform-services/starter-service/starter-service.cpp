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

#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <iomanip>

#include "asim/syntax.h"
#include "asim/atomic.h"

#include "awb/rrr/service_ids.h"
#include "awb/provides/starter_service.h"
#include "awb/provides/application_env.h"

#include "asim/ioformat.h"

using namespace std;

// Global lock variables
std::mutex hardwareStatusMutex;
std::condition_variable hardwareFinishedSignal;

int hardwareStarted;
int hardwareFinished;
int hardwareExitCode;


// ===== service instantiation =====
STARTER_SERVICE_SERVER_CLASS STARTER_SERVICE_SERVER_CLASS::instance;

// constructor
STARTER_SERVICE_SERVER_CLASS::STARTER_SERVICE_SERVER_CLASS() :
    lastStatsScanCycle(0),
    exitCode(0)
{

    // Initialize hardware status variables.
    hardwareStarted = 0;
    hardwareFinished = 0;
    hardwareExitCode = 0;

    // instantiate stubs
    clientStub = new STARTER_SERVICE_CLIENT_STUB_CLASS(this);
    serverStub = new STARTER_SERVICE_SERVER_STUB_CLASS(this);
}


// destructor
STARTER_SERVICE_SERVER_CLASS::~STARTER_SERVICE_SERVER_CLASS()
{
    delete clientStub;
    delete serverStub;
}

//
// RRR service requests
//

// init
void
STARTER_SERVICE_SERVER_CLASS::Init(
    PLATFORMS_MODULE p)
{
}

// uninit: override
void
STARTER_SERVICE_SERVER_CLASS::Uninit()
{

}


// End
void
STARTER_SERVICE_SERVER_CLASS::End(
    UINT8 exit_code)
{
    // Set that the hardware is finished.
    // Signal any listening thread that might be listening.

    std::unique_lock<std::mutex> lk(hardwareStatusMutex);

    hardwareFinished = 1;
    hardwareExitCode = exit_code;
    exitCode = exit_code;

    hardwareFinishedSignal.notify_all();
}

// Heartbeat
void
STARTER_SERVICE_SERVER_CLASS::Heartbeat(
    UINT64 fpga_cycles)
{
    // TODO: add deadlock detection timeout.
    cout << "starter: hardware still alive: " << fpga_cycles << "." << endl;
}


// client: Start
void
STARTER_SERVICE_SERVER_CLASS::Start()
{
    // Record that the hardware has started.
    std::unique_lock<std::mutex> lk(hardwareStatusMutex);
    hardwareStarted = 1;
    lk.unlock();

    // call client stub
    clientStub->Start(0);
}

// client: WaitForHardware
UINT8
STARTER_SERVICE_SERVER_CLASS::WaitForHardware()
{
    std::unique_lock<std::mutex> lk(hardwareStatusMutex);
    if(!hardwareFinished)
    {
        hardwareFinishedSignal.wait(lk, []{ return hardwareFinished; });
    }
    return exitCode;
}
    
void
STARTER_SERVICE_SERVER_CLASS::StatusMsg()
{
    if (exitCode == 0)
    {
        cout << "starter: hardware completed successfully." << endl;
    }
    else
    {
        cout << "starter: hardware finished with exit code " << exitCode << "." << endl;
    }
}
