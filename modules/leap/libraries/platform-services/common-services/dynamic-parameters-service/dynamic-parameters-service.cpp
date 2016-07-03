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

#include <sys/types.h>
#include <signal.h>
#include <string.h>
#include <iostream>

#include "asim/syntax.h"
#include "asim/mesg.h"
#include "awb/rrr/service_ids.h"
#include "awb/provides/command_switches.h"
#include "awb/provides/dynamic_parameters_service.h"
#include "awb/provides/application_env.h"

#include "awb/dict/PARAMS.h"

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

// ===== service instantiation =====
DYNAMIC_PARAMS_SERVICE_CLASS DYNAMIC_PARAMS_SERVICE_CLASS::instance;

// SOFT_PARAMS_TYPE

// Disambiguate old-style parameters from new-style string parameters.
// This type is mirrored in bluespec code.

typedef enum
{
    TYPE_ID = 0,
    TYPE_STR = 1
}
  SOFT_PARAMS_TYPE;
   

//
// Dictionary ID array
//
#define RegisterDynDict(VAR,DICT_ENTRY) DICT_ENTRY,
static UINT32 paramDictIDs[] =
{
#include "awb/provides/sim_config.h"
0
};

//
// extern declarations for all dynamic parameter variables
//
#undef RegisterDynDict
#define RegisterDynDict(VAR,DICT_ENTRY) extern UINT64 VAR;
#include "awb/provides/sim_config.h"
#include "awb/provides/soft_strings.h"

//
// Dynamic parameter pointer array
//
#undef RegisterDynDict
#define RegisterDynDict(VAR,DICT_ENTRY) &VAR,
typedef UINT64 *DYN_PARAM_PTR;
static DYN_PARAM_PTR paramValues[] =
{
#include "awb/provides/sim_config.h"
NULL
};

using namespace std;

// constructor
DYNAMIC_PARAMS_SERVICE_CLASS::DYNAMIC_PARAMS_SERVICE_CLASS() :
    clientStub(new PARAMS_CLIENT_STUB_CLASS(this))
{
}

// destructor
DYNAMIC_PARAMS_SERVICE_CLASS::~DYNAMIC_PARAMS_SERVICE_CLASS()
{
    // delete stubs
    delete clientStub;
}

// init
void
DYNAMIC_PARAMS_SERVICE_CLASS::Init(PLATFORMS_MODULE p)
{
    // chain
    PLATFORMS_MODULE_CLASS::Init(p);

    // Initialize those anon parameters.

    // Anonymous dynamic parameters defaults are found by looking up
    // special matching names.
    vector<GLOBAL_STRING_UID> initTargets;

    GLOBAL_STRINGS::LookupMatchingPrefix(string("ANON_DYN_PARAM_INIT_"), initTargets);

    for (auto targets = initTargets.begin(); targets != initTargets.end(); targets++) {
        const int paramSize = 256;
        char paramName[paramSize];
        UINT64 paramValue;
        const string *initString = GLOBAL_STRINGS::Lookup(*targets);

        if (initString->length() > paramSize) { 
          ASIMERROR("Anonymous parameter initializer " << *initString << " is too large!");
        }
     
        sscanf(initString->c_str(), "ANON_DYN_PARAM_INIT_%s_%d", paramName, &paramValue);

        // Now we need to find the actual parameter UID and assign value        
        string paramNameStr(paramName);
        anonParams[paramName] = paramValue;

    }

}

void 
DYNAMIC_PARAMS_SERVICE_CLASS::SendAllParams()
{
    if (PLATFORM_SERVICES_AVAILABLE)
    {
        UINT32 i = 0;
        while (paramValues[i])
        {
            clientStub->sendParam(paramDictIDs[i], TYPE_ID, *paramValues[i]);
            i += 1;
        }

        for (auto params = anonParams.begin(); params != anonParams.end(); params++) {
            clientStub->sendParam(GLOBAL_STRINGS::Lookup(params->first), TYPE_STR, params->second);
        }
    }
}

void 
DYNAMIC_PARAMS_SERVICE_CLASS::SendParam(const string& paramName, UINT64 paramValue)
{
    GLOBAL_STRING_UID uid = GLOBAL_STRINGS::Lookup(paramName, true);
    clientStub->sendParam(uid, TYPE_STR, paramValue);
}


bool 
DYNAMIC_PARAMS_SERVICE_CLASS::SetAnonymousParameter(char *name, UINT64 paramValue) {
  // We will have an error later if this string doesn't exist. 
  anonParams[string(name)] = paramValue;      
  return true;
}
