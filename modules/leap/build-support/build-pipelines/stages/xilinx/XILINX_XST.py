import os
import sys
import SCons.Script
from model import  *
# need to pick up clock frequencies for xcf
from clocks_device import *


#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class Synthesize():
  def __init__(self, moduleList):

    # string together the xcf, sort of like the ucf
    # Concatenate XCF files
    xcfSrcs = moduleList.getAllDependencies('XCF')
    MODEL_CLOCK_FREQ = moduleList.getAWBParam('clocks_device', 'MODEL_CLOCK_FREQ')
    if (len(xcfSrcs) > 0):
      if (getBuildPipelineDebug(moduleList) != 0):
        for xcf in xcfSrcs:
          print 'xst found xcf: ' + xcf

      xilinx_xcf = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '.xcf',
        xcfSrcs,
        'cat $SOURCES > $TARGET')

      xilinx_child_xcf = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '_child.xcf',
        xcfSrcs,
        ['cat $SOURCES > $TARGET',
         'echo -e "NET CLK period =' + str(int(1000/MODEL_CLOCK_FREQ)) + 'ns;\\n"  >> $TARGET'])
    else:
      xilinx_xcf = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '.xcf',
        [],
        'touch $TARGET')

      xilinx_child_xcf = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '.xcf',
        [],
        'echo -e "NET CLK period =' + str(int(1000/MODEL_CLOCK_FREQ)) + 'ns;\\n" > $TARGET')

    ## tweak top xst file
    topXSTPath = 'config/' + moduleList.topModule.wrapperName() + '.modified.xst'
    newXSTFile = open(topXSTPath, 'w')
    oldXSTFile = open('config/' + moduleList.topModule.wrapperName() + '.xst', 'r')
    newXSTFile.write(oldXSTFile.read());
    if moduleList.getAWBParam('synthesis_tool', 'XST_PARALLEL_CASE'):
        newXSTFile.write('-vlgcase parallel\n');
    if moduleList.getAWBParam('synthesis_tool', 'XST_INSERT_IOBUF'):
        newXSTFile.write('-iobuf yes\n');
    else:
        newXSTFile.write('-iobuf no\n');
    newXSTFile.write('-uc ' + moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '.xcf\n');
    newXSTFile.close();
    oldXSTFile.close();

    synth_deps = []

    for module in moduleList.synthBoundaries():    
        # we must tweak the xst files of the internal module list
        # to prevent the insertion of iobuffers
        newXSTPath = 'config/' + module.wrapperName() + '.modified.xst'
        newXSTFile = open(newXSTPath, 'w')
        oldXSTFile = open('config/' + module.wrapperName() + '.xst', 'r')
        newXSTFile.write(oldXSTFile.read());
        if moduleList.getAWBParam('synthesis_tool', 'XST_PARALLEL_CASE'):
            newXSTFile.write('-vlgcase parallel\n');
        newXSTFile.write('-iobuf no\n');
        newXSTFile.write('-uc  ' + moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '_child.xcf\n');
        newXSTFile.close();
        oldXSTFile.close();

        if (getBuildPipelineDebug(moduleList) != 0):
            print 'For ' + module.name + ' explicit vlog: ' + str(module.moduleDependency['VERILOG'])

        # Sort dependencies because SCons will rebuild if the order changes.
        sub_netlist = moduleList.env.Command(
            moduleList.compileDirectory + '/' + module.wrapperName() + '.ngc',
            sorted(module.moduleDependency['VERILOG']) +
            sorted(moduleList.getAllDependencies('VERILOG_STUB')) +
            sorted(moduleList.getAllDependencies('VERILOG_LIB')) +
            module.moduleDependency['XST'] +
            moduleList.topModule.moduleDependency['XST'] +
            [ newXSTPath ] +
            xilinx_child_xcf,
            [ SCons.Script.Delete(moduleList.compileDirectory + '/' + module.wrapperName() + '.srp'),
              SCons.Script.Delete(moduleList.compileDirectory + '/' + module.wrapperName() + '_xst.xrpt'),
              'xst -intstyle silent -ifn config/' + module.wrapperName() + '.modified.xst -ofn ' + moduleList.compileDirectory + '/' + module.wrapperName() + '.srp',
              '@echo xst ' + module.wrapperName() + ' build complete.' ])

        module.moduleDependency['SYNTHESIS'] = [sub_netlist]
        synth_deps += sub_netlist
        SCons.Script.Clean(sub_netlist,  moduleList.compileDirectory + '/' + module.wrapperName() + '.srp')
    

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
        moduleList.topModule.moduleDependency['XST'] +
        [ topXSTPath ] +
        xilinx_xcf,
        [ SCons.Script.Delete(topSRP),
          SCons.Script.Delete(moduleList.compileDirectory + '/' + moduleList.apmName + '_xst.xrpt'),
          basicio_cmd,
          'xst -intstyle silent -ifn config/' + moduleList.topModule.wrapperName() + '.modified.xst -ofn ' + topSRP,
          '@echo xst ' + moduleList.topModule.wrapperName() + ' build complete.' ])    

    moduleList.topModule.moduleDependency['SYNTHESIS'] = [top_netlist]
    synth_deps += top_netlist
    SCons.Script.Clean(top_netlist, topSRP)

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)
