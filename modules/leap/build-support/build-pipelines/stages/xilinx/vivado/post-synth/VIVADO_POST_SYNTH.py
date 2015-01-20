import os
import re
import sys
import SCons.Script


import model
import xilinx_loader
import wrapper_gen_tool
import synthesis_library

try:
    import area_group_tool
except ImportError:
    pass # we won't be using this tool.

#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class PostSynthesize():
  def __init__(self, moduleList):

    firstPassLIGraph = wrapper_gen_tool.getFirstPassLIGraph()

    apm_name = moduleList.compileDirectory + '/' + moduleList.apmName

    paramTclFile = moduleList.compileDirectory + '/params.xdc'

    # If the TMP_XILINX_DIR doesn't exist, create it.
    if not os.path.isdir(moduleList.env['DEFS']['TMP_XILINX_DIR']):
        os.mkdir(moduleList.env['DEFS']['TMP_XILINX_DIR'])

    # Gather Tcl files for handling constraints.
    tcl_headers = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_HEADERS')) > 0):
        tcl_headers = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_HEADERS'))

    tcl_defs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_DEFINITIONS')) > 0):
        tcl_defs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_DEFINITIONS'))

    tcl_algs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_ALGEBRAS')) > 0):
        tcl_algs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_ALGEBRAS'))


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


    synthDepsBase =  moduleList.getAllDependencies('GEN_VIVADO_DCPS')

    print "synthDepsBase: " + str(synthDepsBase)

    # We got a stack of synthesis results for the LI modules.  We need
    # to convert these to design checkpoints for the fast place and
    # route flow.
    ngcModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore]

    for module in ngcModules + [moduleList.topModule]:   
        print "Examining netlists: " + str(module.name) 
        # did we get a dcp from the first pass?  If so, did the lim
        # graph give code for this module?  If both are true, then we
        # will link the old ngc in, rather than regenerate it. 
        if((not firstPassLIGraph is None) and (module.name in firstPassLIGraph.modules)):
            synthesis_library.linkFirstPassObject(moduleList, module, firstPassLIGraph, 'GEN_VIVADO_DCPS', 'GEN_VIVADO_DCPS')
            
        # it's possible that we got dcp from this compilation
        # pass. This will happen for the platform modules.
        elif(len(module.getDependencies('GEN_VIVADO_DCPS')) > 0):
            print "Found design checkpoint for " + module.name + ":" + str(module.getDependencies('GEN_VIVADO_DCPS'))

        # we got neither. therefore, we must create a dcp out of the ngc.
        else:
            print "building new checkpoint"
            module.moduleDependency['GEN_VIVADO_DCPS'] = [self.edf_to_dcp(moduleList, module)]
                        
    synthDeps =  moduleList.getAllDependencies('GEN_VIVADO_DCPS')

    print "synthDeps: " + str(synthDeps)

    postSynthTcl = apm_name + '.physical.tcl'

    topWrapper = moduleList.topModule.wrapperName()

    newTclFile = open(postSynthTcl,'w')

    # To resolve black boxes, we need to load checkpoints in the
    # following order:
    # 1) topModule
    # 2) platformModule
    # 3) user program, in any order

    userModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore and not module.platformModule]
    platformModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore and module.platformModule]

    for module in [moduleList.topModule] + platformModules + userModules:   
        checkpoint = model.convertDependencies(module.getDependencies('GEN_VIVADO_DCPS'))
        # There should only be one checkpoint here. 
        if(len(checkpoint) > 1):
            print "Error too many checkpoints for " + str(module.name) + ":  " + str(checkpoint)  
        #newTclFile.write('read_checkpoint -cell ' + module.wrapperName() + ' ' + checkpoint[0] + '\n')
        newTclFile.write('read_checkpoint ' + checkpoint[0] + '\n')

    #for module in [moduleList.topModule]:   
    #    checkpoint = model.convertDependencies(module.getDependencies('GEN_VIVADO_DCPS'))
        # There should only be one checkpoint here. 
    #    if(len(checkpoint) > 1):
    #        print "Error too many checkpoints for " + str(module.name) + ":  " + str(checkpoint)  
        #newTclFile.write('read_checkpoint -cell ' + module.wrapperName() + ' ' + checkpoint[0] + '\n')
    #    newTclFile.write('open_checkpoint ' + checkpoint[0] + '\n')

    given_netlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ]

    for netlist in given_netlists:
        newTclFile.write('read_edif ' + netlist + '\n')

    newTclFile.write("set_property SEVERITY {Warning} [get_drc_checks NSTD-1]\n")
    newTclFile.write("set_property SEVERITY {Warning} [get_drc_checks UCIO-1]\n")

#    newTclFile.write("link_design -mode out_of_context -top " + topWrapper + " -part " + part  + "\n")
    newTclFile.write("link_design -top " + topWrapper + " -part " + part  + "\n")

    newTclFile.write("report_utilization -file " + apm_name + ".link.util\n")

    newTclFile.write("write_checkpoint -force " + apm_name + ".link.dcp\n")
 
    newTclFile.write('source ' + paramTclFile + '\n')

    for tcl_header in tcl_headers:
        newTclFile.write('source ' + tcl_header + '\n')

    for tcl_def in tcl_defs:
#        newTclFile.write('read_xdc -mode out_of_context ' + tcl_def + '\n')
         newTclFile.write('read_xdc ' + tcl_def + '\n')

    for tcl_alg in tcl_algs:
#        newTclFile.write('read_xdc -mode out_of_context ' + tcl_alg + '\n')
        newTclFile.write('read_xdc ' + tcl_alg + '\n')

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

    # We have lots of dangling wires (Thanks, Bluespec).  Set the
    # following properties to silence the warnings. 
    
    newTclFile.write("write_bitstream -force " + apm_name + "_par.bit\n")

    newTclFile.close()

    # generate bitfile
    xilinx_bit = moduleList.env.Command(
      apm_name + '_par.bit',
      synthDeps + tcl_algs + tcl_defs + [paramTclFile], 
      ['vivado -mode batch -source ' + postSynthTcl + ' -log postsynth.log'])

    moduleList.topModule.moduleDependency['BIT'] = [apm_name + '_par.bit']

    # We still need to generate a download script. 
    xilinx_loader.LOADER(moduleList)


  # If we didn't get a design checkpoint (i.e. we used synplify) we
  # need to decorate the edif as a checkpoint.  This will eventually
  # help on recompilation. 
  def edf_to_dcp_name(self, moduleList, module):
      return moduleList.compileDirectory + '/' + module.name + ".synth.dcp"

  def edf_to_dcp(self, moduleList, module):
      edfTcl = self.edf_to_dcp_name(moduleList, module) + ".tcl"
      edfTclFile = open(edfTcl,'w')
      gen_netlists = module.getDependencies('GEN_NGCS')

      given_netlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ]

      for netlist in gen_netlists + given_netlists:
          edfTclFile.write('read_edif ' + netlist + '\n')

      edfTclFile.write("set_property HD.PARTITION 1 [current_design]\n")
      edfTclFile.write('write_checkpoint -force ' + self.edf_to_dcp_name(moduleList, module) + '\n')

      edfTclFile.close()
      
      # generate bitfile
      return [moduleList.env.Command(
          [self.edf_to_dcp_name(moduleList, module)],
          gen_netlists + given_netlists + [edfTcl], 
          ['vivado -mode batch -source ' + edfTcl + ' -log ' + module.name + 'synth.dcp.log'])]





