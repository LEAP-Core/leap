//
// Copyright (C) 2008 Massachusetts Institute of Technology
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

import Vector::*;
import List::*;

//The interface of a module with Connections
interface WITH_CONNECTIONS#(parameter numeric type t_NUM_IN,
                            parameter numeric type t_NUM_OUT,
                            parameter numeric type t_NUM_IN_MULTI,
                            parameter numeric type t_NUM_OUT_MULTI);

  interface Vector#(t_NUM_IN, PHYSICAL_CONNECTION_IN)  incoming;
  interface Vector#(t_NUM_OUT, PHYSICAL_CONNECTION_OUT) outgoing;
  interface Vector#(t_NUM_IN, PHYSICAL_CONNECTION_IN_MULTI)  incomingMultis;
  interface Vector#(t_NUM_OUT, PHYSICAL_CONNECTION_OUT_MULTI) outgoingMultis;

  interface Vector#(CON_NUM_CHAINS, PHYSICAL_CHAIN) chains;

endinterface

// Backwards compatability:
typedef WITH_CONNECTIONS#(nI, nO, 0, 0) WithConnections#(parameter numeric type nI, parameter numeric type nO);


