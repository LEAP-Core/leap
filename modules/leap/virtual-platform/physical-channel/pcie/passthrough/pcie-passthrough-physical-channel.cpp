//
// Copyright (C) 2010 Intel Corporation
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

////////////////////////////////////////////////////////////////////////////////
// Filename      : pcie-passthorugh-physical-channel.cpp
// Brief         : physical channel between channel IO and PCIe device
// Author        : rfadeev
// Mailto        : roman.fadeev@intel.com

////////////////////////////////////////////////////////////////////////////////
// Description   : IMPORTANT! It's just stub for correct hasim model build flow
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Notes :
// Revision history :
////////////////////////////////////////////////////////////////////////////////

#include <stdio.h>
#include <unistd.h>
#include <strings.h>
#include <assert.h>
#include <stdlib.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/signal.h>
#include <sys/ioctl.h>
#include <signal.h>
#include <string.h>
#include <iostream>
#include <termios.h>
#include <errno.h>
#include <fcntl.h>

#include "asim/provides/physical_channel.h"
#include "asim/provides/umf.h"

using namespace std;

PHYSICAL_CHANNEL_CLASS::PHYSICAL_CHANNEL_CLASS(
    PLATFORMS_MODULE p,
    PHYSICAL_DEVICES d) :
    PLATFORMS_MODULE_CLASS(p)
{
}

// destructor
PHYSICAL_CHANNEL_CLASS::~PHYSICAL_CHANNEL_CLASS()
{
}

UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::Read()
{
  return NULL;
}

// non-blocking read
UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::TryRead()
{
  return NULL;
}

// write
void
PHYSICAL_CHANNEL_CLASS::Write(UMF_MESSAGE message)
{
}
