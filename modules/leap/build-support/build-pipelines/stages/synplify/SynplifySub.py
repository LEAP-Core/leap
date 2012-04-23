import os
import errno
import re
import SCons.Script  
from model import  *
# need to get the model clock frequency
from clocks_device import  *


#
# Generate path string to add source file into the Synplify project
#
def _generate_synplify_include(file):
  # Check for relative/absolute path
  directoryFix = ''
  if (not re.search('^\s*/',file)):  directoryFix = '../'

  type = 'unknown'
  if (re.search('\.ngc\s*$',file)):  type = 'ngc'
  if (re.search('\.v\s*$',file)):    type = 'verilog'
  if (re.search('\.vhdl\*$',file)):  type = 'vhdl'
  if (re.search('\.vhd\s*$',file)):  type = 'vhdl'
  if (re.search('\.ucf\s*$',file)):  type = 'ucf'
  if (re.search('\.sdc\s*$',file)):  type = 'constraint'

  return 'add_file -'+ type +' \"'+ directoryFix + file + '\"\n'


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
def _xst_top_level(moduleList):
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
  topXSTPath = 'config/' + moduleList.topModule.wrapperName() + '.modified.xst'
  newXSTFile = open(topXSTPath, 'w')
  oldXSTFile = open('config/' + moduleList.topModule.wrapperName() + '.xst','r')
  newXSTFile.write(oldXSTFile.read());
  if moduleList.getAWBParam('synthesis_tool', 'XST_PARALLEL_CASE'):
    newXSTFile.write('-vlgcase parallel\n');
  if moduleList.getAWBParam('synthesis_tool', 'XST_INSERT_IOBUF'):
    newXSTFile.write('-iobuf yes\n');
  else:
    newXSTFile.write('-iobuf no\n');
  newXSTFile.write('-uc ' + moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.xcf\n');
  newXSTFile.close();
  oldXSTFile.close();

  # Use xst to tie the world together.
  topSRP = moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.srp'

  top_netlist = moduleList.env.Command(
    moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.ngc',
    moduleList.topModule.moduleDependency['VERILOG'] +
    moduleList.getAllDependencies('VERILOG_STUB') +
    moduleList.getAllDependencies('VERILOG_LIB') +
    moduleList.topModule.moduleDependency['XST'] +
    [ topXSTPath ] +
    xilinx_xcf,
    [ SCons.Script.Delete(topSRP),
      SCons.Script.Delete(moduleList.compileDirectory + '/' + moduleList.apmName + '_xst.xrpt'),
      'xst -intstyle silent -ifn config/' + moduleList.topModule.wrapperName() + '.modified.xst -ofn ' + topSRP,
      '@echo xst ' + moduleList.topModule.wrapperName() + ' build complete.' ])    

  SCons.Script.Clean(top_netlist, topSRP)

  return top_netlist



class Synthesize(ProjectDependency):
  def __init__(self, moduleList):

    # We first do things related to the Xilinx build

    if (getBuildPipelineDebug(moduleList) != 0):
        print "Env BUILD_DIR = " + moduleList.env['ENV']['BUILD_DIR']

    synth_deps = []

    for module in moduleList.synthBoundaries():
      # need to eventually break this out into a seperate function
      # first step - modify prj options file to contain any generated wrappers
      prjFile = open('config/' + moduleList.apmName  + '.synplify.prj','r');  
      newPrjPath = 'config/' + module.wrapperName()  + '.modified.synplify.prj'
      newPrjFile = open(newPrjPath,'w');  

      newPrjFile.write('add_file -verilog \"../hw/'+module.buildPath + '/.bsc/' + module.wrapperName()+'.v\"\n');      

      # now dump all the 'VERILOG' 
      fileArray = moduleList.getAllDependencies('VERILOG') + \
                  moduleList.getAllDependencies('VERILOG_LIB') + \
                  moduleList.getAllDependencies('VHD') + \
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
  
      # once we get synth boundaries up, this will be needed only for top level
      newPrjFile.write('set_option -disable_io_insertion 1\n')
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

      sub_netlist = moduleList.env.Command(
        [build_dir + '/' +  module.wrapperName() + '.edf'],
        moduleList.getAllDependencies('VERILOG') +
        moduleList.getAllDependencies('VERILOG_STUB') +
        moduleList.getAllDependencies('VERILOG_LIB') +
        [moduleList.compileDirectory + '/' + moduleList.apmName + '.ucf'] +        
        [ newPrjPath ] +
        ['config/' + moduleList.apmName + '.synplify.prj'],
        [ SCons.Script.Delete(build_dir + '/' + module.wrapperName()  + '.srr'),
          'synplify_pro -batch -license_wait ' + newPrjPath + '> ' + build_dir + '.log',
          # Files in coreip just copied from elsewhere and waste space
          SCons.Script.Delete(build_dir + '/coreip'),
          '@echo synplify_pro ' + module.wrapperName() + ' build complete.' ])    

      module.moduleDependency['SYNTHESIS'] = [sub_netlist]
      synth_deps += sub_netlist

      SCons.Script.Clean(sub_netlist, build_dir + '/' + module.wrapperName() + '.srr')
      SCons.Script.Clean(sub_netlist, 'config/' + module.wrapperName() + '.modified.synplify.prj')

    # Build the top level using Xst
    top_netlist = _xst_top_level(moduleList)

    moduleList.topModule.moduleDependency['SYNTHESIS'] = [top_netlist]
    synth_deps += top_netlist

    # Alias for synthesis
    moduleList.env.Alias('synth', synth_deps)
