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
#include <errno.h>
#include <stdarg.h>
#include <ctype.h>
#include <algorithm>

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
    clientStub(new STDIO_CLIENT_STUB_CLASS(this)),
    serverStub(new STDIO_SERVER_STUB_CLASS(this))
{
    memset(fileTable, 0, sizeof(fileTable));
    memset(fileIsPipe, 0, sizeof(fileIsPipe));

    fileTable[0] = stdout;
    fileTable[1] = stdin;
    fileTable[2] = stderr;
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
    delete clientStub;
}


//
// Sync --
//     Called at the end of a run.  Ensure that all pending client requests
//     have arrived at the host.
//
void
STDIO_SERVER_CLASS::Sync()
{
    clientStub->Sync(0);
}


//
// openFile --
//     Open a file and add it to the hardware/software file mapping table.
//
UINT8
STDIO_SERVER_CLASS::openFile(const char *name, const char *mode, bool isPipe)
{
    UINT32 idx = 3;
    while ((idx < 256) && (fileTable[idx] != NULL)) idx += 1;

    VERIFY(idx < 256, "Out of file descriptors");

    fileIsPipe[idx] = isPipe;
    fileTable[idx] = isPipe ? popen(name, mode) : fopen(name, mode);
    VERIFY(fileTable[idx] != NULL, "Failed to open file (" << name << "), errno = " << errno);

    return idx;
}


//
// closeFile --
//     Close a file in the hardware/software file mapping table.
//
void
STDIO_SERVER_CLASS::closeFile(UINT8 idx)
{
    if (idx <= 2) return;

    FILE *f = fileTable[idx];
    VERIFY(f != NULL, "Operation on unopened file handle (" << UINT32(idx) << ")");

    if (fileIsPipe[idx])
    {
        pclose(f);
    }
    else
    {
        fclose(f);
    }

    fileTable[idx] = NULL;
}


//
// getFile --
//     Convert a hardware file index to system FILE pointer.
//
FILE *
STDIO_SERVER_CLASS::getFile(UINT8 idx)
{
    FILE *f = fileTable[idx];
    VERIFY(f != NULL, "Operation on unopened file handle (" << UINT32(idx) << ")");

    return f;
}


//
// Req --
//     Receive a request chunk from hardware.
//
void
STDIO_SERVER_CLASS::Req(UINT64 data, UINT8 eom)
{
    VERIFYX((reqBufferWriteIdx + 1) < (sizeof(reqBuffer) / sizeof(reqBuffer[0])));

    // Data arrives as a pair of 32 bit values combined into a 64 bit chunk
    reqBuffer[reqBufferWriteIdx++] = data;
    reqBuffer[reqBufferWriteIdx++] = data >> 32;

    if (eom)
    {
        VERIFY(reqBufferWriteIdx > 1, "STDIO service received partial request");

        // Decode the header
        UINT32 header = reqBuffer[0];

        STDIO_REQ_HEADER req;
        req.command = STDIO_REQ_COMMAND(reqBuffer[0] & 255);
        req.fileHandle = (header >> 8) & 255;
        req.clientID = STDIO_CLIENT_ID((reqBuffer[0] >> 16) & 255);
        req.dataSize = (header >> 24) & 3;
        req.numData = (header >> 26) & 15;
        req.text = reqBuffer[1];
            
        switch (req.command)
        {
          case STDIO_REQ_FCLOSE:
            Req_fclose(req);
            break;

          case STDIO_REQ_FFLUSH:
            Req_fflush(req);
            break;

          case STDIO_REQ_FOPEN:
            Req_fopen(req, reqBuffer[2]);
            break;

          case STDIO_REQ_FPRINTF:
          case STDIO_REQ_SPRINTF:
            Req_printf(req, &reqBuffer[2]);
            break;

          case STDIO_REQ_FREAD:
            Req_fread(req);
            break;

          case STDIO_REQ_FWRITE:
            Req_fwrite(req, &reqBuffer[2]);
            break;

          case STDIO_REQ_PCLOSE:
            Req_pclose(req);
            break;

          case STDIO_REQ_POPEN:
            Req_popen(req);
            break;

          case STDIO_REQ_REWIND:
            Req_rewind(req);
            break;

          case STDIO_REQ_STRING_DELETE:
            Req_string_delete(req);
            break;

          case STDIO_REQ_SYNC:
            Req_sync(req, false);
            break;

          case STDIO_REQ_SYNC_SYSTEM:
            Req_sync(req, true);
            break;

          default:
            ASIMERROR("Undefined STDIO service command (" << UINT32(req.command) << ")");
            break;
        }

        reqBufferWriteIdx = 0;
    }
}

