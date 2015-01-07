import os
import re
import sys
import SCons.Script
import model

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

    paramTclFile = moduleList.compileDirectory + '/params.xdc'

    # If the TMP_XILINX_DIR doesn't exist, create it.
    if not os.path.isdir(moduleList.env['DEFS']['TMP_XILINX_DIR']):
        os.mkdir(moduleList.env['DEFS']['TMP_XILINX_DIR'])

    # Gather Tcl files for handling constraints.
    tcl_defs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_DEFINITIONS')) > 0):
        tcl_defs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_DEFINITIONS'))

    tcl_algs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_ALGEBRAS')) > 0):
        tcl_algs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_ALGEBRAS'))

    tcl_bmms = []
    if(len(moduleList.getAllDependencies('GIVEN_XILINX_BMMS')) > 0):
        tcl_bmms = moduleList.getAllDependencies('GIVEN_XILINX_BMMS')

    tcl_elfs = []
    if(len(moduleList.getAllDependencies('GIVEN_XILINX_ELFS')) > 0):
        tcl_elfs = moduleList.getAllDependencies('GIVEN_XILINX_ELFS')

    #Emit area group definitions
    # If we got an area group placement data structure, now is the
    # time to convert it into a new constraint tcl. 
    if ('AREA_GROUPS' in moduleList.topModule.moduleDependency):
        area_constraints = area_group_tool.AreaConstraints(moduleList)
        area_group_file = moduleList.compileDirectory + '/areagroups.xdc'

        # user ucf may be overridden by our area group ucf.  Put our
        # generated ucf first.
        tcl_defs.insert(0,area_group_file)
        def area_group_ucf_closure(moduleList):

             def area_group_ucf(target, source, env):
                 area_constraints.loadAreaConstraints()
                 area_constraints.emitConstraintsVivado(area_group_file)

             return area_group_ucf

        moduleList.env.Command( 
            [area_group_file],
            area_constraints.areaConstraintsFile(),
            area_group_ucf_closure(moduleList)
            )                             


    def parameter_tcl_closure(moduleList, paramTclFile):
         def parameter_tcl(target, source, env):
             moduleList.awbParamsObj.emitParametersTCL(paramTclFile)
         return parameter_tcl

    moduleList.env.Command( 
        [paramTclFile],
        [],
        parameter_tcl_closure(moduleList, paramTclFile)
        )                             

    # Construct the tcl file 
    part = moduleList.getAWBParam('physical_platform_config', 'FPGA_PART_XILINX')

    synthDeps = moduleList.topModule.moduleDependency['SYNTHESIS']

    postSynthTcl = apm_name + '.physical.tcl'

    topWrapper = moduleList.topModule.wrapperName()

    newTclFile = open(postSynthTcl,'w')
    newTclFile.write('create_project -force ' + moduleList.apmName + ' ' + moduleList.compileDirectory + ' -part ' + part + ' \n')

    for netlist in model.convertDependencies(synthDeps):
        newTclFile.write('read_edif ' + netlist + '\n')

    given_netlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ]

    for netlist in given_netlists:
        newTclFile.write('read_edif ' + netlist + '\n')

    # We have lots of dangling wires (Thanks, Bluespec).  Set the
    # following properties to silence the warnings. 
   
    newTclFile.write("set_property SEVERITY {Warning} [get_drc_checks NSTD-1]\n")
    newTclFile.write("set_property SEVERITY {Warning} [get_drc_checks UCIO-1]\n")

    newTclFile.write("link_design -top " + topWrapper + " -part " + part  + "\n")

    for elf in tcl_elfs:
        newTclFile.write("add_file " + model.modify_path_hw(elf) + "\n")
        newTclFile.write("set_property MEMDATA.ADDR_MAP_CELLS {" + str(elf.attributes['ref']) + "} [get_files " + model.modify_path_hw(elf) + "]\n")
        #newTclFile.write("set_property SCOPED_TO_REF " + str(elf.attributes['ref']) + " [get_files " + model.modify_path_hw(elf) + "]\n")
        #newTclFile.write("set_property SCOPED_TO_CELLS [get_cells " + str(elf.attributes['cell']) + "] [get_files " + model.modify_path_hw(elf) + "]\n")



    # We will now attempt to link in any bmm that we might have.
    for bmm in tcl_bmms:
        newTclFile.write("add_file " + model.modify_path_hw(bmm) + "\n")
        newTclFile.write("set_property SCOPED_TO_REF " + str(bmm.attributes['ref']) + " [get_files " + model.modify_path_hw(bmm) + "]\n")
        #newTclFile.write("set_property SCOPED_TO_CELLS [get_cells " + str(bmm.attributes['cell']) + "] [get_files " + model.modify_path_hw(bmm) + "]\n")


    newTclFile.write("report_utilization -file " + apm_name + ".link.util\n")

    newTclFile.write("write_checkpoint -force " + apm_name + ".link.dcp\n")
 
    newTclFile.write('source ' + paramTclFile + '\n')
    for tcl_def in tcl_defs:
        newTclFile.write('source ' + tcl_def + '\n')

    for tcl_alg in tcl_algs:
        newTclFile.write('source ' + tcl_alg + '\n')

    newTclFile.write("report_timing_summary -file " + apm_name + ".map.twr\n")

    newTclFile.write('dumpPBlockUtilization "link.util"\n')

    newTclFile.write("opt_design\n")

    newTclFile.write("report_utilization -file " + apm_name + ".opt.util\n")

    newTclFile.write('dumpPBlockUtilization "opt.util"\n')

    newTclFile.write("write_checkpoint -force " + apm_name + ".opt.dcp\n")

    newTclFile.write("place_design -no_drc\n")

    newTclFile.write('dumpPBlockUtilization "place.util"\n')

    newTclFile.write("phys_opt_design\n")

    newTclFile.write("write_checkpoint -force " + apm_name + ".map.dcp\n")

    newTclFile.write("report_utilization -file " + apm_name + ".map.util\n")
    newTclFile.write('dumpPBlockUtilization "phyopt.util"\n')

    newTclFile.write("route_design\n")

    newTclFile.write("write_checkpoint -force " + apm_name + ".par.dcp\n")

    newTclFile.write("report_timing_summary -file " + apm_name + ".par.twr\n")

    newTclFile.write("report_utilization -hierarchical -file " + apm_name + ".par.util\n")
    newTclFile.write('dumpPBlockUtilization "par.util"\n')

    newTclFile.write("report_drc -file " + topWrapper + ".drc\n")
 
    newTclFile.write("write_bitstream -force " + apm_name + "_par.bit\n")

    newTclFile.close()

    # generate bitfile
    xilinx_bit = moduleList.env.Command(
      apm_name + '_par.bit',
      synthDeps + tcl_algs + tcl_defs + [paramTclFile], 
      ['vivado -verbose -mode batch -source ' + postSynthTcl + ' -log postsynth.log'])

    moduleList.topModule.moduleDependency['BIT'] = [apm_name + '_par.bit']

    # We still need to generate a download script. 
    xilinx_loader.LOADER(moduleList)
