import os
import functools
import re

import SCons

import model
import li_module
import parameter_substitution 
import wrapper_gen_tool 


def getModuleRTLs(moduleList, module):
    moduleVerilogs = []
    moduleVHDs = []
    MODULE_PATH =  model.get_build_path(moduleList, module) 
    for v in moduleList.getDependencies(module, 'GEN_VERILOGS'):              
        moduleVerilogs += [MODULE_PATH + '/' + moduleList.env['DEFS']['TMP_BSC_DIR'] + '/' + v]
    for v in moduleList.getDependencies(module, 'GIVEN_VERILOGS'): 
        moduleVerilogs += [MODULE_PATH + '/' + v]
    for v in moduleList.getDependencies(module, 'GIVEN_VHDS'): 
        moduleVHDs += [MODULE_PATH + '/' + v]
    for v in moduleList.getDependencies(module, 'GIVEN_VHDLS'):
        lib = ""
        if('lib' in v.attributes):
            lib = v.attributes['lib'] + '/'
        moduleVHDs += [model.Source.Source(MODULE_PATH + '/' + lib + v.file, v.attributes)]


    return [moduleVerilogs, moduleVHDs] 

# Construct a list of all generated and given Verilog and VHDL.  These
# can appear anywhere in the code. The generated Verilog live in the
# .bsc directory.
def globalRTLs(moduleList, rtlModules):
    globalVerilogs = moduleList.getAllDependencies('VERILOG_LIB')

    globalVHDs = []

    for module in rtlModules + [moduleList.topModule]:
         [moduleVerilogs, moduleVHDs] = getModuleRTLs(moduleList, module)
         globalVerilogs += moduleVerilogs
         globalVHDs += moduleVHDs

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
        if (isinstance(token, parameter_substitution.Parameter)):
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
    verilogs = globalVerilogs + [model.get_temp_path(moduleList,module) + module.wrapperName() + '.v']
    verilogs +=  moduleList.getDependencies(module, 'VERILOG_STUB')
    for vlog in sorted(verilogs):
        # ignore system verilog files.  XST can't compile them anyway...
        if (not re.search('\.sv\s*$',vlog)):    
            newPRJFile.write("verilog work " + vlog + "\n")
    for vhd in sorted(globalVHDs):
        newPRJFile.write("vhdl work " + vhd + "\n")

    newPRJFile.close()
    return prjPath


def generateSynthesisTcl(moduleList, module, compileDirectory):

    # Eventually we will want to add some of these to the synthesis tcl
    # From UG905 pg. 11, involving clock definition.

    # We need to declare a top-level clock.  Unfortunately, the platform module will require special handling. 
    clockFiles = []
    
    # Physical devices require special handling, since they have
    # complicated clocking mechanisms which must be exposed at
    # synthesis.

    MODEL_CLOCK_FREQ = moduleList.getAWBParam('clocks_device', 'MODEL_CLOCK_FREQ')
    synthAnnotationsTclPath = compileDirectory.File(module.wrapperName() + '.annotations.tcl')
    synthAnnotationsTclFile = open(str(synthAnnotationsTclPath), 'w') 

    annotationFiles = [os.path.relpath(str(synthAnnotationsTclPath), str(compileDirectory))]
    clockDeps = [synthAnnotationsTclPath]

    relpathCurry = functools.partial(os.path.relpath, start = str(compileDirectory))

    synthAnnotationsTclFile.write('set SYNTH_OBJECT ' + module.name + '\n')
    synthAnnotationsTclFile.write('set IS_TOP_BUILD 0\n')
    synthAnnotationsTclFile.write('set IS_AREA_GROUP_BUILD 0\n')

    tclDefs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_DEFINITIONS')) > 0):
        tclDefs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_DEFINITIONS'))
        clockDeps += tclDefs
        tclDefs = map(relpathCurry, tclDefs)   

    tclSynth = []
    #if (module.platformModule or 'AREA_GROUP' not in module.attributes):        
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_SYNTHESISS')) > 0):
        tclSynth = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_SYNTHESISS'))
        clockDeps += tclSynth
        tclSynth = map(relpathCurry, tclSynth)   
    
    tclParams= []
    if(len(moduleList.getAllDependencies('PARAM_TCL')) > 0):
        tclParams = moduleList.getAllDependencies('PARAM_TCL')

    # Add in other synthesis algorithms
    tclHeaders = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_HEADERS')) > 0):
        tclHeaders = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_HEADERS'))

    tclFuncs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_FUNCTIONS')) > 0):
        tclFuncs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_FUNCTIONS')) 

    for tclParam in tclParams:
         #newTclFile.write('source ' + model.rel_if_not_abspath(tcl_param, str(vivadoCompileDirectory)) + '\n')
         synthAnnotationsTclFile.write('source ' + model.rel_if_not_abspath(tclParam, str(compileDirectory)) + '\n')

    for tclHeader in tclHeaders:
         #newTclFile.write('source ' + model.rel_if_not_abspath(tcl_header, str(vivadoCompileDirectory)) + '\n')
         synthAnnotationsTclFile.write('source ' + model.rel_if_not_abspath(tclHeader, str(compileDirectory)) + '\n')

    synthAnnotationsTclFile.write('annotateModelClock\n')

    # apply tcl synthesis functions/patches 
    for tclFunc in tclFuncs:
        relpath = model.rel_if_not_abspath(tclFunc, str(compileDirectory))
        synthAnnotationsTclFile.write('source ' + relpath + '\n')

    for file in tclDefs:
        synthAnnotationsTclFile.write("source " + file + "\n")
    for file in tclSynth:
        synthAnnotationsTclFile.write("source " + file + "\n")

    # we need some synthesis algorithms... 

    synthAnnotationsTclFile.close()

    return annotationFiles, tclFuncs + tclHeaders + tclParams + clockDeps

