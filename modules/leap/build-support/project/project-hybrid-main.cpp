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
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>

#include "asim/syntax.h"

#include "asim/dict/init.h"

#include "asim/provides/virtual_platform.h"
#include "asim/provides/low_level_platform_interface.h"
#include "asim/provides/virtual_devices.h"
#include "asim/provides/starter_device.h"
#include "asim/provides/application_env.h"
#include "asim/provides/command_switches.h"
#include "asim/provides/model.h"


// =======================================
//           PROJECT MAIN
// =======================================

// Foundation code for HW/SW hybrid projects
// Instantiate the virtual platform and application environment.
// Run the user application through the application environment.

// main
int main(int argc, char *argv[])
{
    // Set line buffering to avoid fflush() everywhere.  stderr was probably
    // unbuffered already, but be sure.
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IOLBF, 0);

    // Initialize pthread conditions so we know
    // when the HW & SW are done.

    VIRTUAL_PLATFORM vp         = new VIRTUAL_PLATFORM_CLASS();
    APPLICATION_ENV  appEnv     = new APPLICATION_ENV_CLASS(vp);

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
        STARTER_DEVICE_CLASS::GetInstance()->WaitForHardware();
    }

    // Cleanup and exit
    delete appEnv;
    delete vp;

    //cout << "SW: Goodbye" << endl;
    return ret_val;
}
