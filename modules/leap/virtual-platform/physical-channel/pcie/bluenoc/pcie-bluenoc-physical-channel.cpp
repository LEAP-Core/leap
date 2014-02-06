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

#include <unistd.h>
#include <stdio.h>

#include "asim/syntax.h"
#include "asim/atomic.h"
#include "awb/provides/physical_channel.h"

using namespace std;

void* BNReadThread(void *argv);
void* BNWriteThread(void *argv);


PHYSICAL_CHANNEL_CLASS::PHYSICAL_CHANNEL_CLASS(
    PLATFORMS_MODULE p) :
    PLATFORMS_MODULE_CLASS(p)
{
    initialized = false;

    umfFactory = new UMF_FACTORY_CLASS();

    //
    // Allocate some page-aligned I/O buffers.
    //
    int psize = getpagesize();
    if (posix_memalign((void**)&outBuf, psize, sizeof(UMF_CHUNK) * bufMaxChunks) != 0 ||
		posix_memalign((void**)&debugBuf, psize, sizeof(UMF_CHUNK) * 32) != 0)
    {
		fprintf (stderr, "PCIe Device: Failed to memalign I/O buffers: %s\n", strerror(errno));
		exit(EXIT_FAILURE);
	}

    //
    // Allocate the pool of read (FPGA -> host) I/O buffers.  These buffers
    // will be filled by the read thread and passed, full, through the
    // readQueue.  Empty (drained) buffers are returned to the read thread
    // through readEmptyBufQueue.
    //
    for (int n = 0; n < nInBufs; n++)
    {
        UMF_CHUNK* buf;
        if (posix_memalign((void**)&buf, psize, sizeof(UMF_CHUNK) * bufMaxChunks) != 0)
        {
            fprintf (stderr, "PCIe Device: Failed to memalign I/O buffers: %s\n", strerror(errno));
            exit(EXIT_FAILURE);
        }

        inBufPool[n] = buf;
        if (n == 0)
            inBuf = buf;
        else
            readEmptyBufQueue.push(buf);
    }

    inBufCurIdx = 0;
    inBufLastIdx = 0;

    pthread_mutex_init(&readLock, NULL);
    tryReadHoldingLock = false;

    scanFile = NULL;

    pcieDev = new PCIE_DEVICE_CLASS(p);
    // this check is non-sensical: the pcie device is not opened until init time.
    VERIFY(pcieDev != NULL, "Failed to open BlueNoC PCIe device");
}


// destructor
PHYSICAL_CHANNEL_CLASS::~PHYSICAL_CHANNEL_CLASS()
{
    delete pcieDev;

    if (initialized)
    {
        // Stop I/O threads
        pthread_cancel(readThreadID);
        pthread_cancel(writeThreadID);
        pthread_join(readThreadID, NULL);
        pthread_join(writeThreadID, NULL);
    }

    // Free I/O buffers
    free(outBuf);
    free(debugBuf);
    for (int n = 0; n < nInBufs; n++)
    {
        free(inBufPool[n]);
    }
}


void
PHYSICAL_CHANNEL_CLASS::Init()
{
    if (initialized) return;
    initialized = true;

    // It is possible that the PCIE device is unbounded. If so,
    // initialization will fail, and we should not spawn threads. 
    if (!pcieDev->Init())
    {
        initialized = false;
        return;
    }

    VERIFY(UMF_CHUNK_BYTES >= 8, "Expected at least 8-byte UMF chunks!");
    VERIFY(pcieDev->BytesPerBeat() == UMF_CHUNK_BYTES, "BlueNoc beat size must equal UMF chunk size!");

    //
    // A single beat packet from host to FPGA initializes the channel.
    //
    // The maximum inactivity timeout for FPGA to host packets is set here,
    // since dynamic parameters can't be passed until the channel is up.
    //
    // Bit 32 of the setup message indicates whether the FPGA must guarantee
    // that an entire BlueNoC packet is ready before attempting to transmit
    // it (1).  Setting (0) may decrease latency by a few cycles though
    // it can lead to host OS deadlocks.  The setting does not affect maximum
    // throughput and, in practice, appears to have no measurable effect
    // on latency.
    //
    outBuf[0] = (UMF_CHUNK(BLUENOC_TIMEOUT_CYCLES) << 33) |
                (UMF_CHUNK(1) << 32) |
                BlueNoCHeader(4, 0, 4, 1);
    VERIFY(BLUENOC_TIMEOUT_CYCLES < 2048, "BLUENOC_TIMEOUT_CYCLES must be < 2048");
    pcieDev->Write(outBuf, UMF_CHUNK_BYTES);

    //
    // Start the I/O threads.
    //

    if (pthread_create(&readThreadID, NULL, BNReadThread, (void*)this) != 0)
    {
        perror("PCIe BlueNoC readThread pthread_create");
        exit(1);
    }

    if (pthread_create(&writeThreadID, NULL, BNWriteThread, (void*)this) != 0)
    {
        perror("PCIe BlueNoC writeThread pthread_create");
        exit(1);
    }
}