# Produce Vivado Synthesis Tcl

def generateVivadoTcl(moduleList, module, globalVerilogs, globalVHDs, vivadoCompileDirectory):
    # spit out a new top-level prj
    prjPath = vivadoCompileDirectory.File(module.wrapperName() + '.synthesis.tcl')
    newTclFile = open(str(prjPath), 'w') 
 
    # Emit verilog source and stub references
    verilogs = globalVerilogs + [model.get_temp_path(moduleList,module) + module.wrapperName() + '.v']
    verilogs +=  moduleList.getDependencies(module, 'VERILOG_STUB')

    givenNetlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ]

    # Replace any known black boxes
    blackBoxDeps = []
    blackBoxes = module.getAttribute('BLACK_BOX')
    for vlog in sorted(verilogs):
        if(not blackBoxes is None):
            if(vlog in blackBoxes):
                vlog = blackBoxes[vlog]
                blackBoxDeps.append(vlog)
        relpath = model.rel_if_not_abspath(vlog, str(vivadoCompileDirectory))
        newTclFile.write("read_verilog -quiet " + relpath + "\n")
       
    for vhd in sorted(globalVHDs):
        if(isinstance(vhd, model.Source.Source)):            
            # Got a source object, potentially more work to do.
            relpath = model.rel_if_not_abspath(vhd.file, str(vivadoCompileDirectory))
            lib = 'work'
            if('lib' in vhd.attributes):
                newTclFile.write("read_vhdl -lib " + vhd.attributes['lib'] + " " + relpath + "\n")
        else:
            # Just got a string
            relpath = model.rel_if_not_abspath(vhd, str(vivadoCompileDirectory))
            newTclFile.write("read_vhdl -lib work " + relpath + "\n")

    for netlist in givenNetlists:
        relpath = model.rel_if_not_abspath(netlist, str(vivadoCompileDirectory))
        newTclFile.write('read_edif ' + relpath + '\n')

    annotationFiles, annotationDeps = generateSynthesisTcl(moduleList, module, vivadoCompileDirectory)

    part = moduleList.getAWBParam('physical_platform_config', 'FPGA_PART_XILINX')
    
    # the out of context option instructs the tool not to place iobuf
    # and friends on the external ports.
 
    # First, elaborate the rtl design. 

    inc_dirs = model.rel_if_not_abspath(moduleList.env['DEFS']['ROOT_DIR_HW_INC'], str(vivadoCompileDirectory))

    # For the top module, we don't use out of context.b
    if(module.getAttribute('TOP_MODULE') is None):
        newTclFile.write("synth_design -rtl -mode out_of_context -top " + module.wrapperName() + " -part " + part + " -include_dirs " + inc_dirs + "\n")
    else:
        newTclFile.write("synth_design -rtl -top " + module.wrapperName() + " -part " + part + " -include_dirs " + inc_dirs + "\n")


    for file in annotationFiles:
        newTclFile.write("add_files " + file + "\n")
        if(module.getAttribute('TOP_MODULE') is None):
            newTclFile.write("set_property USED_IN {synthesis implementation out_of_context} [get_files " + file + "]\n")
        else:
            newTclFile.write("set_property USED_IN {synthesis implementation} [get_files " + file + "]\n")

    if(module.getAttribute('TOP_MODULE') is None):
        clockConversion = ""
        useClockConversion = moduleList.getAWBParamSafe('synthesis_tool', 'VIVADO_ENABLE_CLOCK_CONVERSION')
        print " VIVADO CLOCK CONVERSION: " + str(useClockConversion)
        if(useClockConversion > 0):
            clockConversion = " -gated_clock_conversion auto "
        
        newTclFile.write("synth_design  " + clockConversion + " -mode out_of_context -top " + module.wrapperName() + " -part " + part + " -include_dirs " + inc_dirs + "\n")

        newTclFile.write("set_property HD.PARTITION 1 [current_design]\n")
    else:
        newTclFile.write("synth_design -top " + module.wrapperName() + " -part " + part + " -include_dirs " + inc_dirs + "\n")

    newTclFile.write("all_clocks\n")
    newTclFile.write("report_clocks\n")
    newTclFile.write("report_utilization -file " + module.wrapperName() + ".synth.preopt.util\n")
    

    # We should do opt_design here because it will be faster in
    # parallel.  However, opt_design seems to cause downstream
    # problems and needs more testing. 
   
    newTclFile.write("opt_design -quiet\n")

    newTclFile.write("report_utilization -file " + module.wrapperName() + ".synth.opt.util\n")
    newTclFile.write("write_checkpoint -force " + module.wrapperName() + ".synth.dcp\n")
    newTclFile.write("close_project -quiet\n")
    newTclFile.close()
    return [prjPath] + blackBoxDeps + annotationDeps


