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

#ifndef __PHYSICAL_CHANNEL__
#define __PHYSICAL_CHANNEL__

#include <stdio.h>
#include <pthread.h>

#include "tbb/concurrent_queue.h"

#include "awb/provides/umf.h"
#include "awb/provides/pcie_device.h"

// ============================================
//               Physical Channel              
// ============================================

typedef class PHYSICAL_CHANNEL_CLASS* PHYSICAL_CHANNEL;

class PHYSICAL_CHANNEL_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:


    // Size of an I/O buffer (in UMF_CHUNKS)
    static const int bufMaxChunks = 65536 / sizeof(UMF_CHUNK);
    // Number of buffers in the read buffer pool
    static const int nInBufs = 4;

    bool initialized;

    PCIE_DEVICE pcieDev;

    pthread_mutex_t readLock;
    bool tryReadHoldingLock;

    UMF_FACTORY umfFactory;

    UMF_CHUNK* outBuf;

    UMF_CHUNK* inBuf;
    UINT32 inBufCurIdx;
    UINT32 inBufLastIdx;
    // inBufPool needed only for clean deallocation of the input buffers
    UMF_CHUNK* inBufPool[nInBufs];

    UMF_CHUNK* debugBuf;

    // Internal implementation of Read() / TryRead()
    UMF_MESSAGE DoRead(bool tryRead);

    // Read up to nChunks from the PCIe device, returning a pointer to the
    // chunks.  nChunks is updated with the actual number read.
    UMF_CHUNK* ReadChunks(UINT32* nChunks);

    UINT32 BlueNoCHeader(UINT8 dst, UINT8 src, UINT8 msgBytes, UINT8 flags);

    // Internal buffer state passed from reader thread to consumers
    typedef struct
    {
        UMF_CHUNK* buf;
        UINT32 nChunks;
    }
    PHYSICAL_CHANNEL_READ_BUF;

    //
    // Read (FPGA -> host) queue
    //
    friend void* BNReadThread(void* argv);
    void ReadThread();
    pthread_t readThreadID;
    class tbb::concurrent_queue<PHYSICAL_CHANNEL_READ_BUF> readQueue;
    class tbb::concurrent_queue<UMF_CHUNK*> readEmptyBufQueue;

    //
    // Write (host -> FPGA) queue
    //
    friend void* BNWriteThread(void* argv);
    void WriteThread();
    void WriteFlush();
    pthread_t writeThreadID;
    class tbb::concurrent_bounded_queue<UMF_MESSAGE> writeQueue;
    UMF_CHUNK* wrNext;
    UMF_CHUNK* wrLastBNHeader;

    // Debug support
    void Debug();
    void DebugDump(UINT64 packet);
    void ScanHistory();
    FILE *scanFile;

  public:

    PHYSICAL_CHANNEL_CLASS(PLATFORMS_MODULE);
    ~PHYSICAL_CHANNEL_CLASS();

    void Init();

    // blocking read
    UMF_MESSAGE Read() 
    { 
        UMF_MESSAGE msg = NULL; 
	msg = TryRead();                       
        while (msg == NULL) 
	{
            msg = TryRead();                       
	}

        return msg;
    }

    /*
bool
PCIE_DEVICE_CLASS::Probe(bool block)
{
    struct pollfd pcie_poll;
    pcie_poll.fd = pcieDev;
    pcie_poll.events = POLLIN | POLLPRI;

    int result = poll(&pcie_poll, 1, block ? -1 : 0);
    return (result > 0);
}

     */

    // non-blocking read
    UMF_MESSAGE TryRead();

    void Write(UMF_MESSAGE msg) {writeQueue.push(msg); }
    class tbb::concurrent_bounded_queue<UMF_MESSAGE> *GetWriteQ() { return &writeQueue; }
    void SetUMFFactory(UMF_FACTORY factoryInit) { umfFactory = factoryInit; };
};

#endif
