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

#
# Configure the top-level Xst build
#
def _xst_top_level(moduleList, firstPassGraph):
    # string together the xcf, sort of like the ucf                                                                                                          
    # Concatenate UCF files                                                                                                                                  
    if('XCF' in moduleList.topModule.moduleDependency and len(moduleList.topModule.moduleDependency['XCF']) > 0):
      xilinx_xcf = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '.xcf',
        moduleList.topModule.moduleDependency['XCF'],
        'cat $SOURCES > $TARGET')
    else:
      xilinx_xcf = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '.xcf',
        [],
        'touch $TARGET')

    ## tweak top xst file                                                        
    #Only parse the xst file once.  
    templates = moduleList.getAllDependenciesWithPaths('GIVEN_XSTS')
    if(len(templates) != 1):
        print "Found more than one XST template file: " + str(templates) + ", exiting\n" 
    templateFile = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + templates[0]
    xstTemplate = parseAWBFile(templateFile)
                  

    [globalVerilogs, globalVHDs] = globalRTLs(moduleList, moduleList.moduleList)
    synth_deps = []
    for module in [ mod for mod in moduleList.synthBoundaries() if mod.platformModule]:
        if((not firstPassGraph is None) and (module.name in firstPassGraph.modules)):
            # we link from previous.
            synth_deps += linkNGC(moduleList, module, self.firstPassLIGraph)
        else:
            synth_deps += buildNGC(moduleList, module, globalVerilogs, globalVHDs, xstTemplate, xilinx_xcf)

    generatePrj(moduleList, moduleList.topModule, globalVerilogs, globalVHDs)
    topXSTPath = generateXST(moduleList, moduleList.topModule, xstTemplate)       

    # Use xst to tie the world together.
    topSRP = moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.srp'

    top_netlist = moduleList.env.Command(
      moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.ngc',
      moduleList.topModule.moduleDependency['VERILOG'] +
      moduleList.getAllDependencies('VERILOG_STUB') +
      moduleList.getAllDependencies('VERILOG_LIB') +
      [ templateFile ] +
      [ topXSTPath ] + xilinx_xcf,
      [ SCons.Script.Delete(topSRP),
        SCons.Script.Delete(moduleList.compileDirectory + '/' + moduleList.apmName + '_xst.xrpt'),
        'xst -intstyle silent -ifn config/' + moduleList.topModule.wrapperName() + '.modified.xst -ofn ' + topSRP,
        '@echo xst ' + moduleList.topModule.wrapperName() + ' build complete.' ])    

    SCons.Script.Clean(top_netlist, topSRP)

    moduleList.topModule.moduleDependency['SYNTHESIS'] = [top_netlist]

    return [top_netlist] + synth_deps
    

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
    synth_deps += _xst_top_level(moduleList, self.firstPassLIGraph)

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)