# Converts SRP file into resource representation which can be used
# by the LIM compiler to assign modules to execution platforms.
def getSRPResourcesClosure(module):

    def collect_srp_resources(target, source, env):

        srpFile = str(source[0])
        rscFile = str(target[0])

        srpHandle = open(srpFile, 'r')
        rscHandle = open(rscFile, 'w')
        resources =  {}
        #block ram seems to have floating values.
        attributes = {'LUT': " Number of Slice LUTs",'Reg': " Slice Registers", 'BRAM': " Block RAM Tile"}

        for line in srpHandle:
            for attribute in attributes:
                if (re.match(attributes[attribute],line)):
                    match = re.search(r'\D+(\d+)\D+(\d+)', line)
                    if(match):
                        resources[attribute] = [match.group(1), match.group(2)]

        ## This needs to be merged with the platform-specific LUT to slice
        ## conversion code, currently only in Vivado support code.
        ## For now, we just use a hack.
        if ('LUT' in resources):
            # Assume 6 LUTs per slice
            resources['SLICE'] = [str(int(int(resources['LUT'][0]) / 6.0)),
                                  str(int(int(resources['LUT'][1]) / 6.0))]
        else:
            resources['SLICE'] = ["0", "0"]

        rscHandle.write(module.name + ':')
        rscHandle.write(':'.join([resource + ':' + resources[resource][0] + ':Total' + resource + ':' + resources[resource][1] for resource in resources]) + '\n')
                                   
        rscHandle.close()
        srpHandle.close()
    return collect_srp_resources



