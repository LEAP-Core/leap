import math
import cPickle as pickle

import tsp
from area_group_parser import *
from model import  *
from li_module import *
import wrapper_gen_tool


def _areaConstraintsFileIncomplete(moduleList):
    return moduleList.compileDirectory + '/areagroups.nopaths.pickle'

def _areaConstraintsFile(moduleList):
    return moduleList.compileDirectory + '/areagroups.pickle'


###########################################################################
##
## Class AreaConstraints:
##   Operates on the area constraints dictionary built by the Floorplanner
##   class (below).
##
###########################################################################

class AreaConstraints():

    def __init__(self, moduleList):
        self.moduleList = moduleList

        self.enabled = (moduleList.getAWBParam('area_group_tool',
                                               'AREA_GROUPS_ENABLE') != 0)
        self.enableBufferInsertion = \
            (moduleList.getAWBParam('area_group_tool',
                                    'AREA_GROUPS_CHANNEL_BUFFERING_ENABLE') != 0)

        self.constraints = None


    def areaConstraintType(self):
        return 'UCF'

    ##
    ## Area constraints are computed and stored in a file.  There are two
    ## files generated: one with early information (incomplete) and one
    ## with full closure.
    ##
    ## The following two functions load the area group descriptions from
    ## files.
    ##

    def loadAreaConstraints(self):
        self._loadAreaConstraintsFromFile(self.areaConstraintsFile())

    def loadAreaConstraintsIncomplete(self):
        self._loadAreaConstraintsFromFile(self.areaConstraintsFileIncomplete())

    def storeAreaConstraints(self):
        pickle_handle = open(self.areaConstraintsFile(), 'wb')
        pickle.dump(self.constraints, pickle_handle, protocol = -1)
        pickle_handle.close()

    def _loadAreaConstraintsFromFile(self, filename):
        # We got a valid LI graph from the first pass.
        pickle_handle = open(filename, 'rb')
        self.constraints = pickle.load(pickle_handle)
        pickle_handle.close()

    def areaConstraintsFileIncomplete(self):
        return _areaConstraintsFileIncomplete(self.moduleList)

    def areaConstraintsFile(self):
        return _areaConstraintsFile(self.moduleList)

    ##
    ## numIOBufs --
    ##   Compute the number of I/O buffers required for a path between two
    ##   area groups.
    ##
    def numIOBufs(self, agOut, agIn):
        if (not self.enableBufferInsertion):
            return 0

        d = self._distance(agOut, agIn)

        if (d > 0):
            # This should call a platform-specific library...
            return 1
        else:
            return 0

    ##
    ## _distance --
    ##    Distance between agOut and agIn.
    ##
    def _distance(self, agOut, agIn):
        # Use the center
        out_x = agOut.xLoc + (agOut.xDimension / 2)
        out_y = agOut.yLoc + (agOut.yDimension / 2)
        in_x = agIn.xLoc + (agIn.xDimension / 2)
        in_y = agIn.yLoc + (agIn.yDimension / 2)

        return math.sqrt((in_x - out_x)**2 + (in_y - out_y)**2)


    # Backends are called by specific tool flows. Thus we can have both
    # backends here.
    def emitConstraintsXilinx(self, fileName):
        constraintsFile = open(fileName, 'w')
        for areaGroupName in self.constraints:
            areaGroupObject = self.constraints[areaGroupName]

            # if area group was tagged as None, do not emit an area group
            # for it.  This allows us to handle area groups hidden in the
            # user UCF.
            if(areaGroupObject.sourcePath is None):
                continue

            # This is a magic conversion factor for virtex 7.  It might
            # need to change for different architectures.
            haloCells = 1

            #INST "m_sys_sys_syn_m_mod/common_services_inst/*" AREA_GROUP = "AG_common_services";
