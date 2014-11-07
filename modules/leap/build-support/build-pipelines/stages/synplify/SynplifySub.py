import os
import errno
import re
import SCons.Script  
from model import  *
# need to get the model clock frequency
from clocks_device import  *
from synthesis_library import  *
from wrapper_gen_tool import *

from SynplifyCommon import *

class Synthesize(ProjectDependency):
  def __init__(self, moduleList):

    # We load this graph in to memory several times. 
    # TODO: load this graph once. 
    self.firstPassLIGraph = getFirstPassLIGraph()

    # We first do things related to the Xilinx build

    if (getBuildPipelineDebug(moduleList) != 0):
        print "Env BUILD_DIR = " + moduleList.env['ENV']['BUILD_DIR']

    synth_deps = []
    [globalVerilogs, globalVHDs] = globalRTLs(moduleList, moduleList.moduleList)

    netlistModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore] 

    for module in [ mod for mod in netlistModules if not mod.platformModule]:  
        if((not self.firstPassLIGraph is None) and (module.name in self.firstPassLIGraph.modules)):
            # we link from previous.
            synth_deps += linkNGC(moduleList, module, self.firstPassLIGraph)
        else:
            buildModuleEDF(moduleList, module, globalVerilogs, globalVHDs, getSRRResourcesClosureXilinx)
            
    # Build the top level/platform using Xst
    synth_deps += buildXSTTopLevel(moduleList, self.firstPassLIGraph)

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)
