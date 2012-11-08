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

#include "awb/provides/umf.h"
#include "awb/provides/pcie_device.h"
#include "awb/provides/physical_platform.h"

// ============================================
//               Physical Channel              
// ============================================

class PHYSICAL_CHANNEL_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:
    static const int bufMaxChunks = 65536 / sizeof(UMF_CHUNK);

    // links to useful physical devices
    PCIE_DEVICE pcieDev;

    UMF_CHUNK* outBuf;

    UMF_CHUNK* inBuf;
    UINT32 inBufCurIdx;
    UINT32 inBufLastIdx;

    // Internal implementation of Read() / TryRead()
    UMF_MESSAGE DoRead(bool tryRead);

    // Read up to nChunks from the PCIe device, returning a pointer to the
    // chunks.  nChunks is updated with the actual number read.
    UMF_CHUNK* ReadChunks(UINT32* nChunks);

    UINT32 BlueNoCHeader(UINT8 dst, UINT8 src, UINT8 msgBytes, UINT8 flags);

  public:

    PHYSICAL_CHANNEL_CLASS(PLATFORMS_MODULE, PHYSICAL_DEVICES);
    ~PHYSICAL_CHANNEL_CLASS();

    void Init();

    // blocking read
    UMF_MESSAGE Read() { return DoRead(false); }
    // non-blocking read
    UMF_MESSAGE TryRead();
    // write
    void        Write(UMF_MESSAGE);
};

#endif
