
import Clocks::*;
import ModuleContext::*;

`include "asim/provides/fpga_components.bsh"
`include "asim/provides/clocks_device.bsh"
`include "asim/provides/soft_services_lib.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_clocks_lib.bsh"
//`include "asim/provides/soft_services_deps.bsh"

instance SOFT_SERVICE#(LOGICAL_CLOCK_INFO);

    module initializeServiceContext (LOGICAL_CLOCK_INFO);

        let clock <- exposeCurrentClock();
        let reset <- exposeCurrentReset();
        // If the model clock frequency and the crystal clock frequency don't square
        // we should bail out.  

        if(`MODEL_CLOCK_FREQ != `CRYSTAL_CLOCK_FREQ*
                                `MODEL_CLOCK_MULTIPLIER/
                                `MODEL_CLOCK_DIVIDER)
          begin
            errorM("ERROR: Model Clock Frequency and Calculated frequency not equivalent");
          end

        return LOGICAL_CLOCK_INFO {clk: clock, rst: reset};

    endmodule
    
    module finalizeServiceContext#(LOGICAL_CLOCK_INFO info) (Empty);
        // Currently nothing to do here.
    endmodule

endinstance

instance SYNTHESIZABLE_SOFT_SERVICE#(LOGICAL_CLOCK_INFO, Empty);

    module exposeServiceContext#(LOGICAL_CLOCK_INFO info) (Empty);
        // Currently nothing to do here.
    endmodule

endinstance


module [t_CONTEXT] mkSoftClock#(Integer outputFreq) (UserClock)
    provisos
        (Context#(t_CONTEXT, LOGICAL_CLOCK_INFO),
         IsModule#(t_CONTEXT, t_DUMMY));

  // Get a reference to the known clock
  LOGICAL_CLOCK_INFO modelClock <- getContext();
  let returnClock <- mkUserClockFromFrequency(`MODEL_CLOCK_FREQ,
                                              outputFreq,
                                              clocked_by modelClock.clk, 
                                              reset_by modelClock.rst);
  return returnClock; 
endmodule