#AREA_GROUP "AG_common_services"                   RANGE=SLICE_X146Y201:SLICE_X168Y223;
#AREA_GROUP "AG_common_services"                   GROUP = CLOSED;
            constraintsFile.write('#Generated Area Group for ' + areaGroupObject.name + ' with area ' + str(areaGroupObject.area) + ' \n')
            constraintsFile.write('INST "' + areaGroupObject.sourcePath + '/*" AREA_GROUP = "AG_' + areaGroupObject.name + '";\n')
            slice_LowerLeftX = int(areaGroupObject.xLoc) + haloCells
            slice_LowerLeftY = int(areaGroupObject.yLoc) + haloCells

            slice_UpperRightX = int(areaGroupObject.xLoc + areaGroupObject.xDimension) - haloCells
            slice_UpperRightY = int(areaGroupObject.yLoc + areaGroupObject.yDimension) - haloCells

            constraintsFile.write('AREA_GROUP "AG_' + areaGroupObject.name + '" RANGE=SLICE_X' + str(slice_LowerLeftX) + 'Y' + str(slice_LowerLeftY) + ':SLICE_X' + str(slice_UpperRightX) + 'Y' + str(slice_UpperRightY) + ';\n')
            constraintsFile.write('AREA_GROUP "AG_' + areaGroupObject.name + '" GROUP=CLOSED;\n')
            constraintsFile.write('AREA_GROUP "AG_' + areaGroupObject.name + '" PLACE=CLOSED;\n')
        
        constraintsFile.close()

    def emitConstraintsVivado(self, fileName):
        constraintsFile = open(fileName, 'w')
        for areaGroupName in self.constraints:
            areaGroupObject = self.constraints[areaGroupName]

            # if area group was tagged as None, do not emit an area group
            # for it.  This allows us to handle area groups hidden in the
            # user UCF.
            if(areaGroupObject.sourcePath is None):
                continue

            # We need to place halo cells around pblocks, so that they
            # do not overlap on rounding.
            haloCells = 1

            #startgroup
            #set_property  gridtypes {RAMB18 DSP48 SLICE} [get_pblocks AG_fpga0_platform]
            #create_pblock pblock_ddr3 
            #resize_pblock pblock_ddr3 -add {SLICE_X134Y267:SLICE_X173Y349}
            #add_cells_to_pblock pblock_ddr3 [get_cells -hier -filter {NAME =~ m_sys_sys_vp_m_mod/llpi_phys_plat_sdram_b_ddrSynth/*}]
            #endgroup

            constraintsFile.write('#Generated Area Group for ' + areaGroupObject.name + ' with area ' + str(areaGroupObject.area) + ' \n')
            constraintsFile.write('startgroup \n')
            constraintsFile.write('create_pblock AG_' + areaGroupObject.name + '\n')

            slice_LowerLeftX = int(areaGroupObject.xLoc) + haloCells
            slice_LowerLeftY = int(areaGroupObject.yLoc) + haloCells

            slice_UpperRightX = int(areaGroupObject.xLoc + areaGroupObject.xDimension) - haloCells
            slice_UpperRightY = int(areaGroupObject.yLoc + areaGroupObject.yDimension) - haloCells
  
            constraintsFile.write('resize_pblock AG_' + areaGroupObject.name + ' -add {SLICE_X' + str(slice_LowerLeftX) + 'Y' + str(slice_LowerLeftY) + ':SLICE_X' + str(slice_UpperRightX) + 'Y' + str(slice_UpperRightY) + '}\n')

            constraintsFile.write('add_cells_to_pblock AG_' + areaGroupObject.name + ' [get_cells -hier -filter {NAME =~ "' + areaGroupObject.sourcePath + '/*"}]\n')

            # Optionally emit code to exclude some specific portion of code     
            if('EXCLUSIONS' in areaGroupObject.attributes):
                constraintsFile.write('remove_cells_from_pblock AG_' + areaGroupObject.name + ' [get_cells -hier -filter {NAME =~ "' + areaGroupObject.attributes['EXCLUSIONS'] + '"}]\n')

            # include all resource in the slice area
            constraintsFile.write('set_property   gridtypes {RAMB36 RAMB18 DSP48 SLICE} [get_pblocks AG_' + areaGroupObject.name + ']\n')

            constraintsFile.write('set_property CONTAIN_ROUTING false [get_pblocks AG_' + areaGroupObject.name + ']\n')
            constraintsFile.write('set_property EXCLUDE_PLACEMENT true [get_pblocks AG_' + areaGroupObject.name + ']\n')

            constraintsFile.write('endgroup \n')

        constraintsFile.close()




###########################################################################
##
## Class Floorplanner:
##   Invoked as part of the build flow.  The floorplanner generates an
##   area group dictionary and stores it in a file.  The file may be
##   loaded and used by the AreaConstraints class above.
##
###########################################################################