//
// Handle read.
//
// No locks are required here because the Channel I/O layer above provides
// locks to guarantee that only one instance of Read and TryRead is active.
// 
UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::DoRead(bool tryRead)
{
    UINT32 n_bn_bytes_left;
    UINT64 header;
    UINT32 n_beats;

    do
    {
        // Both the BlueNoC header and the UMF header are stored in the same
        // beat.  The BlueNoC header is bits 0-31.
        n_beats = 1;
        header = *ReadChunks(&n_beats);

        // Messages from port 0xff are debug state.
        if ((header >> 8) & 0xff == 0xff)
        {
            DebugDump(header);
        }
        else
        {
            // Get the BlueNoC packet length from the BlueNoC header (bits 16-23)
            n_bn_bytes_left = (header >> 16) & 0xff;
      
        }

        // If the BlueNoC packet has no payload then it is a "flush" packet.
        // For flush packets we simply drop the BlueNoC packet and move on to
        // the next one.
        if (tryRead && (n_bn_bytes_left == 0))
        {
            // The BlueNoC flush packet may have looked like a message
            // is available when, in fact, one is not.  After the flush
            // packet return to TryRead and poll the socket again.
            return NULL;
        }
    }
    while (n_bn_bytes_left == 0);

    // Start parsing the UMF message
    UMF_MESSAGE msg = umfFactory->createUMFMessage();
    msg->DecodeHeader(header >> 32);
    // Subtract the payload bytes in the initial beat (header + padding)
    n_bn_bytes_left -= (UMF_CHUNK_BYTES - 4);
    
    // Collect the remainder of the UMF message
    while (msg->CanAppend())
    {
        // Starting a new BlueNoC packet?  The maximum BlueNoC packet size
        // is smaller than the maximum UMF message size, so we may see
        // multiple BlueNoC packets.
        while (n_bn_bytes_left == 0)
        {
            // Get the length of the new BlueNoC packet
            n_beats = 1;
            

            header = *ReadChunks(&n_beats);
            if ((header >> 8) & 0xff == 0xff)
            {
                DebugDump(header);
            }
            else
            {
                n_bn_bytes_left = (header >> 16) & 0xff;
            }

            //
            // If the number of bytes left in the new packet is 0 then it
            // was injected due to inactivity in the FPGA->host channel.
            // Just ignore it.  If non-zero, this is a continuation packet
            // of a larger UMF packet.
            //
            if (n_bn_bytes_left != 0)
            {
                // The payload of a continuation header has no data.
                n_bn_bytes_left -= (UMF_CHUNK_BYTES - 4);

                // The FPGA side sets the high bit of the header's flags to
                // indicate a continuation packet.  Confirm that the two sides
                // agree.
                ASSERTX(((header >> 31) & 1) == 1);
            }
        }

        // Try to read the remainder of the BlueNoC packet.  BlueNoC packets
        // always end at the end of a UMF message, so this is safe.
        n_beats = n_bn_bytes_left / UMF_CHUNK_BYTES;
        UMF_CHUNK* beats_in = ReadChunks(&n_beats);

        // Use whatever was returned
        msg->AppendChunks(n_beats, beats_in);
        n_bn_bytes_left -= (n_beats * UMF_CHUNK_BYTES);

    }

    return msg;
}


