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
from subprocess import call


def makePlatformName(name, apm):
  return name +'_'+ apm + '_multifpga.apm'

class ParseMultiFPGA():

  def __init__(self, moduleList):
    APM_FILE = moduleList.env['DEFS']['APM_FILE']
    APM_NAME = moduleList.env['DEFS']['APM_NAME']
    applicationName = APM_NAME  + '_mutlifpga.apm'
    applicationPath =  'config/pm/private/' + applicationName
  
    # build the compiler
    lex.lex()
    yacc.yacc()

    envFile = moduleList.getAllDependenciesWithPaths('GIVEN_FPGAENVS')
    if(len(envFile) != 1):
      print "Found more than one environment file: " + str(envFile) + ", exiting\n"
    environmentDescription = (open(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + envFile[0], 'r')).read()
    #print "opened env file: " + moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + envFile[0] + " -> " + environmentDescription
    environment = yacc.parse(environmentDescription)
    print "environment keys: " + str(environment.getPlatformNames)

    # select the connected_app and make it a submodel
    call(['asim-shell','create', 'submodel', APM_FILE , 'connected_application', applicationPath])        

    # the stuff below here should likely go in a different file, and there will be many hard-coded paths
    # copy the environment descriptions to private 
    #APM_FILE
    #WORKSPACE_ROOT
    for platformName in environment.getPlatformNames():
        platform = environment.getPlatform(platformName)
        platformName = makePlatformName(platform.name,APM_NAME)
        platformPath = 'config/pm/private/' + platformName
        call(['asim-shell','cp', platform.path , platformPath])        
        call(['asim-shell','replace','module', platformPath ,applicationPath])        
        
