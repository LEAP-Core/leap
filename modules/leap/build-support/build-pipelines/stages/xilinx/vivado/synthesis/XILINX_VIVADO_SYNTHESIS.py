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

    # string together the xcf, sort of like the ucf
    # Concatenate XCF files
    MODEL_CLOCK_FREQ = moduleList.getAWBParam('clocks_device', 'MODEL_CLOCK_FREQ')

    ngcModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore] 

    [globalVerilogs, globalVHDs] = globalRTLs(moduleList, moduleList.moduleList)

    generateVivadoTcl(moduleList, moduleList.topModule, globalVerilogs, globalVHDs)

    synth_deps = []
    # drop exiting boundaries. 

    for module in ngcModules:
   
        # did we get an ngc from the first pass?  If so, did the lim
        # graph give code for this module?  If both are true, then we
        # will link the old ngc in, rather than regenerate it. 
        if((not self.firstPassLIGraph is None) and (module.name in self.firstPassLIGraph.modules)):
            synth_deps += linkNGC(moduleList, module, self.firstPassLIGraph)
        else:
            synth_deps += buildVivadoEDF(moduleList, module, globalVerilogs, globalVHDs)
          
    topSRP = moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.srp'

    # Sort dependencies because SCons will rebuild if the order changes.
    top_netlist = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.edf',
        sorted(moduleList.topModule.moduleDependency['VERILOG']) +
        sorted(moduleList.getAllDependencies('VERILOG_STUB')) +
        sorted(moduleList.getAllDependencies('VERILOG_LIB')),
        [ SCons.Script.Delete(topSRP),
          SCons.Script.Delete(moduleList.compileDirectory + '/' + moduleList.apmName + '_xst.xrpt'),
          'ulimit -s unlimited; vivado -mode batch -source config/' + moduleList.topModule.wrapperName() + '.synthesis.tcl -log ' + topSRP,
          '@echo xst ' + moduleList.topModule.wrapperName() + ' build complete.' ])    

    moduleList.topModule.moduleDependency['SYNTHESIS'] = [top_netlist] + synth_deps
    synth_deps += top_netlist
    SCons.Script.Clean(top_netlist, topSRP)

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)



