import os
import re 
import sys
import SCons.Script
from model import  *
# need to pick up clock frequencies for xcf
from clocks_device import *
from synthesis_library import *
from parameter_substitution import *

   
#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class Synthesize():
  def __init__(self, moduleList):

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
        #Let's synthesize a xilinx .prj file for this synth boundary.
        # spit out a new prj
        generatePrj(moduleList, module, globalVerilogs, globalVHDs)
        newXSTPath = generateXST(moduleList, module, xstTemplate)

        if (self.DEBUG != 0):
            if('VERILOG' in module.moduleDependency):
                print 'For ' + module.name + ' explicit vlog: ' + str(module.moduleDependency['VERILOG'])

        ngcFile = moduleList.compileDirectory + '/' + module.wrapperName() + '.ngc'
        srpFile = moduleList.compileDirectory + '/' + module.wrapperName() + '.srp'
        resourceFile = moduleList.compileDirectory + '/' + module.wrapperName() + '.resources'


        # Sort dependencies because SCons will rebuild if the order changes.
        sub_netlist = moduleList.env.Command(
            [ngcFile, srpFile],
            sorted(module.moduleDependency['VERILOG']) +
            sorted(moduleList.getAllDependencies('VERILOG_LIB')) +
            sorted(convertDependencies(moduleList.getDependencies(module, 'VERILOG_STUB'))) +
            [ newXSTPath ] +
            xilinx_xcf,
            [ SCons.Script.Delete(moduleList.compileDirectory + '/' + module.wrapperName() + '.srp'),
              SCons.Script.Delete(moduleList.compileDirectory + '/' + module.wrapperName() + '_xst.xrpt'),
              'xst -intstyle silent -ifn config/' + module.wrapperName() + '.modified.xst -ofn ' + moduleList.compileDirectory + '/' + module.wrapperName() + '.srp',
              '@echo xst ' + module.wrapperName() + ' build complete.' ])


        module.moduleDependency['SRP'] = [srpFile]

        module.moduleDependency['RESOURCES'] = [resourceFile]

        module.moduleDependency['SYNTHESIS'] = [sub_netlist]
        synth_deps += sub_netlist
        SCons.Script.Clean(sub_netlist,  moduleList.compileDirectory + '/' + module.wrapperName() + '.srp')

        moduleList.env.Command(resourceFile,
                               srpFile,
                               self.getSRPResourcesClosure(module))

        # If we're building for the FPGA, we'll claim that the
        # top-level build depends on the existence of the ngc
        # file. This allows us to do resource analysis later on.
        if(moduleList.getAWBParam('bsv_tool', 'BUILD_LOGS_ONLY')):
            moduleList.topDependency += [resourceFile]
  
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

    moduleList.topModule.moduleDependency['SYNTHESIS'] = [top_netlist]
    synth_deps += top_netlist
    SCons.Script.Clean(top_netlist, topSRP)

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)


  # Converts SRP file into resource representation which can be used
  # by the LIM compiler to assign modules to execution platforms.
  def getSRPResourcesClosure(self, module):

    def collect_srp_resources(target, source, env):
  
        srpFile = str(source[0])
        rscFile = str(target[0])

        srpHandle = open(srpFile, 'r')
        rscHandle = open(rscFile, 'w')
        resources =  {}

        attributes = {'LUT': " Number of Slice LUTs",'Reg': " Number of Slice Registers", 'BRAM': " Number of Block RAM/FIFO:"}

        for line in srpHandle:
            for attribute in attributes:
                if (re.match(attributes[attribute],line)):
                    match = re.search(r'\D+(\d+)\D+(\d+)', line)
                    if(match):
                        resources[attribute] = [match.group(1), match.group(2)]

        rscHandle.write(module.name + ':')
        rscHandle.write(':'.join([resource + ':' + resources[resource][0] + ':Total' + resource + ':' + resources[resource][1] for resource in resources]) + '\n')
                                   
        rscHandle.close()
        srpHandle.close()
    return collect_srp_resources
