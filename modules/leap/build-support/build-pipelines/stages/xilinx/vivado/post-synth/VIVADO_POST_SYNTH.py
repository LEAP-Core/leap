import os
import re
import sys
import SCons.Script
from model import  *

import xilinx_loader

#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class PostSynthesize():
  def __init__(self, moduleList):

    apm_name = moduleList.compileDirectory + '/' + moduleList.apmName

    def modify_path_hw(path):
        return 'hw/' + path 

    # Concatenate XDC files
    xilinx_xdc = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_XDCS')) > 0):
        xilinx_xdc = map(modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_XDCS'))
          

    # Construct the tcl file 
    part = moduleList.getAWBParam('physical_platform_config', 'FPGA_PART_XILINX')

    synthDeps = moduleList.topModule.moduleDependency['SYNTHESIS']

    postSynthTcl = apm_name + '.physical.tcl'

    topWrapper = moduleList.topModule.wrapperName()

    newPrjFile = open(postSynthTcl,'w')

    print "EDFS: " + str(synthDeps) + "\n"
    for netlist in convertDependencies(synthDeps):
        newPrjFile.write('read_edif ' + netlist + '\n')

    for xdc in xilinx_xdc:
        newPrjFile.write('read_xdc ' + xdc + '\n')

    newPrjFile.write("link_design -top " + topWrapper + " -part " + part  + "\n")

    newPrjFile.write("report_timing_summary -file " + apm_name + ".map.twr\n")

    newPrjFile.write("opt_design\n")

    newPrjFile.write("place_design -no_drc\n")

    newPrjFile.write("write_checkpoint -force " + apm_name + ".map.dcp\n")

    newPrjFile.write("report_utilization -file " + apm_name + ".map.util\n")

    newPrjFile.write("route_design\n")

    newPrjFile.write("write_checkpoint -force " + apm_name + ".par.dcp\n")

    newPrjFile.write("report_timing_summary -file " + apm_name + ".par.twr\n")

    newPrjFile.write("report_utilization -file " + apm_name + ".par.util\n")

    newPrjFile.write("report_drc -file " + topWrapper + ".drc\n")

    # We have lots of dangling wires (Thanks, Bluespec).  Set the
    # following properties to silence the warnings. 
    
    newPrjFile.write("set_property SEVERITY {Warning} [get_drc_checks NSTD-1]\n")
    newPrjFile.write("set_property SEVERITY {Warning} [get_drc_checks UCIO-1]\n")

    newPrjFile.write("write_bitstream -force " + apm_name + "_par.bit\n")

    newPrjFile.close()

    # generate bitfile
    xilinx_bit = moduleList.env.Command(
      apm_name + '_par.bit',
      synthDeps + [xilinx_xdc], 
      ['vivado -mode batch -source ' + postSynthTcl + ' -log postsynth.log'])

    moduleList.topModule.moduleDependency['BIT'] = [apm_name + '_par.bit']

    # We still need to generate a download script. 
    xilinx_loader.LOADER(moduleList)
