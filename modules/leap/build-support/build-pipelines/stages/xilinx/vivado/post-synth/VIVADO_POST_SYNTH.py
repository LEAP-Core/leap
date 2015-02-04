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

    # if we have a deps build, don't do anything...
    if(moduleList.isDependsBuild):
        return

    firstPassLIGraph = wrapper_gen_tool.getFirstPassLIGraph()

    # A collector for all of the checkpoint objects we will gather/build in the following code. 
    dcps = []

    # Construct the tcl file 
    self.part = moduleList.getAWBParam('physical_platform_config', 'FPGA_PART_XILINX')

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

    tcl_funcs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_FUNCTIONS')) > 0):
        tcl_funcs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_FUNCTIONS'))

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
    self.area_group_file = moduleList.compileDirectory + '/areagroups.xdc'
    if ('AREA_GROUPS' in moduleList.topModule.moduleDependency):
        self.area_constraints = area_group_tool.AreaConstraints(moduleList)

        # user ucf may be overridden by our area group ucf.  Put our
        # generated ucf first.
        #tcl_defs.insert(0,self.area_group_file)
        def area_group_ucf_closure(moduleList):

             def area_group_ucf(target, source, env):
                 self.area_constraints.loadAreaConstraints()
                 self.area_constraints.emitConstraintsVivado(self.area_group_file)

             return area_group_ucf

        moduleList.env.Command( 
            [self.area_group_file],
            self.area_constraints.areaConstraintsFile(),
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


    synthDepsBase =  moduleList.getAllDependencies('GEN_VIVADO_DCPS')

    # We got a stack of synthesis results for the LI modules.  We need
    # to convert these to design checkpoints for the fast place and
    # route flow.
    ngcModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore]

    for module in ngcModules + [moduleList.topModule]:   
        # did we get a dcp from the first pass?  If so, did the lim
        # graph give code for this module?  If both are true, then we
        # will link the old ngc in, rather than regenerate it. 
        if ((not firstPassLIGraph is None) and (module.name in firstPassLIGraph.modules)):
            if (synthesis_library.linkFirstPassObject(moduleList, module, firstPassLIGraph, 'GEN_VIVADO_DCPS', 'GEN_VIVADO_DCPS') is None):
                module.moduleDependency['GEN_VIVADO_DCPS'] = [self.edf_to_dcp(moduleList, module)]
            
        # it's possible that we got dcp from this compilation
        # pass. This will happen for the platform modules.
        elif (len(module.getDependencies('GEN_VIVADO_DCPS')) > 0):
            continue

        # we got neither. therefore, we must create a dcp out of the ngc.
        else:            
            module.moduleDependency['GEN_VIVADO_DCPS'] = [self.edf_to_dcp(moduleList, module)]

                        
   

    synthDeps =  moduleList.getAllDependencies('GEN_VIVADO_DCPS')

    postSynthTcl = apm_name + '.physical.tcl'

    topWrapper = moduleList.topModule.wrapperName()

    newTclFile = open(postSynthTcl,'w')
    newTclFile.write('create_project -force ' + moduleList.apmName + ' ' + moduleList.compileDirectory + ' -part ' + self.part + ' \n')

    # To resolve black boxes, we need to load checkpoints in the
    # following order:
    # 1) topModule
    # 2) platformModule
    # 3) user program, in any order

    userModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore and not module.platformModule]
    platformModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore and module.platformModule]
 
    if(not moduleList.getAWBParamSafe('area_group_tool', 'AREA_GROUPS_ENABLE')):
         
        for module in [moduleList.topModule] + platformModules + userModules:   
            dcps.append(module.getDependencies('GEN_VIVADO_DCPS'))
            checkpoint = model.convertDependencies(module.getDependencies('GEN_VIVADO_DCPS'))

            # There should only be one checkpoint here. 
            if(len(checkpoint) > 1):
                print "Error too many checkpoints for " + str(module.name) + ":  " + str(checkpoint)  
                continue

            if(len(checkpoint) == 0):
                print "No checkpoints for " + str(module.name) + ":  " + str(checkpoint)  
                continue

            newTclFile.write('read_checkpoint ' + checkpoint[0] + '\n')

            
    # We're attempting the new, parallel flow. 
    else:
        # we need to issue seperate place commands.  Therefore, we attempt to place each design 

        # There may be some special area groups in platforms -- handle them
        elabAreaConstraints = area_group_tool.AreaConstraints(moduleList)
        elabAreaConstraints.loadAreaConstraintsElaborated()
        userAreaGroups = [elabAreaConstraints.constraints[area_constraint] for area_constraint in elabAreaConstraints.constraints if not elabAreaConstraints.constraints[area_constraint].parent is None]
        #self.area_constraints = area_group_tool.AreaConstraints(moduleList)

        print "User Area Groups: " + str(userAreaGroups)

        for areaGroup in userAreaGroups:   
            # get the parent module. 
            parentModule = moduleList.modules[areaGroup.parent.name]
            ag_dcp = self.place_ag_dcp(moduleList, parentModule, areaGroup)
            model.dictionary_list_create_append(parentModule.moduleDependency, 'GEN_VIVADO_PLACEMENT_DCPS', ag_dcp)
            dcps.append(ag_dcp)


        for module in userModules:   
            dcp = self.place_dcp(moduleList, module)
            model.dictionary_list_create_append(module.moduleDependency, 'GEN_VIVADO_PLACEMENT_DCPS', dcp)
            dcps.append(dcp)

        for module in [moduleList.topModule] + platformModules:   
            checkpoint = model.convertDependencies(module.getDependencies('GEN_VIVADO_DCPS'))
            dcps.append(checkpoint)
              
            # There should only be one checkpoint here. 
            if(len(checkpoint) > 1):
                print "Error too many checkpoints for " + str(module.name) + ":  " + str(checkpoint)  
                continue

            if(len(checkpoint) == 0):
                print "No checkpoints for " + str(module.name) + ":  " + str(checkpoint)  
                continue

            newTclFile.write('read_checkpoint ' + checkpoint[0] + '\n')

        for module in userModules:   
            checkpoint = model.convertDependencies(module.getDependencies('GEN_VIVADO_PLACEMENT_DCPS'))

            # There should only be one checkpoint here. 
            if(len(checkpoint) > 1):
                print "Error too many checkpoints for " + str(module.name) + ":  " + str(checkpoint)  
                continue

            if(len(checkpoint) == 0):
                print "No checkpoints for " + str(module.name) + ":  " + str(checkpoint)  
                continue
            #read in new checkoutpoint
            #newTclFile.write('read_checkpoint -cell '+  module.wrapperName() + " " + checkpoint[0] + '\n')
            newTclFile.write('read_checkpoint ' + checkpoint[0] + '\n')
            #newTclFile.write('lock_design -level placement ' +  module.wrapperName() + '\n')
           

    given_netlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ]

    for netlist in given_netlists:
        newTclFile.write('read_edif ' + netlist + '\n')

    # We have lots of dangling wires (Thanks, Bluespec).  Set the
    # following properties to silence the warnings. 
   
    newTclFile.write("set_property SEVERITY {Warning} [get_drc_checks NSTD-1]\n")
    newTclFile.write("set_property SEVERITY {Warning} [get_drc_checks UCIO-1]\n")

    newTclFile.write("link_design -top " + topWrapper + " -part " + self.part  + "\n")

    newTclFile.write("report_utilization -file " + apm_name + ".link.util\n")

    newTclFile.write("write_checkpoint -force " + apm_name + ".link.dcp\n")


    if(moduleList.getAWBParamSafe('area_group_tool', 'AREA_GROUPS_ENABLE')):
        for module in userModules:  
            moduleObject = firstPassLIGraph.modules[module.name]
            if(moduleObject.getAttribute('PLATFORM_MODULE') is None):
                newTclFile.write('lock_design -level routing [get_cells -hier -filter {REF_NAME =~ "' +  module.wrapperName() + '"}]\n') 


    for elf in tcl_elfs:
        newTclFile.write("add_file " + model.modify_path_hw(elf) + "\n")
        newTclFile.write("set_property MEMDATA.ADDR_MAP_CELLS {" + str(elf.attributes['ref']) + "} [get_files " + model.modify_path_hw(elf) + "]\n")



    # We will now attempt to link in any bmm that we might have.
    for bmm in tcl_bmms:
        newTclFile.write("add_file " + model.modify_path_hw(bmm) + "\n")
        newTclFile.write("set_property SCOPED_TO_REF " + str(bmm.attributes['ref']) + " [get_files " + model.modify_path_hw(bmm) + "]\n")


 
    newTclFile.write('source ' + paramTclFile + '\n')

    for tcl_header in tcl_headers:
        newTclFile.write('source ' + tcl_header + '\n')

    for tcl_def in tcl_defs:
         newTclFile.write('source ' + tcl_def + '\n') 

    for tcl_func in tcl_funcs:
        newTclFile.write('source ' + tcl_func + '\n')

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
      synthDeps + tcl_algs + tcl_defs + tcl_funcs + [paramTclFile] + dcps, 
      ['vivado -verbose -mode batch -source ' + postSynthTcl + ' -log postsynth.log'])

    moduleList.topModule.moduleDependency['BIT'] = [apm_name + '_par.bit']

    # We still need to generate a download script. 
    xilinx_loader.LOADER(moduleList)


  # If we didn't get a design checkpoint (i.e. we used synplify) we
  # need to decorate the edif as a checkpoint.  This will eventually
  # help on recompilation. 
  def edf_to_dcp(self, moduleList, module):
      edfCompileDirectory =  moduleList.compileDirectory + '/' + module.name + '_synth/'      
      dcp = edfCompileDirectory + module.name + ".synth.dcp"
      edfTcl = edfCompileDirectory + module.name + ".synth.tcl"

      if not os.path.isdir(edfCompileDirectory):
         os.mkdir(edfCompileDirectory)

      edfTclFile = open(edfTcl,'w')
      gen_netlists = module.getDependencies('GEN_NGCS')

      given_netlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ]

      for netlist in gen_netlists + given_netlists:
          edfTclFile.write('read_edif ' + model.rel_if_not_abspath(netlist, edfCompileDirectory) + '\n')
      
      if(module.getAttribute('TOP_MODULE') is None):
          edfTclFile.write("link_design -mode out_of_context -top " +  module.wrapperName() + " -part " + self.part  + "\n")
          edfTclFile.write("set_property HD.PARTITION 1 [current_design]\n")
      else:
          edfTclFile.write("link_design -top " +  module.wrapperName() + " -part " + self.part  + "\n")

      if(not module.platformModule):
          edfTclFile.write("opt_design -quiet\n")

      edfTclFile.write('write_checkpoint -force ' + module.name + ".synth.dcp" + '\n')

      edfTclFile.close()

      # generate bitfile
      return moduleList.env.Command(
          [dcp],
          [gen_netlists] + [given_netlists] + [edfTcl], 
          ['cd ' + edfCompileDirectory + '; vivado -mode batch -source ' +  module.name + ".synth.tcl" + ' -log ' + module.name + '.synth.checkpoint.log'])


  def place_ag_dcp(self, moduleList, module, areaGroup):

      groupName = module.name + '_ag_' + areaGroup.name

      # Due to area groups,  we first need a closure to generate tcl. 
      placeCompileDirectory = moduleList.compileDirectory + '/' + groupName + '_physical/'
      dcp = placeCompileDirectory + groupName + ".place.dcp"
      edfTcl = placeCompileDirectory + groupName + ".place.tcl"
      checkpoint = model.convertDependencies(module.getDependencies('GEN_VIVADO_DCPS'))

      if not os.path.isdir(placeCompileDirectory):
         os.mkdir(placeCompileDirectory)

      def place_dcp_tcl_closure(moduleList):

           def place_dcp_tcl(target, source, env):
               self.area_constraints.loadAreaConstraints()

               edfTclFile = open(edfTcl,'w')
               
               edfTclFile.write('open_checkpoint ' + model.rel_if_not_abspath(checkpoint[0], placeCompileDirectory) + '\n')

               # throw out area group constraints. (and maybe loc constraints too?)
               # Some modules may not have placement information.  Ignore them for now. 
               if(not self.area_constraints.emitModuleConstraintsVivado(edfTclFile, areaGroup.name, useSourcePath=False) is None):               
                   edfTclFile.write("place_design -no_drc \n")
                   edfTclFile.write("phys_opt_design \n")

               edfTclFile.write('write_checkpoint -force ' + groupName + ".place.dcp" + '\n')

               edfTclFile.close()
 
           return place_dcp_tcl

      moduleList.env.Command(
          [edfTcl],
          self.area_constraints.areaConstraintsFile(),
          place_dcp_tcl_closure(moduleList)
          )

      # generate bitfile
      return moduleList.env.Command(
          [dcp],
          [checkpoint] + [edfTcl] + [self.area_group_file], 
          ['cd ' + placeCompileDirectory + ';vivado -mode batch -source ' + groupName + ".place.tcl" + ' -log ' + groupName + '.par.log'])


  def place_dcp(self, moduleList, module):

      # Due to area groups,  we first need a closure to generate tcl. 
      placeCompileDirectory = moduleList.compileDirectory + '/' + module.name + '_physical/'
      dcp = placeCompileDirectory + module.name + ".place.dcp"
      edfTcl = placeCompileDirectory + module.name + ".place.tcl"
      checkpoint = model.convertDependencies(module.getDependencies('GEN_VIVADO_DCPS'))

      if not os.path.isdir(placeCompileDirectory):
         os.mkdir(placeCompileDirectory)

      def place_dcp_tcl_closure(moduleList):

           def place_dcp_tcl(target, source, env):
               self.area_constraints.loadAreaConstraints()

               edfTclFile = open(edfTcl,'w')
               
               edfTclFile.write('open_checkpoint ' + model.rel_if_not_abspath(checkpoint[0], placeCompileDirectory) + '\n')

               # throw out area group constraints. (and maybe loc constraints too?)
               # Some modules may not have placement information.  Ignore them for now. 
               if(not self.area_constraints.emitModuleConstraintsVivado(edfTclFile, module.name, useSourcePath=False) is None):               
                   edfTclFile.write("place_design -no_drc \n")
                   edfTclFile.write("phys_opt_design \n")
                   edfTclFile.write("route_design\n")

               edfTclFile.write('write_checkpoint -force ' + module.name + ".place.dcp" + '\n')

               edfTclFile.close()
 
           return place_dcp_tcl

      moduleList.env.Command(
          [edfTcl],
          self.area_constraints.areaConstraintsFile(),
          place_dcp_tcl_closure(moduleList)
          )

      # generate bitfile
      return moduleList.env.Command(
          [dcp],
          [checkpoint] + [edfTcl], 
          ['cd ' + placeCompileDirectory + ';vivado -mode batch -source ' + module.name + ".place.tcl" + ' -log ' + module.name + '.par.log'])





