import os
import re
import sys
import string
import SCons.Script
import SCons.Util
import model
from model import  *
import bsv_tool


def getIfaceIncludeDirs():
    return 'iface/build/include:iface/build/hw'

class Iface():

  def __init__(self, moduleList):

    # Create link for legacy asim include tree
    if os.path.exists('iface/build/include') and not os.path.exists('iface/build/include/asim'):
        os.symlink('awb', 'iface/build/include/asim')

    BSC = moduleList.env['DEFS']['BSC']
    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
    ROOT_DIR_SW_INC = ":".join(moduleList.env['DEFS']['ROOT_DIR_SW_INC'].split(" ") + moduleList.env['DEFS']['SW_INC_DIRS'].split(" "))
    BSC_FLAGS_VERILOG = moduleList.env['DEFS']['BSC_FLAGS_VERILOG']

    moduleList.env['ENV']['SHELL'] = '/bin/sh'

    # First pass of LIM build may supply us with extra context for backend compilation. 
    if(re.search('\w', moduleList.getAWBParam('iface_tool', 'EXTRA_INC_DIRS'))):
        EXTRA_INC_DIRS = moduleList.getAWBParam('iface_tool', 'EXTRA_INC_DIRS')
        ROOT_DIR_SW_INC += ":" + EXTRA_INC_DIRS


    inc_tgt = 'iface/build/include'
    dict_inc_tgt = inc_tgt + '/awb/dict'
    rrr_inc_tgt = inc_tgt + '/awb/rrr'
    hw_tgt = 'iface/build/hw'

    # RRR files seem to reflect the synthesis boundary hierarchy
    def addPathDic(path):
      return 'iface/src/dict/' + path

    def addPathRRR(path):
      return 'iface/src/rrr/' + path

    if moduleList.env.GetOption('clean'):
        os.system('rm -rf iface/build')
    else:
      if not os.path.isdir(dict_inc_tgt):
          os.makedirs(inc_tgt + '/' + TMP_BSC_DIR)
          os.makedirs(dict_inc_tgt)
      if not os.path.isdir(rrr_inc_tgt):
          os.makedirs(rrr_inc_tgt)
      if not os.path.isdir(hw_tgt):
          os.makedirs(hw_tgt + '/' + TMP_BSC_DIR)

    tgt = []


    inc_dirs = ROOT_DIR_SW_INC 

    # Compile dictionary
    #  NOTE: this must run even if there are no dictionary files.  It always
    #  builds an init.h, even if it is empty.  That way any model can safely
    #  include init.h in a standard place.

    # First define an emitter that describes all the files generated by dictionaries
    self.all_gen_bsv = []
    def dict_emitter(target, source, env):        
        # Output file names are a function of the contents of dictionary files,
        # not the names of dictionary files.
        src_names = ''
        for s in source:
            src_names += ' ' + str(s)

        # Ask leap-dict for the output names based on the input file
        if(getBuildPipelineDebug(moduleList) != 0):
            print 'leap-dict --querymodules --src-inc ' + inc_dirs + ' ' + src_names +'\n'

        for d in os.popen('leap-dict --querymodules --src-inc ' + inc_dirs + ' ' + src_names).readlines():
            #
            # Querymodules describes both targets and dependence info.  Targets
            # are the first element of each line followed by a colon and a
            # space separated list of other dictionaries on which the target
            # depends, e.g.:
            #     STREAMS: STREAMS_A STREAMS_B
            #
            # Start by breaking the line into a one or two element array.  The
            # first element is a dictionary name.  The second element, if it
            # exists, is a list of other dictionaries on which the first element
            # depends.
            #
            tgt = d.rstrip().split(':')
            if (len(tgt) > 1):
                tgt[1] = [x for x in tgt[1].split(' ') if x != '']

            # Add to the target list for the build
            target.append(dict_inc_tgt + '/' + tgt[0] + '.bsh')
            target.append(dict_inc_tgt + '/' + tgt[0] + '.h')

            # Build a list of BSV files for building later
            bsv = [hw_tgt + '/' + tgt[0] + '_DICT.bsv']
            target.append(bsv[0])
            if (len(tgt) > 1):
                bsv.append([hw_tgt + '/' + x + '_DICT.bsv' for x in tgt[1]])
            self.all_gen_bsv.append(bsv)
            
        return target, source

    # Define the dictionary builder
    # not really sure why srcs stopped working?
    # leap-configure creates this dynamic_params.dic. Gotta handle is specially. Boo.
    localDictionaries = moduleList.getAllDependencies('GIVEN_DICTS') 
    extra_dicts = []
    if(re.search('\w', moduleList.getAWBParam('iface_tool', 'EXTRA_DICTS'))):
        EXTRA_DICTS = moduleList.getAWBParam('iface_tool', 'EXTRA_DICTS')
        extra_dicts = EXTRA_DICTS.split(':') 

    dicts = map(addPathDic, set(localDictionaries + ['dynamic_params.dic'] + extra_dicts))

    # leap-dict generates dictionary entries in the order
    # received. Force this order to be lexical
    dicts.sort()

    curdir = moduleList.rootDirectory
    r_dicts = [model.rebase_if_not_abspath(d, start=curdir) for d in dicts]
    dictCommand = 'leap-dict --src-inc ' + \
                  model.rebase_if_not_abspath(inc_dirs, start=curdir, sep=':') + \
                  ' --tgt-inc ' + model.rebase_if_not_abspath(dict_inc_tgt, start=curdir, sep=':') + \
                  ' --tgt-hw ' + model.rebase_if_not_abspath(hw_tgt, start=curdir, sep=':') + \
                  " " + (" ".join(r_dicts))
    if(getBuildPipelineDebug(moduleList) != 0):
        print dictCommand

    d_bld = moduleList.env.Builder(action = dictCommand,
                    emitter = dict_emitter)
    moduleList.env.Append(BUILDERS = {'DIC' : d_bld})

    # Add dependence info computed by previous dictionary builds (it uses cpp).
    for dic in dicts:
        d = '.depends-dic-' + os.path.basename(dic)
        moduleList.env.NoCache(d)
        moduleList.env.ParseDepends(d, must_exist = False)

    # Finally, request dictionary build    
    d_tgt = moduleList.env.DIC(dict_inc_tgt + '/init.h', dicts)
    tgt += d_tgt

    # Add dependence info computed by previous RRR builds (it uses cpp).
    extra_rrrs = []
    localRRRs = moduleList.getAllDependenciesWithPaths('GIVEN_RRRS')
    if(re.search('\w', moduleList.getAWBParam('iface_tool', 'EXTRA_RRRS'))):
        EXTRA_RRRS = moduleList.getAWBParam('iface_tool', 'EXTRA_RRRS')
        extra_rrrs = EXTRA_RRRS.split(':') 

    rrrs = map(addPathRRR, set(localRRRs + extra_rrrs))

    # leap-rrr-stubgen generates dictionary entries in the order
    # received. Force this order to be lexical
    rrrs.sort()
    for rrr in rrrs:
        d = '.depends-rrr-' + os.path.basename(rrr)
        moduleList.env.NoCache(d)
        moduleList.env.ParseDepends(d, must_exist = False)

    # Compile RRR stubs
    #  NOTE: like dictionaries, some files must be created even when no .rrr
    #  files exist.
    generate_vico = ''
    if (moduleList.getAWBParam('iface_tool', 'GENERATE_VICO')):
        generate_vico = '--vico'

    stubgen = 'leap-rrr-stubgen ' + generate_vico + \
              ' --incdirs ' + model.rebase_if_not_abspath(inc_dirs, start=curdir, sep=':') + \
              ' --odir ' + model.rebase_if_not_abspath(rrr_inc_tgt, start=curdir, sep=':') + \
              ' --mode stub --target hw --type server $SOURCES'

    r_tgt = moduleList.env.Command(rrr_inc_tgt + '/service_ids.h', rrrs, stubgen)

    tgt += r_tgt

    #
    # Compile generated BSV stubs
    #
    def emitter_bo(target, source, env):
        if (bsv_tool.getBluespecVersion() < 26572):
            target.append(str(target[0]).replace('.bo', '.bi'))
        return target, source

    def compile_bo(source, target, env, for_signature):
        bdir = os.path.dirname(str(target[0]))

        # Older compilers don't put -bdir on the search path
        maybe_bdir_tgt = ''
        if (bsv_tool.getBluespecVersion() < 15480):
            maybe_bdir_tgt = ':' + bdir

        cmd = BSC + ' ' + BSC_FLAGS_VERILOG + \
              ' -p +:' + inc_tgt + ':' + hw_tgt + maybe_bdir_tgt + \
              ' -bdir ' + bdir + ' -vdir ' + bdir + ' -simdir ' + bdir + ' ' + \
              str(source[0])
        return cmd

    bsc = moduleList.env.Builder(generator = compile_bo, suffix = '.bo', src_suffix = '.bsv',
                  emitter = emitter_bo)

    moduleList.env.Append(BUILDERS = {'BSC' : bsc})

    #
    # Describe BSV builds.  At the same time collect a Python dictionary of the
    # targets of the BSV builds.
    #
    bsv_targets = {}
    for bsv in self.all_gen_bsv:
        bo = os.path.dirname(bsv[0]) + '/' + TMP_BSC_DIR + '/' + os.path.splitext(os.path.basename(bsv[0]))[0] + '.bo'
        bsv_targets[bsv[0]] = moduleList.env.BSC(bo, bsv[0])
        tgt += bsv_targets[bsv[0]]

    #
    # Add BSV module dependence information.
    #
    for bsv in self.all_gen_bsv:
        if (len(bsv) > 1):
           for dep in bsv[1]:
               moduleList.env.NoCache(bsv_targets[dep])
               moduleList.env.Depends(bsv_targets[bsv[0]], bsv_targets[dep])

    #
    # Build everything
    # 
    moduleList.topModule.moduleDependency['IFACE'] = tgt
    moduleList.topModule.moduleDependency['IFACE_HEADERS'] = d_tgt + r_tgt

    moduleList.env.NoCache(tgt)
    moduleList.env.NoCache(d_tgt)
    moduleList.env.NoCache(r_tgt)   

    #
    # Backwards compatability link
    #
    if not moduleList.env.GetOption('clean') and not os.path.exists('iface/build/include/asim'):
        os.symlink('awb', 'iface/build/include/asim')

    moduleList.env.Alias('iface', tgt)
