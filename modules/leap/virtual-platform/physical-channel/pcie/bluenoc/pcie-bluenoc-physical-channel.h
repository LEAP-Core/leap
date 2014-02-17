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


#ifndef __PCIE_PHYSICAL_CHANNEL__
#define __PCIE_PHYSICAL_CHANNEL__

#include <stdio.h>
#include <pthread.h>

#include "tbb/concurrent_queue.h"
#include "awb/provides/physical_platform_utils.h"
#include "awb/provides/umf.h"
#include "awb/provides/pcie_device.h"

// ============================================
//               Physical Channel              
// ============================================

typedef class PCIE_BLUENOC_PHYSICAL_CHANNEL_CLASS* PCIE_BLUENOC_PHYSICAL_CHANNEL;

class PCIE_BLUENOC_PHYSICAL_CHANNEL_CLASS: public PHYSICAL_CHANNEL_CLASS
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

    PCIE_BLUENOC_PHYSICAL_CHANNEL_CLASS(PLATFORMS_MODULE);
    ~PCIE_BLUENOC_PHYSICAL_CHANNEL_CLASS();

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
    void RegisterLogicalDeviceName(string name) { pcieDev->RegisterLogicalDeviceName(name); }
};

#endif
