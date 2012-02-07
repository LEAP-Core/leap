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
// @file hello.cpp
// @brief Raw Application
//
// @author Angshuman Parashar
//

#include "awb/provides/connected_application.h"

using namespace std;

// constructor
CONNECTED_APPLICATION_CLASS::CONNECTED_APPLICATION_CLASS(VIRTUAL_PLATFORM vp)
{
}

// destructor
CONNECTED_APPLICATION_CLASS::~CONNECTED_APPLICATION_CLASS()
{
}

// init
void
CONNECTED_APPLICATION_CLASS::Init()
{
    return;
}

// main
void
CONNECTED_APPLICATION_CLASS::Main()
{
    // Print a message
    cout << "Hello, World! This is software speaking." << endl;
    // Wait for the hardware to exit. If it is done before us
    // this will just instantly return.
    STARTER_DEVICE_CLASS::GetInstance()->WaitForHardware();
    return;
}
