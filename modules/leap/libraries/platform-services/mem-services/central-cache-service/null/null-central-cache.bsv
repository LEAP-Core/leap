//
// Copyright (C) 2009 Intel Corporation
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
// NULL implementation of a central cache.  The NULL version still implements
// full central cache semantics by routing incoming requests to the backing
// storage.  Without a cache all requests are routed to backing storage.
//


import FIFO::*;
import FIFOF::*;
import Vector::*;


`include "awb/provides/central_cache_common.bsh"


module mkCentralCache
    // interface:
    (CENTRAL_CACHE_IFC);

    let cc <- mkBypassCentralCache();
    return cc;

endmodule
