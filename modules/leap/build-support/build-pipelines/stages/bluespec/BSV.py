import os
import sys
import re
import string
import SCons.Script
from model import  *
from config import *

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

    self.BSC_FLAGS = BSC_FLAGS  + bsc_events_flag
   
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
    SUBDIRS = ''
    for child in surrogate_children:
      # Make sure module doesn't self-depend
      if(child.name != module.name):
        SUBDIRS += child.name + ' ' 

    SURROGATE_BSVS = transform_string_list(SUBDIRS, None, MODULE_PATH + '/', '.bsv')
    if (SURROGATE_BSVS != ''):
      DERIVED = ' -derived "' + SURROGATE_BSVS + '"'
    else:
      DERIVED = ''

    depends_bsv = MODULE_PATH + '/.depends-bsv'
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


    ## Builder for running just the compiler front end on a wrapper to find
    ## the dangling connections.  This will then be passed to leap-connect
    ## to determine the required connection array sizes.
    def compile_bsc_log(source, target, env, for_signature):
      ## Note -- we pipe through sed during the build to get rid of an extra
      ##         newline emitted by bsc's printType().  New compilers will make
      ##         this unnecessary
      cmd = compile_bo_bsc_base(target) + ' -KILLexpanded ' + str(source[0]) + \
            ' 2>&1 | sed \':S;/{[^}]*$/{N;bS};s/\\n/\\\\n/g\' | tee ' + str(target[0]) + ' ; test $${PIPESTATUS[0]} -eq 0'
      return cmd

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

    def compile_rm_bo(source, target, env, for_signature):
      cmd = 'rm -f ' + str(target[0]) + ' ; ' + compile_bo_bsc_base(target) + ' -D CONNECTION_SIZES_KNOWN ' + str(source[0])
      return cmd


    bsc = moduleList.env.Builder(generator = compile_bo, suffix = '.bo', src_suffix = '.bsv',
                                 emitter = emitter_bo)


    # This guy has to depend on children existing?
    # and requires a bash shell
    moduleList.env['SHELL'] = 'bash' # coerce commands to be spanwed under bash
    bsc_log = moduleList.env.Builder(generator = compile_bsc_log, suffix = '.log', src_suffix = '.bsv')
    

    # SUBD method for building generated .bsv file.  Can't use automatic
    # suffix detection since source must be named explicitly.
    bsc_subd = moduleList.env.Builder(generator = compile_bo, emitter = emitter_bo)

    env.Append(BUILDERS = {'BSC' : bsc, 'BSC_LOG' : bsc_log, 'BSC_SUBD' : bsc_subd})


    moduleList.env.BuildDir(MODULE_PATH + '/' + TMP_BSC_DIR, '.', duplicate=0)

    bsc_builds = []
    for bsv in BSVS + GEN_BSVS:
      bsc_builds += env.BSC(MODULE_PATH + '/' + TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''), MODULE_PATH + '/' + bsv)

    for bsv in  [get_wrapper(module)]:
      ##
      ## First pass just generates a log file to figure out cross synthesis
      ## boundary soft connection array sizes.
      ##
      logfile = MODULE_PATH + '/' + TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.log')     

      log = env.BSC_LOG(MODULE_PATH + '/' + TMP_BSC_DIR + '/' + bsv.replace('bsv', 'log'),
                        MODULE_PATH + '/' + bsv.replace('Wrapper.bsv', 'Log'))

      ##
      ## Parse the log, generate a stub file
      ##
      stub_name = bsv.replace('.bsv', '_con_size.bsh')
      stub = env.Command(MODULE_PATH + '/' + stub_name, log, 'leap-connect --softservice --dynsize $SOURCE $TARGET')

      ##
      ## Now we are ready for the real build
      ##
      wrapper_bo = env.BSC(MODULE_PATH + '/' + TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''), MODULE_PATH + '/' + bsv)

      if(getBuildPipelineDebug(moduleList) != 0):
        print 'wrapper_bo: ' + str(wrapper_bo)
        print 'stub: ' + str(stub)
      moduleList.env.Depends(wrapper_bo, stub)

      # now we should call leap-connect soft-services again
      # unfortunately leap-connect wants this file to reside in our 
      if(module.name != moduleList.topModule.name):
        synth_stub_path = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/'
        synth_stub = synth_stub_path + module.name +'.bsv'
        c = env.Command(synth_stub, # target
                      [stub,wrapper_bo],  
                      [ 'mkdir -p ' + synth_stub_path,
                        'leap-connect --alternative_logfile ' + logfile  + ' --softservice ' + APM_FILE + ' $TARGET'])


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


      if(BUILD_VERILOG == 1):
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

      # Spam this file to all synthesis boundaries in case one of them wants it. 
      boundaries = moduleList.synthBoundaries() + [moduleList.topModule]
      for boundary in boundaries:
        # Make sure module doesn't self-depend
        boundarydir  = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + boundary.buildPath +'/'
        boundarycopy = boundarydir +  module.name + '.bsv'
        
        if(module.name != boundary.name  and module.name != moduleList.topModule.name): 
          if(getBuildPipelineDebug(moduleList) != 0):
            print  " module: " + module.name + " boundary: " + boundary.name
            print "command: cp " + str(synth_stub) + " " + boundarycopy
          BOUNDARY_PATH =  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + boundary.buildPath + '/' 
          copy_bo = BOUNDARY_PATH + TMP_BSC_DIR + '/' + module.name + '.bo'
          c_boundary = env.Command(boundarycopy,
                                   [synth_stub,bld_ba,stub,wrapper_bo],
                                   ['mkdir -p '+ boundarydir,
                                    'cp ' + synth_stub + ' $TARGET'])

          bo_dep = env.BSC_SUBD(copy_bo, boundarycopy)
          
          # If you need the child bo, then you will need its verilog also. 
          if(getBuildPipelineDebug(moduleList) != 0):
            print "bo_dep is: " + str(bo_dep)

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
