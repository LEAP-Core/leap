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
#include <pthread.h>
#include <errno.h>
#include <sys/select.h>
#include <sys/types.h>
#include <signal.h>
#include <string.h>
#include <strings.h>
#include <string>
#include <iostream>
#include <cmath>
#include <list>

#include "asim/syntax.h"
#include "awb/rrr/service_ids.h"
#include "awb/provides/debug_scan_service.h"

using namespace std;

void *DeadRRRTimer(void *arg);


// ===== service instantiation =====
DEBUG_SCAN_SERVER_CLASS DEBUG_SCAN_SERVER_CLASS::instance;

// ===== methods =====

// constructor
DEBUG_SCAN_SERVER_CLASS::DEBUG_SCAN_SERVER_CLASS() :
    of(stdout),
    // instantiate stubs
    clientStub(new DEBUG_SCAN_CLIENT_STUB_CLASS(this)),
    serverStub(new DEBUG_SCAN_SERVER_STUB_CLASS(this))
{
}


// destructor
DEBUG_SCAN_SERVER_CLASS::~DEBUG_SCAN_SERVER_CLASS()
{
    Cleanup();
}


// init
void
DEBUG_SCAN_SERVER_CLASS::Init(
    PLATFORMS_MODULE p)
{
    // set parent pointer
    parent = p;
}


// uninit: we have to write this explicitly
void
DEBUG_SCAN_SERVER_CLASS::Uninit()
{
    Cleanup();

    // chain
    PLATFORMS_MODULE_CLASS::Uninit();
}

// cleanup
void
DEBUG_SCAN_SERVER_CLASS::Cleanup()
{
    // kill stubs
    delete serverStub;
    delete clientStub;
}

//
// RRR request methods
//


//
// Scan --
//     Tell the hardware to scan all the data out. Block on an ACK and then
//     return control and proceed.
//
void
DEBUG_SCAN_SERVER_CLASS::Scan()
{
    // Avoid multiple paths to scan.  Could probably spin, but for now just
    // ignore multiple simultaneous requests.
    static ATOMIC32_CLASS isActive(0);
    if (isActive++ != 0)
    {
        isActive--;
        return;
    }
    
    fprintf(of, "\nDEBUG SCAN:\n");
    fflush(of);

    // Start a dead RRR timer so the program doesn't hang if RRR has failed
    pthread_t test_thread;
    VERIFYX(! pthread_create(&test_thread, NULL, &DeadRRRTimer, NULL));
    
    // Test RRR
    bool rrr_ok = (clientStub->CheckRRR(27) == 27);

    // RRR responded.  Kill the dead
    VERIFYX(pthread_cancel(test_thread) == 0);

    if (rrr_ok)
    {
        fprintf(of, "    OK\n");
        fflush(of);

        // Dump the debug scan chain
        clientStub->Scan(0);
    }
    else
    {
        fprintf(of, "    FAILED!\n");
        fflush(of);
    }

    isActive--;
}


//
// Send --
//     Receive a debug scan packet.
//
void
DEBUG_SCAN_SERVER_CLASS::Send(UINT8 value, UINT8 eom)
{
    msg.Put(value);
    
    // End of message?
    if (eom)
    {
        DisplayMsg();
        msg.Reset();
    }
}


//
// DisplayMsg --
//     Print a message for a given scan message.
//
void
DEBUG_SCAN_SERVER_CLASS::DisplayMsg()
{
    GLOBAL_STRING_UID tag_uid = msg.Get(GLOBAL_STRING_UID_SZ);
    const string* tag = GLOBAL_STRINGS::Lookup(tag_uid);
    const char* tag_c = tag->c_str();

    // Make sure string meets some basic properties
    VERIFYX((tag->length() > 2) && (tag_c[1] == ':'));

    // The tag indicates the message type
    switch (tag_c[0])
    {
      case 'C':
        {
            int n_connections = atoi(&tag_c[2]);
            DisplayMsgSoftConnection(tag_uid, n_connections);
        }
        break;

      case 'R':
        DisplayMsgRaw(tag_uid, &tag_c[2]);
        break;

      case 'N':
        DisplayMsgFormatted(tag_uid, &tag_c[2]);
        break;

      default:
        ASIMERROR("Unexpected debug scan tag: " << *tag);
    }
}


void
DEBUG_SCAN_SERVER_CLASS::DisplayMsgSoftConnection(
    GLOBAL_STRING_UID tagID,
    int numConnections)
{
    // The synthesis boundary name is stored as a string with the local
    // UID 0.
    GLOBAL_STRING_UID synth_uid = tagID & (~0 << GLOBAL_STRING_LOCAL_UID_SZ);

    fprintf(of, "  Soft connection state [%s]:\n",
            (*GLOBAL_STRINGS::Lookup(synth_uid)).c_str());

    while (numConnections--)
    {
        // Construct the connection name from the synth_uid and the local UID
        // passed in the data.
        GLOBAL_STRING_UID local_uid = msg.Get(GLOBAL_STRING_LOCAL_UID_SZ);

        bool not_empty = (msg.Get(1) != 0);
        bool not_full = (msg.Get(1) != 0);

        fprintf(of, "\t%s:  %sfull / %sempty\n",
                (*GLOBAL_STRINGS::Lookup(synth_uid | local_uid)).c_str(),
                not_full ? "not " : "",
                not_empty ? "not " : "");
    }
}


