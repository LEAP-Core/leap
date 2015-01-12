import os
import functools
import re

import SCons

import model
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
        print "VHDL:" +  str(v) 
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


# Produce Vivado Synthesis Tcl

def generateVivadoTcl(moduleList, module, globalVerilogs, globalVHDs, vivadoCompileDirectory):
    # spit out a new top-level prj
    prjPath = vivadoCompileDirectory + '/' + module.wrapperName() + '.synthesis.tcl' 
    newTclFile = open(prjPath, 'w') 
 
    # Emit verilog source and stub references
    verilogs = globalVerilogs + [model.get_temp_path(moduleList,module) + module.wrapperName() + '.v']
    verilogs +=  moduleList.getDependencies(module, 'VERILOG_STUB')

    givenNetlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ]

    for vlog in sorted(verilogs):
        relpath = model.rel_if_not_abspath(vlog, vivadoCompileDirectory)
        newTclFile.write("read_verilog -quiet " + relpath + "\n")
       
    for vhd in sorted(globalVHDs):
        if(isinstance(vhd, model.Source.Source)):            
            # Just got a string
            relpath = model.rel_if_not_abspath(vhd.file, vivadoCompileDirectory)
            lib = 'work'
            if('lib' in vhd.attributes):
                newTclFile.write("read_vhdl -lib " + vhd.attributes['lib'] + " " + relpath + "\n")
        else:
            # Just got a string
            relpath = model.rel_if_not_abspath(vhd, vivadoCompileDirectory)
            newTclFile.write("read_vhdl -lib work " + relpath + "\n")

    for netlist in givenNetlists:
        relpath = model.rel_if_not_abspath(netlist, vivadoCompileDirectory)
        newTclFile.write('read_edif ' + relpath + '\n')

    # Eventually we will want to add some of these to the synthesis tcl
    # From UG905 pg. 11, involving clock definition.

    # We need to declare a top-level clock.  Unfortunately, the platform module will require special handling. 
    clockFiles = []

    if(not module.platformModule):        
        MODEL_CLOCK_FREQ = moduleList.getAWBParam('clocks_device', 'MODEL_CLOCK_FREQ')
        clockTclPath = vivadoCompileDirectory + '/' + module.wrapperName() + '.clocks.tcl'  
        clockTclFile = open(clockTclPath, 'w') 
        clockTclFile.write('create_clock -name ' + module.name + '_CLK -period ' + str(1000.0/MODEL_CLOCK_FREQ) + ' [get_ports CLK]\n')
        clockTclFile.close()
        clockFiles = [os.path.relpath(clockTclPath, vivadoCompileDirectory)]
    else:
        if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_SYNTHESISS')) > 0):
            clockFiles = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_SYNTHESISS'))
            relpathCurry = functools.partial(os.path.relpath, start = vivadoCompileDirectory)
            clockFiles = map(relpathCurry, clockFiles)   

    for file in clockFiles:
        newTclFile.write("add_files " + file + "\n")
        newTclFile.write("set_property USED_IN {synthesis implementation out_of_context} [get_files " + file + "]\n")

    part = moduleList.getAWBParam('physical_platform_config', 'FPGA_PART_XILINX')
    # the out of context option instructs the tool not to place iobuf
    # and friends on the external ports.
    newTclFile.write("synth_design -mode out_of_context -top " + module.wrapperName() + " -part " + part  + "\n")
    newTclFile.write("report_utilization -file " + module.wrapperName() + ".synth.preopt.util\n")
    newTclFile.write("set_property HD.PARTITION 1 [current_design]\n")

    # We should do opt_design here because it will be faster in
    # parallel.  However, opt_design seems to cause downstream
    # problems and needs more testing. 
   
    #if(not module.platformModule):
    #    newTclFile.write("opt_design -quiet\n")

    newTclFile.write("report_utilization -file " + module.wrapperName() + ".synth.opt.util\n")
    newTclFile.write("write_checkpoint -force " + module.wrapperName() + ".synth.dcp\n")
    newTclFile.write("write_edif " + module.wrapperName() + ".edf\n")

    newTclFile.close()
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
    deps = []
    moduleObject = firstPassLIGraph.modules[module.name]
    if('GEN_NGCS' in moduleObject.objectCache):
        for ngc in moduleObject.objectCache['GEN_NGCS']:
            linkPath = moduleList.compileDirectory + '/' + os.path.basename(ngc)
            def linkNGC(target, source, env):
                # It might be more useful if the Module contained a pointer to the LIModules...                        
                if(os.path.lexists(str(target[0]))):
                    os.remove(str(target[0]))
                print "Linking: " + str(source[0]) + " to " + str(target[0])
                os.symlink(str(source[0]), str(target[0]))
            moduleList.env.Command(linkPath, ngc, linkNGC)            
            module.moduleDependency['SYNTHESIS'] = [linkPath]
            deps += [linkPath]
        else:
            # Warn that we did not find the ngc we expected to find..
            print "Warning: We did not find an ngc file for module " + module.name 
    return deps

