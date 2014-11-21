import math
import cPickle as pickle

import tsp
from area_group_parser import *
from model import  *
from li_module import *
import wrapper_gen_tool

#from glpkpi import *

def areaConstraintType():
    return 'UCF'

##
## Area constraints are computed and stored in a file.  There are two files
## generated: one with early information (incomplete) and one with full closure.
##
## The following two functions load the area group descriptions from files.
##

def loadAreaConstraints(moduleList):
    return _loadAreaConstraintsFromFile(areaConstraintsFile(moduleList))

def loadAreaConstraintsIncomplete(moduleList):
    return _loadAreaConstraintsFromFile(areaConstraintsFileIncomplete(moduleList))

def storeAreaConstraints(moduleList, areaGroups):
    pickle_handle = open(areaConstraintsFile(moduleList), 'wb')
    pickle.dump(areaGroups, pickle_handle, protocol = -1)
    pickle_handle.close()

def _loadAreaConstraintsFromFile(filename):
    # The first pass will dump a well known file. 
    if(os.path.isfile(filename)):
        # We got a valid LI graph from the first pass.
        pickle_handle = open(filename, 'rb')
        areaGroups = pickle.load(pickle_handle)
        pickle_handle.close()
        return areaGroups
    return None

def areaConstraintsFileIncomplete(moduleList):
    return  moduleList.compileDirectory + '/areagroups.nopaths.pickle'  

def areaConstraintsFile(moduleList):
    return  moduleList.compileDirectory + '/areagroups.pickle'  


# Backends are called by specific tool flows. Thus we can have both
# backends here. 
def emitConstraintsXilinx(fileName, areaGroups):
    constraintsFile = open(fileName, 'w')
    for areaGroupName in areaGroups:
        areaGroupObject = areaGroups[areaGroupName]

        # if area group was tagged as None, do not emit an area group
        # for it.  This allows us to handle area groups hidden in the
        # user UCF.
        if(areaGroupObject.sourcePath is None):
            continue

        # This is a magic conversion factor for virtex 7.  It might
        # need to change for different architectures.
        lutToSliceRatio = 1

        #INST "m_sys_sys_syn_m_mod/common_services_inst/*" AREA_GROUP = "AG_common_services";
#AREA_GROUP "AG_common_services"                   RANGE=SLICE_X146Y201:SLICE_X168Y223;
#AREA_GROUP "AG_common_services"                   GROUP = CLOSED;
        constraintsFile.write('#Generated Area Group for ' + areaGroupObject.name + ' with area ' + str(areaGroupObject.area) + ' \n')
        constraintsFile.write('INST "' + areaGroupObject.sourcePath + '/*" AREA_GROUP = "AG_' + areaGroupObject.name + '";\n')
        slice_LowerLeftX = int((areaGroupObject.xLoc - .5  * areaGroupObject.xDimension)/lutToSliceRatio)
        slice_LowerLeftY = int((areaGroupObject.yLoc - .5  * areaGroupObject.yDimension)/lutToSliceRatio)

        slice_UpperRightX = int((areaGroupObject.xLoc + .5  * areaGroupObject.xDimension)/lutToSliceRatio)
        slice_UpperRightY = int((areaGroupObject.yLoc + .5  * areaGroupObject.yDimension)/lutToSliceRatio)
  
        constraintsFile.write('AREA_GROUP "AG_' + areaGroupObject.name + '" RANGE=SLICE_X' + str(slice_LowerLeftX) + 'Y' + str(slice_LowerLeftY) + ':SLICE_X' + str(slice_UpperRightX) + 'Y' + str(slice_UpperRightY) + ';\n')
        constraintsFile.write('AREA_GROUP "AG_' + areaGroupObject.name + '" GROUP=CLOSED;\n')
        constraintsFile.write('AREA_GROUP "AG_' + areaGroupObject.name + '" PLACE=CLOSED;\n')
        
    constraintsFile.close()

