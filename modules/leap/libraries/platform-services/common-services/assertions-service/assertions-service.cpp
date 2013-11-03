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
#include <stdlib.h>
#include <assert.h>
#include <sys/select.h>
#include <sys/types.h>
#include <signal.h>
#include <string.h>
#include <iostream>

#include "awb/provides/model.h"
#include "awb/provides/assertions_service.h"
#include "awb/provides/librl_bsv_base.h"
#include "awb/provides/soft_services_deps.h"
#include "awb/rrr/service_ids.h"

#include "awb/dict/ASSERTIONS.h"

using namespace std;

enum ASSERTION_SEVERITY
{
    ASSERT_NONE,
    ASSERT_MESSAGE,
    ASSERT_WARNING,
    ASSERT_ERROR
};


// ===== service instantiation =====
ASSERTIONS_SERVER_CLASS ASSERTIONS_SERVER_CLASS::instance;

// ===== methods =====

// constructor
ASSERTIONS_SERVER_CLASS::ASSERTIONS_SERVER_CLASS()
{
    // instantiate stubs
    serverStub = new ASSERTIONS_SERVER_STUB_CLASS(this);
}

// destructor
ASSERTIONS_SERVER_CLASS::~ASSERTIONS_SERVER_CLASS()
{
    Cleanup();
}

// init
void
ASSERTIONS_SERVER_CLASS::Init(
    PLATFORMS_MODULE     p)
{
    // set parent pointer
    parent = p;
    
    // Open the output file
    assertionsFile = fopen(LEAP_DEBUG_PATH "/assertions.out", "w+");
}

// uninit: we have to write this explicitly
void
ASSERTIONS_SERVER_CLASS::Uninit()
{
    fclose(assertionsFile);

    Cleanup();

    // chain
    PLATFORMS_MODULE_CLASS::Uninit();
}

// cleanup
void
ASSERTIONS_SERVER_CLASS::Cleanup()
{
    // kill stubs
    delete serverStub;
}

//
// RRR request methods
//

// AssertStr
void
ASSERTIONS_SERVER_CLASS::AssertStr(
    UINT64 fpgaCC,
    UINT32 strUID,
    UINT8 severity)
{
    ASSERTION_SEVERITY a_severity = ASSERTION_SEVERITY(severity);
    
    if (a_severity != ASSERT_NONE)
    {
        // lookup event name from dictionary
        const string *assert_msg = GLOBAL_STRINGS::Lookup(strUID);

        // write to file
        fprintf(assertionsFile, "[%016llu]: %s\n", fpgaCC, assert_msg->c_str());
        fflush(assertionsFile);

        // if severity is great, end the simulation.
        if (a_severity > ASSERT_WARNING)
        {
            cerr << "ERROR: Fatal FPGA assertion failure.\n";
            cerr << "MESSAGE: " << *assert_msg << "\n";
            CallbackExit(1);
        }
    }
}


// AssertDict
void
ASSERTIONS_SERVER_CLASS::AssertDict(
    UINT64 fpgaCC,
    UINT32 assertBase,
    UINT32 assertions)
{
    //
    // Assertions come from hardware in groups as a bit vector.  Each element
    // of the vector is a 2-bit value, equivalent to an ASSERTION_SEVERITY.
    // The dictionary ID is assertBase + the index of the vector.
    //

    // Check each vector entry and generate messages
    for (int i = 0; i < ASSERTIONS_PER_NODE; i++)
    {
        UINT32 assert_id = assertBase + i;
        ASSERTION_SEVERITY severity = ASSERTION_SEVERITY((assertions >> i*2) & 3);

        if (severity != ASSERT_NONE)
        {
            // lookup event name from dictionary
            const char *assert_msg = ASSERTIONS_DICT::Str(assert_id);
            if (assert_msg == NULL)
            {
                cerr << "assert: " << ASSERTIONS_DICT::Str(assert_id)
                     << ": invalid assert_id: " << assert_id << endl;
                CallbackExit(1);
            }

            // write to file
            fprintf(assertionsFile, "[%016llu]: %s\n", fpgaCC, assert_msg);
            fflush(assertionsFile);
    
            // if severity is great, end the simulation.
            if (severity > ASSERT_WARNING)
            {
                cerr << "ERROR: Fatal FPGA assertion failure.\n";
                cerr << "MESSAGE: " << assert_msg << "\n";
                CallbackExit(1);
            }
        }
    }
}
