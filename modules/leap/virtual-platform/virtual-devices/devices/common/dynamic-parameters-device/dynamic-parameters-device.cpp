//
// Copyright (C) 2011 Intel Corporation
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

#include <sys/types.h>
#include <signal.h>
#include <string.h>
#include <iostream>

#include "asim/syntax.h"
#include "asim/mesg.h"
#include "asim/rrr/service_ids.h"
#include "asim/provides/command_switches.h"
#include "asim/provides/dynamic_parameters_device.h"
#include "asim/provides/application_env.h"

#include "asim/dict/PARAMS.h"

//
// This code builds parallel arrays for mapping dynamic parameter values to
// dictionary entries.  Two arrays are built instead of using a struct to save
// space since values pointers are 64 bits and dictionary entries are 32 bits.
//
// sim_config.h is built by leap-configure and depends on macros to give
// information about parameters.  We define the macro multiple times to build
// the table.
//
#undef Register
#undef Declare
#undef RegisterDyn

//
// Dictionary ID array
//
#define RegisterDynDict(VAR,DICT_ENTRY) DICT_ENTRY,
static UINT32 paramDictIDs[] =
{
#include "asim/provides/sim_config.h"
0
};

//
// extern declarations for all dynamic parameter variables
//
#undef RegisterDynDict
#define RegisterDynDict(VAR,DICT_ENTRY) extern UINT64 VAR;
#include "asim/provides/sim_config.h"

//
// Dynamic parameter pointer array
//
#undef RegisterDynDict
#define RegisterDynDict(VAR,DICT_ENTRY) &VAR,
typedef UINT64 *DYN_PARAM_PTR;
static DYN_PARAM_PTR paramValues[] =
{
#include "asim/provides/sim_config.h"
NULL
};

using namespace std;

// constructor
DYNAMIC_PARAMS_DEVICE_CLASS::DYNAMIC_PARAMS_DEVICE_CLASS() :
    clientStub(new PARAMS_CLIENT_STUB_CLASS(this))
{
}

// destructor
DYNAMIC_PARAMS_DEVICE_CLASS::~DYNAMIC_PARAMS_DEVICE_CLASS()
{
    Cleanup();
}

// init
void
DYNAMIC_PARAMS_DEVICE_CLASS::Init(PLATFORMS_MODULE p)
{
    // chain
    PLATFORMS_MODULE_CLASS::Init(p);
}

void
DYNAMIC_PARAMS_DEVICE_CLASS::Uninit()
{
    Cleanup();

    // chain
    PLATFORMS_MODULE_CLASS::Uninit();
}

// cleanup
void
DYNAMIC_PARAMS_DEVICE_CLASS::Cleanup()
{
    // delete stubs
    delete clientStub;
}

void 
DYNAMIC_PARAMS_DEVICE_CLASS::SendAllParams()
{
    if (PLATFORM_SERVICES_AVAILABLE)
    {
        UINT32 i = 0;
        while (paramValues[i])
        {
            clientStub->sendParam(paramDictIDs[i], *paramValues[i]);
            i += 1;
        }
    }
}
