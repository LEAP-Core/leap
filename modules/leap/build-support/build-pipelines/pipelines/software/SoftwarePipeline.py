##
## Build pipeline for software simulation
##
 
import os
import re
import SCons.Script  
from iface_tool import *
from software_tool import *
#from wrapper_gen_tool import *
from model import  *

class Build(ProjectDependency):
  def __init__(self, moduleList):

    # Build interface first 
    Iface(moduleList)
    #if not bsv.isDependsBuild:
    Software(moduleList)
 