# Converts SRP file into resource representation which can be used
# by the LIM compiler to assign modules to execution platforms.
def getVivadoUtilResourcesClosure(module):

    def collect_srp_resources(target, source, env):

        srpFile = str(source[0])
        rscFile = str(target[0])

        srpHandle = open(srpFile, 'r')
        rscHandle = open(rscFile, 'w')
        resources =  {}

        attributes = {'LUT': "\| Slice LUTs",'Reg': "\| Slice Registers", 'BRAM': "\| Block RAM Tile"} 

        primitives = {'LUT6': "\| LUT6", 'LUT5': "\| LUT5", 'LUT4': "\| LUT4",  'LUT3': "\| LUT3",  'LUT2': "\| LUT2",  'LUT1': "\| LUT1", 'SRL16E': '\| SRL16E', "Slice": "\| Slice      ", "RAMD32":"\RAMD32", "RAMS32":"\RAMS32", "RAMD64E":"\RAMD64E"}

        attributes.update(primitives)

        for line in srpHandle:
            for attribute in attributes:
                if (re.search(attributes[attribute],line)):
                    match = False
                    if(attribute in primitives):
                        match = re.search(attributes[attribute] + '\D+(\d+)\D+', line)
                        if(match):
                            # Since the primitives don't really have a
                            # total, give an arbitrarly large number
                            # here.
                            resources[attribute] = [match.group(1), str(10000000)]
                    else:
                        match = re.search(r'\D+(\d+\.?\d*)\D+\d+\D+(\d+)\D+', line)
                        if(match):
                            if(attribute in resources):
                                print "ERROR: Resource extractor found multiple pattern matches"
                                exit(1)
                            resources[attribute] = [match.group(1), match.group(2)]

        # This function figures converts the primitive resource usage
        # to a number of slices. This function is highly device
        # specific. Probably we will need to factor this over to a
        # device library at some point.
        def getResourceCount(deviceResources, resourceType):
            if(resourceType in deviceResources):
                return int(deviceResources[resourceType][0])
            return 0

        def convertSlicesVirtex7(deviceResources):
            slices = 0
            baseLUTs = getResourceCount(deviceResources, 'LUT')
            lut6s = getResourceCount(deviceResources, 'LUT6')
            lut5s = getResourceCount(deviceResources, 'LUT5')
            lut4s = getResourceCount(deviceResources, 'LUT4')
            lut3s = getResourceCount(deviceResources, 'LUT3')
            lut2s = getResourceCount(deviceResources, 'LUT2')
            lut1s = getResourceCount(deviceResources, 'LUT1')            
            ramd32s = getResourceCount(deviceResources, 'RAMD32')            
            rams32s = getResourceCount(deviceResources, 'RAMS32')            
            ram64es = getResourceCount(deviceResources, 'RAMD64E')            
            srl16es = getResourceCount(deviceResources, 'SRL16E')            

            # Some 4/5 LUTs take a whole slice. We'll conservatively
            # assume that they all do.  We should use 'LUT' count to
            # figure out combinability
            slice4LUTs = lut6s + lut5s + lut4s + srl16es + rams32s + 2 * ramd32s + 2 * ram64es  
            slice8LUTs = lut1s + lut2s + lut3s 
            slices = slice8LUTs / 8 + slice4LUTs / 4

            return slices

        # we should really know how many slices we have. But I am not
        # sure how to do that.
        resources['SLICE'] = [str(convertSlicesVirtex7(resources)), str(10000000)]

        rscHandle.write(module.name + ':')
        rscHandle.write(':'.join([resource + ':' + resources[resource][0] + ':Total' + resource + ':' + resources[resource][1] for resource in resources if resource not in primitives]) + '\n')
                                   
        rscHandle.close()
        srpHandle.close()

    return collect_srp_resources

    
def linkNGC(moduleList, module, firstPassLIGraph):
    return li_module.linkFirstPassObject(moduleList, module, firstPassLIGraph, 'GEN_NGCS', 'GEN_NGCS')

