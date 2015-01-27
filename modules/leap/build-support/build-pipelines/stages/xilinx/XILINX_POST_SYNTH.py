import os
import re
import sys
import SCons.Script
from model import  *
from xilinx_ngd import *
from xilinx_map import *
from xilinx_par import *
from xilinx_bitgen import *
from xilinx_loader import *

#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class PostSynthesize():
  def __init__(self, moduleList):

    # if we have a deps build, don't do anything...
    if(moduleList.isDependsBuild):
        return
      
    NGD(moduleList)

    MAP(moduleList)

    PAR(moduleList)

    BITGEN(moduleList)

    LOADER(moduleList)
    
