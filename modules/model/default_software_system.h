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

#ifndef __SYSTEM__
#define __SYSTEM__

#include <stdio.h>
#include <pthread.h>

#include "platforms-module.h"
#include "asim/provides/low_level_platform_interface.h"

typedef class SYSTEM_CLASS* SYSTEM;
class SYSTEM_CLASS
{
  private:
    pthread_mutex_t lock;
    pthread_cond_t  cond;

  public:
    SYSTEM_CLASS()
    {
        pthread_mutex_init(&lock, NULL);
        pthread_cond_init(&cond, NULL);
    }

    virtual void Main()
    {
        return;
    }
};

#endif