void
DEBUG_SCAN_SERVER_CLASS::DisplayMsgRaw(
    GLOBAL_STRING_UID tagID,
    const char *tag)
{
    fprintf(of, "  %s:\n\tH", tag);

    //
    // Get the data message.  It is easiest to get the data in 64 bit chunks
    // that have to be reversed in order to print the high bit first.
    //
    list<UINT16> ordered_data;

    int n_bits;
    while ((n_bits = msg.MsgBitsLeft()) != 0)
    {
        int get_bits = (n_bits >= 16 ? 16 : n_bits);
        UINT16 d = msg.Get(get_bits);

        ordered_data.push_front(d);
    }

    // Print a long hex string
    for (list<UINT16>::iterator it = ordered_data.begin();
         it != ordered_data.end();
         it++)
    {
        fprintf(of, " %04x", *it);
    }

    fprintf(of, "  \tB");

    // Print a long binary string
    for (list<UINT16>::iterator it = ordered_data.begin();
         it != ordered_data.end();
         it++)
    {
        for (int b = 16; b > 0; b--)
        {
            if ((b & 3) == 0)
                fprintf(of, " ");

            fprintf(of, "%d", (*it >> (b - 1)) & 1);
        }
    }

    fprintf(of, "\n");
}


void
DEBUG_SCAN_SERVER_CLASS::DisplayMsgFormatted(
    GLOBAL_STRING_UID tagID,
    const char *tag)
{
    char *fmt = new char[strlen(tag) + 1];
    VERIFYX(fmt != NULL);
    strcpy(fmt, tag);

    const char *tok = strtok(fmt, "~");
    if (tok != NULL)
    {
        // The synthesis boundary name is stored as a string with the local
        // UID 0.
        GLOBAL_STRING_UID synth_uid = tagID & (~0 << GLOBAL_STRING_LOCAL_UID_SZ);

        fprintf(of, "  %s [%s]:\n",
                tok,
                (*GLOBAL_STRINGS::Lookup(synth_uid)).c_str());

        tok = strtok(NULL, "~");
    }

    //
    // Parse the set of length/tag tuples representing fields.
    //
    while (tok != NULL)
    {
        // Length (bits) is first.  If length starts with an 'M' the field
        // is a maybe.
        bool is_maybe = (tok[0] == 'M');
        int n_bits = atoi(is_maybe ? &tok[1] : tok);
        VERIFY(n_bits <= 64, "Formatted fields must be 64 bits or smaller");

        // Field name is next
        tok = strtok(NULL, "~");

        if (tok != NULL)
        {
            UINT64 val = msg.Get(n_bits);

            if (is_maybe)
            {
                bool maybe = (msg.Get(1) == 1);
                if (maybe)
                {
                    fprintf(of, "\t%s:  Valid 0x%x\n", tok, val);
                }
                else
                {
                    fprintf(of, "\t%s:  Invalid\n", tok);
                }
            }
            else
            {
                fprintf(of, "\t%s:  0x%x\n", tok, val);
            }

            tok = strtok(NULL, "~");
        }
    }
}


//
// Buffer management
//

DEBUG_SCAN_DATA_CLASS::DEBUG_SCAN_DATA_CLASS() :
    buf(NULL),
    bufLen(0),
    writeIdx(0),
    readIdx(0)
{}

DEBUG_SCAN_DATA_CLASS::~DEBUG_SCAN_DATA_CLASS()
{
    if (buf != NULL)
    {
        delete[] buf;
    }
}

    
void
DEBUG_SCAN_DATA_CLASS::Reset()
{
    writeIdx = 0;
    readIdx = 0;
}

    
void
DEBUG_SCAN_DATA_CLASS::Put(UINT8 data)
{
    if (writeIdx >= bufLen)
    {
        // Buffer is too small.  Replace it with a larger one.
        UINT8 *new_buf = new UINT8[bufLen + 512];
        memcpy(new_buf, buf, bufLen);

        delete[] buf;
        buf = new_buf;
        bufLen += 512;
    }

    buf[writeIdx++] = data;
}


UINT64
DEBUG_SCAN_DATA_CLASS::Get(int nBits)
{
    VERIFYX(nBits <= 64);

    UINT64 result = 0;

    //
    // This code is only triggered on an error, so it doesn't have to be fast.
    //
    for (UINT32 i = 0; i < nBits; i++)
    {
        VERIFYX((readIdx >> 3) < writeIdx);

        UINT64 b = buf[readIdx >> 3];       // Select correct byte
        b >>= (readIdx & 7);                // Shift desired bit to position 0
        b &= 1;                             // Select only bit 0
        b <<= i;                            // Shift to desired position

        result |= b;

        readIdx += 1;
    }

    return result;
}

UINT32
DEBUG_SCAN_DATA_CLASS::MsgBits()
{
    return writeIdx * 8;
}

UINT32
DEBUG_SCAN_DATA_CLASS::MsgBitsLeft()
{
    return MsgBits() - readIdx;
}


//
// Used by Scan when testing RRR to abort the program if RRR hangs.  This
// function will be spawned as a pthread and killed if RRR works.
//
void *DeadRRRTimer(void *arg)
{
    sleep(30);
    
    ASIMERROR("RRR communication lost.  Exiting...");
    return (void*) 0;
}
