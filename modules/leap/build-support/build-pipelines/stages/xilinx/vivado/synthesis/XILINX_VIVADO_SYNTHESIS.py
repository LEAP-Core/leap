import os
import re 
import sys
import SCons.Script
import functools


from model import  *
# need to pick up clock frequencies for xcf
import synthesis_library 
from parameter_substitution import *
import wrapper_gen_tool

   
#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path

class Synthesize():
  def __init__(self, moduleList):

    synthesis_library.buildNetlists(moduleList, synthesis_library.buildVivadoEDF, synthesis_library.buildVivadoEDF)





