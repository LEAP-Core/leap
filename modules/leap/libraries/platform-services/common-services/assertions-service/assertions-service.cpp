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
ASSERTIONS_SERVER_CLASS::ASSERTIONS_SERVER_CLASS():
    uninitialized()
{
    // instantiate stubs
    serverStub = new ASSERTIONS_SERVER_STUB_CLASS(this);
    uninitialized = false;
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

    bool didCleanup = uninitialized.fetch_and_store(true);

    if (didCleanup)
    {
        return;
    }

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
