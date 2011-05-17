import os
import sys
import re
import SCons.Script
import ply.yacc as yacc
import ply.lex as lex
from model import  *
from config import *
from multilex import *
from multiparse import *

class ParseMultiFPGA():

  def __init__(self, moduleList):
    # build the compiler
    lex.lex()
    yacc.yacc()

    envFile = moduleList.getAllDependenciesWithPaths('GIVEN_FPGAENVS')
    if(len(envFile) != 1):
      print "Found more than one environment file: " + str(envFile) + ", exiting\n"
    environmentDescription = (open(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + envFile[0], 'r')).read()
    #print "opened env file: " + moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + envFile[0] + " -> " + environmentDescription
    environmentTree = yacc.parse(environmentDescription)
    print "environment keys: " + str(environmentTree.getPlatformNames)