def buildNGC(moduleList, module, globalVerilogs, globalVHDs, xstTemplate, xilinx_xcf):
    #Let's synthesize a xilinx .prj file for ths synth boundary.
    # spit out a new prj
    generatePrj(moduleList, module, globalVerilogs, globalVHDs)
    newXSTPath = generateXST(moduleList, module, xstTemplate)

    compile_dir = moduleList.env.Dir(moduleList.compileDirectory)

    ngcFile = compile_dir.File(module.wrapperName() + '.ngc')
    srpFile = compile_dir.File(module.wrapperName() + '.srp')
    resourceFile = compile_dir.File(module.wrapperName() + '.resources')

    # sorted(moduleList.getAllDependencies('VERILOG_LIB')) + sorted(model.convertDependencies(moduleList.getDependencies(module, 'VERILOG_STUB'))))))

    # Sort dependencies because SCons will rebuild if the order changes.
    sub_netlist = moduleList.env.Command(
        [ngcFile, srpFile],
        sorted(module.moduleDependency['VERILOG']) +
        sorted(moduleList.getAllDependencies('VERILOG_LIB')) +
        sorted(model.convertDependencies(moduleList.getDependencies(module, 'VERILOG_STUB'))) +
        [ newXSTPath ] +
        xilinx_xcf,
        [ SCons.Script.Delete(compile_dir.File(module.wrapperName() + '.srp')),
          SCons.Script.Delete(compile_dir.File(module.wrapperName() + '_xst.xrpt')),
          'xst -intstyle silent -ifn config/' + module.wrapperName() + '.modified.xst -ofn ' + compile_dir.File(module.wrapperName() + '.srp').path,
          '@echo xst ' + module.wrapperName() + ' build complete.' ])


    module.moduleDependency['SRP'] = [srpFile]

    if(not 'GEN_NGCS' in module.moduleDependency):
        module.moduleDependency['GEN_NGCS'] = [ngcFile]
    else:
        module.moduleDependency['GEN_NGCS'] += [ngcFile]

    module.moduleDependency['RESOURCES'] = [resourceFile]

    module.moduleDependency['SYNTHESIS'] = [sub_netlist]
    SCons.Script.Clean(sub_netlist, compile_dir.File(module.wrapperName() + '.srp'))

    moduleList.env.Command(resourceFile,
                           srpFile,
                           getSRPResourcesClosure(module))

    # If we're building for the FPGA, we'll claim that the
    # top-level build depends on the existence of the ngc
    # file. This allows us to do resource analysis later on.
    if(moduleList.getAWBParam('bsv_tool', 'BUILD_LOGS_ONLY')):
        moduleList.topDependency += [resourceFile]      
    return sub_netlist


def buildVivadoEDF(moduleList, module, globalVerilogs, globalVHDs):

    compile_dir = moduleList.env.Dir(moduleList.compileDirectory)
    vivadoCompileDirectory = compile_dir.Dir(module.wrapperName() + '_synth/')

    if not os.path.isdir(str(vivadoCompileDirectory)):
       os.mkdir(str(vivadoCompileDirectory))

    #Let's synthesize a xilinx .prj file for this synth boundary.
    # spit out a new prj
    tclDeps = generateVivadoTcl(moduleList, module, globalVerilogs, globalVHDs, vivadoCompileDirectory)

    checkpointFile = vivadoCompileDirectory.File(module.wrapperName() + '.synth.dcp')
    edfFile = vivadoCompileDirectory.File(module.wrapperName() + '.edf')
    srpFile = vivadoCompileDirectory.File(module.wrapperName() + '.synth.opt.util')
    logFile = module.wrapperName() + '.synth.log'
    resourceFile = vivadoCompileDirectory.File(module.wrapperName() + '.resources')

    # area group modules have a different base dependency than normal
    # modules
    wrapperVerilogDependency = model.get_temp_path(moduleList,module) + module.wrapperName() + '_stub.v'
    if(not module.getAttribute('AREA_GROUP') is None):
        # grab the parent stub?          
        wrapperVerilogDependency = model.get_temp_path(moduleList,module) + module.wrapperName() + '.v'

    # Sort dependencies because SCons will rebuild if the order changes.
    sub_netlist = moduleList.env.Command(
        [edfFile, srpFile, checkpointFile],
        [wrapperVerilogDependency] +
        sorted(moduleList.getDependencies(module,'VERILOG')) +
        tclDeps + 
        sorted(moduleList.getAllDependencies('VERILOG_LIB')) +
        sorted(model.convertDependencies(moduleList.getDependencies(module, 'VERILOG_STUB'))),
        [ SCons.Script.Delete(vivadoCompileDirectory.File(module.wrapperName() + '.synth.opt.util')),
          SCons.Script.Delete(vivadoCompileDirectory.File(module.wrapperName() + '_xst.xrpt')),
          'cd ' + vivadoCompileDirectory.path + '; touch start.txt; vivado -nojournal -mode batch -source ' + module.wrapperName() + '.synthesis.tcl 2>&1 > ' + logFile,
          '@echo vivado synthesis ' + module.wrapperName() + ' build complete.' ])

    utilFile = moduleList.env.Command(resourceFile,
                                      srpFile,
                                      getVivadoUtilResourcesClosure(module))

    module.moduleDependency['SRP'] = [srpFile]

    if (not 'GEN_NGCS' in module.moduleDependency):
        module.moduleDependency['GEN_NGCS'] = [edfFile]
    else:
        module.moduleDependency['GEN_NGCS'] += [edfFile]

    module.moduleDependency['GEN_VIVADO_DCPS'] = [checkpointFile]

    module.moduleDependency['RESOURCES'] = [utilFile]

    module.moduleDependency['SYNTHESIS'] = [edfFile]
    SCons.Script.Clean(sub_netlist,  compile_dir.File(module.wrapperName() + '.srp'))

    # If we're building for the FPGA, we'll claim that the
    # top-level build depends on the existence of the ngc
    # file. This allows us to do resource analysis later on.
    if(moduleList.getAWBParam('bsv_tool', 'BUILD_LOGS_ONLY')):
        moduleList.topDependency += [utilFile]      

    return sub_netlist


