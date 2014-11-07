import os
import re 
import sys
import SCons.Script
from model import  *
# need to pick up clock frequencies for xcf
from clocks_device import *
from synthesis_library import *
from parameter_substitution import *
from wrapper_gen_tool import *


#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class Synthesize():
  def __init__(self, moduleList):

    # We load this graph in to memory several times. 
    # TODO: load this graph once. 
    self.firstPassLIGraph = getFirstPassLIGraph()

    self.DEBUG = getBuildPipelineDebug(moduleList) 

    netlistModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore] 

    [globalVerilogs, globalVHDs] = globalRTLs(moduleList, moduleList.moduleList)

    synth_deps = []
    # drop exiting boundaries. 

    for module in [ mod for mod in netlistModules if not mod.platformModule]:     
        # did we get an netlist from the first pass?  If so, did the lim
        # graph give code for this module?  If both are true, then we
        # will link the old netlist in, rather than regenerate it. 
        if((not self.firstPassLIGraph is None) and (module.name in self.firstPassLIGraph.modules)):
            synth_deps += linkNGC(moduleList, module, self.firstPassLIGraph)
        else:
            synth_deps += buildVivadoEDF(moduleList, module, globalVerilogs, globalVHDs)
          
    # Build the top level/platform using Xst
    synth_deps += buildXSTTopLevel(moduleList, self.firstPassLIGraph)

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)



