from model import  *
from parameter_substitution import *

# Construct a list of all generated and given Verilog and VHDL.  These
# can appear anywhere in the code. The generated Verilog live in the
# .bsc directory.
def globalRTLs(moduleList, rtlModules):
    globalVerilogs = moduleList.getAllDependencies('VERILOG_LIB')
    globalVHDs = []
    for module in rtlModules + [moduleList.topModule]:
        MODULE_PATH =  get_build_path(moduleList, module) 
        for v in moduleList.getDependencies(module, 'GEN_VERILOGS'):              
            globalVerilogs += [MODULE_PATH + '/' + moduleList.env['DEFS']['TMP_BSC_DIR'] + '/' + v]
        for v in moduleList.getDependencies(module, 'GIVEN_VERILOGS'): 
            globalVerilogs += [MODULE_PATH + '/' + v]
        for v in moduleList.getDependencies(module, 'GIVEN_VHDS'): 
            globalVHDs += [MODULE_PATH + '/' + v]
    return [globalVerilogs, globalVHDs] 

# produce an XST-consumable prj file from a global template. 
# not that the top level file is somehow different.  Each module has
# some local context that gets bound in the xst file.  We will query this 
# context before examining.  After that we will query the shell environment.
# Next up, we query the scons environment.
# Finally, we will query the parameter space. If all of these fail, we will give up.
  
#may need to do something about TMP_XILINX_DIR
def generateXST(moduleList, module, xstTemplate):
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

# We need to generate a prj for each synthesis boundary.  For
# efficiency we handle these specially by generating stub
# modules. This adds a little complexity to the synthesis case.

def generatePrj(moduleList, module, globalVerilogs, globalVHDs):
    # spit out a new top-level prj
    prjPath = 'config/' + module.wrapperName() + '.prj' 
    newPRJFile = open(prjPath, 'w') 
 
    # Emit verilog source and stub references
    verilogs = globalVerilogs + [get_temp_path(moduleList,module) + module.wrapperName() + '.v']
    verilogs +=  moduleList.getDependencies(module, 'VERILOG_STUB')
    for vlog in sorted(verilogs):
        # ignore system verilog files.  XST can't compile them anyway...
        if (not re.search('\.sv\s*$',vlog)):    
            newPRJFile.write("verilog work " + vlog + "\n")
    for vhd in sorted(globalVHDs):
        newPRJFile.write("vhdl work " + vhd + "\n")

    newPRJFile.close()
    return prjPath


# Converts SRP file into resource representation which can be used
# by the LIM compiler to assign modules to execution platforms.
def getSRPResourcesClosure(module):

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
    
def buildNGC(moduleList, module, globalVerilogs, globalVHDs, xstTemplate, xilinx_xcf):
    #Let's synthesize a xilinx .prj file for this synth boundary.
    # spit out a new prj
    generatePrj(moduleList, module, globalVerilogs, globalVHDs)
    newXSTPath = generateXST(moduleList, module, xstTemplate)

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

    if(not 'GEN_NGC' in module.moduleDependency):
        module.moduleDependency['GEN_NGCS'] = [ngcFile]
    else:
        module.moduleDependency['GEN_NGCS'] += [ngcFile]

    module.moduleDependency['RESOURCES'] = [resourceFile]

    module.moduleDependency['SYNTHESIS'] = [sub_netlist]
    SCons.Script.Clean(sub_netlist,  moduleList.compileDirectory + '/' + module.wrapperName() + '.srp')

    moduleList.env.Command(resourceFile,
                           srpFile,
                           getSRPResourcesClosure(module))

    # If we're building for the FPGA, we'll claim that the
    # top-level build depends on the existence of the ngc
    # file. This allows us to do resource analysis later on.
    if(moduleList.getAWBParam('bsv_tool', 'BUILD_LOGS_ONLY')):
        moduleList.topDependency += [resourceFile]      
    return sub_netlist