def emitConstraintsVivado(fileName, areaGroups):
    constraintsFile = open(fileName, 'w')
    for areaGroupName in areaGroups:
        areaGroupObject = areaGroups[areaGroupName]

        # if area group was tagged as None, do not emit an area group
        # for it.  This allows us to handle area groups hidden in the
        # user UCF.
        if(areaGroupObject.sourcePath is None):
            continue

        # This is a magic conversion factor for virtex 7.  It might
        # need to change for different architectures.
        lutToSliceRatio = 1

        #startgroup
        #create_pblock pblock_ddr3 
        #resize_pblock pblock_ddr3 -add {SLICE_X134Y267:SLICE_X173Y349}
        #add_cells_to_pblock pblock_ddr3 [get_cells -hier -filter {NAME =~ m_sys_sys_vp_m_mod/llpi_phys_plat_sdram_b_ddrSynth/*}]
        #endgroup

        constraintsFile.write('#Generated Area Group for ' + areaGroupObject.name + ' with area ' + str(areaGroupObject.area) + ' \n')
        constraintsFile.write('startgroup \n')
        constraintsFile.write('create_pblock AG_' + areaGroupObject.name + '\n')

        slice_LowerLeftX = int((areaGroupObject.xLoc - .5  * areaGroupObject.xDimension)/lutToSliceRatio)
        slice_LowerLeftY = int((areaGroupObject.yLoc - .5  * areaGroupObject.yDimension)/lutToSliceRatio)

        slice_UpperRightX = int((areaGroupObject.xLoc + .5  * areaGroupObject.xDimension)/lutToSliceRatio)
        slice_UpperRightY = int((areaGroupObject.yLoc + .5  * areaGroupObject.yDimension)/lutToSliceRatio)
  
        constraintsFile.write('resize_pblock AG_' + areaGroupObject.name + ' -add {SLICE_X' + str(slice_LowerLeftX) + 'Y' + str(slice_LowerLeftY) + ':SLICE_X' + str(slice_UpperRightX) + 'Y' + str(slice_UpperRightY) + '}\n')

        constraintsFile.write('add_cells_to_pblock AG_' + areaGroupObject.name + ' [get_cells -hier -filter {NAME =~ "' + areaGroupObject.sourcePath + '/*"}]\n')



        constraintsFile.write('set_property CONTAIN_ROUTING true [get_pblocks AG_' + areaGroupObject.name + ']\n')
        constraintsFile.write('set_property EXCLUDE_PLACEMENT true [get_pblocks AG_' + areaGroupObject.name + ']\n')

        constraintsFile.write('endgroup \n')
        
    constraintsFile.close()