class Floorplanner():

    def __init__(self, moduleList):
        self.pipeline_debug = getBuildPipelineDebug(moduleList)

        def modify_path_hw(path):
            return  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + path

        if (not moduleList.getAWBParam('area_group_tool', 'AREA_GROUPS_ENABLE')):
            return

        self.emitPlatformAreaGroups = (moduleList.getAWBParam('area_group_tool',
                                                              'AREA_GROUPS_GROUP_PLATFORM_CODE') != 0)

        self.enableParentClustering = (moduleList.getAWBParam('area_group_tool',
                                                              'AREA_GROUPS_ENABLE_PARENT_CLUSTERING') != 0)

        self.enableCommunicationClustering = (moduleList.getAWBParam('area_group_tool',
                                                                     'AREA_GROUPS_ENABLE_COMMUNICATION_CLUSTERING') != 0)


        liGraph = LIGraph([])
        firstPassGraph = wrapper_gen_tool.getFirstPassLIGraph()
        # We should ignore the 'PLATFORM_MODULE'                                                                                                                    
        liGraph.mergeModules(firstPassGraph.modules.values())
        self.firstPassLIGraph = liGraph

        # We'll build a rather complex function to emit area group constraints 
        def area_group_closure(moduleList):

             def area_group(target, source, env):

                 # have we built these area groups before? If we have,
                 # then, we'll get a pickle which we can read in and
                 # operate on.
                 areaGroupsPrevious = None 
                 if(os.path.exists(_areaConstraintsFile(moduleList))):
                     # We got some previous area groups.  We'll try to
                     # reuse the solution to save on compile time.
                     pickle_handle = open(_areaConstraintsFile(moduleList), 'rb')
                     areaGroupsPrevious = pickle.load(pickle_handle)
                     pickle_handle.close()


                 extraAreaFactor = 1.25               
                 extraAreaOffset = 150.0

                 # we should now assemble the LI Modules that we got
                 # from the synthesis run
                 moduleResources = {}
                 if(self.firstPassLIGraph is None):
                     moduleResources = assignResources(moduleList)
                 else:
                     moduleResources = assignResources(moduleList, None, self.firstPassLIGraph)
                 

                 areaGroups = {}
                 totalLUTs = 0
                 # We should make a bunch of AreaGroups here. 
                 for module in sorted(moduleResources):
                     if('LUT' in moduleResources[module]):
                         totalLUTs = totalLUTs + moduleResources[module]['LUT']

                     # EEEK I don't think I know what the paths will
                     # be at this point. Probably need to memoize and
                     # fill those in later?
                     if(module in moduleResources):
                         if('LUT' in moduleResources[module]):
                             areaGroups[module] = AreaGroup(module, '')
 
                 # now that we have the modules, let's apply constraints. 

                 # Grab area groups declared/defined in the agrp file supplied by the user. 
                 constraints = []
                 for constraintFile in moduleList.getAllDependenciesWithPaths('GIVEN_AREA_CONSTRAINTS'):
                     constraints += parseAreaGroupConstraints(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + constraintFile)

                 # first bind new area groups. 
                 for constraint in constraints:
                     if(isinstance(constraint,AreaGroup)):                         
                         areaGroups[constraint.name] = constraint

                 # We should have gotten a chip dimension. Find and assign chip. 
                 self.chipXDimension = -1
                 self.chipYDimension = -1               
                 
                 # Fill in any other information we obtanied about the
                 # area groups.
                 for constraint in constraints:
                     if(isinstance(constraint,AreaGroupSize)): 
                         if(constraint.name == 'FPGA'):
                             if(self.chipXDimension > 0):
                                 print "Got too many FPGA dimension statements, bailing"
                                 exit(1)
                             self.chipXDimension = constraint.xDimension
                             self.chipYDimension = constraint.yDimension
                         else:
                             # this is a dimensional constraint for an
                             # area group. This will wipe the affine
                             # coefficients that we filled in during
                             # the previous loop.
                             areaGroups[constraint.name].xDimension = constraint.xDimension
                             areaGroups[constraint.name].yDimension = constraint.yDimension
                    

                     if(isinstance(constraint,AreaGroupResource)): 
                         if(not constraint.name in moduleResources):
                             moduleResources[constraint.name] = {}
 
                         moduleResources[constraint.name][constraint.type] = constraint.value

                     if(isinstance(constraint,AreaGroupLocation)): 
                         areaGroups[constraint.name].xLoc = constraint.xLocation
                         areaGroups[constraint.name].yLoc = constraint.yLocation

                     if(isinstance(constraint,AreaGroupLowerLeft)): 
                         areaGroups[constraint.name].lowerLeft = constraint

                     if(isinstance(constraint,AreaGroupUpperRight)): 
                         areaGroups[constraint.name].upperRight = constraint
                         
                     if(isinstance(constraint,AreaGroupAttribute)): 
                         areaGroups[constraint.name].attributes[constraint.key] = constraint.value



                     if(isinstance(constraint,AreaGroupPath)): 
                         areaGroups[constraint.name].sourcePath = constraint.path

                     if(isinstance(constraint,AreaGroupRelationship)): 
                         areaGroups[constraint.parent].children[constraint.child] = areaGroups[constraint.child]
                         if(areaGroups[constraint.child].parent is None):
                             areaGroups[constraint.child].parent = areaGroups[constraint.parent]
                             if(len(areaGroups[constraint.child].children) != 0):
                                 print "Area group " + constraint.child + " already has children, so it cannot have a parent.  Reconsider your area group file. Bailing."
                                 exit(1)
                         else:
                             print "Area group " + constraint.child + " already had a parent.  Reconsider your area group file. Bailing."
                             exit(1)

                 # assign areas for all areagroups.
                 for areaGroup in areaGroups.values():
                     # EEEK I don't think I know what the paths will
                     # be at this point. Probably need to memoize and
                     # fill those in later?
                     if((areaGroup.name in moduleResources) and ('SLICE' in moduleResources[areaGroup.name])):
                         areaGroup.area = moduleResources[areaGroup.name]['SLICE']
                     else:
                         areaGroup.area = areaGroup.xDimension * areaGroup.yDimension

                 # We've now built a tree of parent/child
                 # relationships, which we can use to remove area from
                 # the parent (double counting is a problem).  
                 for areaGroup in areaGroups.values():
                     for child in areaGroup.children.values():
                         # If we have a slice resource declaration,
                         # use it else, use 1/2 the area as an estimate
                         if ('SLICE' in moduleResources[child.name]):
                             areaGroup.area = areaGroup.area - moduleResources[child.name]['SLICE']
                         else:
                             areaGroup.area = areaGroup.area - child.area/2

                 affineCoefs = [1, 2, 4, 8] # just make them all squares for now. 
                 #affineCoefs = [ 221.0/349.0] # just make them all squares for now. 
                 #affineCoefs = [float(self.chipXDimension)/float(self.chipYDimension)] # just make them all squares for now. 

                 for areaGroup in areaGroups:
                     areaGroupObject = areaGroups[areaGroup]
                     # we might have gotten coefficients from the constraints.
                     if(areaGroupObject.xDimension is None):
                         areaGroupObject.xDimension = []
                         areaGroupObject.yDimension = []  

                         moduleRoot = math.sqrt(extraAreaFactor * areaGroupObject.area + extraAreaOffset)
                         for coef in affineCoefs:
                             areaGroupObject.xDimension.append(coef*moduleRoot)
                             areaGroupObject.yDimension.append(moduleRoot/coef)
        
                 # If we've been instructed to remove the platform module, purge it here. 
                 if(not self.emitPlatformAreaGroups):
                     for areaGroup in sorted(areaGroups):
                         areaGroupObject = areaGroups[areaGroup]
                         if(areaGroupObject.name in self.firstPassLIGraph.modules):
                             moduleObject = self.firstPassLIGraph.modules[areaGroupObject.name]
                             if(moduleObject.getAttribute('PLATFORM_MODULE') == True):
                                 del areaGroups[areaGroup]


                 areaGroupsFinal = None
                 # If we got a previous area group, we'll attempt to
                 # reuse its knowledge
                 if(not areaGroupsPrevious is None):
                     areaGroupsModified = copy.deepcopy(areaGroups)
                     # if the area didn't change much (within say a
                     # few percent, we will reuse previous placement
                     # information
                     allowableAreaDelta = 1.01
                     for groupName in areaGroupsPrevious:
                         if(groupName in areaGroupsModified):
                             previousGroupObject = areaGroupsPrevious[groupName]
                             modifiedGroupObject = areaGroupsModified[groupName]
                             if((modifiedGroupObject.area > previousGroupObject.area/allowableAreaDelta) and (modifiedGroupObject.area < previousGroupObject.area*allowableAreaDelta)):
                                 modifiedGroupObject.xDimension = previousGroupObject.xDimension
                                 modifiedGroupObject.yDimension = previousGroupObject.yDimension

                     areaGroupsFinal = self.solveILPPartial(areaGroupsModified, fileprefix="partial_ilp_reuse_")

                 # Either we didn't have the previous information, or
                 # we failed to use it.
                 if(areaGroupsFinal is None):        
                     areaGroupsFinal = self.solveILPPartial(areaGroups)

                 # We failed to assign area groups.  Eventually, we
                 # could demote this to a warning.
                 if(areaGroupsFinal is None):      
                     print "Failed to obtain area groups"   
                     exit(1)

                 # Sort area groups topologically, annotating each area group
                 # with a sortIdx field.
                 self.sort_area_groups(areaGroupsFinal)

                 # Now that we've solved (to some extent) the area
                 # group mapping problem we can dump the results for 
                 # the build tree. 

                 pickle_handle = open(_areaConstraintsFileIncomplete(moduleList), 'wb')
                 pickle.dump(areaGroupsFinal, pickle_handle, protocol=-1)
                 pickle_handle.close()                 
                 
             return area_group

        # expose this dependency to the backend tools.
        moduleList.topModule.moduleDependency['AREA_GROUPS'] = [_areaConstraintsFileIncomplete(moduleList)]

        # We need to get the resources for all modules, except the top module, which can change. 
        resources = [dep for dep in moduleList.getAllDependencies('RESOURCES')]

        areagroup = moduleList.env.Command( 
            [_areaConstraintsFileIncomplete(moduleList)],
            resources + map(modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_AREA_CONSTRAINTS')),
            area_group_closure(moduleList)
            )                   

        moduleList.env.AlwaysBuild(areagroup)


    ##
    ## sort_area_groups --
    ##   Sort all area groups using traveling salesman to minimize the distance
    ##   of a circuit through the groups.  This is intended to miminize the
    ##   lengths of chains.
    ##
    def sort_area_groups(self, areaGroups):
        # Get a canonical order for the set of area groups (used in loops below)
        group_names = areaGroups.keys()

        # The coordinate of each group is its midpoint
        coords = []
        for name in group_names:
            group = areaGroups[name]
            x = group.xLoc + (group.xDimension / 2)
            y = group.yLoc + (group.yDimension / 2)
            coords.append((x, y))

        if (self.pipeline_debug):
            print "Sorting area groups:"

        # Pick a short path
        path = tsp.travelingSalesman(coords)

        # Store path as sort order in areaGroups entries
        for i in range(len(group_names)):
            name = group_names[i]
            group = areaGroups[name]

            group.sortIdx = path[i]

            if (self.pipeline_debug):
                print "  " + name + ": " + str(group.sortIdx)

    def dumpILPRosen(self, modHandle, areaGroups):

        # let's begin setting up the ILP problem 
        modHandle.write('var comms;\n')                         
        modHandle.write('\n\nminimize dist: comms;\n\n')
        variables = ['comms']

        # first we need to establish the options for the module area groups
        for areaGroup in sorted(areaGroups):
            areaGroupObject = areaGroups[areaGroup]
            modHandle.write('\n# ' + str(areaGroupObject) + '\n\n')
            variables += ['xloc_' + areaGroupObject.name, 'yloc_' + areaGroupObject.name]  

            if(areaGroupObject.xLoc is None):
                modHandle.write('var xloc_' + areaGroupObject.name + ';\n')
                modHandle.write('var yloc_' + areaGroupObject.name + ';\n')                         
            else:
                modHandle.write('var xloc_' + areaGroupObject.name + ' = ' + str(areaGroupObject.xLoc) + ';\n')
                modHandle.write('var yloc_' + areaGroupObject.name + ' = ' + str(areaGroupObject.yLoc) + ';\n')

            if(isinstance(areaGroupObject.xDimension, list)):
                dimsX = []
                dimsY = []
                dimSelectX = []
                dimSelectY = []
                for dimensionIndex in range(len(areaGroupObject.xDimension)):
                    aspectName = areaGroupObject.name + '_' + str(dimensionIndex)
                    modHandle.write('var ' + aspectName + ' binary;\n')
                    variables += [aspectName]
                    dimsX.append(str(areaGroupObject.xDimension[dimensionIndex]) + ' * ' + aspectName)
                    dimsY.append(str(areaGroupObject.yDimension[dimensionIndex]) + ' * ' + aspectName)
                    dimSelectX.append(str(aspectName))
                    dimSelectY.append(str(aspectName))

                modHandle.write('var xdim_' + areaGroupObject.name + ';\n')
                modHandle.write('var ydim_' + areaGroupObject.name + ';\n')
                    
                modHandle.write('subject to xdim_' + areaGroupObject.name + '_assign:\n')
                modHandle.write(' + '.join(dimsX) + ' = xdim_' + areaGroupObject.name +';\n')
                modHandle.write('subject to ydim_' + areaGroupObject.name + '_assign:\n')
                modHandle.write(' + '.join(dimsY) + ' = ydim_' + areaGroupObject.name +';\n')

                modHandle.write('subject to xdim_select_' + areaGroupObject.name + '_assign:\n')
                modHandle.write(' + '.join(dimSelectX) + ' = 1;\n')
                modHandle.write('subject to ydim_select_' + areaGroupObject.name + '_assign:\n')
                modHandle.write(' + '.join(dimSelectY) + ' = 1;\n')

            else:
                # Much simpler constraints when considering single shapes.                 
                modHandle.write('var xdim_' + areaGroupObject.name + ' = ' + str(areaGroupObject.xDimension) + ';\n')
                modHandle.write('var ydim_' + areaGroupObject.name + ' = ' + str(areaGroupObject.yDimension) +';\n')

            variables += ['xdim_' + areaGroupObject.name, 'ydim_' + areaGroupObject.name]

            # Throw a bounding box on the location variables
            if(areaGroupObject.xLoc is None):
                modHandle.write('subject to xdim_' + areaGroupObject.name + '_high_bound:\n')
                modHandle.write('xloc_' + areaGroupObject.name + '+ xdim_' + areaGroupObject.name + ' <= ' + str(self.chipXDimension) + ';\n')
                modHandle.write('subject to xdim_' + areaGroupObject.name + '_low_bound:\n')
                modHandle.write('xloc_' + areaGroupObject.name + ' >= 0 ;\n')           

            if(areaGroupObject.yLoc is None):
                modHandle.write('subject to ydim_' + areaGroupObject.name + '_high_bound:\n')
                modHandle.write('yloc_' + areaGroupObject.name + '+ ydim_' + areaGroupObject.name +' <= ' + str(self.chipYDimension) + ';\n')
                modHandle.write('subject to ydim_' + areaGroupObject.name + '_low_bound:\n')
                modHandle.write('yloc_' + areaGroupObject.name + ' >= 0;\n')           

        # Now we need to lay down the non-overlap constraints
        areaGroupNames = sorted([name for name in areaGroups])
        sumTerms = []
        for areaGroupAIndex in range(len(areaGroupNames)):
            areaGroupA = areaGroups[areaGroupNames[areaGroupAIndex]]
            for areaGroupBIndex in range(areaGroupAIndex, len(areaGroupNames)):             
                areaGroupB = areaGroups[areaGroupNames[areaGroupBIndex]]
                # In some cases, we don't emit constraints: 
                # 1) between area group and itself
                if(areaGroupA.name == areaGroupB.name):
                    continue

                # 2) If the area groups have been pre-placed
                #    by the user.  If these constraints are
                #    illegal, the backend tools will fail,
                #    but this is the user's problem.
                if((areaGroupA.xLoc is not None) and 
                   (areaGroupB.xLoc is not None)):
                    continue 

                # None objects need not have contraints with
                # one another, since they represent user
                # constraints.  This helps with areas of the
                # chip that just don't have slices/CLBs.                        
                if(('EMPTYBOX' in areaGroupA.attributes) and ('EMPTYBOX' in areaGroupB.attributes)): 
                    continue

                posI = 'i_' + areaGroupA.name + '_' +  areaGroupB.name 
                posJ = 'j_' + areaGroupA.name + '_' +  areaGroupB.name 

                variables += [posI, posJ]

                modHandle.write('var ' + posI + ' binary;\n')
                modHandle.write('var ' + posJ + ' binary;\n')


                # Need to find out how much the two modules communicate.                         

                commsXY = 0 
                if(('EMPTYBOX' in areaGroupA.attributes) or ('EMPTYBOX' in areaGroupB.attributes)):
                   commsXY = 0 
                else:
                    # Area groups come in two types -- parents
                    # and children.  Children communicate only
                    # with parents, while parents may communicate
                    # with other parents.
                    parentChild = False
                    if(areaGroupA.parent is not None):
                        if(areaGroupA.parent.name == areaGroupB.name):
                            parentChild = not ('IGNORE_PARENT_CHILD' in areaGroupA.attributes)
                    elif(areaGroupB.parent is not None):
                        if(areaGroupB.parent.name == areaGroupA.name):
                            parentChild = not ('IGNORE_PARENT_CHILD' in areaGroupB.attributes)

                    communicatingModules = (areaGroupA.name in self.firstPassLIGraph.modules) and (areaGroupB.name in self.firstPassLIGraph.modules)                            


                    #Handle parents/children 
                    if(self.enableCommunicationClustering):
                        if((not parentChild) and communicatingModules):                                   
                            moduleAObject = self.firstPassLIGraph.modules[areaGroupA.name]
                            for channel in moduleAObject.channels:
                                # some channels may not be assigned
                                if(isinstance(channel.partnerModule, LIModule)):
                                    if(channel.partnerModule.name == areaGroupB.name):
                                        commsXY = commsXY + 10
        
                    #Handle parents/children
                    if(self.enableParentClustering):
                        if(parentChild):
                            commsXY = commsXY + 1000

                # Scrub out the EMPTYBOX constraints
                if(commsXY > 0):
                    absX = 'xdist_' + areaGroupA.name + '_' +  areaGroupB.name 
                    absY = 'ydist_' + areaGroupA.name + '_' +  areaGroupB.name 

                    variables += [absX, absY]

                    modHandle.write('var ' + absX + ';\n')
                    modHandle.write('var ' + absY + ';\n')

                    if(True):
                        modHandle.write('subject to abs_xdim_0_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                        modHandle.write('xloc_' + areaGroupA.name + ' - xloc_'  +  areaGroupB.name + ' <= ' + absX + ';\n')

                        modHandle.write('subject to abs_xdim_1_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                        modHandle.write('xloc_' + areaGroupB.name + ' - xloc_'  +  areaGroupA.name + ' <= ' + absX + ';\n')   

                        modHandle.write('subject to abs_ydim_0_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                        modHandle.write('yloc_' + areaGroupA.name + ' - yloc_'  +  areaGroupB.name + ' <= ' + absY + ';\n')

                        modHandle.write('subject to abs_ydim_1_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                        modHandle.write('yloc_' + areaGroupB.name + ' - yloc_'  +  areaGroupA.name + ' <= ' + absY + ';\n')   
                    else:
                        modHandle.write('subject to abs_xdim_0_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                        modHandle.write('xloc_' + areaGroupA.name + ' + .5 * xdim_' + areaGroupA.name +' - xloc_'  +  areaGroupB.name + ' - .5 * xdim_' + areaGroupB.name + ' <= ' + absX + ';\n')

                        modHandle.write('subject to abs_xdim_1_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                        modHandle.write('xloc_' + areaGroupB.name + ' + .5 * xdim_' + areaGroupB.name + ' - xloc_'  +  areaGroupA.name + ' - .5 * xdim_' + areaGroupA.name + ' <= ' + absX + ';\n')   

                        modHandle.write('subject to abs_ydim_0_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                        modHandle.write('yloc_' + areaGroupA.name + ' + .5 * ydim_' + areaGroupA.name + ' - yloc_'  +  areaGroupB.name + ' - .5 * ydim_' + areaGroupB.name + ' <= ' + absY + ';\n')

                        modHandle.write('subject to abs_ydim_1_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                        modHandle.write('yloc_' + areaGroupB.name + ' + .5 * ydim_' + areaGroupB.name + ' - yloc_'  +  areaGroupA.name + ' - .5 * ydim_' + areaGroupA.name + ' <= ' + absY + ';\n')                           

                    sumTerms += [str(commsXY) + ' * ' + absX, str(commsXY) + ' * ' + absY]

                # Add in terms for abs value

                modHandle.write('subject to left_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                modHandle.write('xloc_' + areaGroupA.name + ' + xdim_'  +  areaGroupA.name + ' <= xloc_' + areaGroupB.name + ' +  '+ str(self.chipXDimension) + ' * ' + posI + ' + ' + str(self.chipXDimension) + ' * ' + posJ + ';\n')

                modHandle.write('subject to right_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                modHandle.write('xloc_' + areaGroupA.name + ' - xdim_'  +  areaGroupB.name + ' >= xloc_' + areaGroupB.name + ' - '+ str(self.chipXDimension) + ' +  '+ str(self.chipXDimension) + ' * ' + posI + ' - ' + str(self.chipXDimension) + ' * ' + posJ + ';\n')


                modHandle.write('subject to below_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                modHandle.write('yloc_' + areaGroupA.name + ' + ydim_'  +  areaGroupA.name + ' <= yloc_' + areaGroupB.name + ' + '+ str(self.chipYDimension) + ' +  '+ str(self.chipYDimension) + ' * ' + posI + ' - ' + str(self.chipYDimension) + ' * ' + posJ + ';\n')


                modHandle.write('subject to above_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                modHandle.write('yloc_' + areaGroupA.name + ' - ydim_'  +  areaGroupB.name + ' >= yloc_' + areaGroupB.name + ' - '+ str(2*self.chipYDimension) + ' +  '+ str(self.chipYDimension) + ' * ' + posI + ' + ' + str(self.chipYDimension) + ' * ' + posJ + ';\n')


        modHandle.write('subject to  comms_total: \n')                       
        if(len(sumTerms) > 0):  
            modHandle.write(' + '.join(sumTerms) + ' = comms;\n')                 
        else:
            modHandle.write('1 = comms;\n')                 

        modHandle.write('\n\nend;')
        return variables

    def solveILPProblem(self, modFile, areaGroups, variables):

        # now that we've written out the file, solve it. 
        # Necessary to force ply rebuild.  Sad...
        import glpk 

        example = glpk.glpk(modFile)
        example._parm.tm_lim = 100 # value in milliseconds
        example._parm.it_lim = 1000 # value in milliseconds

        # This function is a copy of the solve function
        # provided by python-glpk.  However, because we need
        # to tweak some of the icop struct arguments, we must
        # expose this routine. 
        def solve_int(self, instantiate = True, bounds = True):
            #glp_term_out(GLP_OFF);                                                   
            if not self._ready:
                self.update()
            #glp_term_out(GLP_ON);                                                    
            if self._cols == None or self._rows == None:
                self._read_variables()
            if bounds:
                self._apply_bounds()
            if  glpk.glp_get_num_int(self._lp) == 0:   # problem is continuous              
                res = glpk.glp_simplex(self._lp, self._parm) # self._parm !!!              
            else:   # problem is MIP                                                  
                if self._tran:
                    glpk.glp_mpl_build_prob(self._tran, self._lp);
                res = glpk.glp_simplex(self._lp, self._parm);  # ??? should use dual simplex ???                                                                            
                iocp_param = glpk.glp_iocp();
                glpk.glp_init_iocp(iocp_param);
                #iocp_param.tm_lim=600*1000

                iocp_param.mip_gap=0.95

                glpk.glp_intopt(self._lp, iocp_param);
                if self._tran:
                    ret = glpk.glp_mpl_postsolve(self._tran, self._lp, glpk.GLP_MIP);
                    if ret != 0:
                        print "Error on postsolving model"
                        raise AttributeError
            if instantiate:
                self._instantiate_solution()
            if res != 0:
                return None
            else:
                return glpk.glp_get_obj_val(self._lp);


                         
        print str(example._parm)
        example.update()
        solve_int(example)

        # dump interesting variables
        def dumpVariables(example):
            for variable in variables:
                print variable + ' is: ' + str(eval('example.' + variable).value()) 

        dumpVariables(example)

        # print out module locations 
        areaGroupNames = sorted([name for name in areaGroups])
        for areaGroupIndex in range(len(areaGroupNames)):
            areaGroup = areaGroups[areaGroupNames[areaGroupIndex]]

            areaGroup.xLoc = eval('example.xloc_' + areaGroup.name).value()
            areaGroup.yLoc = eval('example.yloc_' + areaGroup.name).value()

            # figure out the chose dimensions.
            # unfortunately, the tools may give 'None' for
            # some dimensions, if they were previously
            # defined...
            
            xDimension = eval('example.xdim_' + areaGroup.name).value()
            yDimension = eval('example.ydim_' + areaGroup.name).value()

            if(xDimension is None):
                areaGroup.xDimension = areaGroup.xDimension[0]
            else:
                areaGroup.xDimension = xDimension

            if(yDimension is None):
                areaGroup.yDimension = areaGroup.yDimension[0]
            else:
                areaGroup.yDimension = yDimension

            # If problem was not satisfiable, then all variables
            # are set to zero.  We should really give up and
            # clear all area groups, since this technically
            # results in a correct solution.
            if(areaGroup.xDimension < 1 or areaGroup.yDimension < 1):
                print "Failed to find solution to area group placement for: " + areaGroup.name
                return False

        return True

    def solveILPFull(areaGroups):
         modFile = 'areaGroup.mod'
         modHandle = open(modFile,'w')
                        
         variables = self.dumpILPRosen(modHandle, areaGroups)

         modHandle.close()

         if(not self.solveILPProblem(modFile, areaGroups, variables)):
             return None

         return areaGroups
   
    # we could also apply different heuristics to the ordering that we pick.
    def solveILPPartial(self, areaGroups, fileprefix=""):
         solvedILP = False
         for modulesAtATime in range(1,4):
             areaGroupsPartial = {}
             unplacedGroups = []
             # fill in the new area group structure with previously placed area groups. 
             for areaGroupName in areaGroups:
                 areaGroupObject = areaGroups[areaGroupName]
                 if(not areaGroupObject.xLoc is None):
                     areaGroupsPartial[areaGroupName] = copy.deepcopy(areaGroupObject)
                 else:
                     unplacedGroups += [copy.deepcopy(areaGroupObject)]
                 
             unplacedGroups.sort(key=lambda group: group.area)

             # build groupings.
             while(len(unplacedGroups) > 0):
                 name = ""
                 for i in range(modulesAtATime):
                     if(len(unplacedGroups) > 0):
                         group = unplacedGroups.pop()
                         areaGroupsPartial[group.name] = group 
                         name += group.name + "_"

                 modFile = fileprefix + name + '_areaGroup.mod'
                 modHandle = open(modFile,'w')
                 
                 variables = self.dumpILPRosen(modHandle, areaGroupsPartial)

                 modHandle.close()
                 print "Solving: " + str(modFile) + "\n"
       
                 solvedILP = self.solveILPProblem(modFile, areaGroupsPartial, variables)
                 if(not solvedILP):
                     break
                 
             if(solvedILP):
                 return areaGroupsPartial

         return None        
