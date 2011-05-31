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

//
// @file params-controller-hybrid.h
// @brief Pass dynamic parameters to the hardware side
//
// @author Michael Adler
//

#ifndef _PARAMS_CONTROLLER_
#define _PARAMS_CONTROLLER_

#include <stdio.h>

#include "platforms-module.h"
#include "awb/provides/rrr.h"
#include "awb/rrr/client_stub_PARAMS.h"

// PARAMS_CONTROLLER has no RRR server functionalities. Why then is the code
// structured like an RRR server (with self-instantiation etc.)? FIXME

typedef class PARAMS_SERVER_CLASS* PARAMS_SERVER;

class PARAMS_SERVER_CLASS: public RRR_SERVER_CLASS,
                           public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static PARAMS_SERVER_CLASS instance;

    // stubs
    PARAMS_CLIENT_STUB clientStub;

  public:
    PARAMS_SERVER_CLASS();
    ~PARAMS_SERVER_CLASS();

    // static methods
    static PARAMS_SERVER GetInstance() { return &instance; }

    // Send dynamic parameters to hardware
    void SendAllParams();

    // required RRR service methods
    void Init(PLATFORMS_MODULE);
    void Uninit();
    void Cleanup();
};

// PARAMS_CONTROLLER functionalities are completely implemented by the PARAMS_SERVER class
typedef PARAMS_SERVER_CLASS PARAMS_CONTROLLER_CLASS;

#endif
