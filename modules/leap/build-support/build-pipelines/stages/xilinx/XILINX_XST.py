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

    # if we have a deps build, don't do anything...                                                                                  
    if(moduleList.isDependsBuild):
        return

    # We load this graph in to memory several times. 
    # TODO: load this graph once. 
    self.firstPassLIGraph = getFirstPassLIGraph()

    self.DEBUG = getBuildPipelineDebug(moduleList) 

    # string together the xcf, sort of like the ucf
    # Concatenate XCF files
    xcfSrcs = moduleList.getAllDependencies('XCF')
    MODEL_CLOCK_FREQ = moduleList.getAWBParam('clocks_device', 'MODEL_CLOCK_FREQ')
    if (len(xcfSrcs) > 0):
      if (self.DEBUG != 0):
        for xcf in xcfSrcs:
          print 'xst found xcf: ' + xcf

      xilinx_xcf = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '.xcf',
        xcfSrcs,
        'cat $SOURCES > $TARGET')
    else:
      xilinx_xcf = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '.xcf',
        [],
        'touch $TARGET')


    #Only parse the xst file once.  
    templateFile = moduleList.getAllDependenciesWithPaths('GIVEN_XSTS')
    if(len(templateFile) != 1):
        print "Found more than one XST template file: " + str(templateFile) + ", exiting\n" 

    xstTemplate = parseAWBFile(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + templateFile[0])
                
    ngcModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore] 

    [globalVerilogs, globalVHDs] = globalRTLs(moduleList, moduleList.moduleList)

    generatePrj(moduleList, moduleList.topModule, globalVerilogs, globalVHDs)
    topXSTPath = generateXST(moduleList, moduleList.topModule, xstTemplate)

    synth_deps = []
    # drop exiting boundaries. 

    for module in ngcModules:
        # did we get an ngc from the first pass?  If so, did the lim
        # graph give code for this module?  If both are true, then we
        # will link the old ngc in, rather than regenerate it. 
        if((not self.firstPassLIGraph is None) and (module.name in self.firstPassLIGraph.modules)):
            synth_deps += linkNGC(moduleList, module, self.firstPassLIGraph)
        else:
            synth_deps += buildNGC(moduleList, module, globalVerilogs, globalVHDs, xstTemplate, xilinx_xcf)
          
    if moduleList.getAWBParam('synthesis_tool', 'XST_BLUESPEC_BASICINOUT'):
        basicio_cmd = env['ENV']['BLUESPECDIR'] + '/bin/basicinout ' + 'hw/' + moduleList.topModule.buildPath + '/.bsc/' + moduleList.topModule.wrapperName() + '.v',     #patch top verilog
    else:
        basicio_cmd = '@echo Bluespec basicinout disabled'

    topSRP = moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.srp'

    # Sort dependencies because SCons will rebuild if the order changes.
    top_netlist = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.ngc',
        sorted(moduleList.topModule.moduleDependency['VERILOG']) +
        sorted(moduleList.getAllDependencies('VERILOG_STUB')) +
        sorted(moduleList.getAllDependencies('VERILOG_LIB')) +
        [ topXSTPath ] + 
        xilinx_xcf,
        [ SCons.Script.Delete(topSRP),
          SCons.Script.Delete(moduleList.compileDirectory + '/' + moduleList.apmName + '_xst.xrpt'),
          basicio_cmd,
          'ulimit -s unlimited; xst -intstyle silent -ifn config/' + moduleList.topModule.wrapperName() + '.modified.xst -ofn ' + topSRP,
          '@echo xst ' + moduleList.topModule.wrapperName() + ' build complete.' ])    

    synth_deps += top_netlist
    moduleList.topModule.moduleDependency['SYNTHESIS'] = synth_deps

    SCons.Script.Clean(top_netlist, topSRP)

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)



