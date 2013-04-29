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

#ifndef _DEBUG_SCAN_SERVICE_
#define _DEBUG_SCAN_SERVICE_

#include <bitset>
#include <pthread.h>
#include <stdio.h>

#include "asim/syntax.h"
#include "platforms-module.h"
#include "awb/provides/rrr.h"
#include "awb/provides/soft_services_deps.h"

#include "awb/rrr/client_stub_DEBUG_SCAN.h"

//
// Manage debug scan chain coming from the hardware.
//

typedef class DEBUG_SCAN_SERVER_CLASS* DEBUG_SCAN_SERVER;


//
// Debug scan data class manages a received stream of 8-bit data and parses
// it into caller-specified chunks.
//
typedef class DEBUG_SCAN_DATA_CLASS* DEBUG_SCAN_DATA;

class DEBUG_SCAN_DATA_CLASS
{
    UINT8 *buf;
    UINT32 bufLen;

    UINT32 writeIdx;        // Current (byte) write point in the buffer
    UINT32 readIdx;         // Current (bit) read point in the buffer

  public:
    DEBUG_SCAN_DATA_CLASS();
    ~DEBUG_SCAN_DATA_CLASS();
    
    // Clear all managed state
    void Reset();
    
    // Add new data from a message.
    void Put(UINT8 data);

    // Get some number of bits, starting with bit 0 of the first byte passed
    // to Put().
    UINT64 Get(int nBits);

    // Number of bits in the full message.
    UINT32 MsgBits();

    // Number of bits remaining in the message not yet returned by Get().
    UINT32 MsgBitsLeft();
};


class DEBUG_SCAN_SERVER_CLASS: public RRR_SERVER_CLASS,
                               public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static DEBUG_SCAN_SERVER_CLASS instance;

    // stubs
    RRR_SERVER_STUB serverStub;
    DEBUG_SCAN_CLIENT_STUB clientStub;

    // Internal display method
    void DisplayMsg();
    void DisplayMsgSoftConnection(GLOBAL_STRING_UID tagID, int numConnections);
    void DisplayMsgRaw(GLOBAL_STRING_UID tagID, const char *tag);
    void DisplayMsgFormatted(GLOBAL_STRING_UID tagID, const char *tag);

    DEBUG_SCAN_DATA_CLASS msg;
    FILE *of;

    pthread_mutex_t scanLock;
    pthread_t liveDbgThread;

  public:
    DEBUG_SCAN_SERVER_CLASS();
    ~DEBUG_SCAN_SERVER_CLASS();

    // static methods
    static DEBUG_SCAN_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE);
    void Uninit();
    void Cleanup();

    // Method to tell the hardware to dump state.
    void Scan(FILE *outFile = stdout);

    // RRR service methods
    void  Send(UINT8 value, UINT8 eom);
    // Done exists solely to signal receipt of all Send() calls before returning
    // control to Scan().  It has lower priority than Send().
    UINT8 Done(UINT8 dummy) { return dummy; }
};

// server stub
#include "awb/rrr/server_stub_DEBUG_SCAN.h"

// all functionalities of the debug scan are completely implemented
// by the DEBUG_SCAN_SERVER class
typedef DEBUG_SCAN_SERVER_CLASS DEBUG_SCAN_CLASS;

#endif
