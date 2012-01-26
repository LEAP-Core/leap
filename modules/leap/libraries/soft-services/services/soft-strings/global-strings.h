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

#ifndef __GLOBAL_STRINGS_H__
#define __GLOBAL_STRINGS_H__

#include <string>
#include <unordered_map>

#include "asim/syntax.h"
#include "awb/provides/command_switches.h"

using namespace std;

//
// Global strings are a method of passing strings between hardware and software
// using a unique token instead of passing entire strings.
//
// All methods within the class are static, since we have only a single instance
// of the global strings class.
//

#define GLOBAL_STRING_UID_SZ (GLOBAL_STRING_PLATFORM_UID_SZ + GLOBAL_STRING_SYNTH_UID_SZ + GLOBAL_STRING_LOCAL_UID_SZ)

typedef UINT32 GLOBAL_STRING_UID;


class GLOBAL_STRINGS : public COMMAND_SWITCH_STRING_CLASS
{
  private:
    static unordered_map <GLOBAL_STRING_UID, string> uidToString;

  public:
    GLOBAL_STRINGS();

    static const string* Lookup(GLOBAL_STRING_UID uid, bool abortIfUndef = true);

    static void AddString(GLOBAL_STRING_UID uid, const string& str);

    // Command line argument for passing the name of a string database.
    void ProcessSwitchString(const char *db);
};

#endif // __GLOBAL_STRINGS_H__