//
// Non-blocking read.
//
// No locks are required here because the Channel I/O layer above provides
// locks to guarantee that only one instance of Read and TryRead is active.
// 
//
UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::TryRead()
{
    UMF_MESSAGE msg = NULL;

    if ((inBufCurIdx != inBufLastIdx) || ! readQueue.empty())
    {
        msg = DoRead(true);
    }
    else if (tryReadHoldingLock)
    {
        // This thread is responsible for reading directly.  Is a message
        // ready?
        if (pcieDev->Probe())
        {
            msg = DoRead(true);
        }
    }
    else
    {
        // Nothing to read.  Take control from the reader thread and do the
        // read directly to avoid the cross-thread latency.
        if (pthread_mutex_trylock(&readLock) == 0)
        {
            // Did the reader thread add a buffer between the test and the lock?
            if (! readQueue.empty())
            {
                pthread_mutex_unlock(&readLock);
                msg = DoRead(true);
            }
            else
            {
                // The consumer has taken control of the next read.
                tryReadHoldingLock = true;
            }
        }
    }

    return msg;
};


//
// ReadChunks --
//   Read up to nChunks from the PCIe device.  Reads are buffered in large
//   requests in order to optimize PCIe throughput.
//
inline UMF_CHUNK*
PHYSICAL_CHANNEL_CLASS::ReadChunks(UINT32 *nChunks)
{
    //
    // Is the current read buffer empty?  If so, fill it.
    //
    if (inBufCurIdx == inBufLastIdx)
    {
        if (! tryReadHoldingLock)
        {
            // Return the old empty buffer to the reader thread
            readEmptyBufQueue.push(inBuf);

            // Get the next full buffer
            PHYSICAL_CHANNEL_READ_BUF r_buf;
            while (! readQueue.try_pop(r_buf)) CpuPause();

            inBuf = r_buf.buf;
            inBufLastIdx = r_buf.nChunks;
        }
        else
        {
            //
            // This thread is responsible for the next read.
            //
            UINT32 n_bytes_read = pcieDev->Read(inBuf, sizeof(UMF_CHUNK) *
                                                       bufMaxChunks);
            ASSERTX(n_bytes_read >= sizeof(UMF_CHUNK));

            inBufLastIdx = n_bytes_read / sizeof(UMF_CHUNK);

            // Reset the reader to multi-threaded mode
            tryReadHoldingLock = false;
            pthread_mutex_unlock(&readLock);
        }

        inBufCurIdx = 0;
    }

    UMF_CHUNK* in_data = &inBuf[inBufCurIdx];
    UINT32 n_read = min(inBufLastIdx - inBufCurIdx, *nChunks);
    
    inBufCurIdx += n_read;
    *nChunks = n_read;
    
    return in_data;
}


//
// BlueNoCHeader --
//   Generate the 4-byte BlueNoC header for a packet.
//
inline UINT32
PHYSICAL_CHANNEL_CLASS::BlueNoCHeader(
    UINT8 dst,
    UINT8 src,
    UINT8 msgBytes,
    UINT8 flags)
{
    return (flags << 24) | (msgBytes << 16) | (src << 8) | dst;
}

//
// Debug --
//   Request state of the channel.  This would work better as CSRs if
//   BlueNoC's bridge exposed some PCIe registers.
//
void
PHYSICAL_CHANNEL_CLASS::Debug()
{
    // Request state by sending an empty message to port 0xff.  The response
    // will come back in the message stream and will be detected by the
    // packet processing code above and emitted by DebugDump().
    debugBuf[0] = BlueNoCHeader(0xff, 0, 0, 1);
    pcieDev->Write(debugBuf, sizeof(UMF_CHUNK));
}

//
// DebugDump --
//   Called by the packet processing code when a debug scan packet is detected.
//
void
PHYSICAL_CHANNEL_CLASS::DebugDump(UINT64 packet)
{
    UINT64 len = (packet >> 16) & 0xff;

    if (len == 4)
    {
        // Request initiated by Debug()
        cout << "PCIe BlueNoC Debug Scan:" << endl
             << "  fromHostSyncQ.notFull: " << ((packet >> 32) & 1) << endl
             << "  toHostCountedQ.count:  " << ((packet >> 40) & 0xff) << endl
             << "  remChunksOut:          " << ((packet >> 48) & 0xffff) << endl;
    }
    else
    {
        // Request initiated by ScanHistory()
        VERIFYX(len == sizeof(UMF_CHUNK) * 2 - 4);

        // The index is stored in the header
        UINT64 idx = packet >> 32;

        // Get the payload beat with the history entry
        UINT32 n = 1;
        UMF_CHUNK value = *ReadChunks(&n);
        fprintf(scanFile, "[%05d] 0x%016llx:  0x%016llx 0x%016llx\n",
                idx, packet, UINT64(value >> 64), UINT64(value));
        fflush(scanFile);

        // Done indicated by setting high bit of flags in header
        if ((packet >> 31) & 1)
        {
            // Done
            fclose(scanFile);
            scanFile = NULL;
            printf("Finished scan.\n");
        }
    }
}