void
STDIO_SERVER_CLASS::Req_fopen(
    const STDIO_REQ_HEADER &req,
    GLOBAL_STRING_UID mode)
{
    const string* file_name = GLOBAL_STRINGS::Lookup(req.text);
    const string* file_mode = GLOBAL_STRINGS::Lookup(mode);

    UINT32 file_handle = openFile(file_name->c_str(), file_mode->c_str(), false);
    clientStub->Rsp(req.clientID, STDIO_RSP_FOPEN, 0, file_handle);
}

void
STDIO_SERVER_CLASS::Req_fclose(const STDIO_REQ_HEADER &req)
{
    closeFile(req.fileHandle);
}

void
STDIO_SERVER_CLASS::Req_popen(const STDIO_REQ_HEADER &req)
{
    const string* file_name = GLOBAL_STRINGS::Lookup(req.text);
    // Mode is encoded in the fileHandle field
    const char *mode = (req.fileHandle ? "r" : "w");

    UINT32 file_handle = openFile(file_name->c_str(), mode, true);
    clientStub->Rsp(req.clientID, STDIO_RSP_POPEN, 0, file_handle);
}

void
STDIO_SERVER_CLASS::Req_pclose(const STDIO_REQ_HEADER &req)
{
    closeFile(req.fileHandle);
}

void
STDIO_SERVER_CLASS::Req_fread(const STDIO_REQ_HEADER &req)
{
    static bool foo = false;
    MemBarrier();
    ASSERTX(! foo);
    foo = true;
    MemBarrier();

    FILE *ifile = getFile(req.fileHandle);

    // Number of elements to read is stored in text field
    size_t n_elem_req = req.text;

    static UINT32 buf[128];

    // Compute element size (bytes)
    const size_t elem_n_bytes = 1 << req.dataSize;
    const size_t marshalled_elem_per_msg = sizeof(buf[0]) / elem_n_bytes;

    const size_t max_elem_per_read = sizeof(buf) / elem_n_bytes;

    VERIFY(n_elem_req != 0, "Illegal (0 size) STDIO fread request");

    while (n_elem_req != 0)
    {
        size_t n = fread(buf,
                         elem_n_bytes,
                         min(n_elem_req, max_elem_per_read),
                         ifile);

        if (n)
        {
            if (marshalled_elem_per_msg == 0)
            {
                //
                // 64 bit reads use a special RRR service to send the value in
                // a single message.
                //
                for (size_t i = 0; i < n; i += 1)
                {
                    // End of response?  Bit 2 in metadata indicates the end.
                    UINT8 meta = 0;
                    if (--n_elem_req == 0) meta = 4;

                    UINT64* val_p = (UINT64*)&buf[i * 2];
                    clientStub->Rsp64(req.clientID, STDIO_RSP_FREAD, meta, *val_p);
                }
            }
            else
            {
                //
                // All other sizes pack one or more elements in each marshalled
                // message.
                //
                size_t i = 0;
                while (n)
                {
                    size_t remaining;
                    UINT8 meta = marshalled_elem_per_msg - 1;
                    if (n < marshalled_elem_per_msg)
                    {
                        // Short flit?
                        meta = n - 1;
                        remaining = n_elem_req - n;
                        n = 0;
                    }
                    else
                    {
                        // Full flit
                        remaining = n_elem_req - marshalled_elem_per_msg;
                        n -= marshalled_elem_per_msg;
                    }

                    if (remaining == 0)
                    {
                        // End of response?
                        meta |= 4;
                    }

                    clientStub->Rsp(req.clientID, STDIO_RSP_FREAD, meta, buf[i++]);
                    n_elem_req = remaining;
                }
            }
        }
        else
        {
            // End of file!
            clientStub->Rsp(req.clientID, STDIO_RSP_FREAD_EOF, 0, 0);
            n_elem_req = 0;

            if (! feof(ifile) && ferror(ifile))
            {
                ASIMERROR("Error (" << errno << ") in STDIO fread, file descriptor " << req.fileHandle);
            }
        }
    }

    MemBarrier();
    foo = false;
    MemBarrier();
}

