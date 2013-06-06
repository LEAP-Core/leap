from model import  *
from parameter_substitution import *

# Construct a list of all generated and given Verilog and VHDL.  These
# can appear anywhere in the code. The generated Verilog live in the
# .bsc directory.
def globalRTLs(moduleList):
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
        newPRJFile.write("verilog work " + vlog + "\n")
    for vhd in sorted(globalVHDs):
        newPRJFile.write("vhdl work " + vhd + "\n")

    newPRJFile.close()
    return prjPath




