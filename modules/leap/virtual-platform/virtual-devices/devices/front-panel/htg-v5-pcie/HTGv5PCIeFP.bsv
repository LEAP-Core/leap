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

`include "asim/provides/low_level_platform_interface.bsh"
`include "asim/provides/physical_platform.bsh"
`include "asim/provides/switch_device.bsh"
`include "asim/provides/led_device.bsh"
// TEMPORARY:
`include "asim/provides/pci_express_device.bsh"

typedef 8 FRONTP_NUM_LEDS;
typedef 8 FRONTP_NUM_SWITCHES;
typedef 5 FRONTP_NUM_BUTTONS;   // Fake buttons

typedef Bit#(FRONTP_NUM_LEDS)     FRONTP_LEDS;
typedef Bit#(FRONTP_NUM_SWITCHES) FRONTP_SWITCHES;
typedef Bit#(FRONTP_NUM_BUTTONS)  FRONTP_BUTTONS;

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

module mkFrontPanel#(LowLevelPlatformInterface llpi) (FrontPanel);

    Reg#(FRONTP_LEDS) led_state <- mkReg(0);

    method FRONTP_SWITCHES readSwitches();
        // read from physical platform
        return (llpi.physicalDrivers.switchesDriver.getSwitches());
    endmethod

    method FRONTP_BUTTONS readButtons();
        // read from toplevel wires
        FRONTP_BUTTONS all_inputs = 0;

        return all_inputs;
    endmethod

    method Action writeLEDs(FRONTP_LEDS state, FRONTP_LEDS mask);
        FRONTP_LEDS s = (led_state & ~mask) | (state & mask);
        led_state <= s;
        llpi.physicalDrivers.ledsDriver.setLEDs(s);
    endmethod

endmodule
