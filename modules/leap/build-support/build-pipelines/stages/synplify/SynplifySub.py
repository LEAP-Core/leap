import os
import re
import SCons.Script  
from model import  *
# need to get the model clock frequency
from clocks_device import  *
from config import  *


#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

def _generate_synplify_include(file):
  #Check for relative/absolute path
  directoryFix = ''
  if(not re.search('^\s*/',file)):
    directoryFix = '$env(BUILD_DIR)/'

  type = 'unknown'

  if(re.search('\.ngc\s*$',file)):
    type = 'ngc'

  if(re.search('\.v\s*$',file)):
    type = 'verilog'

  if(re.search('\.vhdl\*$',file)):
    type = 'vhdl'

  if(re.search('\.vhd\s*$',file)):
    type = 'vhdl'
    
  if(re.search('\.ucf\s*$',file)):
    type = 'ucf'

  return 'add_file -'+ type +' \"'+ directoryFix + file + '\"\n'

def _filter_file_add(file):
  #Check for relative/absolute path   
  output = ''
  for line in file.readlines():
    output += re.sub('add_file.*$','',line)
    if(SYNPLIFY_DEBUG == 1):
      print 'converted ' + line + 'to ' + re.sub('add_file.*$','',line)

  return output;

class Synthesize(ProjectDependency):
  def __init__(self, moduleList):

    # We first do things related to the Xilinx build

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
    newXSTFile = open('config/' + moduleList.topModule.wrapperName() + '.modified.xst','w')
    oldXSTFile = open('config/' + moduleList.topModule.wrapperName() + '.xst','r')
    newXSTFile.write(oldXSTFile.read());
    newXSTFile.write('-iobuf yes\n');
    newXSTFile.write('-uc ' + moduleList.env['DEFS']['BUILD_DIR'] + '/'+ moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName()+ '.xcf\n');
    newXSTFile.close();
    oldXSTFile.close();

    synthDeps = []

    for module in moduleList.synthBoundaries():

       # need to eventually break this out into a seperate function
       # first step - modify prj options file to contain any generated wrappers
       prjFile = open('config/' + moduleList.apmName  + '.synplify.prj','r');  
       newPrjFile = open('config/' + module.wrapperName()  + '.modified.synplify.prj','w');  


       newPrjFile.write('add_file -verilog \"$env(BUILD_DIR)/hw/'+module.buildPath + '/.bsc/' + module.wrapperName()+'.v\"\n');      

       # now dump all the 'VERILOG' 
       fileArray = moduleList.getAllDependencies('VERILOG') + moduleList.getAllDependencies('VHD') + moduleList.getAllDependencies('NGC') + ['config/' + moduleList.topModule.wrapperName() + '.ucf'] 
       for file in fileArray:
         if(type(file) is str):
           newPrjFile.write(_generate_synplify_include(file))        
         else:
           if(SYNPLIFY_DEBUG == 1):
             print type(file)
             print "is not a string"

       #Set up new implementation
  
       #once we get synth boundaries up, this will be needed only for top level
       newPrjFile.write('set_option -disable_io_insertion 1\n')
       newPrjFile.write('set_option -frequency ' + str(MODEL_CLOCK_FREQ) + '\n')

       newPrjFile.write('impl -add ' + module.wrapperName()  + ' -type fpga\n')

       #dump synplify options file
       # MAYBE NOT A GOOD IDEA

       newPrjFile.write(_filter_file_add(prjFile))

       #write the tail end of the options file to actually do the synthesis
     
       newPrjFile.write('set_option -top_module '+ module.wrapperName() +'\n')
       newPrjFile.write('project -result_file \"$env(BUILD_DIR)/' + moduleList.compileDirectory + '/' + module.wrapperName() + '.edf\"\n')



       
       newPrjFile.write('project -run hdl_info_gen fileorder\n');
    
       newPrjFile.write('project -run constraint_check\n');
       newPrjFile.write('project -run synthesis\n');
       newPrjFile.write('impl -active \"'+ module.wrapperName() +'\"\n');


       newPrjFile.close();
       prjFile.close();

       sub_netlist = moduleList.env.Command(
        [moduleList.compileDirectory + '/' +  module.wrapperName() + '.edf'],
        moduleList.getAllDependencies('VERILOG')+  moduleList.getAllDependencies('VERILOG_STUB')+ ['config/' + moduleList.apmName + '.synplify.prj'],
        [ SCons.Script.Delete(moduleList.compileDirectory + '/' + module.wrapperName()  + '.srr'),
          SCons.Script.Delete(moduleList.compileDirectory + '/' + module.wrapperName()  + '_xst.xrpt'), 
          'synplify_pro -batch config/' + module.wrapperName() + '.modified.synplify.prj' ])
       SCons.Script.Clean(sub_netlist,moduleList.compileDirectory + '/' + module.wrapperName() + '.srr')
       SCons.Script.Clean(sub_netlist,'config/' + module.wrapperName() + '.modified.synplify.prj')

       synthDeps += sub_netlist

    # Now we use Xilinx to tie the world together.

    topSRP = moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.srp'

    top_netlist = moduleList.env.Command(
        moduleList.compileDirectory + '/' + moduleList.topModule.wrapperName() + '.ngc',
        moduleList.topModule.moduleDependency['VERILOG'] +  moduleList.getAllDependencies('VERILOG_STUB') + moduleList.topModule.moduleDependency['XST'] + moduleList.topModule.moduleDependency['XCF'] + xilinx_xcf + synthDeps,
        [ SCons.Script.Delete(topSRP),
          SCons.Script.Delete(moduleList.compileDirectory + '/' + moduleList.apmName + '_xst.xrpt'),

          'xst -intstyle silent -ifn config/' + moduleList.topModule.wrapperName() + '.modified.xst -ofn ' + topSRP,
          '@echo xst ' + moduleList.apmName + ' build complete.' ])    

    moduleList.topModule.moduleDependency['SYNTHESIS'] = [top_netlist]
    SCons.Script.Clean(top_netlist, topSRP)

    # Alias for synthesis
    moduleList.env.Alias('synth', [top_netlist])
