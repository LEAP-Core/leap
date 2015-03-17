import os
import re
import sys
import SCons.Script
import model
import xilinx_loader
import wrapper_gen_tool
import synthesis_library
import li_module

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

    self.firstPassLIGraph = wrapper_gen_tool.getFirstPassLIGraph()

    # A collector for all of the checkpoint objects we will gather/build in the following code. 
    dcps = []

    # Construct the tcl file 
    self.part = moduleList.getAWBParam('physical_platform_config', 'FPGA_PART_XILINX')

    apm_name = moduleList.compileDirectory + '/' + moduleList.apmName

    self.paramTclFile = moduleList.topModule.moduleDependency['PARAM_TCL'][0]

    # If the TMP_XILINX_DIR doesn't exist, create it.
    if not os.path.isdir(moduleList.env['DEFS']['TMP_XILINX_DIR']):
        os.mkdir(moduleList.env['DEFS']['TMP_XILINX_DIR'])

    # Gather Tcl files for handling constraints.
    self.tcl_headers = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_HEADERS')) > 0):
        self.tcl_headers = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_HEADERS'))

    self.tcl_defs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_DEFINITIONS')) > 0):
        self.tcl_defs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_DEFINITIONS'))

    self.tcl_funcs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_FUNCTIONS')) > 0):
        self.tcl_funcs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_FUNCTIONS'))

    self.tcl_algs = []
    if(len(moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_ALGEBRAS')) > 0):
        self.tcl_algs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_VIVADO_TCL_ALGEBRAS'))

    self.tcl_bmms = []
    if(len(moduleList.getAllDependencies('GIVEN_XILINX_BMMS')) > 0):
        self.tcl_bmms = moduleList.getAllDependencies('GIVEN_XILINX_BMMS')

    self.tcl_elfs = []
    if(len(moduleList.getAllDependencies('GIVEN_XILINX_ELFS')) > 0):
        self.tcl_elfs = moduleList.getAllDependencies('GIVEN_XILINX_ELFS')

    self.tcl_ag = []

    #Emit area group definitions
    # If we got an area group placement data structure, now is the
    # time to convert it into a new constraint tcl. 
    self.area_group_file = moduleList.compileDirectory + '/areagroups.xdc'
    if ('AREA_GROUPS' in moduleList.topModule.moduleDependency):
        self.area_constraints = area_group_tool.AreaConstraints(moduleList)
        self.routeAG = (moduleList.getAWBParam('area_group_tool',
                                               'AREA_GROUPS_ROUTE_AG') != 0)

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



    synthDepsBase =  moduleList.getAllDependencies('GEN_VIVADO_DCPS')

    # We got a stack of synthesis results for the LI modules.  We need
    # to convert these to design checkpoints for the fast place and
    # route flow.
    ngcModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore]

    for module in ngcModules + [moduleList.topModule]:   
        # did we get a dcp from the first pass?  If so, did the lim
        # graph give code for this module?  If both are true, then we
        # will link the old ngc in, rather than regenerate it. 
        if ((not self.firstPassLIGraph is None) and (module.name in self.firstPassLIGraph.modules) and (self.firstPassLIGraph.modules[module.name].getAttribute('RESYNTHESIZE') is None)):
            if (li_module.linkFirstPassObject(moduleList, module, self.firstPassLIGraph, 'GEN_VIVADO_DCPS', 'GEN_VIVADO_DCPS') is None):
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

    newTclFile = open(postSynthTcl, 'w')
    newTclFile.write('create_project -force ' + moduleList.apmName + ' ' + moduleList.compileDirectory + ' -part ' + self.part + ' \n')

    # To resolve black boxes, we need to load checkpoints in the
    # following order:
    # 1) topModule
    # 2) platformModule
    # 3) user program, in any order

    userModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore and not module.platformModule]
    platformModules = [module for module in moduleList.synthBoundaries() if not module.liIgnore and module.platformModule]
    checkpointCommands = [] 

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
        #self.area_constraints = area_group_tool.AreaConstraints(moduleList)
        for module in userModules:  
            # Did we get a placed module already?
            if((module.name in elabAreaConstraints.constraints) and ('LIBRARY_DCP' in elabAreaConstraints.constraints[module.name].attributes)):
                # we need to locate the dcp corresponding to this area group. 
                candidates = moduleList.getAllDependencies('GIVEN_VIVADO_DCPS')
                for dcpCandidate in moduleList.getAllDependencies('GIVEN_VIVADO_DCPS'):                   
                   if dcpCandidate.attributes['module'] == module.name:         
                       dcp = str(model.modify_path_hw(dcpCandidate))
                       model.dictionary_list_create_append(module.moduleDependency, 'GEN_VIVADO_PLACEMENT_DCPS', dcp)
                       dcps.append(dcp)
            else:
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

        # We can have parent/child relationships in the user modules.
        # Vivado requires that checkpoints be read in topological
        # order.
        def isBlackBox(module):
            if(self.firstPassLIGraph.modules[module.name].getAttribute('BLACK_BOX_AREA_GROUP')):
                return 1
            return 0


        for module in sorted(userModules, key=isBlackBox):   
            checkpoint = model.convertDependencies(module.getDependencies('GEN_VIVADO_PLACEMENT_DCPS'))

            # There should only be one checkpoint here. 
            if(len(checkpoint) > 1):
                print "Error too many checkpoints for " + str(module.name) + ":  " + str(checkpoint)  
                continue

            if(len(checkpoint) == 0):
                print "No checkpoints for " + str(module.name) + ":  " + str(checkpoint)  
                continue
            #read in new checkoutpoint

            newTclFile.write('read_checkpoint ' + checkpoint[0] + '\n')

            emitPlatformAreaGroups = (moduleList.getAWBParam('area_group_tool',
                                                             'AREA_GROUPS_GROUP_PLATFORM_CODE') != 0)

            # platformModule refers to the main platform module, not
            # the subordinate device area groups.
            platformModule = (self.firstPassLIGraph.modules[module.name].getAttribute('BLACK_BOX_AREA_GROUP') is None) and (not self.firstPassLIGraph.modules[module.name].getAttribute('PLATFORM_MODULE') is None)

            allowAGPlatform = (not platformModule) or emitPlatformAreaGroups 

            emitDeviceGroups = (moduleList.getAWBParam('area_group_tool',
                                                       'AREA_GROUPS_PAR_DEVICE_AG') != 0)           
            allowAGDevice = (self.firstPassLIGraph.modules[module.name].getAttribute('BLACK_BOX_AREA_GROUP') is None) or emitDeviceGroups

            if (allowAGPlatform and allowAGDevice):               
                refName = module.wrapperName()
                lockPlacement = True
                lockRoute = self.routeAG
                # If this is an platform/user-defined area group, the wrapper name may be different.
                if (not self.firstPassLIGraph.modules[module.name].getAttribute('BLACK_BOX_AREA_GROUP') is None):
                    refName = elabAreaConstraints.constraints[module.name].attributes['MODULE_NAME']
                    lockPlacement = not ('NO_PLACE' in elabAreaConstraints.constraints[module.name].attributes) and lockPlacement
                    lockRoute = not ('NO_ROUTE' in elabAreaConstraints.constraints[module.name].attributes) and lockRoute

                checkpointCommands.append('if { [llength [get_cells -hier -filter {REF_NAME =~ "' + refName + '"}]] } {\n')            
                checkpointCommands.append('    puts "Locking ' + refName + '"\n')
                if (lockRoute):
                    # locking routing requires us to emit an area group. boo. 
                    ag_tcl = self.ag_constraints(moduleList, module)
                    self.tcl_ag.append(ag_tcl)
                    checkpointCommands.append('    source ' + str(ag_tcl) + '\n')
                    checkpointCommands.append('    lock_design -level routing [get_cells -hier -filter {REF_NAME =~ "' + refName + '"}]\n')            
                elif (lockPlacement):
                    checkpointCommands.append('    lock_design -level placement [get_cells -hier -filter {REF_NAME =~ "' + refName + '"}]\n')            
                checkpointCommands.append('}\n')

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

    # lock down the area group routing.
    newTclFile.write("\n".join(checkpointCommands) + "\n")

    for elf in self.tcl_elfs:
        newTclFile.write("add_file " + model.modify_path_hw(elf) + "\n")
        newTclFile.write("set_property MEMDATA.ADDR_MAP_CELLS {" + str(elf.attributes['ref']) + "} [get_files " + model.modify_path_hw(elf) + "]\n")



    # We will now attempt to link in any bmm that we might have.
    for bmm in self.tcl_bmms:
        newTclFile.write("add_file " + model.modify_path_hw(bmm) + "\n")
        newTclFile.write("set_property SCOPED_TO_REF " + str(bmm.attributes['ref']) + " [get_files " + model.modify_path_hw(bmm) + "]\n")


 
    newTclFile.write('set IS_TOP_BUILD 1\n ')
    newTclFile.write('set IS_AREA_GROUP_BUILD 0\n ')
    newTclFile.write('source ' + self.paramTclFile + '\n')

    for tcl_header in self.tcl_headers:
        newTclFile.write('source ' + tcl_header + '\n')

    for tcl_def in self.tcl_defs:
         newTclFile.write('source ' + tcl_def + '\n') 

    for tcl_func in self.tcl_funcs:
        newTclFile.write('source ' + tcl_func + '\n')

    for tcl_alg in self.tcl_algs:
        newTclFile.write('source ' + tcl_alg + '\n')

    def dumpPBlockCmd(tgt):
        return 'dumpPBlockUtilization "' + moduleList.compileDirectory + '/' + tgt + '.util"\n'

    newTclFile.write(dumpPBlockCmd('link'))
    newTclFile.write("report_timing_summary -file " + apm_name + ".map.twr\n\n")

    newTclFile.write("opt_design -directive AddRemap\n")
    newTclFile.write("report_utilization -file " + apm_name + ".opt.util\n")
    newTclFile.write(dumpPBlockCmd('opt'))
    newTclFile.write("write_checkpoint -force " + apm_name + ".opt.dcp\n\n")

    newTclFile.write("place_design -no_drc -directive WLDrivenBlockPlacement\n")
    newTclFile.write(dumpPBlockCmd('place'))

    newTclFile.write("phys_opt_design -directive AggressiveFanoutOpt\n")
    newTclFile.write("write_checkpoint -force " + apm_name + ".map.dcp\n")
    newTclFile.write(dumpPBlockCmd('phyopt'))
    newTclFile.write("report_utilization -file " + apm_name + ".map.util\n\n")

    newTclFile.write("route_design\n")
    newTclFile.write("write_checkpoint -force " + apm_name + ".par.dcp\n")
    newTclFile.write(dumpPBlockCmd('par'))
    newTclFile.write("report_timing_summary -file " + apm_name + ".par.twr\n\n")

    newTclFile.write("report_utilization -hierarchical -file " + apm_name + ".par.util\n")
    newTclFile.write("report_drc -file " + topWrapper + ".drc\n\n")
 
    newTclFile.write("write_bitstream -force " + apm_name + "_par.bit\n")

    newTclFile.close()

    # generate bitfile
    xilinx_bit = moduleList.env.Command(
      apm_name + '_par.bit',
      synthDeps + self.tcl_algs + self.tcl_defs + self.tcl_funcs + self.tcl_ag + [self.paramTclFile] + dcps + [postSynthTcl], 
      ['touch start.txt; vivado -verbose -mode batch -source ' + postSynthTcl + ' -log ' + moduleList.compileDirectory + '/postsynth.log'])


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

      gen_netlists = module.getDependencies('GEN_NGCS')
      given_netlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ]

      constraintsFile = []
      area_constraints = None
      if(moduleList.getAWBParamSafe('area_group_tool', 'AREA_GROUPS_ENABLE')):
          area_constraints = area_group_tool.AreaConstraints(moduleList)
          constraintsFile = [area_constraints.areaConstraintsFile()]
 
      def edf_to_dcp_tcl_closure(moduleList):

           def edf_to_dcp_tcl(target, source, env):

               edfTclFile = open(edfTcl,'w')

               for netlist in gen_netlists + given_netlists:
                   edfTclFile.write('read_edif ' + model.rel_if_not_abspath(netlist, edfCompileDirectory) + '\n')

               refName = module.wrapperName()

               # If this is an platform/user-defined area group, the wrapper name may be different.
               if((not self.firstPassLIGraph is None) and (module.name in self.firstPassLIGraph.modules)):
                   if (not self.firstPassLIGraph.modules[module.name].getAttribute('BLACK_BOX_AREA_GROUP') is None):
                       area_constraints.loadAreaConstraints()
                       refName =  area_constraints.constraints[module.name].attributes['MODULE_NAME']           
               
               if(module.getAttribute('TOP_MODULE') is None):
                   edfTclFile.write("link_design -mode out_of_context -top " +  refName + " -part " + self.part  + "\n")
                   edfTclFile.write("set_property HD.PARTITION 1 [current_design]\n")
               else:
                   edfTclFile.write("link_design -top " +  refName + " -part " + self.part  + "\n")

               if(not module.platformModule):
                   edfTclFile.write("opt_design -quiet\n")

               edfTclFile.write('write_checkpoint -force ' + module.name + ".synth.dcp" + '\n')

               edfTclFile.close()
           return edf_to_dcp_tcl
      
      moduleList.env.Command(
          [edfTcl],
          constraintsFile,
          edf_to_dcp_tcl_closure(moduleList)
          )
                  
      # generate bitfile
      return moduleList.env.Command(
          [dcp],
          [gen_netlists] + [given_netlists] + [edfTcl], 
          ['cd ' + edfCompileDirectory + '; touch start.txt; vivado -mode batch -source ' +  module.name + ".synth.tcl" + ' -log ' + module.name + '.synth.checkpoint.log'])


  def place_dcp(self, moduleList, module):

      # Due to area groups,  we first need a closure to generate tcl. 
      placeCompileDirectory = moduleList.compileDirectory + '/' + module.name + '_physical/'
      dcp = placeCompileDirectory + module.name + ".place.dcp"
      edfTcl = placeCompileDirectory + module.name + ".place.tcl"
      constraintsTcl = placeCompileDirectory + module.name + ".constraints.tcl"
      checkpoint = model.convertDependencies(module.getDependencies('GEN_VIVADO_DCPS'))

      if not os.path.isdir(placeCompileDirectory):
         os.mkdir(placeCompileDirectory)

      area_constraints = area_group_tool.AreaConstraints(moduleList)

      def place_dcp_tcl_closure(moduleList):

           def place_dcp_tcl(target, source, env):

               # TODO: Eventually, we'll need to examine the contstraints to decide if we need to rebuild.

               area_constraints.loadAreaConstraints()

               edfTclFile = open(edfTcl,'w')
               constraintsTclFile = open(constraintsTcl,'w')
               
               edfTclFile.write('read_checkpoint ' + model.rel_if_not_abspath(checkpoint[0], placeCompileDirectory) + '\n')

               # throw out area group constraints. (and maybe loc constraints too?)
               # Some modules may not have placement information.  Ignore them for now.
                 
               needToLink = True
               refName = module.wrapperName()
               # If this is an platform/user-defined area group, the wrapper name may be different.
               if (not self.firstPassLIGraph.modules[module.name].getAttribute('BLACK_BOX_AREA_GROUP') is None):
                   refName =  area_constraints.constraints[module.name].attributes['MODULE_NAME']           

               if((self.firstPassLIGraph.modules[module.name].getAttribute('BLACK_BOX_AREA_GROUP') is None) or moduleList.getAWBParamSafe('area_group_tool', 'AREA_GROUPS_PAR_DEVICE_AG')):               
                   if(not area_constraints.emitModuleConstraintsVivado(constraintsTclFile, module.name, useSourcePath=False) is None):
                       # for platform modules, we need to insert the tcl environment.  

                       constraintsTclFile.write('set IS_TOP_BUILD 0\n')
                       constraintsTclFile.write('set AG_OBJECT ' + module.name + '\n')
                       constraintsTclFile.write('set IS_AREA_GROUP_BUILD 1\n')
                       constraintsTclFile.write('source ' + model.rel_if_not_abspath(self.paramTclFile, placeCompileDirectory) + '\n')

                       for tcl_header in self.tcl_headers:
                           constraintsTclFile.write('source ' + model.rel_if_not_abspath(tcl_header, placeCompileDirectory) + '\n')

                       for tcl_def in self.tcl_defs:
                           constraintsTclFile.write('source ' + model.rel_if_not_abspath(tcl_def, placeCompileDirectory) + '\n') 

                       for tcl_func in self.tcl_funcs:
                           constraintsTclFile.write('source ' + model.rel_if_not_abspath(tcl_func, placeCompileDirectory) + '\n')

                       constraintsTclFile.write("annotateModelClock\n")
                       constraintsTclFile.write("annotateCLK_SRC\n")

                       for tcl_alg in self.tcl_algs:
                           constraintsTclFile.write('source ' + model.rel_if_not_abspath(tcl_alg, placeCompileDirectory) + '\n')
              
 
                       
                       edfTclFile.write('add_file ' + model.rel_if_not_abspath(constraintsTcl, placeCompileDirectory) + '\n')

                       if(not 'NO_PLACE' in area_constraints.constraints[module.name].attributes):                                   
                           if(not 'NO_ROUTE' in area_constraints.constraints[module.name].attributes and self.routeAG):
                               edfTclFile.write("set_property USED_IN {synthesis implementation opt_design place_design phys_opt_design route_design out_of_context} [get_files " + model.rel_if_not_abspath(constraintsTcl, placeCompileDirectory) + "]\n")
                           else:
                               edfTclFile.write("set_property USED_IN {synthesis implementation opt_design place_design phys_opt_design out_of_context} [get_files " + model.rel_if_not_abspath(constraintsTcl, placeCompileDirectory) + "]\n")


                       # linking lets us pull in placement constraints.                                    
                       edfTclFile.write("link_design -mode out_of_context  -top " + refName + " -part " + self.part  + "\n")
                       needToLink = False
                       # if ended here... 
                       if(not 'NO_PLACE' in area_constraints.constraints[module.name].attributes):
                           edfTclFile.write("place_design -no_drc \n")
                           edfTclFile.write("report_timing_summary -file " + module.name + ".place.twr\n")
                           edfTclFile.write("phys_opt_design \n")
                          
                           if(not 'NO_ROUTE' in area_constraints.constraints[module.name].attributes and self.routeAG):

                               edfTclFile.write("route_design\n")
                               edfTclFile.write("report_timing_summary -file " + module.name + ".route.twr\n")
                               edfTclFile.write("report_route_status\n")
                
               
               # still need to link design. 
               if(needToLink):
                   edfTclFile.write("link_design -mode out_of_context  -top " + refName + " -part " + self.part  + "\n")

               edfTclFile.write('write_checkpoint -force ' + module.name + ".place.dcp" + '\n')

               edfTclFile.close()
               constraintsTclFile.close()
 
           return place_dcp_tcl
 
      moduleList.env.Command(
          [edfTcl, constraintsTcl],
          [area_constraints.areaConstraintsFile()],
          place_dcp_tcl_closure(moduleList)
          )


      # generate checkpoint
      return moduleList.env.Command(
          [dcp],
          [checkpoint] + [edfTcl, constraintsTcl]  +  self.tcl_headers + self.tcl_algs + self.tcl_defs + self.tcl_funcs, 
          ['cd ' + placeCompileDirectory + '; touch start.txt; vivado -mode batch -source ' + module.name + ".place.tcl" + ' -log ' + module.name + '.place.log'])


  def ag_constraints(self, moduleList, module):

      # Due to area groups,  we first need a closure to generate tcl. 
      agCompileDirectory = moduleList.compileDirectory + '/' 
      agTcl = agCompileDirectory + module.name + ".ag.tcl"
      refName = module.wrapperName()

      area_constraints = area_group_tool.AreaConstraints(moduleList)

      def ag_tcl_closure(moduleList):

           def ag_tcl(target, source, env):

               # TODO: Eventually, we'll need to examine the contstraints to decide if we need to rebuild.

               area_constraints.loadAreaConstraints()
               # give our area constraint is a MODULE_NAME, if it doesn't have one. 
               if(not 'MODULE_NAME' in area_constraints.constraints[module.name].attributes):
                   area_constraints.constraints[module.name].attributes['MODULE_NAME'] = refName 
   
               area_constraints.constraints[module.name].attributes['SHARE_PLACEMENT'] = False 
               agFile = open(agTcl,'w')
               area_constraints.emitModuleConstraintsVivado(agFile, module.name, useSourcePath=True)
               agFile.close()

           return ag_tcl
 
      moduleList.env.Command(
          [agTcl],
          [area_constraints.areaConstraintsFile()],
          ag_tcl_closure(moduleList)
          )
     
      return agTcl




