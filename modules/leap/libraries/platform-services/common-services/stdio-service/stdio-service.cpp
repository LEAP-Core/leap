//
// Copyright (C) 2012 Intel Corporation
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
#include <stdlib.h>
#include <stdarg.h>
#include <ctype.h>

#include "awb/rrr/service_ids.h"
#include "awb/provides/stdio_service.h"

using namespace std;

// ===== service instantiation =====
STDIO_SERVER_CLASS STDIO_SERVER_CLASS::instance;

// ===== methods =====

// constructor
STDIO_SERVER_CLASS::STDIO_SERVER_CLASS() :
    reqBufferWriteIdx(0),
    // instantiate stubs
//    clientStub(new STDIO_CLIENT_STUB_CLASS(this)),
    serverStub(new STDIO_SERVER_STUB_CLASS(this))
{
}


// destructor
STDIO_SERVER_CLASS::~STDIO_SERVER_CLASS()
{
    Cleanup();
}


// init
void
STDIO_SERVER_CLASS::Init(
    PLATFORMS_MODULE p)
{
    // set parent pointer
    parent = p;
}


// uninit: we have to write this explicitly
void
STDIO_SERVER_CLASS::Uninit()
{
    Cleanup();

    // chain
    PLATFORMS_MODULE_CLASS::Uninit();
}

// cleanup
void
STDIO_SERVER_CLASS::Cleanup()
{
    // kill stubs
    delete serverStub;
//    delete clientStub;
}


//
// Req --
//     Receive a request chunk from hardware.
//
void
STDIO_SERVER_CLASS::Req(UINT32 chunk, UINT8 eom)
{
    VERIFYX(reqBufferWriteIdx < (sizeof(reqBuffer) / sizeof(reqBuffer[0])));

    reqBuffer[reqBufferWriteIdx++] = chunk;

    if (eom)
    {
        Req_printf();
        reqBufferWriteIdx = 0;
    }
}


//
// Req_printf --
//
void
STDIO_SERVER_CLASS::Req_printf()
{
    VERIFY(reqBufferWriteIdx > 1, "STDIO service received partial request");

    UINT32 header = reqBuffer[0];
    const UINT32 data_size = (header >> 16) & 3;
    const UINT32 num_data = (header >> 18) & 7;

    const string* str = GLOBAL_STRINGS::Lookup(reqBuffer[1]);

    UINT64 ar[7] = { 0, 0, 0, 0, 0, 0, 0 };

    if (data_size == 0)
    {
        // Bytes
        UINT8* src = (UINT8*)&reqBuffer[2];
        for (int i = 0; i < num_data; i++) ar[i] = *src++;
    }
    else if (data_size == 1)
    {
        // UINT16's
        UINT16* src = (UINT16*)&reqBuffer[2];
        for (int i = 0; i < num_data; i++) ar[i] = *src++;
    }
    else if (data_size == 2)
    {
        // UINT32's
        UINT32* src = (UINT32*)&reqBuffer[2];
        for (int i = 0; i < num_data; i++) ar[i] = *src++;
    }
    else
    {
        // UINT64's
        UINT64* src = (UINT64*)&reqBuffer[2];
        for (int i = 0; i < num_data; i++) ar[i] = *src++;
    }

    //
    // Parse the format string, looking for references to %s.  For those,
    // the global string UID argument must be converted to a string pointer.
    //
    size_t pos = 0;
    size_t len = str->length();
    int fmt_idx = 0;

    while ((pos = str->find("%", pos)) != string::npos)
    {
        // Found a %.  If it isn't escaped, continue.
        if ((pos + 1 < len) && (*str)[pos+1] == '%')
        {
            // Skip %%
            pos += 1;
            printf("Skip to %d\n", pos);
        }
        else
        {
            // Look for the format type
            while ((++pos < len) && ! isalpha((*str)[pos])) ;

            if (pos < len)
            {
                if ((*str)[pos] == 's')
                {
                    // Found a string.  It is passed from the hardware as a
                    // global string UID.  Convert that to a pointer.
                    const string *arg_str = GLOBAL_STRINGS::Lookup(ar[fmt_idx], false);
                    VERIFY(arg_str != NULL,
                           "STDIO service: failed to find string global string " << ar[fmt_idx] << " position " << fmt_idx+1 << " format string " << *str);

                    ar[fmt_idx] = (UINT64)arg_str->c_str();
                }
            }
        }

        pos += 1;
        fmt_idx += 1;
    }

    printf(str->c_str(), ar[0], ar[1], ar[2], ar[3], ar[4], ar[5], ar[6], ar[7]);
}
