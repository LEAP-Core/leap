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

`include "awb/provides/shared_scratchpad_memory_common.bsh"

//
// mkSharedScratchpadClient --
//     This is the typical shared scratchpad client module.
//
//     Build a shared scratchpad client of an arbitrary data type with 
// marshalling to the global scratchpad base memory size.
//
module [CONNECTED_MODULE] mkSharedScratchpadClient#(Integer scratchpadID, 
                                                    SHARED_SCRATCH_CLIENT_CONFIG conf)
    // interface:
    (SHARED_MEMORY_IFC#(t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));
    //
    // The shared scratchpad implementation is all in the multi-reader interface.
    // Allocate a multi-reader shared scratchpad client with a single reader 
    // and convert it to SHARED_MEMORY_IFC.
    //
    SHARED_MEMORY_MULTI_READ_IFC#(1, t_ADDR, t_DATA) m_scratch <- mkMultiReadSharedScratchpadClient(scratchpadID, conf);
    SHARED_MEMORY_MULTI_READ_IFC#(t_ADDR, t_DATA) scratch <- mkMultiReadSharedMemIfcToSharedMemIfc(m_scratch);
    return scratch;
endmodule

//
// mkMultiReadSharedScratchpadClient --
//     The same as a normal mkSharedScratchpadClient but with multiple read ports.
//     Requests are processed in order, with reads being scheduled before
//     a write requested in the same cycle.
//
module [CONNECTED_MODULE] mkMultiReadSharedScratchpadClient#(Integer scratchpadID, 
                                                             SHARED_SCRATCH_CLIENT_CONFIG conf)
    // interface:
    (SHARED_MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ));

    SHARED_MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) mem = ?;

    if (conf.clientType == UNCACHED_SCRATCHPAD)
    begin
        String debugFileName = "";
        if (conf.debugLogPath matches tagged Valid .log_name)
        begin
            debugFileName = log_name;
        end
        DEBUG_FILE debugLog <- (isValid(conf.debugLogPath))? mkDebugFile(debugFileName) : mkDebugFileNull(debugFileName); 
        // There are no private caches in this shared memory region. 
        MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA) uncached_scratch <- mkUncachedSharedScratchpadClient(scratchpadID, debugLog);
        mem <- mkMultiReadMemFenceIfcToMultiReadSharedMemIfc(uncached_scratch);
    end
    else if (conf.clientType == COHERENT_SCRATCHPAD)
    begin
        let coh_conf =  COH_SCRATCH_CLIENT_CONFIG { cacheMode: COH_SCRATCH_CACHED,
                                                    cacheEntries: conf.cacheEntries, 
                                                    multiController: conf.multiController,
                                                    enablePrefetching: conf.enablePrefetching, 
                                                    requestMerging: conf.requestMerging, 
                                                    debugLogPath: conf.debugLogPath,
                                                    enableDebugScan: conf.enableDebugScan,
                                                    enableStatistics: conf.enableStatistics };
        
        MEMORY_MULTI_READ_WITH_FENCE_IFC#(n_READERS, t_ADDR, t_DATA) coherent_scratch <- mkMultiReadCoherentScratchpadClient(scratchpadID, coh_conf);
        mem <- mkMultiReadMemFenceIfcToMultiReadSharedMemIfc(coherent_scratch);
    end
    // else
    // begin
    //     SHARED_MEMORY_SIMPLE_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) shared_scratch <- mkCachedSharedScratchpadClient(scratchpadID, conf);
    //     mem <- mkMultiReadSimpleSharedMemIfcToMultiReadSharedMemIfc(shared_scratch);
    // end

    return mem;

endmodule