#
# Configure the top-level Xst build
#
def buildXSTTopLevel(moduleList, firstPassGraph):
    compile_dir = moduleList.env.Dir(moduleList.compileDirectory)

    BUILD_LOGS_ONLY = moduleList.getAWBParam('bsv_tool', 'BUILD_LOGS_ONLY')
    
    # string together the xcf, sort of like the ucf                                                                                                          
    # Concatenate UCF files     
                                                                                                                             
    if('XCF' in moduleList.topModule.moduleDependency and len(moduleList.topModule.moduleDependency['XCF']) > 0):
        xilinx_xcf = moduleList.env.Command(
            compile_dir.File(moduleList.topModule.wrapperName() + '.xcf'),
            moduleList.topModule.moduleDependency['XCF'],
            'cat $SOURCES > $TARGET')
    else:
        xilinx_xcf = moduleList.env.Command(
            compile_dir.File(moduleList.topModule.wrapperName() + '.xcf'),
            [],
            'touch $TARGET')

    ## tweak top xst file                                                        
    #Only parse the xst file once.  
    templates = moduleList.getAllDependenciesWithPaths('GIVEN_XSTS')
    if(len(templates) != 1):
        print "Found more than one XST template file: " + str(templates) + ", exiting\n" 
    templateFile = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + templates[0]
    xstTemplate = parameter_substitution.parseAWBFile(templateFile)
                  
    [globalVerilogs, globalVHDs] = globalRTLs(moduleList, moduleList.moduleList)
    synth_deps = []
 
    if(not firstPassGraph is None):
        wrapper_gen.validateFirstPassLIGraph(moduleList)

    for module in [ mod for mod in moduleList.synthBoundaries() if mod.platformModule]:
        if((not firstPassGraph is None) and (module.name in firstPassGraph.modules)):
            # we link from previous.
            synth_deps += linkNGC(moduleList, module, firstPassLIGraph)
        else:
            synth_deps += buildNGC(moduleList, module, globalVerilogs, globalVHDs, xstTemplate, xilinx_xcf)

    generatePrj(moduleList, moduleList.topModule, globalVerilogs, globalVHDs)
    topXSTPath = generateXST(moduleList, moduleList.topModule, xstTemplate)       

    # Use xst to tie the world together.
    topSRP = compile_dir.File(moduleList.topModule.wrapperName() + '.srp')

    top_netlist = moduleList.env.Command(
        compile_dir.File(moduleList.topModule.wrapperName() + '.ngc'),
        moduleList.topModule.moduleDependency['VERILOG'] +
        moduleList.getAllDependencies('VERILOG_STUB') +
        moduleList.getAllDependencies('VERILOG_LIB') +
        [ templateFile ] +
        [ topXSTPath ] + xilinx_xcf,
        [ SCons.Script.Delete(topSRP),
          SCons.Script.Delete(compile_dir.File(moduleList.apmName + '_xst.xrpt')),
          'xst -intstyle silent -ifn config/' + moduleList.topModule.wrapperName() + '.modified.xst -ofn ' + topSRP,
          '@echo xst ' + moduleList.topModule.wrapperName() + ' build complete.' ])    

    SCons.Script.Clean(top_netlist, topSRP)

    if(not BUILD_LOGS_ONLY):
        moduleList.topModule.moduleDependency['SYNTHESIS'] = [top_netlist]
        return [top_netlist] + synth_deps
    else:
        moduleList.topModule.moduleDependency['SYNTHESIS'] = synth_deps
        return synth_deps

