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
#include <strings.h>
#include <string>
#include <iostream>
#include <cmath>

#include "awb/rrr/service_ids.h"
#include "awb/dict/DEBUG_SCAN.h"

#include "awb/provides/soft_services_deps.h"
#include "awb/provides/debug_scan_device.h"

using namespace std;

// ===== service instantiation =====
DEBUG_SCAN_DEVICE_SERVER_CLASS DEBUG_SCAN_DEVICE_SERVER_CLASS::instance;

// ===== methods =====

// constructor
DEBUG_SCAN_DEVICE_SERVER_CLASS::DEBUG_SCAN_DEVICE_SERVER_CLASS() :
    msgIdx(0),
    of(stdout),
    // instantiate stubs
    clientStub(new DEBUG_SCAN_CLIENT_STUB_CLASS(this)),
    serverStub(new DEBUG_SCAN_SERVER_STUB_CLASS(this))
{
}



// destructor
DEBUG_SCAN_DEVICE_SERVER_CLASS::~DEBUG_SCAN_DEVICE_SERVER_CLASS()
{
    Cleanup();
}


// init
void
DEBUG_SCAN_DEVICE_SERVER_CLASS::Init(
    PLATFORMS_MODULE p)
{
    // set parent pointer
    parent = p;
}


// uninit: we have to write this explicitly
void
DEBUG_SCAN_DEVICE_SERVER_CLASS::Uninit()
{
    Cleanup();

    // chain
    PLATFORMS_MODULE_CLASS::Uninit();
}

// cleanup
void
DEBUG_SCAN_DEVICE_SERVER_CLASS::Cleanup()
{
    // kill stubs
    delete serverStub;
    delete clientStub;
}

//
// RRR request methods
//

//
// Send --
//     Receive a debug scan packet.
//
void
DEBUG_SCAN_DEVICE_SERVER_CLASS::Send(
    UINT32 id,
    UINT8 value,
    UINT8 eom)
{
    VERIFY(id < DEBUG_SCAN_DICT_ENTRIES, "debug-scan-controller:  Invalid id");

    ASSERT(msgIdx < DEBUG_SCAN_MAX_MSG_SIZE, "DEBUG SCAN " << DEBUG_SCAN_DICT::Name(id) << "message is too large");

    msg[msgIdx] = value;
    msgIdx += 1;

    // End of message?
    if (eom)
    {
        DisplayMsg(id);

        msgIdx = 0;
    }
}


//
// Scan --
//     Tell the hardware to scan all the data out. Block on an ACK and then
//     return control and proceed.
//
void
DEBUG_SCAN_DEVICE_SERVER_CLASS::Scan()
{
    fprintf(of, "\nDEBUG SCAN:\n");

    clientStub->Scan(0);
}


//
// DisplayMsg --
//     Print a message for a given scan message.
//
void
DEBUG_SCAN_DEVICE_SERVER_CLASS::DisplayMsg(UINT32 msgID)
{
    if (msgID == DEBUG_SCAN_SOFT_CONNECTIONS_FIFO)
    {
        DisplayMsgSoftConnection(msgID);
    }
    else
    {
        DisplayMsgGeneric(msgID);
    }
}


void
DEBUG_SCAN_DEVICE_SERVER_CLASS::DisplayMsgSoftConnection(UINT32 msgID)
{
    // First two bytes are the high part synthesis boundary ID portion
    // of the string UID.  This portion is constant for all strings in
    // the record.
    UINT32 synth_uid = ((msg[0] << 8) | (msg[1])) << GLOBAL_STRING_LOCAL_UID_SZ;

    fprintf(of, "  %s [%s]: %s\n",
            DEBUG_SCAN_DICT::Name(msgID),
            (*GLOBAL_STRINGS::Lookup(synth_uid)).c_str(),
            DEBUG_SCAN_DICT::Str(msgID));

    int i = 2;
    while (i < msgIdx)
    {
        // Local UID portion is stored in 16 bits
        UINT32 local_uid = (msg[i] << 8) | msg[i + 1];

        // The high 2 bits are notFull / notEmpty bits
        bool not_full = ((local_uid & 0x8000) != 0);
        bool not_empty = ((local_uid & 0x4000) != 0);
        local_uid &= (1 << GLOBAL_STRING_LOCAL_UID_SZ) - 1;

        fprintf(of, "\t%s:  %sfull / %sempty\n",
                (*GLOBAL_STRINGS::Lookup(synth_uid | local_uid)).c_str(),
                not_full ? "not " : "",
                not_empty ? "not " : "");

        i += 2;
    }
}


void
DEBUG_SCAN_DEVICE_SERVER_CLASS::DisplayMsgGeneric(UINT32 msgID)
{
    // Default just prints a number
    fprintf(of, "  %s: %s\n\tH ", DEBUG_SCAN_DICT::Name(msgID), DEBUG_SCAN_DICT::Str(msgID));

    // Print a long hex string
    for (int i = 0; i < msgIdx; i++)
    {
        if ((i & 1) == 0)
            fprintf(of, " ");

        fprintf(of, "%02x", msg[i]);
    }

    fprintf(of, "  \tB");

    // Print a long binary string
    for (int i = 0; i < msgIdx; i++)
    {
        for (int b = 8; b > 0; b--)
        {
            if ((b & 3) == 0)
                fprintf(of, " ");

            fprintf(of, "%d", (msg[i] >> (b - 1)) & 1);
        }
    }

    fprintf(of, "\n");
}
