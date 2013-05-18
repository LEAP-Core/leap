import os
import sys
import SCons.Script
from parameter_substitution import *
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
    else:
      xilinx_xcf = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '.xcf',
        [],
        'touch $TARGET')

    # We need to generate a prj for each synthesis boundary.  For efficiency we handle 
    # these specially by generating stub modules. This adds a little complexity to the 
    # synthesis case. 
   
    # Construct a list of all generated and given Verilog and VHDL.  These can
    # appear anywhere in the code. The generated Verilog live in the .bsc
    # directory. 
    globalVerilogs = moduleList.getAllDependencies('VERILOG_LIB')
    globalVHDs = []
    for module in moduleList.moduleList + [moduleList.topModule]:
        MODULE_PATH =  get_build_path(moduleList, module) 
        for v in moduleList.getDependencies(module, 'GEN_VERILOGS'): 
            globalVerilogs += [MODULE_PATH + '/' + moduleList.env['DEFS']['TMP_BSC_DIR'] + '/' + v]
        for v in moduleList.getDependencies(module, 'GIVEN_VERILOGS'): 
            globalVerilogs += [MODULE_PATH + '/' + v]
        for v in moduleList.getDependencies(module, 'GIVEN_VHDS'): 
            globalVHDs += [MODULE_PATH + '/' + v]

    def generatePrj(module):
        # spit out a new top-level prj
        prjPath = 'config/' + module.wrapperName() + '.prj' 
        newPRJFile = open(prjPath, 'w') 
 
        # Emit verilog source and stub references
        verilogs = globalVerilogs + [get_temp_path(moduleList,module) + module.wrapperName() + '.v']
        verilogs +=  moduleList.getDependencies(module, 'VERILOG_STUB')
        for vlog in sorted(verilogs):
            newPRJFile.write("verilog work " + vlog + "\n")

        for vhd in sorted(globalVHDs):
            newPRJFile.write("vhdl work " + vhd + "\n")

        newPRJFile.close()
        return prjPath

    #Only parse the xst file once.  
    templateFile = moduleList.getAllDependenciesWithPaths('GIVEN_XSTS')
    if(len(templateFile) != 1):
        print "Found more than one XST template file: " + str(templateFile) + ", exiting\n" 
    xstTemplate = parseAWBFile(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + templateFile[0])
                

    # produce an XST-consumable prj file from a global template. 
    # not that the top level file is somehow different.  Each module has
    # some local context that gets bound in the xst file.  We will query this 
    # context before examining.  After that we will query the shell environment.
    # Next up, we query the scons environment.
    # Finally, we will query the parameter space. If all of these fail, we will give up.
  
    #may need to do something about TMP_XILINX_DIR
    def generateXST(module):
        localContext = {'APM_NAME': module.wrapperName(),\
                        'HW_BUILD_DIR': module.buildPath}

        XSTPath = 'config/' + module.wrapperName() + '.modified.xst'
        XSTFile = open(XSTPath, 'w')

        # dump the template file, substituting symbols as we find them
        for token in xstTemplate:
            if (isinstance(token, Parameter)):
                # 1. local context 
                if (token.name in localContext):    
                    XSTFile.write(localContext[token.name])
                # 2. search the local environment
                elif (token.name in os.environ):
                    XSTFile.write(os.environ[token.name])
                # 3. Search module list environment.
                elif (token.name in moduleList.env['DEFS']):
                    XSTFile.write(moduleList.env['DEFS'][token.name])
                # 3. Search the AWB parameters or DIE.
                else:  
                    XSTFile.write(moduleList.getAWBParam(moduleList.moduleList,token.name))
            else:
                #we got a string
                XSTFile.write(token)

        # we have some XST switches that are handled by parameter
        if moduleList.getAWBParam('synthesis_tool', 'XST_PARALLEL_CASE'):
            XSTFile.write('-vlgcase parallel\n')
        if moduleList.getAWBParam('synthesis_tool', 'XST_INSERT_IOBUF') and (module.name == moduleList.topModule.name):
            XSTFile.write('-iobuf yes\n')
        else:
            XSTFile.write('-iobuf no\n')
        XSTFile.write('-uc ' + moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.xcf\n')
        return XSTPath

    generatePrj(moduleList.topModule)
    topXSTPath = generateXST(moduleList.topModule)

    synth_deps = []

    for module in moduleList.synthBoundaries():
        #Let's synthesize a xilinx .prj file for this synth boundary.
        # spit out a new prj
        generatePrj(module)
        newXSTPath = generateXST(module)

        if (getBuildPipelineDebug(moduleList) != 0):
            print 'For ' + module.name + ' explicit vlog: ' + str(module.moduleDependency['VERILOG'])

        # Sort dependencies because SCons will rebuild if the order changes.
        sub_netlist = moduleList.env.Command(
            moduleList.compileDirectory + '/' + module.wrapperName() + '.ngc',
            sorted(module.moduleDependency['VERILOG']) +
            sorted(moduleList.getAllDependencies('VERILOG_LIB')) +
            [ newXSTPath ] +
            xilinx_xcf,
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
