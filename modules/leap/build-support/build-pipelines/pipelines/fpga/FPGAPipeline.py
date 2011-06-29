import os
import re
import SCons.Script  
from model import  *
from iface_tool import *
from bsv_tool import *
from fpga_program_tool import *
from software_tool import *
from synthesis_tool import  *
from post_synthesis_tool import *
from mcd_tool import *
from wrapper_gen import *

class Build(ProjectDependency):
  def __init__(self, moduleList):
    WrapperGen(moduleList)
    Iface(moduleList)
    BSV(moduleList)
    FPGAProgram(moduleList)
    Software(moduleList)
    MCD(moduleList)
    #moduleList.dump()
    Synthesize(moduleList)
    #moduleList.dump()
    PostSynthesize(moduleList)



