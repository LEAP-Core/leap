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

#include <stdio.h>

#include "tbb/atomic.h"

#include "awb/provides/low_level_platform_interface.h"
#include "awb/provides/rrr.h"

// this module handles reporting assertion failures.

typedef class ASSERTIONS_SERVER_CLASS* ASSERTIONS_SERVER;
class ASSERTIONS_SERVER_CLASS: public RRR_SERVER_CLASS,
                     public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static ASSERTIONS_SERVER_CLASS instance;
    
    // stubs
    RRR_SERVER_STUB serverStub;

    class tbb::atomic<bool> uninitialized;

    // File for output until we use DRAL.
    FILE* assertionsFile;

  public:
    ASSERTIONS_SERVER_CLASS();
    ~ASSERTIONS_SERVER_CLASS();
    
    // static methods
    static ASSERTIONS_SERVER GetInstance() { return &instance; }
    
    // required RRR methods
    void Init(PLATFORMS_MODULE);
    void Uninit();
    void Cleanup();

    // RRR service methods
    void AssertStr(UINT64 fpgaCC, UINT32 strUID, UINT8 severity);
    void AssertDict(UINT64 fpgaCC, UINT32 assertBase, UINT32 assertions);
};

// server stub
#include "awb/rrr/server_stub_ASSERTIONS.h"

// all functionalities of the assertions io are completely implemented
// by the ASSERTIONS_SERVER class
typedef ASSERTIONS_SERVER_CLASS ASSERTIONS_DEVICE_CLASS;
