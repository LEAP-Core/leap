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


#include "awb/provides/common_services.h"
#include "awb/provides/dynamic_parameters_service.h"
#include "awb/provides/stats_service.h"

using namespace std;

// constructor
COMMON_SERVICES_CLASS::COMMON_SERVICES_CLASS() :
    dynamicParamsService(new DYNAMIC_PARAMS_SERVICE_CLASS())
{
}

// destructor
COMMON_SERVICES_CLASS::~COMMON_SERVICES_CLASS()
{
}

// init
void
COMMON_SERVICES_CLASS::Init()
{
    // Tell the dynamic parameters IO service to send all
    // parameters to the hardware.
    
    dynamicParamsService->SendAllParams();

    // Tell the stats device to setup itself.
    STATS_SERVER_CLASS::GetInstance()->SetupStats();
}
