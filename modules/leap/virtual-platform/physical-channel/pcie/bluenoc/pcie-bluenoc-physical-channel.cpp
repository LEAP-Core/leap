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

#include "asim/syntax.h"
#include "awb/provides/physical_channel.h"

using namespace std;

PHYSICAL_CHANNEL_CLASS::PHYSICAL_CHANNEL_CLASS(
    PLATFORMS_MODULE p,
    PHYSICAL_DEVICES d) :
    PLATFORMS_MODULE_CLASS(p)
{
    if (posix_memalign((void**)&outBuf, 128, sizeof(UMF_CHUNK) * bufMaxChunks) != 0 ||
		posix_memalign((void**)&inBuf, 128, sizeof(UMF_CHUNK) * bufMaxChunks) != 0 ||
		posix_memalign((void**)&debugBuf, 128, sizeof(UMF_CHUNK) * 32) != 0)
    {
		fprintf (stderr, "PCIe Device: Failed to memalign I/O buffers: %s\n", strerror(errno));
		exit(EXIT_FAILURE);
	}

    inBufCurIdx = 0;
    inBufLastIdx = 0;

    pcieDev = new PCIE_DEVICE_CLASS(p);
}


// destructor
PHYSICAL_CHANNEL_CLASS::~PHYSICAL_CHANNEL_CLASS()
{
    delete pcieDev;
    free(outBuf);
    free(inBuf);
    free(debugBuf);
}


void
PHYSICAL_CHANNEL_CLASS::Init()
{
    static bool initialized = false;
    if (initialized) return;
    initialized = true;

    pcieDev->Init();

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
}


//
// Handle read
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
    UMF_MESSAGE msg = new UMF_MESSAGE_CLASS();
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
// Non-blocking read
//
UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::TryRead()
{
    if ((inBufCurIdx != inBufLastIdx) || pcieDev->Probe())
    {
        return DoRead(true);
    }
    else
    {
        return NULL;
    }
};


void
PHYSICAL_CHANNEL_CLASS::Write(UMF_MESSAGE msg)
{
    UMF_CHUNK* last_bn_header = NULL;

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
    
    UMF_CHUNK* op = outBuf;
    UMF_CHUNK* op_end = &outBuf[bufMaxChunks];
    
    last_bn_header = op;
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
            last_bn_header = op;
            *op++ = BlueNoCHeader(4,
                                  0,
                                  bn_header_payload_bytes +
                                  bn_chunks * sizeof(UMF_CHUNK),
                                  0x80);
        }
    }

    ASSERTX(umf_chunks == 0);
    ASSERTX(msg->GetReadIndex() == 0);

    // Set the don't wait (send immediately) flag in the last BlueNoC header
    *last_bn_header |= 0x01000000;

    // Emit the message
    pcieDev->Write(outBuf, (op - outBuf) * sizeof(outBuf[0]));

    // Write() method is expected to delete the chunk
    delete msg;
}


//
// ReadChunks --
//   Read up to nChunks from the PCIe device.  Reads are buffered in large
//   requests in order to optimize PCIe throughput.
//
UMF_CHUNK*
PHYSICAL_CHANNEL_CLASS::ReadChunks(UINT32 *nChunks)
{
    //
    // Is the current read buffer empty?  If so, fill it.
    //
    if (inBufCurIdx == inBufLastIdx)
    {
        UINT32 n_bytes_read = pcieDev->Read(inBuf, sizeof(UMF_CHUNK) * bufMaxChunks);
        ASSERTX(n_bytes_read >= sizeof(UMF_CHUNK));

        inBufCurIdx = 0;
        inBufLastIdx = n_bytes_read / sizeof(UMF_CHUNK);
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
    cout << "PCIe BlueNoC Debug Scan:" << endl
         << "  fromHostSyncQ.notFull: " << ((packet >> 32) & 1) << endl
         << "  toHostCountedQ.count:  " << ((packet >> 40) & 0xff) << endl
         << "  remChunksOut:          " << ((packet >> 48) & 0xffff) << endl;
}
