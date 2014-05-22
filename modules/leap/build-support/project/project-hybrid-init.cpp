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
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>
#include <errno.h>

#include "asim/syntax.h"

#include "awb/dict/init.h"

#include "awb/provides/virtual_platform.h"
#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/virtual_devices.h"
#include "awb/provides/starter_service.h"
#include "awb/provides/stats_service.h"
#include "awb/provides/stdio_service.h"
#include "awb/provides/application_env.h"
#include "awb/provides/command_switches.h"
#include "awb/provides/model.h"

// =======================================
//           PROJECT MAIN
// =======================================

// Foundation code for HW/SW hybrid projects
// Instantiate the virtual platform and application environment.
// Run the user application through the application environment.

// main
int Init(int argc, char *argv[])
{
    int st;

    // Set line buffering to avoid fflush() everywhere.  stderr was probably
    // unbuffered already, but be sure.
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IOLBF, 0);

    // Initialize pthread conditions so we know
    // when the HW & SW are done.

    VIRTUAL_PLATFORM vp         = new VIRTUAL_PLATFORM_CLASS();
    APPLICATION_ENV  appEnv     = new APPLICATION_ENV_CLASS(vp);

    //
    // Create standard debugging directory.
    //
    struct stat sbuf;
    // Only create it if not already present.
    st = stat(LEAP_DEBUG_PATH, &sbuf);
    if (st != 0)
    {
        if (errno != ENOENT)
        {
            fprintf(stderr, "Error accessing directory \"" LEAP_DEBUG_PATH "\".\n");
            exit(1);
        }
        st = mkdir(LEAP_DEBUG_PATH, 0755);
        if (st != 0)
        {
            fprintf(stderr, "Error creating directory \"" LEAP_DEBUG_PATH "\".\n");
            exit(1);
        }
    }

    //
    // Live debugging directory will be filled with live filesystem entries
    // (mostly named FIFOs) that can be used for debugging during a run.
    //
    st = system("/bin/rm -rf " LEAP_LIVE_DEBUG_PATH "; mkdir -p " LEAP_LIVE_DEBUG_PATH);
    if ((st == -1) || (WEXITSTATUS(st) != 0))
    {
        fprintf(stderr, "Error creating directory " LEAP_LIVE_DEBUG_PATH "\".\n");
        exit(1);
    }

    // Set up default switches
    globalArgs = new GLOBAL_ARGS_CLASS();
    
    // Process command line arguments
    COMMAND_SWITCH_PROCESSOR switchProc = new COMMAND_SWITCH_PROCESSOR_CLASS();
    switchProc->ProcessArgs(argc, argv);

    // Init the virtual platform and the application environment.
    vp->Init();
    appEnv->InitApp(argc, argv);

    // Transfer control to Application via Environment
    int ret_val = appEnv->RunApp(argc, argv);

    // Application's Main() exited => wait for hardware to be done.
    // If the starter service is not available then we assume
    // the hardware never terminates (IE because it's a pure server).
    
    if (PLATFORM_SERVICES_AVAILABLE)
    {
        STARTER_SERVICE_CLASS::GetInstance()->WaitForHardware();
        STDIO_SERVER_CLASS::GetInstance()->Sync();
        STARTER_SERVICE_CLASS::GetInstance()->StatusMsg();

        // Emit statistics
        STATS_SERVER_CLASS::GetInstance()->DumpStats();
        STATS_SERVER_CLASS::GetInstance()->EmitFile();
    }

    // Cleanup and exit
    delete appEnv;
    delete vp;

    return ret_val;
}
