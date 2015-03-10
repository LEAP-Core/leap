############################################################################
############################################################################
##
## Utility functions used in this module and in submodules
##
############################################################################
############################################################################

import os
import re
import sys
import subprocess

import model

##
## get_bluespec_verilog --
##     Return a list of Verilog files from the Bluespec compiler release.
##
def get_bluespec_verilog(env, resultArray = {}, filePath='Verilog'):
    bluespecdir = env['ENV']['BLUESPECDIR']
    
    fileProc = subprocess.Popen(["ls", "-1", bluespecdir + '/' + filePath + '/'], stdout = subprocess.PIPE)
    fileList = fileProc.stdout.read()
    fileArray = model.clean_split(fileList, sep = '\n')
    for file in fileArray:
        if ((file[-2:] == '.v') and
            (file != 'main.v') and
            (file != 'ConstrainedRandom.v')):
            resultArray[file] = bluespecdir + '/' + filePath + '/' + file

    fileProc = subprocess.Popen(["ls", "-1", bluespecdir + '/Libraries/'], stdout = subprocess.PIPE)
    fileList = fileProc.stdout.read()
    fileArray = model.clean_split(fileList, sep = '\n')
    for file in fileArray:
        if ((file[-2:] == '.v') and
            (file[:6] != 'xilinx')):
            resultArray[file] = bluespecdir + '/Libraries/' + file

    return resultArray

##
## get_bluespec_xcf --
##     Return a list of XCF files associated with Bluespec provided libraries.
##
def get_bluespec_xcf(env):
    bluespecdir = env['ENV']['BLUESPECDIR']

    # Bluespec only provides board-specific XCF files, but for now they are
    # all the same.  Find one.
    xcf = bluespecdir + '/board_support/xilinx/XUPV5/default.xcf.template'
    if os.path.exists(xcf):
        return [ xcf ];
    else:
        return [];


##
## What is the Bluespec compiler version?
##
def getBluespecVersion():
    if not hasattr(getBluespecVersion, 'version'):
        bsc_ostream = os.popen('bsc -verbose')
        ver_regexp = re.compile('^Bluespec Compiler, version.*\(build ([0-9]+),')
        for ln in bsc_ostream.readlines():
            m = ver_regexp.match(ln)
            if (m):
                getBluespecVersion.version = int(m.group(1))
        bsc_ostream.close()

        if getBluespecVersion.version == 0:
            print "Failed to get Bluespec compiler version"
            sys.exit(1)

        ## Generate an include file as a side-effect of calling this function
        ## that describes the compiler's capabilities.
        bsv_cap = open('hw/include/awb/provides/bsv_version_capabilities.bsh', 'w')
        bsv_cap.write('//\n')
        bsv_cap.write('// Bluespec compiler version\'s capabilities.\n')
        bsv_cap.write('// Generated at build time by Utils.py.\n\n')
        bsv_cap.write('//\n')
        bsv_cap.write('// Compiler version: ' + str(getBluespecVersion.version) + '\n')
        bsv_cap.write('//\n\n')

        bsv_cap.write('`ifndef INCLUDED_bsv_version_capabilities\n');
        bsv_cap.write('`define INCLUDED_bsv_version_capabilities\n\n');

        bsv_cap.write('// Char type implemented?\n')
        if (getBluespecVersion.version < 31201):
            bsv_cap.write('// ')
        bsv_cap.write('`define BSV_VER_CAP_CHAR 1\n')

        bsv_cap.write('\n`endif // INCLUDED_bsv_version_capabilities\n');
        bsv_cap.close()

    return getBluespecVersion.version

## 
## The functions below are a little ugly.  Ultimately, we should be
## building some include path using a -y like syntax as the other EDA
## tools do.  The code flow is most below: only an option parser is missing. 
## 

##
## decorateBluespecLibraryCodeBaseline --
##     Decorates the module list with information about bluespec library files. 
##
def decorateBluespecLibraryCodeBaseline(moduleList):
    bsvVerilog = get_bluespec_verilog(moduleList.env).values()

    for module in moduleList.synthBoundaries():
        model.dictionary_list_create_append(module.moduleDependency, 'VERILOG_LIB', bsvVerilog)

    model.dictionary_list_create_append(moduleList.topModule.moduleDependency, 'VERILOG_LIB', bsvVerilog)


##
## decorateBluespecLibraryCodeVivado --
##     Decorates the module list with information. Bluespec has a 
##
def decorateBluespecLibraryCodeVivado(moduleList):
    # get the baseline verilog
    bsvBaselineArray = get_bluespec_verilog(moduleList.env)

    # now get the vivado specific verilogs
    bsvVerilog = get_bluespec_verilog(moduleList.env, resultArray = bsvBaselineArray, filePath = 'Verilog.Vivado').values()

    for module in moduleList.synthBoundaries():
        model.dictionary_list_create_append(module.moduleDependency, 'VERILOG_LIB', bsvVerilog)

    model.dictionary_list_create_append(moduleList.topModule.moduleDependency, 'VERILOG_LIB', bsvVerilog)


