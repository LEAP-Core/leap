import os
import errno
import re
import SCons.Script  
from model import  *
# need to get the model clock frequency
from clocks_device import  *
from synthesis_library import  *
from wrapper_gen_tool import *

#
# Generate path string to add source file into the Synplify project
#
def _generate_synplify_include(file):
    # Check for relative/absolute path
    directoryFix = ''
    if (not re.search('^\s*/',file)):  directoryFix = '../'

    type = 'unknown'
    prefix = ''
    if (re.search('\.ngc\s*$',file)):  
        type = 'ngc'
    if (re.search('\.v\s*$',file)):    
        type = 'verilog'
    if (re.search('\.sv\s*$',file)):    
        type = 'verilog'
        prefix = ' -vlog_std sysv '
    if (re.search('\.vhdl\s*$',file)):  
        type = 'vhdl'
    if (re.search('\.vhd\s*$',file)):  
        type = 'vhdl'
    if (re.search('\.ucf\s*$',file)):  
        type = 'ucf'
    if (re.search('\.sdc\s*$',file)):  
        type = 'constraint'

    # don't include unidentified files
    if(type == 'unknown'):
        return ''

    return 'add_file -' + type + prefix + ' \"'+ directoryFix + file + '\"\n'


def _filter_file_add(file, moduleList):
  # Check for relative/absolute path   
  output = ''
  for line in file.readlines():
      output += re.sub('add_file.*$','',line)
      if (getBuildPipelineDebug(moduleList) != 0):
          print 'converted ' + line + 'to ' + re.sub('add_file.*$','',line)

  return output;


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
    

# Converts SRR file into resource representation which can be used
# by the LIM compiler to assign modules to execution platforms.
def getSRRResourcesClosure(module):

    def collect_srr_resources(target, source, env):

        srrFile = str(source[0])
        rscFile = str(target[0])

        srrHandle = open(srrFile, 'r')
        rscHandle = open(rscFile, 'w')
        resources =  {}

        attributes = {'LUT': "Total  LUTs:",'Reg': "Register bits not including I/Os:", 'BRAM': " Number of Block RAM/FIFO:"}

        for line in srrHandle:
            for attribute in attributes:
                if (re.match(attributes[attribute],line)):
                    print "LINE: " + line
                    match = re.search(r'\D+:\D+(\d+)', line)
                    if(match):
                        resources[attribute] = [match.group(1)]

        rscHandle.write(module.name + ':')
        rscHandle.write(':'.join([resource + ':' + resources[resource][0] for resource in resources]) + '\n')
                                   
        rscHandle.close()
        srrHandle.close()
    return collect_srr_resources

