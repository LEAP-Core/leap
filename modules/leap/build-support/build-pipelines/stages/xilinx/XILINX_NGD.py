import os
import SCons.Script
from model import  *

try:
    import area_group_tool
except ImportError:
    pass # we won't be using this tool.


#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class NGD():
  def __init__(self, moduleList):

    fpga_part_xilinx = moduleList.env['DEFS']['FPGA_PART_XILINX']
    xilinx_apm_name = moduleList.compileDirectory + '/' + moduleList.apmName


    # If we got an area group placement data structure, now is the
    # time to convert it into a UCF. 
    if ('AREA_GROUPS' in moduleList.topModule.moduleDependency):
        area_constraints = area_group_tool.AreaConstraints(moduleList)
        area_group_file = moduleList.compileDirectory + '/areagroups.ucf'

        # user ucf may be overridden by our area group ucf.  Put our
        # generated ucf first.
        moduleList.topModule.moduleDependency['UCF'].insert(0,area_group_file)
        def area_group_ucf_closure(moduleList):

             def area_group_ucf(target, source, env):
                 area_constraints.loadAreaConstraints()
                 area_constraints.emitConstraintsXilinx(area_group_file)
                                    
             return area_group_ucf

        moduleList.env.Command( 
            [area_group_file],
            area_constraints.areaConstraintsFile(),
            area_group_ucf_closure(moduleList)
            )                   

    # Concatenate UCF files
    if(len(moduleList.topModule.moduleDependency['UCF']) > 0):
        xilinx_ucf = moduleList.env.Command(
        xilinx_apm_name + '.ucf',
        moduleList.topModule.moduleDependency['UCF'],
        'cat $SOURCES > $TARGET')

    if len(moduleList.env['DEFS']['GIVEN_BMMS']) != 0:
      xilinx_bmm = moduleList.env.Command(
        xilinx_apm_name + '.bmm',
        Utils.clean_split(moduleList.env['DEFS']['GIVEN_BMMS'], sep = ' '),
        'cat $SOURCES > $TARGET')
    #./ works around crappy xilinx parser
      bmm = ' -bm ./' + xilinx_apm_name + '.bmm' 
    else:
      xilinx_bmm = ''
      bmm = ''

    # Generate include for each synthesis boundary.  (Synplify build uses
    # subdirectories.)
    sd_list = [moduleList.env['DEFS']['ROOT_DIR_HW_MODEL'], moduleList.compileDirectory]
    for module in moduleList.synthBoundaries():
      w = moduleList.compileDirectory + '/' + module.wrapperName()
      sd_list += [w,moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/']

    given_netlists = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + netlist for netlist in moduleList.getAllDependenciesWithPaths('GIVEN_NGCS') + moduleList.getAllDependenciesWithPaths('GIVEN_EDFS') ]
    module_ngcs = moduleList.getAllDependencies('SYNTHESIS')

    xilinx_ngd = moduleList.env.Command(
      xilinx_apm_name + '.ngd',
      moduleList.topModule.moduleDependency['SYNTHESIS'] + given_netlists,
      [ SCons.Script.Delete(xilinx_apm_name + '.bld'),
        SCons.Script.Delete(xilinx_apm_name + '_ngdbuild.xrpt'),
        # Xilinx project files are created automatically by Xilinx tools, but not
        # needed for command line tools.  The project files may be corrupt due
        # to parallel invocation of xst.  Until we figure out how to move them
        # or guarantee their safety, just delete them.
        SCons.Script.Delete('xlnx_auto_0.ise'),
        SCons.Script.Delete('xlnx_auto_0_xdb'),
        'ngdbuild -aul -aut -p ' + fpga_part_xilinx + \
          ' -sd ' + ' -sd '.join(sd_list) + \
          ' -uc ' + xilinx_apm_name + '.ucf ' + bmm + ' $SOURCE $TARGET | tee ' + xilinx_apm_name +'.ngdrpt',
        SCons.Script.Move(moduleList.compileDirectory + '/netlist.lst', 'netlist.lst') ])

    moduleList.env.Depends(xilinx_ngd,
                           given_netlists +
                           module_ngcs + 
                           xilinx_ucf +
                           xilinx_bmm)

    moduleList.topModule.moduleDependency['NGD'] = [xilinx_ngd]
      
    SCons.Script.Clean(xilinx_ngd, moduleList.compileDirectory + '/netlist.lst')

    # Alias for NGD
    moduleList.env.Alias('ngd', xilinx_ngd)
