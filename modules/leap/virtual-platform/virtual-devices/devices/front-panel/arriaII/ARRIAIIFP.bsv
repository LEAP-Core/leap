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

`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/led_device.bsh"

typedef 4 FRONTP_NUM_LEDS;
typedef 4 FRONTP_NUM_SWITCHES;
typedef 5 FRONTP_NUM_BUTTONS;

typedef Bit#(FRONTP_NUM_LEDS) FRONTP_LEDS;
typedef Bit#(FRONTP_NUM_SWITCHES) FRONTP_SWITCHES;
typedef Bit#(FRONTP_NUM_BUTTONS) FRONTP_BUTTONS;

typedef struct
{
    Bit#(1) bUp;
    Bit#(1) bDown;
    Bit#(1) bLeft;
    Bit#(1) bRight;
    Bit#(1) bCenter;
}
FRONTP_BUTTON_INFO
    deriving (Eq, Bits);

typedef Bit#(32) FRONTP_INPUT_STATE;


//
// Data structure for updating specific LEDs and leaving others unchanged.
//
typedef struct
{
    FRONTP_LEDS state;
    FRONTP_LEDS mask;
}
FRONTP_MASKED_LEDS deriving (Eq, Bits);

interface FrontPanel;
    method FRONTP_SWITCHES readSwitches();
    method FRONTP_BUTTONS  readButtons();
    method Action          writeLEDs(FRONTP_LEDS state, FRONTP_LEDS mask);
endinterface

typedef FrontPanel FRONT_PANEL;

module mkFrontPanel#(LowLevelPlatformInterface llpi) (FrontPanel);

   Reg#(FRONTP_LEDS) led_state <- mkReg(0);

   method FRONTP_SWITCHES readSwitches();
//       // read from toplevel wires
//       return (llpi.physicalDrivers.switchesDriver.getSwitches());
      return ?;
   endmethod
   
   method FRONTP_BUTTONS readButtons();
//    // read from toplevel wires
//       FRONTP_BUTTONS all_inputs = llpi.physicalDrivers.buttonsDriver.getButtons();
   
//       return all_inputs;
      return ?;
   endmethod

   method Action writeLEDs(FRONTP_LEDS state, FRONTP_LEDS mask);
      FRONTP_LEDS s = (led_state & ~mask) | (state & mask);
      led_state <= s;
      llpi.physicalDrivers.ledsDriver.setLEDs(~s); // arria board uses 0 to turn on light
   endmethod

endmodule