def buildNGC(moduleList, module, globalVerilogs, globalVHDs, xstTemplate, xilinx_xcf):
    #Let's synthesize a xilinx .prj file for ths synth boundary.
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
        sorted(model.convertDependencies(moduleList.getDependencies(module, 'VERILOG_STUB'))) +
        [ newXSTPath ] +
        xilinx_xcf,
        [ SCons.Script.Delete(moduleList.compileDirectory + '/' + module.wrapperName() + '.srp'),
          SCons.Script.Delete(moduleList.compileDirectory + '/' + module.wrapperName() + '_xst.xrpt'),
          'xst -intstyle silent -ifn config/' + module.wrapperName() + '.modified.xst -ofn ' + moduleList.compileDirectory + '/' + module.wrapperName() + '.srp',
          '@echo xst ' + module.wrapperName() + ' build complete.' ])


    module.moduleDependency['SRP'] = [srpFile]

    if(not 'GEN_NGCS' in module.moduleDependency):
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


def buildVivadoEDF(moduleList, module, globalVerilogs, globalVHDs):

    vivadoCompileDirectory = moduleList.compileDirectory + '/' + module.wrapperName() + '_synth/' 

    if not os.path.isdir(vivadoCompileDirectory):
       os.mkdir(vivadoCompileDirectory)

    #Let's synthesize a xilinx .prj file for this synth boundary.
    # spit out a new prj
    generateVivadoTcl(moduleList, module, globalVerilogs, globalVHDs, vivadoCompileDirectory)

    edfFile = vivadoCompileDirectory + '/' + module.wrapperName() + '.edf'
    srpFile = vivadoCompileDirectory + '/' + module.wrapperName() + '.synth.opt.util'
    logFile = module.wrapperName() + '.synth.log'
    resourceFile = vivadoCompileDirectory + '/' + module.wrapperName() + '.resources'

    # Sort dependencies because SCons will rebuild if the order changes.
    sub_netlist = moduleList.env.Command(
        [edfFile, srpFile],
        [model.get_temp_path(moduleList,module) + module.wrapperName() + '_stub.v'] +
        sorted(module.moduleDependency['VERILOG']) +
        sorted(moduleList.getAllDependencies('VERILOG_LIB')) +
        sorted(model.convertDependencies(moduleList.getDependencies(module, 'VERILOG_STUB'))),
        [ SCons.Script.Delete(vivadoCompileDirectory + '/' + module.wrapperName() + '.synth.opt.util'),
          SCons.Script.Delete(vivadoCompileDirectory + '/' + module.wrapperName() + '_xst.xrpt'),
          'cd ' + vivadoCompileDirectory + '; vivado -nojournal -mode batch -source ' + module.wrapperName() + '.synthesis.tcl > ' + logFile,
          '@echo vivado synthesis ' + module.wrapperName() + ' build complete.' ])


    module.moduleDependency['SRP'] = [srpFile]

    if(not 'GEN_NGCS' in module.moduleDependency):
        module.moduleDependency['GEN_NGCS'] = [edfFile]
    else:
        module.moduleDependency['GEN_NGCS'] += [edfFile]

    module.moduleDependency['RESOURCES'] = [resourceFile]

    module.moduleDependency['SYNTHESIS'] = [sub_netlist]
    SCons.Script.Clean(sub_netlist,  moduleList.compileDirectory + '/' + module.wrapperName() + '.srp')

    utilFile = moduleList.env.Command(resourceFile,
                                      srpFile,
                                      getVivadoUtilResourcesClosure(module))

    # If we're building for the FPGA, we'll claim that the
    # top-level build depends on the existence of the ngc
    # file. This allows us to do resource analysis later on.
    if(moduleList.getAWBParam('bsv_tool', 'BUILD_LOGS_ONLY')):
        moduleList.topDependency += [resourceFile]      

    return sub_netlist


#
# Configure the top-level Xst build
#
def buildXSTTopLevel(moduleList, firstPassGraph):
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
    xstTemplate = parameter_substitution.parseAWBFile(templateFile)
                  

    [globalVerilogs, globalVHDs] = globalRTLs(moduleList, moduleList.moduleList)
    synth_deps = []
    for module in [ mod for mod in moduleList.synthBoundaries() if mod.platformModule]:
        if((not firstPassGraph is None) and (module.name in firstPassGraph.modules)):
            # we link from previous.
            synth_deps += linkNGC(moduleList, module, firstPassLIGraph)
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
        if((not firstPassLIGraph is None) and (module.name in firstPassLIGraph.modules)):
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
