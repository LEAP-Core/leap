//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

import List::*;

`include "awb/provides/shared_scratchpad_memory_common.bsh"

//
// mkSharedScratchpadController --
//     Initialize a controller for a new shared scratchpad memory region.
//
module [CONNECTED_MODULE] mkSharedScratchpadController#(List#(Integer) scratchpadIDs,
                                                        NumTypeParam#(t_IN_ADDR_SZ) inAddrSz,
                                                        NumTypeParam#(t_IN_DATA_SZ) inDataSz,
                                                        SHARED_SCRATCH_CONTROLLER_CONFIG conf)
    // interface:
    ();
    
    if (conf.controllerType == UNCACHED_SCRATCHPAD_CONTROLLER)
    begin
        if (List::length(args) != 1)
        begin
            error("Wrong number of scratchpadIDs: uncached shared scratchpad controller needs 1 registered scratchpad ID");
        end
        // There are no private caches in this shared memory region. 
        // Shared scratchpad clients just send remote reads/writes to the centralized 
        // private scratchpad inside the shared scratchpad controller
        mkUncachedSharedScratchpadController(scratchpadIDs[0], inAddrSz, inDataSz, conf);
    end
    else if (conf.controllerType == CACHED_SCRATCHPAD_CONTROLLER)
    begin
        if (List::length(args) != 1)
        begin
            error("Wrong number of scratchpadIDs: cached shared scratchpad controller needs 1 registered scratchpad ID");
        end
        mkCachedSharedScratchpadController(scratchpadIDs[0], inAddrSz, inDataSz, conf);
    end
    else // default: coherent scratchpad controller
    begin
        // Coherent scratchpad controller requires 2 scratchpad IDs (one for data, one for ownership) 
        if (List::length(args) != 2)
        begin
            error("Wrong number of scratchpadIDs: coherent scratchpad controller needs 2 registered scratchpad IDs");
        end
        let coh_conf =  COH_SCRATCH_CONTROLLER_CONFIG { cacheMode: COH_SCRATCH_CACHED,
                                                        multiController: conf.multiController,
                                                        coherenceDomainID: conf.sharedDomainID,
                                                        isMaster: conf.isMaster,
                                                        partition: conf.partition,
                                                        initFilePath: conf.initFilePath,
                                                        debugLogPath: conf.debugLogPath,
                                                        enableDebugScan: conf.enableDebugScan,
                                                        enableStatistics: conf.enableStatistics };
        
        mkCoherentScratchpadController#(scratchpadIDs[0], scratchpadIDs[1], inAddrSz, inDataSz, coh_conf);
    end

endmodule

