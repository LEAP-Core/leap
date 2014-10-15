import math
import cPickle as pickle

from area_group_parser import *
from model import  *
from li_module import *
from wrapper_gen_tool import *

def areaConstraintType():
    return 'UCF'

def loadAreaConstraints(filename):
    # The first pass will dump a well known file. 
    if(os.path.isfile(filename)):
        # We got a valid LI graph from the first pass.
        pickleHandle = open(filename, 'rb')
        areaGroups = pickle.load(pickleHandle)
        pickleHandle.close()
        return areaGroups
    return None

def areaConstraintFileIncomplete(moduleList):
    return  moduleList.compileDirectory + '/areagroups.nopaths.pickle'  

def areaConstraintFileComplete(moduleList):    
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

        print "Emitting Code for: " + str(areaGroupObject)
        # This is a magic conversion factor for virtex 7.  It might
        # need to change for different architectures.
        lutToSliceRatio = 2.828 

        #INST "m_sys_sys_syn_m_mod/common_services_inst/*" AREA_GROUP = "AG_common_services";
#AREA_GROUP "AG_common_services"                   RANGE=SLICE_X146Y201:SLICE_X168Y223;
#AREA_GROUP "AG_common_services"                   GROUP = CLOSED;
        constraintsFile.write('#Generated Area Group for ' + areaGroupObject.name + '\n')
        constraintsFile.write('INST "' + areaGroupObject.sourcePath + '/*" AREA_GROUP = "AG_' + areaGroupObject.name + '";\n')
        slice_LowerLeftX = int((areaGroupObject.xLoc - .5  * areaGroupObject.xDimension)/lutToSliceRatio)
        slice_LowerLeftY = int((areaGroupObject.yLoc - .5  * areaGroupObject.yDimension)/lutToSliceRatio)

        slice_UpperRightX = int((areaGroupObject.xLoc + .5  * areaGroupObject.xDimension)/lutToSliceRatio)
        slice_UpperRightY = int((areaGroupObject.yLoc + .5  * areaGroupObject.yDimension)/lutToSliceRatio)
  
        constraintsFile.write('AREA_GROUP "AG_' + areaGroupObject.name + '" RANGE=SLICE_X' + str(slice_LowerLeftX) + 'Y' + str(slice_LowerLeftY) + ':SLICE_X' + str(slice_UpperRightX) + 'Y' + str(slice_UpperRightY) + ';\n')
        constraintsFile.write('AREA_GROUP "AG_' + areaGroupObject.name + '" GROUP=CLOSED;\n')
        
    constraintsFile.close()
    

