import os
import sys
import re
import string
import SCons.Script
from model import  *


#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path



class MCD():

  # apparently for functional-style python we can only pass a reference
  # to a function so, all args must be a part of the object.
  # we also apparently get to see target, source, and env in the build
  def mcdCommand(self, target, source, env):

    # the tcl script will be locate in the hw/model directory
    # we could search for it, but it probably isn't needed. 
    mcd_ostream = os.popen('bluetcl ./hw/model/mcd.tcl  -p ' + self.bluespecBuilddirs)
 
    # Open file, into which we will dump the magic TIG strings 
    mcdUCF = open(self.mcdUCFFile,'w')
    
    i = 0
    for clock in mcd_ostream.readlines():
      clock_s = string.strip(clock)
      mcdUCF.write('\nNET  "' + clock_s + '" TNM_NET = ff_clk_' + str(i) +';\n') 
      ## This is wrong.  We need to find the true frequency of each clock
      ## domain.  For now we act as though all are at MODEL_CLOCK_FREQ.
      mcdUCF.write('TIMESPEC TS_ff_clk_' + str(i) + ' = PERIOD ff_clk_' + str(i) + ' ' +
                   str(self.modelClockFreq) + 'MHz HIGH 50%;\n')
      i = i + 1
      

    for clk1 in range(0,i):
      for clk2 in range(clk1 + 1,i):
        mcdUCF.write('TIMESPEC TS_'+ str(clk1) +'_'+ str(clk2) + '= FROM ff_clk_' + str(clk1) + ' TO ff_clk_' + str(clk2) + ' TIG;\n')
        mcdUCF.write('TIMESPEC TS_'+ str(clk2) +'_'+ str(clk1) + '= FROM ff_clk_' + str(clk2) + ' TO ff_clk_' + str(clk1) + ' TIG;\n')
   

    mcdUCF.close();

    # we need to snuff out those extra BUFG, which xilinx loves to instantiate
    bufg_ostream = os.popen('bluetcl ./hw/model/bufg.tcl  -p ' + self.bluespecBuilddirs)


    mcdXCF = open(self.mcdXCFFile,'w')

    mcdXCF.write(bufg_ostream.read())
    mcdXCF.close();
    # maybe we should be writing an xcf herew to keep these clocks around?
    

  def __init__(self, moduleList):
   
    # concat the modules and the top
    allModules = [moduleList.topModule] + moduleList.synthBoundaries()
    self.mcdUCFFile = 'config/' + moduleList.topModule.wrapperName() + '.mcd.ucf' 
    self.mcdXCFFile = 'config/' + moduleList.topModule.wrapperName() + '.mcd.xcf' 
    self.bluespecBuilddirs = ''

    for boundary in allModules:
      self.bluespecBuilddirs += 'hw/' + boundary.buildPath + '/.bsc/:'

    # need ifc as well
    self.bluespecBuilddirs += './iface/build/hw/.bsc/'

    self.modelClockFreq = int(moduleList.getAWBParam('clocks_device', 'MODEL_CLOCK_FREQ'))

        
    # although we examine the log files, we depend on the 
    # verilogs which are produced in conjunction.
    # thus we must wait to run
    if('UCF' in moduleList.topModule.moduleDependency):
        mcd_ucf = moduleList.env.Command(
        [self.mcdUCFFile, self.mcdXCFFile],
        moduleList.topModule.moduleDependency['VERILOG'],
        self.mcdCommand)
        moduleList.topModule.moduleDependency['UCF'] = moduleList.topModule.moduleDependency['UCF'] + [self.mcdUCFFile]
        moduleList.topModule.moduleDependency['XCF'] = moduleList.topModule.moduleDependency['XCF'] + [self.mcdXCFFile]
        SCons.Script.Clean(moduleList.topModule.moduleDependency['UCF'] , self.mcdUCFFile)
        SCons.Script.Clean(moduleList.topModule.moduleDependency['XCF'] , self.mcdXCFFile)


