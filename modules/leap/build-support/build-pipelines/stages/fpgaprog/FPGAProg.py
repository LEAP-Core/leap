import os
from model import  *

##
## The purpose of this build stage is to provide the run script context
## about programming the FPGA.
##

class FPGAProgram(ProjectDependency):
  def __init__(self, moduleList):
    fpgaFile = open('config/fpga.sh','w') 
    fpgaFile.write('#Generated by build pipeline\n')

    try:
      FPGA_PLATFORM = moduleList.getAWBParam('physical_platform', 'FPGA_PLATFORM')
    except:
      FPGA_PLATFORM = 'DEFAULT'

    try:
      SOFT_RESET = moduleList.getAWBParam('physical_channel', 'SOFT_RESET')
    except:
      SOFT_RESET = 1

    fpgaFile.write('FPGA="' + str(FPGA_PLATFORM) + '"\n')
    fpgaFile.write('SOFT_RESET=' + str(SOFT_RESET) + '\n')