//
// ScanHistory --
//   Scan out channel history from hardware side.  Enabled by setting
//   AWB parameter BLUENOC_HISTORY_INDEX_BITS to a non-zero value.
//
void
PHYSICAL_CHANNEL_CLASS::ScanHistory()
{
    if (BLUENOC_HISTORY_INDEX_BITS == 0)
    {
        cerr << "Scan not enabled.  BLUENOC_HISTORY_INDEX_BITS is 0!" << endl;
        return;
    }

    printf("Starting scan...\n");
    scanFile = fopen("scan.out", "w");
    if (scanFile == NULL)
    {
        cerr << "Failed to open scan.out" << endl;
        return;
    }

    // Request history by sending a message to the debug port and setting
    // the high bit of the flags in the BlueNoC packet header.
    debugBuf[0] = BlueNoCHeader(0xff, 0, 4, 0x81);

    pcieDev->Write(debugBuf, sizeof(debugBuf[0]));

    // The responses will be deliverd to DebugDump().
}


// ========================================================================
//
//   Read thread (FPGA to host).  Fill raw BlueNoC buffers and pass them
//   to the host-side consumer.
//
//   Bursting the raw buffers into UMF_MESSAGEs hurts performance due
//   to cross-processor cache latency.  Performance is better when simply
//   passing raw buffers.
//
// ========================================================================

//
// BNReadThread --
//   Pthread entry point.  The class instance is passed as the argument.
//
void* BNReadThread(void* argv)
{
    int oldstate;
    pthread_setcanceltype(PTHREAD_CANCEL_ASYNCHRONOUS, &oldstate);
    pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, &oldstate);

    // Rejoin the PHYSICAL_CHANNEL_CLASS instance
    PHYSICAL_CHANNEL instance = PHYSICAL_CHANNEL(argv);
    instance->ReadThread();
    return NULL;
}

//
// ReadThread --
//   Read a BlueNoC stream pass buffers to the main reader thread(s).
//
void
PHYSICAL_CHANNEL_CLASS::ReadThread()
{
    while (true)
    {
        pthread_testcancel();

        if (pcieDev->Probe(true))
        {
            // Data available.  Get the read lock.  This read thread is
            // competing with the main consumer of the readQueue.  When
            // the main consumer has nothing to do it will try to read
            // from the FPGA directly to avoid the latency of messages
            // passing through this reader thread.
            pthread_mutex_lock(&readLock);
            
            // Is the message still available?
            if (pcieDev->Probe(false))
            {
                // Get an empty buffer, passed back after the consumer is done.
                UMF_CHUNK* buf;
                while (! readEmptyBufQueue.try_pop(buf)) CpuPause();

                // Fill a read buffer.
                UINT32 n_bytes_read = pcieDev->Read(buf, sizeof(UMF_CHUNK) *
                                                         bufMaxChunks);
                ASSERTX(n_bytes_read >= sizeof(UMF_CHUNK));

                // Pass full buffer to consumer
                PHYSICAL_CHANNEL_READ_BUF r_buf;
                r_buf.buf = buf;
                r_buf.nChunks = n_bytes_read / sizeof(UMF_CHUNK);
                readQueue.push(r_buf);
            }

            pthread_mutex_unlock(&readLock);
        }
    }
}


// ========================================================================
//
//   Write thread (host to FPGA).  Outbound messages are passed to this
//   thread, which manages writes to the FPGA.
//
// ========================================================================

//
// BNWriteThread --
//   Pthread entry point.  The class instance is passed as the argument.
//
void* BNWriteThread(void* argv)
{
    int oldstate;
    pthread_setcanceltype(PTHREAD_CANCEL_ASYNCHRONOUS, &oldstate);
    pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, &oldstate);

    // Rejoin the PHYSICAL_CHANNEL_CLASS instance
    PHYSICAL_CHANNEL instance = PHYSICAL_CHANNEL(argv);
    instance->WriteThread();
    return NULL;
}

