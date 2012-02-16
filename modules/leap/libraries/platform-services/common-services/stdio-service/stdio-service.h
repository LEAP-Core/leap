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

#ifndef _STDIO_SERVICE_
#define _STDIO_SERVICE_

#include <stdio.h>

#include "asim/syntax.h"
#include "asim/trace.h"
#include "asim/regexobj.h"

#include "platforms-module.h"
#include "awb/provides/rrr.h"
#include "awb/provides/soft_services_deps.h"

#include "awb/rrr/client_stub_STDIO.h"

typedef class STDIO_SERVER_CLASS* STDIO_SERVER;

//
// Commands must match the corresponding enum in stdio-local.bsv!
//
enum STDIO_REQ_COMMAND
{
    STDIO_REQ_FCLOSE,
    STDIO_REQ_FFLUSH,
    STDIO_REQ_FOPEN,
    STDIO_REQ_FPRINTF,
    STDIO_REQ_FREAD,
    STDIO_REQ_FWRITE,
    STDIO_REQ_PCLOSE,
    STDIO_REQ_POPEN,
    STDIO_REQ_REWIND,
    STDIO_REQ_SPRINTF,
    STDIO_REQ_STRING_DELETE,
    STDIO_REQ_SYNC
};

enum STDIO_RSP_OP
{
    STDIO_RSP_FOPEN,
    STDIO_RSP_FREAD,
    STDIO_RSP_FREAD_EOF,            // End of file (no payload in packet)
    STDIO_RSP_POPEN,
    STDIO_RSP_SYNC,
    STDIO_RSP_SPRINTF
};

typedef UINT8 STDIO_CLIENT_ID;


//
// Header sent with requests from hardware.  The sizes here do NOT match the
// hardware buffer.
//
typedef struct
{
    GLOBAL_STRING_UID text;
    UINT8 numData;                  // Number of elmenets in data vector
    UINT8 dataSize;                 // Size of data elements (0:1 byte, 1:2 bytes, 2:4 bytes, 4:8 bytes)
    STDIO_CLIENT_ID clientID;       // Ring stop ID for responses
    UINT8 fileHandle;               // Index into file table
    STDIO_REQ_COMMAND command;
    
}
STDIO_REQ_HEADER;


class STDIO_SERVER_CLASS: public RRR_SERVER_CLASS,
                          public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static STDIO_SERVER_CLASS instance;

    UINT32 reqBuffer[32];
    int reqBufferWriteIdx;

    // Map hardware file IDs to software files
    FILE* fileTable[256];
    bool fileIsPipe[256];
    UINT8 openFile(const char *name, const char *mode, bool isPipe);
    void closeFile(UINT8 idx);
    FILE* getFile(UINT8 idx);

    void Req_fopen(const STDIO_REQ_HEADER &req, GLOBAL_STRING_UID mode);
    void Req_fclose(const STDIO_REQ_HEADER &req);

    void Req_popen(const STDIO_REQ_HEADER &req);
    void Req_pclose(const STDIO_REQ_HEADER &req);

    void Req_fread(const STDIO_REQ_HEADER &req);
    void Req_fwrite(const STDIO_REQ_HEADER &req, const UINT32 *data);

    void Req_printf(const STDIO_REQ_HEADER &req, const UINT32 *data);

    void Req_string_delete(const STDIO_REQ_HEADER &req);

    void Req_fflush(const STDIO_REQ_HEADER &req);
    void Req_rewind(const STDIO_REQ_HEADER &req);

    void Req_sync(const STDIO_REQ_HEADER &req);

    // stubs
    RRR_SERVER_STUB serverStub;
    STDIO_CLIENT_STUB clientStub;

  public:
    STDIO_SERVER_CLASS();
    ~STDIO_SERVER_CLASS();

    // static methods
    static STDIO_SERVER GetInstance() { return &instance; }

    // required RRR methods
    void Init(PLATFORMS_MODULE);
    void Uninit();
    void Cleanup();

    // FPGA to software request chunks
    void Req(UINT32 data, UINT8 eom);
};

// server stub
#include "awb/rrr/server_stub_STDIO.h"

// all functionalities of the debug scan are completely implemented
// by the STDIO_SERVER class
typedef STDIO_SERVER_CLASS STDIO_CLASS;

#endif // _STDIO_SERVICE_
