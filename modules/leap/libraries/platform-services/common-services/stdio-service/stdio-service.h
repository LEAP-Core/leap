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

#ifndef _STDIO_SERVICE_
#define _STDIO_SERVICE_

#include <stdio.h>

#include "tbb/atomic.h"

#include "asim/syntax.h"
#include "asim/trace.h"
#include "asim/regexobj.h"

#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/rrr.h"
#include "awb/provides/command_switches.h"
#include "awb/provides/soft_services_deps.h"
#include "awb/provides/stdio_service.h"
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
    STDIO_REQ_SYNC,
    STDIO_REQ_SYNC_SYSTEM
};

enum STDIO_RSP_OP
{
    STDIO_RSP_FOPEN,
    STDIO_RSP_FREAD,
    STDIO_RSP_FREAD_EOF,            // End of file (no payload in packet)
    STDIO_RSP_POPEN,
    STDIO_RSP_SYNC,
    STDIO_RSP_SYNC_SYSTEM,
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


class STDIO_COND_PRINTF_MASK_SWITCH_CLASS : public COMMAND_SWITCH_INT_CLASS
{
  private:
    int mask;

  public:
    STDIO_COND_PRINTF_MASK_SWITCH_CLASS() :
        COMMAND_SWITCH_INT_CLASS("stdio-cond-printf-mask"),
        mask(0)
    {};

    ~STDIO_COND_PRINTF_MASK_SWITCH_CLASS() {};
    
    void ProcessSwitchInt(int arg) { mask = arg; };
    void ShowSwitch(std::ostream& ostr, const string& prefix)
    {
        ostr << prefix << "[--stdio-cond-printf-mask=<n>]" << endl
             << prefix << "                        Enable FPGA-side masked STDIO printf" << endl;
    }
    
    int Mask() const { return mask; }
};


class STDIO_SERVER_CLASS: public RRR_SERVER_CLASS,
                          public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static STDIO_SERVER_CLASS instance;

    class tbb::atomic<bool> uninitialized;

    STDIO_COND_PRINTF_MASK_SWITCH_CLASS maskSwitch;
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

    void Req_sync(const STDIO_REQ_HEADER &req, bool isSystemSync);

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

    // Called at the end of a run to make sure all messages are flushed
    void Sync();

    // FPGA to software request chunks
    void Req(UINT64 data, UINT8 eom);

    // Set mask for conditional printing
    void SetCondMask(UINT32 mask);
};

// server stub
#include "awb/rrr/server_stub_STDIO.h"

// all functionalities of the debug scan are completely implemented
// by the STDIO_SERVER class
typedef STDIO_SERVER_CLASS STDIO_CLASS;

#endif // _STDIO_SERVICE_