//
// WriteThread --
//   Main working in host -> FPGA message passing.  Take a stream of
//   UMF_MESSAGEs and pass them to hardware.
//
void
PHYSICAL_CHANNEL_CLASS::WriteThread()
{
    wrNext = outBuf;
    wrLastBNHeader = outBuf;

    while (true)
    {
        pthread_testcancel();

        // Get the next message
        UMF_MESSAGE msg;
        if (wrNext == outBuf)
        {
            // Output buffer is currently empty.  Wait for the next message.
            while (! writeQueue.try_pop(msg)) CpuPause();
  
        }
        else
        {
            // Output buffer is not empty.  Wait for a short time for a new
            // message before flushing the buffer.  The overhead of the
            // DMA transfer to the FPGA makes waiting a short time to combine
            // writes more efficient.
            int trips = 0;
            bool have_msg = false;
            do
            {
                have_msg = writeQueue.try_pop(msg);
            }
            while (! have_msg && (trips++ < 50));

            if (! have_msg)
            {
                // No new message.  Flush the buffer and wait for a new message.
                WriteFlush();
                while (! writeQueue.try_pop(msg)) CpuPause();
            }
        }

        // Compute UMF chunks in the message (rouned up)
        UINT32 umf_chunks = (msg->GetLength() + UMF_CHUNK_BYTES - 1) / UMF_CHUNK_BYTES;

        // BlueNoC packets are limited to 255 bytes, which may be too short
        // for the full message.
        UINT32 bn_header_payload_bytes = UMF_CHUNK_BYTES - 4;
        UINT32 max_bn_chunks = 256 / UMF_CHUNK_BYTES - 1;
        UINT32 bn_chunks = min(umf_chunks, max_bn_chunks);

        // The first beat is the combination of the UMF and BlueNoC headers
        UMF_CHUNK umf_header = msg->EncodeHeader();

        ASSERTX(umf_header >> 32 == 0);

        UINT32 bn_header = BlueNoCHeader(4,
                                         0,
                                         bn_header_payload_bytes +
                                         bn_chunks * sizeof(UMF_CHUNK),
                                         0);
    
        UMF_CHUNK* op = wrNext;
        UMF_CHUNK* op_end = &outBuf[bufMaxChunks];
    
        wrLastBNHeader = op;
        *op++ = (umf_header << 32) | bn_header;

        // write message data to pipe
        // NOTE: hardware demarshaller expects chunk pattern to start from most
        //       significant chunk and end at least significant chunk, so we will
        //       send chunks in reverse order
        msg->StartReverseExtract();
        while (msg->CanReverseExtract())
        {
            VERIFYX(op + bn_chunks < op_end);
            msg->ReverseExtractChunks(bn_chunks, op);
            op += bn_chunks;
            umf_chunks -= bn_chunks;

            // Need to open a new BlueNoC packet?
            if (umf_chunks != 0)
            {
                // Does the remainder of the message fit in this BlueNoC packet?
                bn_chunks = min(umf_chunks, max_bn_chunks);

                // Send the header beat with the remainder of the beat empty.
                // This allows us to continue beat-aligning the UMF chunks.
                // The high bit set in the flags indicates a continuation header.
                VERIFYX(op < op_end);
                wrLastBNHeader = op;
                *op++ = BlueNoCHeader(4,
                                      0,
                                      bn_header_payload_bytes +
                                      bn_chunks * sizeof(UMF_CHUNK),
                                      0x80);
            }
        }

        VERIFYX(umf_chunks == 0);
        VERIFYX(msg->GetReadIndex() == 0);

        wrNext = op;

        // Write() method is expected to delete the chunk
        delete msg;

        if ((op_end - op) < (256 / sizeof(outBuf[0])))
        {
            // If there isn't enough buffer space left for a full BlueNoC
            // packet then flush the buffer.  Otherwise, wait for more
            // messages to merge into a single write.
            //
            WriteFlush();
        }
    }
}


//
// WriteFlush --
//   Flush the collection of buffered host to FPGA BlueNoC packets.
//
void
PHYSICAL_CHANNEL_CLASS::WriteFlush()
{
    size_t count = (wrNext - outBuf) * sizeof(outBuf[0]);
    if (count > 0)
    {
        // Set the don't wait (send immediately) flag in the last BlueNoC header
        *wrLastBNHeader |= 0x01000000;

        pcieDev->Write(outBuf, count);
    }

    wrNext = outBuf;
    wrLastBNHeader = outBuf;
}
