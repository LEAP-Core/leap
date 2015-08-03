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
#include <string.h>

#include "asim/syntax.h"
#include "asim/mesg.h"

#include "awb/provides/soft_services_deps.h"

//
// Global strings are a method of passing strings between hardware and software
// using a unique token instead of passing entire strings.
//

// Private region of the global ID space used for run-time allocated IDs
const GLOBAL_STRING_UID pvtIdSpace = -1 << (GLOBAL_STRING_SYNTH_UID_SZ +
                                            GLOBAL_STRING_LOCAL_UID_SZ);

// Static objects
unordered_map <GLOBAL_STRING_UID, string>  GLOBAL_STRINGS::uidToString;
unordered_map <string, GLOBAL_STRING_UID>  GLOBAL_STRINGS::stringToUID;
GLOBAL_STRING_UID GLOBAL_STRINGS::nextAllocId = pvtIdSpace;
static GLOBAL_STRINGS instance;
    
//
// Look up a string in the table, given a UID.
//
const string*
GLOBAL_STRINGS::Lookup(GLOBAL_STRING_UID uid, bool abortIfUndef)
{
    unordered_map <GLOBAL_STRING_UID, string>::iterator s = uidToString.find(uid);

    if (s != uidToString.end())
    {
        return &(s->second);
    }
    else
    {
        if (abortIfUndef)
        {
            ASIMERROR("Global string UID " << uid << " undefined!");
        }

        return NULL;
    }
}

//
// Look up a UID in the table, given a string handle.
//
const GLOBAL_STRING_UID
GLOBAL_STRINGS::Lookup(const string& str, bool abortIfUndef)
{
    unordered_map <string, GLOBAL_STRING_UID>::iterator s = stringToUID.find(str);

    if (s != stringToUID.end())
    {
        return (s->second);
    }
    else
    {
        if (abortIfUndef)
        {
            ASIMERROR("Global string " << str << " undefined!");
        }

        return -1;
    }
}


//
// Public version of string addition allocates a UID for the new string.
//
GLOBAL_STRING_UID
GLOBAL_STRINGS::AddString(const string& str)
{
    //
    // This code doesn't yet handle overrunning an initial pass of the string
    // ID space.  The space is quite large but could eventually be a problem,
    // though the transaction cost of allocating strings will likely keep
    // any high performance programs from allocating crazy numbers of strings.
    //

    if (nextAllocId == 0)
    {
        ASIMERROR("Too many strings allocated!");
    }

    if (Lookup(nextAllocId, false) != NULL)
    {
        ASIMERROR("UID already allocated!");
    }

    AddString(nextAllocId, str);
    return nextAllocId++;
}


//
// Remove a string from the table that was added by public version of
// AddString().
//
void
GLOBAL_STRINGS::DeleteString(GLOBAL_STRING_UID uid)
{
    VERIFY((uid & pvtIdSpace) == pvtIdSpace,
           "Attempt to deallocate a static global string");

    unordered_map <GLOBAL_STRING_UID, string>::iterator s = uidToString.find(uid);
    if (s != uidToString.end())
    {
        uidToString.erase(s);
    }
}


//
// Add a string to the table.  (Internal method used when loading a database.)
//
void
GLOBAL_STRINGS::AddString(GLOBAL_STRING_UID uid, const string& str)
{
    unordered_map <GLOBAL_STRING_UID, string>::iterator s = uidToString.find(uid);

    if (s != uidToString.end())
    {
        // UID already present!
        VERIFY(s->second.compare(str) == 0,
               "Strings \"" << s->second << "\" and \"" << str << "\" share UID " << uid);
        return;
    }

    uidToString[uid] = str;
    stringToUID[str] = uid;
}

//
// Read in a global string database built by the Bluespec compilation.
//
// The expected database is very simple.  No comments or whitespace.
// Each line is a of the form:
//   <uid>,<string>
//
void
GLOBAL_STRINGS::ProcessSwitchString(const char *db)
{
    FILE *f;

    f = fopen(db, "r");
    VERIFY(f != NULL, "Failed to open global string database " << db);

    int uid;
    while (fscanf(f, "%u,", &uid) == 1)
    {
        char buf[1024];
        if (fgets(buf, sizeof(buf), f) != NULL)
        {
            // String continues, potentially across multiple lines, until seeing
            // the X!gLb!X end marker.
            string str = buf;
            bool done = false;
            do
            {
                size_t tag = str.rfind("X!gLb!X");
                if (tag != string::npos)
                {
                    str.erase(str.begin() + tag, str.end());
                    done = true;
                }
                else
                {
                    if (fgets(buf, sizeof(buf), f) == NULL)
                    {
                        done = true;
                    }
                    str.append(buf);
                }
            }
            while (! done);

            AddString(uid, str);
        }
    }

    fclose(f);

}


GLOBAL_STRINGS::GLOBAL_STRINGS() :
    COMMAND_SWITCH_STRING_CLASS("global-strings")
{
}


void GLOBAL_STRINGS::DumpUIDs()
{
    cout << "Dumping string state" << endl;
    for(unordered_map<GLOBAL_STRING_UID, string>::iterator idIter = uidToString.begin();
        idIter != uidToString.end();
        idIter++)
    {
        cout << idIter->second << ":" << idIter->first << endl; 
    }
}
