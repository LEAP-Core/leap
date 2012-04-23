import os
import sys
import re
import string
import SCons.Script
from model import  *

def get_wrapper(module):
  return  module.name + '_Wrapper.bsv'

def get_log(module):
  return  module.name + '_Log.bsv'



#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path
# This is going to recursively build all the bsvs
class BSV():

  def __init__(self, moduleList):

    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']

    # Should we be building in events? 
    if (getEvents(moduleList) == 0):
       bsc_events_flag = ' -D HASIM_EVENTS_ENABLED=False '
    else:
       bsc_events_flag = ' -D HASIM_EVENTS_ENABLED=True '

    self.BSC_FLAGS = moduleList.getAWBParam('bsv_tool', 'BSC_FLAGS') + bsc_events_flag

    moduleList.env.BuildDir(TMP_BSC_DIR, '.', duplicate=0)
    moduleList.env['ENV']['BUILD_DIR'] = moduleList.env['DEFS']['BUILD_DIR']  # need to set the builddir for synplify

    # Walk synthesis boundaries in reverse topological order
    topo = moduleList.topologicalOrderSynth()
    topo.reverse()

    ##
    ## Is this a normal build or a build in which only Bluespec dependence
    ## is computed?
    ##

    if getCommandLineTargets(moduleList) != [ 'depends-init' ]:
      ##
      ## Normal build.
      ##
      ## Invoke a separate instance of SCons to compute the Bluespec
      ## dependence before going any farther.  We do this because the
      ## standard trick of having the compiler emit .d files doesn't work
      ## for us.  We can't predict the names of all Bluespec source
      ## files that may be generated in the iface tree for dictionaries
      ## and RRR.  SCons requires that dependence be computed on its first
      ## pass.  If a dictionary changes and a new Bluespec file is produced
      ## this must be discoverable before the ParseDepends call in
      ## build_synth_boundary() below.
      ##
      self.isDependsBuild = False

      if not moduleList.env.GetOption('clean'):
        print 'Building depends-init...'
        s = os.system('scons depends-init')
        if (s & 0xffff) != 0:
          print 'Aborting due to dependence errors'
          sys.exit(1)

      ##
      ## Now that the "depends-init" build is complete we can continue with
      ## accurate inter-Bluespec file dependence.
      ##
      synth = []
      for module in topo:
        synth += self.build_synth_boundary(moduleList, module)

      ##
      ## Generate the global string table.  Bluespec-generated global strings
      ## are found in the log files.
      ##
      ## The global string file will be generated in the top-level .bsc
      ## directory and a link to it will be added to the top-level directory.
      ##
      all_logs = []
      for module in topo:
        all_logs.extend(module.moduleDependency['BSV_LOG'])
      str = moduleList.env.Command(TMP_BSC_DIR + '/' + moduleList.env['DEFS']['APM_NAME'] + '.str',
                                   all_logs,
                                   [ self.gen_global_string_table,
                                     '@ln -fs $TARGET ' + moduleList.env['DEFS']['APM_NAME'] + '.str' ])
      moduleList.topModule.moduleDependency['STR'] += [str]
      moduleList.topDependency += [str]

      if moduleList.env.GetOption('clean'):
        print 'Cleaning depends-init...'
        s = os.system('scons --clean depends-init')

    else:
      ##
      ## Dependence build.  The target of this build is "depens-init".  No
      ## Bluespec modules will be compiled in this invocation of SCons.
      ## Only .depends-bsv files will be produced.
      ##
      self.isDependsBuild = True

      deps = []
      for module in topo:
        deps += self.compute_dependence(moduleList, module)

      moduleList.env.Alias('depends-init', deps)


  ##
  ## compute_dependence --
  ##   Build rules for computing intra-Bluespec file dependence.
  ##
  def compute_dependence(self, moduleList, module):
    env = moduleList.env
    MODULE_PATH =  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath
    TMP_BSC_DIR = env['DEFS']['TMP_BSC_DIR']

    ALL_DIRS_FROM_ROOT = env['DEFS']['ALL_HW_DIRS']
    ALL_BUILD_DIRS_FROM_ROOT = transform_string_list(ALL_DIRS_FROM_ROOT, ':', '', '/' + TMP_BSC_DIR)
    ALL_LIB_DIRS_FROM_ROOT = ALL_DIRS_FROM_ROOT + ':' + ALL_BUILD_DIRS_FROM_ROOT

    ROOT_DIR_HW_INC = env['DEFS']['ROOT_DIR_HW_INC']
 
    LOG_BSV = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/'+ get_log(module)
    WRAPPER_BSV = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/' + get_wrapper(module)

    # We must depend on all sythesis boundaries. They can be instantiated anywhere.
    surrogate_children = moduleList.synthBoundaries()
    SURROGATE_BSVS = ''
    for child in surrogate_children:
      # Make sure module doesn't self-depend
      if(child.name != module.name):
        SURROGATE_BSVS += moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + child.buildPath +'/' + child.name + '.bsv '

    if (SURROGATE_BSVS != ''):
      DERIVED = ' -derived "' + SURROGATE_BSVS + '"'
    else:
      DERIVED = ''

    depends_bsv = MODULE_PATH + '/.depends-bsv'
    moduleList.env.NoCache(depends_bsv)
    compile_deps = 'leap-bsc-mkdepend -ignore ' + MODULE_PATH + '/.ignore' + ' -bdir ' + TMP_BSC_DIR + DERIVED + ' -p +:' + ROOT_DIR_HW_INC + ':' + ROOT_DIR_HW_INC + '/awb/provides:' + ALL_LIB_DIRS_FROM_ROOT + ' ' + LOG_BSV + ' ' + WRAPPER_BSV + ' > ' + depends_bsv

    dep = moduleList.env.Command(depends_bsv,
                                 [ LOG_BSV, WRAPPER_BSV ] +
                                 moduleList.topModule.moduleDependency['IFACE_HEADERS'],
                                 compile_deps)

    # Load an old .depends-bsv file if it exists.  The file describes
    # the previous dependence among Bluespec files, giving a clue of whether
    # anything changed.  The file describes dependence between derived objects
    # and sources.  Here, we need to know about all possible source changes.
    # Scan the file looking for source file names.
    if os.path.isfile(depends_bsv):
      df = open(depends_bsv, 'r')
      dep_lines = df.readlines()

      # Match .bsv and .bsh files
      bsv_file_pattern = re.compile('\S+.[bB][sS][vVhH]$')

      all_bsc_files = []
      for ln in dep_lines:
        all_bsc_files += [f for f in re.split('[:\s]+', ln) if (bsv_file_pattern.match(f))]

      # Sort dependence in case SCons cares
      for f in sorted(all_bsc_files):
        if os.path.exists(f):
          moduleList.env.Depends(dep, f)

      df.close()

    return dep


  ##
  ## build_synth_boundary --
  ##   Build rules for generating a single synthesis boundary.  This function
  ##   may only be run after inter-Bluespec file dependence has been computed
  ##   and written to dependence files.  This requirement is met by running
  ##   a separate instance of SCons first that uses compute_dependence() above.
  ##
  def build_synth_boundary(self, moduleList, module):
    if(getBuildPipelineDebug(moduleList) != 0):
      print "Working on " + module.name

    env = moduleList.env
    MODULE_PATH =  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath
    TMP_BSC_DIR = env['DEFS']['TMP_BSC_DIR']

    ALL_DIRS_FROM_ROOT = env['DEFS']['ALL_HW_DIRS']
    ALL_BUILD_DIRS_FROM_ROOT = transform_string_list(ALL_DIRS_FROM_ROOT, ':', '', '/' + TMP_BSC_DIR)
    ALL_LIB_DIRS_FROM_ROOT = ALL_DIRS_FROM_ROOT + ':' + ALL_BUILD_DIRS_FROM_ROOT

    ROOT_DIR_HW_INC = env['DEFS']['ROOT_DIR_HW_INC']

    BSVS = moduleList.getSynthBoundaryDependencies(module,'GIVEN_BSVS')
    # each submodel will have a generated BSV
    GEN_BSVS = moduleList.getSynthBoundaryDependencies(module,'GEN_BSVS')
    APM_FILE = env['DEFS']['APM_FILE']
    BSC =env['DEFS']['BSC']

    ##
    ## Load intra-Bluespec dependence already computed.  This information will
    ## ultimately drive the building of Bluespec modules.
    ##
    env.ParseDepends(MODULE_PATH + '/.depends-bsv',
                     must_exist = not moduleList.env.GetOption('clean'))

    if not os.path.isdir(TMP_BSC_DIR):
      os.mkdir(TMP_BSC_DIR)

    ##
    ## Cleaning?  There are a few somewhat unpredictable files generated by bsc
    ## depending on the source files.  Delete them here instead of parsing the
    ## source files and generating scons dependence rules.
    ##
    if env.GetOption('clean'):
      os.system('cd '+ MODULE_PATH + '/' + TMP_BSC_DIR + '; rm -f *.ba *.c *.h *.sched')


    ##
    ## Every generated .bo file also has a generated .bi and .log file.  This is
    ## how scons learns about them.
    ##
    def emitter_bo(target, source, env):
      target.append(str(target[0]).replace('.bo', '.bi'))
      return target, source

    def compile_bo_bsc_base(target):
      bdir = os.path.dirname(str(target[0]))
      lib_dirs = self.__bsc_bdir_prune(env, MODULE_PATH + ':' + ALL_LIB_DIRS_FROM_ROOT, ':', bdir)
      return  BSC +" " +  self.BSC_FLAGS + ' -p +:' + \
           ROOT_DIR_HW_INC + ':' + ROOT_DIR_HW_INC + '/asim/provides:' + \
           lib_dirs + ':' + TMP_BSC_DIR + ' -bdir ' + bdir + \
           ' -vdir ' + bdir + ' -simdir ' + bdir + ' -info-dir ' + bdir

    def compile_bo(source, target, env, for_signature):
      cmd = compile_bo_bsc_base(target) + ' -D CONNECTION_SIZES_KNOWN ' + str(source[0])
      return cmd

    ## Builder for running the compiler and generating a log file with the
    ## compiler's messages.  These messages are used to note dangling
    ## connections and to generate the global string table.
    ## Kill compilation as soon as all the log data is generated, since
    ## no binary is needed.
    def compile_log_only(source, target, env, for_signature):
      cmd = compile_bo_bsc_base(target) + ' -KILLexpanded ' + str(source[0]) + \
            ' 2>&1 | tee ' + str(target[0]) + ' ; test $${PIPESTATUS[0]} -eq 0'
      return cmd

    ## Builder for generating a binary and a log file.
    def compile_bo_log(source, target, env, for_signature):
      cmd = compile_bo_bsc_base([target[0]]) + ' -D CONNECTION_SIZES_KNOWN ' + str(source[0]) + \
            ' 2>&1 | tee ' + str(target[1]) + ' ; test $${PIPESTATUS[0]} -eq 0'
      return cmd

    bsc = moduleList.env.Builder(generator = compile_bo, suffix = '.bo', src_suffix = '.bsv',
                                 emitter = emitter_bo)

    bsc_log = moduleList.env.Builder(generator = compile_bo_log, suffix = '.bo', src_suffix = '.bsv',
                                     emitter = emitter_bo)


    # This guy has to depend on children existing?
    # and requires a bash shell
    moduleList.env['SHELL'] = 'bash' # coerce commands to be spanwed under bash
    bsc_log_only = moduleList.env.Builder(generator = compile_log_only, suffix = '.log', src_suffix = '.bsv')
    
    env.Append(BUILDERS = {'BSC' : bsc, 'BSC_LOG' : bsc_log, 'BSC_LOG_ONLY' : bsc_log_only})


    moduleList.env.BuildDir(MODULE_PATH + '/' + TMP_BSC_DIR, '.', duplicate=0)

    bsc_builds = []
    for bsv in BSVS + GEN_BSVS:
      bsc_builds += env.BSC(MODULE_PATH + '/' + TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''), MODULE_PATH + '/' + bsv)

    for bsv in  [get_wrapper(module)]:
      ##
      ## First pass just generates a log file to figure out cross synthesis
      ## boundary soft connection array sizes.
      ##
      ## All but the top level build need the log build pass to compute
      ## the size of the external soft connection vector.  The top level has
      ## no exposed connections and can generate the log file, needed
      ## for global strings, during the final build.
      ##
      logfile = MODULE_PATH + '/' + TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.log')
      module.moduleDependency['BSV_LOG'] += [logfile]
      if (module.name != moduleList.topModule.name):
        log = env.BSC_LOG_ONLY(logfile, MODULE_PATH + '/' + bsv.replace('Wrapper.bsv', 'Log'))

        ##
        ## Parse the log, generate a stub file
        ##
        stub_name = bsv.replace('.bsv', '_con_size.bsh')
        stub = env.Command(MODULE_PATH + '/' + stub_name, log, 'leap-connect --softservice --dynsize $SOURCE $TARGET')

      ##
      ## Now we are ready for the real build
      ##
      if (module.name != moduleList.topModule.name):
        wrapper_bo = env.BSC(MODULE_PATH + '/' + TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''), MODULE_PATH + '/' + bsv)
        moduleList.env.Depends(wrapper_bo, stub)
      else:
        ## Top level build can generate the log in a single pass since no
        ## connections are exposed.
        wrapper_bo = env.BSC_LOG([MODULE_PATH + '/' + TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''),
                                  logfile],
                                 MODULE_PATH + '/' + bsv)

      ##
      ## All but the top level build need the log build pass to compute
      ## the size of the external soft connection vector.  The top level has
      ## no exposed connections and needs no log build pass.
      ##
      if (module.name != moduleList.topModule.name):
        if (getBuildPipelineDebug(moduleList) != 0):
          print 'wrapper_bo: ' + str(wrapper_bo)
          print 'stub: ' + str(stub)

        synth_stub_path = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/'
        synth_stub = synth_stub_path + module.name +'.bsv'
        c = env.Command(synth_stub, # target
                        [stub, wrapper_bo],
                        ['leap-connect --alternative_logfile ' + logfile  + ' --softservice ' + APM_FILE + ' $TARGET'])


      ##
      ## The mk_<wrapper>.v file is really built by the Wrapper() builder
      ## above.  We use NULL commands to convince SCons the file is generated.
      ## This seems easier than SCons SideEffect() calls, which don't clean
      ## targets.
      ##
      ## We also generate all this synth boundary's GEN_VS
      ##
      gen_v = moduleList.getSynthBoundaryDependencies(module, 'GEN_VS')
      ext_gen_v = []
      for v in gen_v:
        ext_gen_v += [MODULE_PATH + '/' + TMP_BSC_DIR + '/' + v]

      bld_v = env.Command([MODULE_PATH + '/' + TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.v')] + ext_gen_v,
                          MODULE_PATH + '/' + TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.bo'),
                          '')
      env.Precious(bld_v)


      if (moduleList.getAWBParam('bsv_tool', 'BUILD_VERILOG') == 1):
        module.moduleDependency['VERILOG'] += [bld_v] + [ext_gen_v]

      if(getBuildPipelineDebug(moduleList) != 0):
        print "Name: " + module.name

      # each synth boundary will produce a ba
      bld_ba = [env.Command([MODULE_PATH + '/' + TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.ba')],
                            MODULE_PATH + '/' + TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.bo'),
                            '')]
      
      ##
      ## We also generate all this synth boundary's GEN_BAS. This is a
      ## little different because we must dependent on awb module bo rather
      ## than the synth boundary bo
      ##
      descendents = moduleList.getSynthBoundaryDescendents(module)
      for descendent in descendents:
        if(getBuildPipelineDebug(moduleList) != 0):
          print "BA: working on " + descendent.name

        gen_ba = moduleList.getDependencies(descendent, 'GEN_BAS')

        # Dress them with the correct directory. Really the ba's depend on
        # their specific bo.
        ext_gen_ba = []
        for ba in gen_ba:
          if(getBuildPipelineDebug(moduleList) != 0):
            print "BA: " + descendent.name + " generates " + MODULE_PATH + '/' + TMP_BSC_DIR + '/' + ba
          ext_gen_ba += [MODULE_PATH + '/' + TMP_BSC_DIR + '/' + ba]    
          
        ##
        ## Do the same for .ba
        ##
        bld_ba += [env.Command(ext_gen_ba,
                               MODULE_PATH + '/' + TMP_BSC_DIR + '/' + descendent.name + '.bo',
                               '')]


      module.moduleDependency['BA'] += bld_ba 
      env.Precious(bld_ba)

      ##
      ## Build the Xst black-box stub.
      ##
      bb = env.Command(MODULE_PATH + '/' + TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '_stub.v'),
                       bld_v + bld_ba,
                       'leap-gen-black-box -nohash $SOURCE > $TARGET')

      # because I'm not sure that we guarantee the wrappers can only be imported
      # by parents, 
      moduleList.topModule.moduleDependency['VERILOG_STUB'] += [bb]

      return [bb]



  ##
  ## As of Bluespec 2008.11.C the -bdir target is put at the head of the search path
  ## and the compiler complains about duplicate path entries.
  ##
  ## This code removes the local build target from the search path.
  ##
  def __bsc_bdir_prune(self, env, str, sep, match):
    t = clean_split(str, sep)

    # Make the list unique to avoid Bluespec complaints about duplicate paths.
    seen = set()
    t = [e for e in t if e not in seen and not seen.add(e)]

    if (getBluespecVersion() >= 15480):
      try:
        while 1:
          i = t.index(match)
          del t[i]
      except ValueError:
        pass
    return string.join(t, sep)


  ##
  ## gen_global_string_table --
  ##   Used as a build rule to parse Bluespec log files, looking for messages
  ##   emitted by the compiler defining global strings.
  ##
  def gen_global_string_table(self, target, source, env):
    str_file = open(str(target[0]), 'w')

    for src in source:
      log_file = open(str(src), 'r')

      ##
      ## Global strings begin with the tag "GlobStr:" and end with the tag
      ## "X!gLb!X".  The end tag permits strings to have newlines.
      ##
      multi_line = False
      for full_line in log_file:
        if not multi_line:
          # Look for the start of a new string
          if (re.search(r'GlobStr', full_line)):
            line = re.sub(r'.* GlobStr: ', '', full_line)
            
            # Single line string?
            if (re.search(r'X!gLb!X$', line.rstrip())):
              line = line.rstrip() + '\n'
            else:
              multi_line = True

            str_file.write(line);

        else:
          # Continuation of a multi-line string
          line = full_line
          if (re.search(r'X!gLb!X$', line.rstrip())):
            line = line.rstrip() + '\n'
            multi_line = False
          str_file.write(line);

      log_file.close()

    str_file.close()
