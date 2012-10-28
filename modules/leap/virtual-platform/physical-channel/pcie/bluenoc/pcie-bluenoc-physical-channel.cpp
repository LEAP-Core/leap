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

#include "awb/provides/physical_channel.h"

using namespace std;

PHYSICAL_CHANNEL_CLASS::PHYSICAL_CHANNEL_CLASS(
    PLATFORMS_MODULE p,
    PHYSICAL_DEVICES d) :
    PLATFORMS_MODULE_CLASS(p)
{
    pcieDev = new PCIE_DEVICE_CLASS(p);
}


// destructor
PHYSICAL_CHANNEL_CLASS::~PHYSICAL_CHANNEL_CLASS()
{
    delete pcieDev;
}


void
PHYSICAL_CHANNEL_CLASS::Init()
{
}


//
// Blocking read
//
UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::Read()
{
    UMF_MESSAGE msg = new UMF_MESSAGE_CLASS();

    msg->DecodeHeader(pcieDev->Read());

    while (msg->CanAppend())
    {
        msg->AppendChunk(pcieDev->Read());
    }

    return msg;
}


//
// Non-blocking read
//
UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::TryRead()
{
    if (pcieDev->Probe())
    {
        return Read();
    }
    else
    {
        return NULL;
    }
};


void
PHYSICAL_CHANNEL_CLASS::Write(UMF_MESSAGE msg)
{
    pcieDev->Write(msg->EncodeHeader());

    // write message data to pipe
    // NOTE: hardware demarshaller expects chunk pattern to start from most
    //       significant chunk and end at least significant chunk, so we will
    //       send chunks in reverse order
    msg->StartReverseExtract();
    while (msg->CanReverseExtract()){
        UMF_CHUNK chunk = msg->ReverseExtractChunk();
        pcieDev->Write(chunk);
    }

    // Write() method is expected to delete the chunk
    delete msg;
}
