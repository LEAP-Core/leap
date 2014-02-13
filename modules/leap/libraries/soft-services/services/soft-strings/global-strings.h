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

#ifndef __GLOBAL_STRINGS_H__
#define __GLOBAL_STRINGS_H__

#include <string>
#include <unordered_map>

#include "asim/syntax.h"
#include "awb/provides/command_switches.h"

using namespace std;

//
// Global strings are a method of passing strings between hardware and software
// using a unique token instead of passing entire strings.
//
// All methods within the class are static, since we have only a single instance
// of the global strings class.
//

#define GLOBAL_STRING_UID_SZ (GLOBAL_STRING_PLATFORM_UID_SZ + GLOBAL_STRING_SYNTH_UID_SZ + GLOBAL_STRING_LOCAL_UID_SZ)

//
// GLOBAL_STRING_UID_SZ is expected to be exactly 32 bits, both to guarantee
// compatibility between host and FPGA and to guarantee a size for service
// interfaces using strings (e.g. STDIO).
//
#if (GLOBAL_STRING_UID_SZ != 32)
#error "GLOBAL_STRING_UID size must be 32 bits!"
#endif

typedef UINT32 GLOBAL_STRING_UID;


class GLOBAL_STRINGS : public COMMAND_SWITCH_STRING_CLASS
{
  private:
    static unordered_map <GLOBAL_STRING_UID, string> uidToString;

    static void AddString(GLOBAL_STRING_UID uid, const string& str);

    static GLOBAL_STRING_UID nextAllocId;

  public:
    GLOBAL_STRINGS();

    static const string* Lookup(GLOBAL_STRING_UID uid, bool abortIfUndef = true);

    // Add a string to the table.  A handle will be allocated and returned.
    static GLOBAL_STRING_UID AddString(const string& str);
    // Remove a string from the table
    static void DeleteString(GLOBAL_STRING_UID uid);

    // Command line argument for passing the name of a string database.
    void ProcessSwitchString(const char *db);
};

#endif // __GLOBAL_STRINGS_H__