class Floorplanner():

    def __init__(self, moduleList):

        def modify_path_hw(path):
            return  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + path

        if(not moduleList.getAWBParam('area_group_tool', 'ENABLE_SMART_AREA_GROUPS')):
               return

        self.firstPassLIGraph = getFirstPassLIGraph()

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
                 
                 print 'Module resources: ' + str(moduleResources)

                 areaGroups = {}
                 # We should make a bunch of AreaGroups here. 
                 for module in sorted(moduleResources):
                     # EEEK I don't think I know what the paths will
                     # be at this point. Probably need to memoize and
                     # fill those in later?
                     if(module in moduleResources):
                         if('LUT' in moduleResources[module]):
                             areaGroups[module] = AreaGroup(module, '')
                             areaGroups[module].area = moduleResources[module]['LUT']

                 # now that we have the modules, let's apply constraints. 

                 # Let's build a graph of the modules.  First, we use
                 # the module resources to setup possible dimension
                 # reprsentation with an affine equation. 
                 print "moduleResources " + str(moduleResources)
                 affineCoefs = [1] # just make them all squares for now. 
                 for areaGroup in areaGroups:
                     areaGroupObject = areaGroups[areaGroup]
                     areaGroupObject.xDimension = []
                     areaGroupObject.yDimension = []
                     moduleRoot = math.sqrt(areaGroupObject.area)
                     for coef in affineCoefs:
                         areaGroupObject.xDimension.append(coef*moduleRoot*extra_area_factor)
                         areaGroupObject.yDimension.append(moduleRoot/coef*extra_area_factor)

                 # Now we will read in user provided constraints and apply these. 

                 print "area sources " + str(convertDependencies(source))
                 constraints = []
                 for constraintFile in moduleList.getAllDependenciesWithPaths('GIVEN_AREA_CONSTRAINTS'):
                     constraints += parseAreaGroupConstraints(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + constraintFile)

                 # We should have gotten a chip dimension. Find and assign chip. 
                 chipXDimension = -1
                 chipYDimension = -1               
                 
                 # a list of all variables in the ILP problem
                 variables = []

                 # first bind new area groups. 
                 for constraint in constraints:
                     if(isinstance(constraint,AreaGroup)):                         
                         areaGroups[constraint.name] = constraint

                 # Fill in any other information we obtanied about the
                 # area groups.
                 for constraint in constraints:
                     if(isinstance(constraint,AreaGroupSize)): 
                         print 'Constraint type Size ' + str(constraints)                             
                         if(constraint.name == 'FPGA'):
                             print 'Constraint for chip ' + str(constraints)                             
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
                     if(isinstance(constraint,AreaGroupLocation)): 
                         areaGroups[constraint.name].xLoc = constraint.xLocation
                         areaGroups[constraint.name].yLoc = constraint.yLocation
                         
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
                         for dimensionIndex in len(areaGroupObject.xDimension):
                             aspectName = areaGroupObject.name + '_' + dimensionIndex
                             modHandle.write('var ' + aspectName + ' binary;\n')
                             dimsX.append(str(areaGroupObject.xDimension[dimensionIndex]) + ' * ' + aspectName)
                             dimsY.append(str(areaGroupObject.yDimension[dimensionIndex]) + ' * ' + aspectName)

                         modHandle.write('var xdim_' + areaGroupObject.name + ';\n')
                         modHandle.write('var ydim_' + areaGroupObject.name + ';\n')
                             
                         modHandle.write('subject to xdim_' + areaGroupObject.name + '_assign:\n')
                         modHandle.write(' + '.join(dimsX) + ' = xdim_' + areaGroupObject.name +';\n')
                         modHandle.write('subject to ydim_' + areaGroupObject.name + '_assign:\n')
                         modHandle.write(' + '.join(dimsY) + ' = ydim_' + areaGroupObject.name +';\n')
                     else:
                         # Much simpler constraints when considering single shapes. 
                         modHandle.write('var xdim_' + areaGroupObject.name + ' = ' + str(areaGroupObject.xDimension[0]) + ';\n')
                         modHandle.write('var ydim_' + areaGroupObject.name + ' = ' + str(areaGroupObject.yDimension[0]) +';\n')

                     # Throw a bounding box on the location variables
                     modHandle.write('subject to xdim_' + areaGroupObject.name + '_high_bound:\n')
                     modHandle.write('xloc_' + areaGroupObject.name + ' <= ' + str(chipXDimension) + ' - 0.5 * xdim_' + areaGroupObject.name +';\n')
                     modHandle.write('subject to xdim_' + areaGroupObject.name + '_low_bound:\n')
                     modHandle.write('xloc_' + areaGroupObject.name + ' >= ' + '0.5 * xdim_' + areaGroupObject.name +';\n')           

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

                         sumTerms += [absX, absY]

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
               
                         modHandle.write('subject to min_xdim_1_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('0.5 * ydim_' + areaGroupB.name + ' + 0.5 * ydim_'  +  areaGroupA.name + ' - ' + str(chipYDimension) + ' * ' + satX +  ' <= ' + absY + ';\n')

                         modHandle.write('subject to min_xdim_2_' + areaGroupA.name + '_' +  areaGroupB.name + ':\n')
                         modHandle.write('0.5 * xdim_' + areaGroupB.name + ' + 0.5 * xdim_'  +  areaGroupA.name + ' - ' + str(chipXDimension) + ' * ' + satY +  ' <= ' + absX + ';\n')
          


                 modHandle.write('subject to  comms_total: \n')                         
                 modHandle.write('+'.join(sumTerms) + ' = comms;\n')                 
                 modHandle.write('\n\nend;')
                 modHandle.close()

                 # now that we've written out the file, solve it. 
                 # Necessary to force ply rebuild.  Sad...
                 import glpk 
                 example = glpk.glpk(modFile)
                 example.update()
                 example.solve()

                 # dump interesting variables
                 for variable in variables:
                     print variable + ' is: ' + str(eval('example.' + variable).value()) 

                 # print out module locations 
                 for areaGroupIndex in range(len(areaGroupNames)):
                     areaGroup = areaGroups[areaGroupNames[areaGroupIndex]]

                     areaGroup.xLoc = eval('example.xloc_' + areaGroup.name).value()
                     areaGroup.yLoc = eval('example.yloc_' + areaGroup.name).value()

                     # figure out the chose dimensions.

                     areaGroup.xDimension = eval('example.xdim_' + areaGroup.name).value()
                     areaGroup.yDimension = eval('example.ydim_' + areaGroup.name).value()

                     print str(areaGroup)

                 # Now that we've solved (to some extent) the area
                 # group mapping problem we can dump the results for 
                 # the build tree. 

                 pickleHandle = open(areaConstraintFileIncomplete(moduleList), 'wb')
                 pickle.dump(areaGroups, pickleHandle, protocol=-1)
                 pickleHandle.close()                 
                 
             return area_group

        # expose this dependency to the backend tools.
        moduleList.topModule.moduleDependency['AREA_GROUPS'] = [areaConstraintFileIncomplete(moduleList)]

        # We need to get the resources for all modules, except the top module, which can change. 
        resources = [dep for dep in moduleList.getAllDependencies('RESOURCES')]

        areagroup = moduleList.env.Command( 
            [areaConstraintFileIncomplete(moduleList)],
            resources + map(modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_AREA_CONSTRAINTS')),
            area_group_closure(moduleList)
            )                   

        moduleList.env.AlwaysBuild(areagroup)