void
STDIO_SERVER_CLASS::Req_fwrite(const STDIO_REQ_HEADER &req, const UINT32 *data)
{
    FILE *ofile = getFile(req.fileHandle);
    size_t n_written = fwrite(data,
                              1 << req.dataSize,
                              req.numData,
                              ofile);
    VERIFY(n_written == req.numData, "Write error, file " << req.fileHandle);
}

//
// Req_printf --
//     Handles printf, fprintf and sprintf.
//
void
STDIO_SERVER_CLASS::Req_printf(const STDIO_REQ_HEADER &req, const UINT32 *data)
{
    const string* str = GLOBAL_STRINGS::Lookup(req.text);

    UINT64 ar[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };

    if (req.dataSize == 0)
    {
        // Bytes
        UINT8* src = (UINT8*)data;
        for (int i = 0; i < req.numData; i++) ar[i] = *src++;
    }
    else if (req.dataSize == 1)
    {
        // UINT16's
        UINT16* src = (UINT16*)data;
        for (int i = 0; i < req.numData; i++) ar[i] = *src++;
    }
    else if (req.dataSize == 2)
    {
        // UINT32's
        UINT32* src = (UINT32*)data;
        for (int i = 0; i < req.numData; i++) ar[i] = *src++;
    }
    else
    {
        // UINT64's
        UINT64* src = (UINT64*)data;
        for (int i = 0; i < req.numData; i++) ar[i] = *src++;
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
                           "STDIO service: failed to find string global string " << ar[fmt_idx] << " position " << fmt_idx+1 << " format string: " << *str);

                    ar[fmt_idx] = (UINT64)arg_str->c_str();
                }
            }
        }

        pos += 1;
        fmt_idx += 1;
    }

    if (req.command == STDIO_REQ_FPRINTF)
    {
        FILE *ofile = getFile(req.fileHandle);
        fprintf(ofile, str->c_str(), ar[0], ar[1], ar[2], ar[3], ar[4], ar[5], ar[6], ar[7], ar[8]);
    }
    else
    {
        char obuf[1024];
        snprintf(obuf, sizeof(obuf), str->c_str(), ar[0], ar[1], ar[2], ar[3], ar[4], ar[5], ar[6], ar[7], ar[8]);

        GLOBAL_STRING_UID uid = GLOBAL_STRINGS::AddString(obuf);
        clientStub->Rsp(req.clientID, STDIO_RSP_SPRINTF, 0, uid);
    }
}


//
// Req_string_delete --
//     Deallocate a dynamically allocated global string (e.g. by sprintf).
//
void
STDIO_SERVER_CLASS::Req_string_delete(const STDIO_REQ_HEADER &req)
{
    GLOBAL_STRINGS::DeleteString(req.text);
}


void
STDIO_SERVER_CLASS::Req_fflush(const STDIO_REQ_HEADER &req)
{
    FILE *ofile = getFile(req.fileHandle);
    fflush(ofile);
}

void
STDIO_SERVER_CLASS::Req_rewind(const STDIO_REQ_HEADER &req)
{
    FILE *ofile = getFile(req.fileHandle);
    rewind(ofile);
}


//
// Req_sync --
//    Both call system sync() and respond to hardware that all commands have
//    been received.
//
void
STDIO_SERVER_CLASS::Req_sync(const STDIO_REQ_HEADER &req, bool isSystemSync)
{
    sync();

    clientStub->Rsp(req.clientID,
                    isSystemSync ? STDIO_RSP_SYNC_SYSTEM : STDIO_RSP_SYNC,
                    0, 0);
}