class Synthesize(ProjectDependency):
  def __init__(self, moduleList):

    # We load this graph in to memory several times. 
    # TODO: load this graph once. 
    self.firstPassLIGraph = getFirstPassLIGraph()

    MODEL_CLOCK_FREQ = moduleList.getAWBParam('clocks_device', 'MODEL_CLOCK_FREQ')

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
            # need to eventually break this out into a seperate function
            # first step - modify prj options file to contain any generated wrappers
            prjFile = open('config/' + moduleList.apmName  + '.synplify.prj','r');  
            newPrjPath = 'config/' + module.wrapperName()  + '.modified.synplify.prj'
            newPrjFile = open(newPrjPath,'w');  

            newPrjFile.write('add_file -verilog \"../hw/'+module.buildPath + '/.bsc/' + module.wrapperName()+'.v\"\n');      

            # now dump all the 'VERILOG' 
            fileArray = globalVerilogs + globalVHDs + \
                        moduleList.getDependencies(module, 'VERILOG_STUB') + \
                        map(lambda x: moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + x, moduleList.getAllDependenciesWithPaths('GIVEN_SYNPLIFY_VERILOGS')) + \
                        moduleList.getAllDependencies('NGC') + \
                        moduleList.getAllDependencies('SDC') + \
                        [moduleList.compileDirectory + '/' + moduleList.apmName + '.ucf']

            for file in fileArray:
                if(type(file) is str):
                    newPrjFile.write(_generate_synplify_include(file))        
                else:
                    if(getBuildPipelineDebug(moduleList) != 0):
                        print type(file)
                        print "is not a string"
      
            # Set up new implementation
            build_dir = moduleList.compileDirectory + '/' + module.wrapperName()
            try:
                os.mkdir(build_dir)
            except OSError, err:
                if err.errno != errno.EEXIST: raise 
        

            # establish an include path for synplify.  This is necessary for true text inclusion in verilog,
            # as raw text files don't always compile standalone. Ugly yes, but it is verilog....
            newPrjFile.write('set_option -include_path {')
            newPrjFile.write(";".join(["../" + moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + moduleDir.buildPath for moduleDir in moduleList.synthBoundaries()] + [moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + moduleDir.buildPath for moduleDir in moduleList.synthBoundaries()] + [moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + moduleDir.buildPath + '/.bsv/' for moduleDir in moduleList.synthBoundaries()]))
            newPrjFile.write('}\n')

            # once we get synth boundaries up, this will be needed only for top level
            newPrjFile.write('set_option -disable_io_insertion 1\n')
            newPrjFile.write('set_option -multi_file_compilation_unit 1\n')

            newPrjFile.write('set_option -frequency ' + str(MODEL_CLOCK_FREQ) + '\n')

            newPrjFile.write('impl -add ' + module.wrapperName()  + ' -type fpga\n')

            #dump synplify options file
            # MAYBE NOT A GOOD IDEA
            newPrjFile.write(_filter_file_add(prjFile, moduleList))

            #write the tail end of the options file to actually do the synthesis
            newPrjFile.write('set_option -top_module '+ module.wrapperName() +'\n')
            newPrjFile.write('project -result_file \"../' + build_dir + '/' + module.wrapperName() + '.edf\"\n')
             
            newPrjFile.write('impl -active \"'+ module.wrapperName() +'\"\n');

            # Enable advanced LUT combining
            newPrjFile.write('set_option -enable_prepacking 1\n')

            newPrjFile.write('project -run hdl_info_gen fileorder\n');
            newPrjFile.write('project -run constraint_check\n');
            newPrjFile.write('project -run synthesis\n');

            newPrjFile.close();
            prjFile.close();

            edfFile = build_dir + '/' +  module.wrapperName() + '.edf'
            resourceFile = build_dir + '/' + module.wrapperName() + '.resources'
            srrFile = build_dir + '/' + module.wrapperName()  + '.srr'

            if(not 'GEN_NGCS' in module.moduleDependency):
                module.moduleDependency['GEN_NGCS'] = [edfFile]
            else:
                module.moduleDependency['GEN_NGCS'] += [edfFile]
              
            sub_netlist = moduleList.env.Command(
              [edfFile, srrFile],
              moduleList.getAllDependencies('VERILOG') +
              moduleList.getAllDependencies('VERILOG_STUB') +
              moduleList.getAllDependencies('VERILOG_LIB') +
              #[moduleList.compileDirectory + '/' + moduleList.apmName + '.ucf'] +        
              [ newPrjPath ] +
              ['config/' + moduleList.apmName + '.synplify.prj'],
              [ SCons.Script.Delete(srrFile),
                'synplify_premier -batch -license_wait ' + newPrjPath + '> ' + build_dir + '.log',
                # Files in coreip just copied from elsewhere and waste space
                SCons.Script.Delete(build_dir + '/coreip'),
                '@echo synplify_premier ' + module.wrapperName() + ' build complete.' ])    

            module.moduleDependency['SYNTHESIS'] = [sub_netlist]
            synth_deps += sub_netlist
            module.moduleDependency['RESOURCES'] = [resourceFile]

            moduleList.env.Command(resourceFile,
                                   srrFile,
                                   getSRRResourcesClosure(module))

            # we must gather resources files for the lim build. 
            if(moduleList.getAWBParam('bsv_tool', 'BUILD_LOGS_ONLY') or True):
                moduleList.topDependency += [resourceFile]      

            SCons.Script.Clean(sub_netlist, build_dir + '/' + module.wrapperName() + '.srr')
            SCons.Script.Clean(sub_netlist, 'config/' + module.wrapperName() + '.modified.synplify.prj')
            
    # Build the top level/platform using Xst
    synth_deps += _xst_top_level(moduleList, self.firstPassLIGraph)

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)