class Floorplanner():

    def __init__(self, moduleList):
        self.pipeline_debug = getBuildPipelineDebug(moduleList)

        def modify_path_hw(path):
            return  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + path

        if(not moduleList.getAWBParam('area_group_tool', 'ENABLE_SMART_AREA_GROUPS')):
               return

        liGraph = LIGraph([])
        firstPassGraph = wrapper_gen_tool.getFirstPassLIGraph()
        # We should ignore the 'PLATFORM_MODULE'                                                                                                                    
        liGraph.mergeModules(firstPassGraph.modules.values())
        self.firstPassLIGraph = liGraph

        # We'll build a rather complex function to emit area group constraints 
        def area_group_closure(moduleList):

             def area_group(target, source, env):
                 modFile = 'areaGroup.mod'
                 modHandle = open(modFile,'w')

                 extra_area_factor = 1.3                

                 # we should now assemble the LI Modules that we got
                 # from the synthesis run
                 moduleResources = {}
                 if(self.firstPassLIGraph is None):
                     moduleResources = assignResources(moduleList)
                 else:
                     moduleResources = assignResources(moduleList, None, self.firstPassLIGraph)
                 

                 areaGroups = {}
                 # We should make a bunch of AreaGroups here. 
                 for module in sorted(moduleResources):
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
                 chipXDimension = -1
                 chipYDimension = -1               
                 
                 # a list of all variables in the ILP problem
                 variables = []

                 # Fill in any other information we obtanied about the
                 # area groups.
                 for constraint in constraints:
                     if(isinstance(constraint,AreaGroupSize)): 
                         if(constraint.name == 'FPGA'):
                             if(chipXDimension > 0):
                                 print "Got too many FPGA dimension statements, bailing"
                                 exit(1)
                             chipXDimension = constraint.xDimension
                             chipYDimension = constraint.yDimension
                         else:
                             # this is a dimensional constraint for an
                             # area group. This will wipe the affine
                             # coefficients that we filled in during
                             # the previous loop.
                             areaGroups[constraint.name].xDimension = [constraint.xDimension]
                             areaGroups[constraint.name].yDimension = [constraint.yDimension]
                    

                     if(isinstance(constraint,AreaGroupResource)): 
                         if(not constraint.name in moduleResources):
                             moduleResources[constraint.name] = {}
 
                         moduleResources[constraint.name][constraint.type] = constraint.value

                     if(isinstance(constraint,AreaGroupLocation)): 
                         areaGroups[constraint.name].xLoc = constraint.xLocation
                         areaGroups[constraint.name].yLoc = constraint.yLocation
                         
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
                         areaGroup.area = areaGroup.xDimension[0] * areaGroup.yDimension[0]

                 # We've now built a tree of parent/child
                 # relationships, which we can use to remove area from
                 # the parent (double counting is a problem).  
                 for areaGroup in areaGroups.values():
                     for child in areaGroup.children.values():
                         print 'AREAGROUP: setting parent ' + areaGroup.name +  ' area from ' +  str(areaGroup.area) + 'to' + str(areaGroup.area - child.area) + ' due to child ' + child.name + '\n'
                         # If we have a slice resource declaration,
                         # use it else, use 1/2 the area as an estimate
                         if('SLICE' in moduleResources[child.name]):
                             areaGroup.area = areaGroup.area - moduleResources[child.name]['SLICE']
                         else:
                             areaGroup.area = areaGroup.area - child.area/2

                 affineCoefs = [.5, .65, .75, 1, 1.33, 1.66, 2] # just make them all squares for now. 
                 for areaGroup in areaGroups:
                     areaGroupObject = areaGroups[areaGroup]
                     # we might have gotten coefficients from the constraints.
                     if(areaGroupObject.xDimension is None):
                         areaGroupObject.xDimension = []
                         areaGroupObject.yDimension = []                       
                         moduleRoot = math.sqrt(areaGroupObject.area)
                         for coef in affineCoefs:
                             areaGroupObject.xDimension.append(coef*moduleRoot*extra_area_factor)
                             areaGroupObject.yDimension.append(moduleRoot/coef*extra_area_factor)
        



                 # let's begin setting up the ILP problem 
                 modHandle.write('var comms;\n')                         
                 modHandle.write('\n\nminimize dist: comms;\n\n')
                 variables += ['comms']
                 
                 # first we need to establish the options for the module area groups
                 for areaGroup in sorted(areaGroups):
                     areaGroupObject = areaGroups[areaGroup]
                     variables += ['xloc_' + areaGroupObject.name, 'yloc_' + areaGroupObject.name]  
                     if(areaGroupObject.xLoc is None):
                         modHandle.write('var xloc_' + areaGroupObject.name + ';\n')
                         modHandle.write('var yloc_' + areaGroupObject.name + ';\n')                         
                     else:
                         modHandle.write('var xloc_' + areaGroupObject.name + ' = ' + str(areaGroupObject.xLoc) + ';\n')
                         modHandle.write('var yloc_' + areaGroupObject.name + ' = ' + str(areaGroupObject.yLoc) + ';\n')

                     if(len(areaGroupObject.xDimension) > 1):
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
                         modHandle.write('var xdim_' + areaGroupObject.name + ' = ' + str(areaGroupObject.xDimension[0]) + ';\n')
                         modHandle.write('var ydim_' + areaGroupObject.name + ' = ' + str(areaGroupObject.yDimension[0]) +';\n')

                     variables += ['xdim_' + areaGroupObject.name, 'ydim_' + areaGroupObject.name]

                     # Throw a bounding box on the location variables
                     if(areaGroupObject.xLoc is None):
                         modHandle.write('subject to xdim_' + areaGroupObject.name + '_high_bound:\n')
                         modHandle.write('xloc_' + areaGroupObject.name + ' <= ' + str(chipXDimension) + ' - 0.5 * xdim_' + areaGroupObject.name +';\n')
                         modHandle.write('subject to xdim_' + areaGroupObject.name + '_low_bound:\n')
                         modHandle.write('xloc_' + areaGroupObject.name + ' >= ' + '0.5 * xdim_' + areaGroupObject.name +';\n')           

                     if(areaGroupObject.yLoc is None):
                         modHandle.write('subject to ydim_' + areaGroupObject.name + '_high_bound:\n')
                         modHandle.write('yloc_' + areaGroupObject.name + ' <= ' + str(chipYDimension) + ' - 0.5 * ydim_' + areaGroupObject.name +';\n')
                         modHandle.write('subject to ydim_' + areaGroupObject.name + '_low_bound:\n')
                         modHandle.write('yloc_' + areaGroupObject.name + ' >= ' + '0.5 * ydim_' + areaGroupObject.name +';\n')           

                 # Now we need to lay down the non-overlap constraints
                 areaGroupNames = sorted([name for name in areaGroups])
                 sumTerms = []
                 for areaGroupAIndex in range(len(areaGroupNames)):
                     areaGroupA = areaGroups[areaGroupNames[areaGroupAIndex]]
                     for areaGroupBIndex in range(areaGroupAIndex, len(areaGroupNames)):             
                         areaGroupB = areaGroups[areaGroupNames[areaGroupBIndex]]
                         if(areaGroupA.name == areaGroupB.name):
                             continue

                         absX = 'xdist_' + areaGroupA.name + '_' +  areaGroupB.name 
                         absY = 'ydist_' + areaGroupA.name + '_' +  areaGroupB.name 
                         satX = 'sat_xdist_' + areaGroupA.name + '_' +  areaGroupB.name 
                         satY = 'sat_ydist_' + areaGroupA.name + '_' +  areaGroupB.name 
                         aBiggerX = 'sat_x_abigger_' + areaGroupA.name + '_' +  areaGroupB.name 
                         aBiggerY = 'sat_y_abigger_' + areaGroupA.name + '_' +  areaGroupB.name 
                         variables += [absX, absY, satX, satY, aBiggerX, aBiggerY]  
                         modHandle.write('var ' + absX + ';\n')
                         modHandle.write('var ' + absY + ';\n')
                         modHandle.write('var ' + satX + ' binary;\n')
                         modHandle.write('var ' + satY + ' binary;\n')
                         modHandle.write('var ' + aBiggerX + ' binary;\n')
                         modHandle.write('var ' + aBiggerY + ' binary;\n')

                         # Need to find out how much the two modules communicate. 
                         commsXY = 1 # we want to force a tight grouping no matter what.

                         # Area groups come in two types -- parents
                         # and children.  Children communicate only
                         # with parents, while parents may communicate
                         # with other parents.
               
                         #Handle parents
                         if(areaGroupA.parent is None):    
                             moduleAObject = self.firstPassLIGraph.modules[areaGroupA.name]
                             for channel in moduleAObject.channels:
                                 # some channels may not be assigned
                                 if(isinstance(channel.partnerModule, LIModule)):
                                     if(channel.partnerModule.name == areaGroupB.name):
                                         commsXY = commsXY + 1000
                         else:
                             # this area group is a child.  Make it close to the parent and nothing else. 
                             if(areaGroupA.parent == areaGroupB.name):
                                 commsXY = commsXY * 10000


                         #if(commsXY < 1):
                         sumTerms += [str(commsXY) + ' * ' + absX, str(commsXY) + ' * ' + absY]

                         # ensure that either X or Y distance is satisfied
                         modHandle.write('subject to sat_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write(satX + ' + ' + satY + ' <= 1;\n')

                         # Add in terms for abs value

                         modHandle.write('subject to abs_xdim_1_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('xloc_' + areaGroupA.name + ' - xloc_'  +  areaGroupB.name + '+' + str(2*chipXDimension) + ' - ' + str(2*chipXDimension) + '*' + aBiggerX +' >= ' + absX + ';\n')

                         modHandle.write('subject to abs_xdim_2_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('xloc_' + areaGroupB.name + ' - xloc_'  +  areaGroupA.name + '+' + str(2*chipXDimension) + '*' + aBiggerX +' >= ' + absX + ';\n')


                         modHandle.write('subject to abs_xdim_3_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('xloc_' + areaGroupA.name + ' - xloc_'  +  areaGroupB.name + ' <= ' + absX + ';\n')

                         modHandle.write('subject to abs_xdim_4_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('xloc_' + areaGroupB.name + ' - xloc_'  +  areaGroupA.name + ' <= ' + absX + ';\n')


                         modHandle.write('subject to abs_ydim_1_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('yloc_' + areaGroupA.name + ' - yloc_'  +  areaGroupB.name + '+' + str(2*chipYDimension) + '-' + str(2*chipYDimension) + '*' + aBiggerY +' >= ' + absY + ';\n')

                         modHandle.write('subject to abs_ydim_2_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('yloc_' + areaGroupB.name + ' - yloc_'  +  areaGroupA.name +  '+' + str(2*chipYDimension) + '*' + aBiggerY + ' >= ' + absY + ';\n')


                         modHandle.write('subject to abs_ydim_3_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('yloc_' + areaGroupA.name + ' - yloc_'  +  areaGroupB.name +  ' <= ' + absY + ';\n')

                         modHandle.write('subject to abs_ydim_4_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('yloc_' + areaGroupB.name + ' - yloc_'  +  areaGroupA.name +  ' <= ' + absY + ';\n')




                         # the abs terms are also bound by some minimum distance
               
                         modHandle.write('subject to min_ydim_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('0.5 * ydim_' + areaGroupB.name + ' + 0.5 * ydim_'  +  areaGroupA.name + ' - ' + str(chipYDimension) + ' * ' + satX +  ' <= ' + absY + ';\n')

                         modHandle.write('subject to min_xdim_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('0.5 * xdim_' + areaGroupB.name + ' + 0.5 * xdim_'  +  areaGroupA.name + ' - ' + str(chipXDimension) + ' * ' + satY +  ' <= ' + absX + ';\n')
          


                 modHandle.write('subject to  comms_total: \n')                         
                 modHandle.write('+'.join(sumTerms) + ' = comms;\n')                 
                 modHandle.write('\n\nend;')
                 modHandle.close()

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
                         iocp_param.mip_gap=0.3

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
                 for areaGroupIndex in range(len(areaGroupNames)):
                     areaGroup = areaGroups[areaGroupNames[areaGroupIndex]]

                     areaGroup.xLoc = eval('example.xloc_' + areaGroup.name).value()
                     areaGroup.yLoc = eval('example.yloc_' + areaGroup.name).value()

                     # If problem was not satisfiable, then xloc/yloc
                     # are set to zero.  We should really give up and
                     # clear all area groups, since this technically
                     # results in a correct solution.
                     if(areaGroup.xLoc < 1 or areaGroup.yLoc < 1):
                         print "Failed to find solution to area group placement"
                         dumpVariables(example)
                         exit(1)

                     # figure out the chose dimensions.

                     areaGroup.xDimension = eval('example.xdim_' + areaGroup.name).value()
                     areaGroup.yDimension = eval('example.ydim_' + areaGroup.name).value()

                     print str(areaGroup)

                 # Sort area groups topologically, annotating each area group
                 # with a sortIdx field.
                 self.sort_area_groups(areaGroups)

                 # Now that we've solved (to some extent) the area
                 # group mapping problem we can dump the results for 
                 # the build tree. 

                 pickle_handle = open(areaConstraintsFileIncomplete(moduleList), 'wb')
                 pickle.dump(areaGroups, pickle_handle, protocol=-1)
                 pickle_handle.close()                 
                 
             return area_group

        # expose this dependency to the backend tools.
        moduleList.topModule.moduleDependency['AREA_GROUPS'] = [areaConstraintsFileIncomplete(moduleList)]

        # We need to get the resources for all modules, except the top module, which can change. 
        resources = [dep for dep in moduleList.getAllDependencies('RESOURCES')]

        areagroup = moduleList.env.Command( 
            [areaConstraintsFileIncomplete(moduleList)],
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
