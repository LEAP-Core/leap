import os
import re
import sys
import SCons.Script
from model import  *

import xilinx_loader

try:
    import area_group_tool
except ImportError:
    pass # we won't be using this tool.

#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class PostSynthesize():
  def __init__(self, moduleList):

    apm_name = moduleList.compileDirectory + '/' + moduleList.apmName


    # If the TMP_XILINX_DIR doesn't exist, create it.
    if not os.path.isdir(moduleList.env['DEFS']['TMP_XILINX_DIR']):
        os.mkdir(moduleList.env['DEFS']['TMP_XILINX_DIR'])

    def modify_path_hw(path):
        return 'hw/' + path 

    # Gather Tcl files for handling constraints.
    tcl_defs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_DEFINITIONS')) > 0):
        tcl_defs = map(modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_DEFINITIONS'))

    tcl_algs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_ALGEBRAS')) > 0):
        tcl_algs = map(modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_ALGEBRAS'))


    #Emit area group definitions
    # If we got an area group placement data structure, now is the
    # time to convert it into a new constraint tcl. 
    if('AREA_GROUPS' in moduleList.topModule.moduleDependency):
        area_group_file = moduleList.compileDirectory + '/areagroups.xdc'
        # user ucf may be overridden by our area group ucf.  Put our
        # generated ucf first.
        tcl_defs.insert(0,area_group_file)
        def area_group_ucf_closure(moduleList):

             def area_group_ucf(target, source, env):
                 area_group_tool.emitConstraintsVivado(area_group_file, 
                                                       area_group_tool.loadAreaConstraints(moduleList))
                                    
             return area_group_ucf

        moduleList.env.Command( 
            [area_group_file],
            area_group_tool.areaConstraintsFile(moduleList),
            area_group_ucf_closure(moduleList)
            )                             

    # Construct the tcl file 
    part = moduleList.getAWBParam('physical_platform_config', 'FPGA_PART_XILINX')

    synthDeps = moduleList.topModule.moduleDependency['SYNTHESIS']

    postSynthTcl = apm_name + '.physical.tcl'

    topWrapper = moduleList.topModule.wrapperName()

    newTclFile = open(postSynthTcl,'w')

    for netlist in convertDependencies(synthDeps):
        newTclFile.write('read_edif ' + netlist + '\n')

    given_netlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ]

    for netlist in given_netlists:
        newTclFile.write('read_edif ' + netlist + '\n')

    newTclFile.write("set_property SEVERITY {Warning} [get_drc_checks NSTD-1]\n")
    newTclFile.write("set_property SEVERITY {Warning} [get_drc_checks UCIO-1]\n")

    newTclFile.write("link_design -top " + topWrapper + " -part " + part  + "\n")

    newTclFile.write("report_utilization -file " + apm_name + ".link.util\n")

    newTclFile.write("write_checkpoint -force " + apm_name + ".link.dcp\n")

    for tcl_def in tcl_defs:
        newTclFile.write('source ' + tcl_def + '\n')

    for tcl_alg in tcl_algs:
        newTclFile.write('source ' + tcl_alg + '\n')

    newTclFile.write("report_timing_summary -file " + apm_name + ".map.twr\n")

    newTclFile.write("opt_design\n")

    newTclFile.write("report_utilization -file " + apm_name + ".opt.util\n")

    newTclFile.write("write_checkpoint -force " + apm_name + ".opt.dcp\n")

    newTclFile.write("place_design -no_drc\n")

    newTclFile.write("phys_opt_design\n")

    newTclFile.write("write_checkpoint -force " + apm_name + ".map.dcp\n")

    newTclFile.write("report_utilization -file " + apm_name + ".map.util\n")

    newTclFile.write("route_design\n")

    newTclFile.write("write_checkpoint -force " + apm_name + ".par.dcp\n")

    newTclFile.write("report_timing_summary -file " + apm_name + ".par.twr\n")

    newTclFile.write("report_utilization -hierarchical -file " + apm_name + ".par.util\n")

    newTclFile.write("report_drc -file " + topWrapper + ".drc\n")

    # We have lots of dangling wires (Thanks, Bluespec).  Set the
    # following properties to silence the warnings. 
    
    newTclFile.write("write_bitstream -force " + apm_name + "_par.bit\n")

    newTclFile.close()

    # generate bitfile
    xilinx_bit = moduleList.env.Command(
      apm_name + '_par.bit',
      synthDeps + tcl_algs + tcl_defs, 
      ['vivado -mode batch -source ' + postSynthTcl + ' -log postsynth.log'])

    moduleList.topModule.moduleDependency['BIT'] = [apm_name + '_par.bit']

    # We still need to generate a download script. 
    xilinx_loader.LOADER(moduleList)