####
#
# buildNetlists -
#   A parameteric function for building the netlists of a design. It takes three
#   arguments: the build context (moduleList), a netlist builder for the user module
#   (userModuleBuilder) and a builder for the platform (platformModuleBuilder).  
#   buildNetlists then invokes these functions as part of a parallel build process.
#
def buildNetlists(moduleList, userModuleBuilder, platformModuleBuilder):
    # We load this graph in to memory several times. 
    # TODO: load this graph once. 
    firstPassLIGraph = wrapper_gen_tool.getFirstPassLIGraph()

    DEBUG = model.getBuildPipelineDebug(moduleList) 

    # string together the xcf, sort of like the ucf
    # Concatenate XCF files
    MODEL_CLOCK_FREQ = moduleList.getAWBParam('clocks_device', 'MODEL_CLOCK_FREQ')

    ngcModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore] 

    [globalVerilogs, globalVHDs] = globalRTLs(moduleList, moduleList.moduleList)

    synth_deps = []
    # drop exiting boundaries. 

    for module in ngcModules:   
        # did we get an ngc from the first pass?  If so, did the lim
        # graph give code for this module?  If both are true, then we
        # will link the old ngc in, rather than regenerate it. 

        if((not firstPassLIGraph is None) and (module.name in firstPassLIGraph.modules) and (firstPassLIGraph.modules[module.name].getAttribute('RESYNTHESIZE') is None)):
            synth_deps += linkNGC(moduleList, module, firstPassLIGraph)
        else:
            # We need to build the netlist. We build platformModules
            # with the platformModuleBuilder.  User modules get built
            # with userModuleBuilder.
            if(module.platformModule):
                synth_deps += platformModuleBuilder(moduleList, module, globalVerilogs, globalVHDs)
            else:
                synth_deps += userModuleBuilder(moduleList, module, globalVerilogs, globalVHDs)


    top_netlist = platformModuleBuilder(moduleList, moduleList.topModule, globalVerilogs, globalVHDs)
    synth_deps += top_netlist
    moduleList.topModule.moduleDependency['SYNTHESIS'] = synth_deps

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)



######
#
# leap_physical_summary -
# Generate a summary of the build and write a target file describing
# whether the build was successful. Achieved by searching for flow specific 
# strings in the post-place and route log.
#
def leap_physical_summary(physical_result, errinfo, success_string, failure_string):
    def leap_physical_summary_closure(target, source, env):
        par_file = open(physical_result,'r')
        errinfo_file = open(errinfo, 'w')

        timing_score = None
        clk_err = 0

        for full_line in par_file:
            line = full_line.rstrip()
            # do a quartus specific search.   
            match = re.search(r'' + success_string, line)
            if (match):
                timing_score = 0 

            match = re.search(r'' + failure_string, line)
            if (match):
                timing_score = 1 
                break

        par_file.close()

        if (timing_score is None):
            print 'Failed to find timing score!'
            clk_err = 1

        if (clk_err or timing_score > 0):
            print '\n        ******** Design does NOT meet timing! ********\n'
            errinfo_file.write('Slack was violated.\n')
        else:
            print '\nDesign meets timing.'

        errinfo_file.close()

        # Timing failures are reported as non-fatal errors.  The error is
        # noted but the build continues.
        if (clk_err or timing_score > 0):
            model.nonFatalFailures.append(str(target[0]))

    return leap_physical_summary_closure
