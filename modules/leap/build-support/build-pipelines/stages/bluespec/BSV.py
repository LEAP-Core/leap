import os
import sys
import re
import string
import cPickle as pickle
import SCons.Script
from model import  *
from li_module import *
import pygraph
try:
    from pygraph.classes.digraph import digraph
except ImportError:
    # don't need to do anything
    print "\n"
    # print "Warning you should upgrade to pygraph 1.8"


#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path
# This is going to recursively build all the bsvs
class BSV():

    def __init__(self, moduleList):
        # some definitions used during the bsv compilation process
        env = moduleList.env
        self.moduleList = moduleList
        self.TMP_BSC_DIR = env['DEFS']['TMP_BSC_DIR']

        self.ALL_DIRS_FROM_ROOT = env['DEFS']['ALL_HW_DIRS']
        self.ALL_BUILD_DIRS_FROM_ROOT = transform_string_list(self.ALL_DIRS_FROM_ROOT, ':', '', '/' + self.TMP_BSC_DIR)
        self.ALL_LIB_DIRS_FROM_ROOT = self.ALL_DIRS_FROM_ROOT + ':' + self.ALL_BUILD_DIRS_FROM_ROOT

        self.ROOT_DIR_HW_INC = env['DEFS']['ROOT_DIR_HW_INC']
        self.TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']

        self.pipeline_debug = getBuildPipelineDebug(moduleList)

        # Should we be building in events? 
        if (getEvents(moduleList) == 0):
            bsc_events_flag = ' -D HASIM_EVENTS_ENABLED=False '
        else:
            bsc_events_flag = ' -D HASIM_EVENTS_ENABLED=True '

        self.BSC_FLAGS = moduleList.getAWBParam('bsv_tool', 'BSC_FLAGS') + bsc_events_flag

        moduleList.env.VariantDir(self.TMP_BSC_DIR, '.', duplicate=0)
        moduleList.env['ENV']['BUILD_DIR'] = moduleList.env['DEFS']['BUILD_DIR']  # need to set the builddir for synplify

        # Walk synthesis boundaries in reverse topological order
        topo = moduleList.topologicalOrderSynth()
        topo.reverse()
        topo.pop() # get rid of top module. 
     
        ##
        ## Is this a normal build or a build in which only Bluespec dependence
        ## is computed?
        ##

        if not moduleList.isDependsBuild:
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
                # Convert command line ARGUMENTS dictionary to a string
                args = ' '.join(['%s="%s"' % (k, v) for (k, v) in moduleList.arguments.items()])
                print 'Building depends-init ' + args + '...'
                s = os.system('scons depends-init ' + args)
                if (s & 0xffff) != 0:
                    print 'Aborting due to dependence errors'
                    sys.exit(1)

            ##
            ## Now that the "depends-init" build is complete we can continue with
            ## accurate inter-Bluespec file dependence.
            ##
            for module in topo:
                self.build_synth_boundary(moduleList, module)
         
            ## We are going to have a whole bunch of BA and V files coming.
            ## We don't yet know what they contain, but we do know that there
            ## will be |synth_modules| - 2 of them

            if (not 'GEN_VERILOGS' in moduleList.topModule.moduleDependency):
                moduleList.topModule.moduleDependency['GEN_VERILOGS'] = []
            if (not 'GEN_BAS' in moduleList.topModule.moduleDependency):
                moduleList.topModule.moduleDependency['GEN_BAS'] = []

            ## Having described the new build tree dependencies we can build
            ## the top module.
            self.build_synth_boundary(moduleList, moduleList.topModule)


            # If we're doing a LIM compilation, we need to dump an LIM Graph. 
            # This must be done before the build tree attempts to reorganize the world.
            do_dump_lim_graph = moduleList.getAWBParam('bsv_tool', 'BUILD_LOGS_ONLY')
            if do_dump_lim_graph:
                all_logs = []
                for module in  moduleList.topologicalOrderSynth():
                    # scrub tree build, which is introduced above us...
                    if (module.name != 'build_tree'):
                        all_logs.extend(module.moduleDependency['BSV_LOG'])

                li_graph = moduleList.env['DEFS']['APM_NAME'] + '.li'

                ## dump a LIM graph for use by the LIM compiler.  here
                ## we wastefully contstruct (or reconstruct, depending on your
                ## perspective, a LIM graph including the platform channels.
                ## Probably this result could be acheived with the mergeGraphs
                ## function.
                def dump_lim_graph(target, source, env):
            
                    connections = []
                    # filter out build_tree connections.  These are not real
                    
                    for connection in parseLogfiles(all_logs):
                        if (connection.module_name != 'build_tree'):
                            connections.append(connection)
                    
                    fullLIGraph = LIGraph(connections) 


                    # annotate modules with relevant object code (useful in
                    # LIM compilation)
                    # this is not technically a part of the tree cut methodology, but we need to do this             

                    # For the LIM compiler, we must also annotate those
                    # channels which are coming out of the platform code.

                    for module in topo + [moduleList.topModule]:
                        modulePath = module.buildPath

                        # Add references to object code to graph module
                        def addBuildPath(fileName):
                            if(not os.path.isabs(fileName)): 
                                return modulePath + '/' + fileName
                            else:
                                return fileName

                        # the liGraph only knows about modules that actually
                        # have connections some modules are vestigial, andso
                        # we can forget about them...
                        if (module.name in fullLIGraph.modules):
                            for objectType in module.moduleDependency:
                                # it appears that we need to filter
                                # these objects.  TODO: Clean the
                                # things adding to this list so we
                                # don't require the filtering step.
                                depList = module.moduleDependency[objectType]
                                
                                convertedDeps = convertDependencies(depList)
                                relativeDeps = map(addBuildPath,convertedDeps)
                                fullLIGraph.modules[module.name].putObjectCode(objectType, relativeDeps)
                             
                    # dump graph representation. 
                    pickleHandle = open(li_graph, 'wb')
                    pickle.dump(fullLIGraph, pickleHandle, protocol=-1)
                    pickleHandle.close()

                    if (self.pipeline_debug != 0):
                        print "Initial Graph is: " + str(fullLIGraph) + ": " + sys.version +"\n"

                # Setup the graph dump
                dumpGraph = env.Command(li_graph,
                                        all_logs,
                                        dump_lim_graph)
                moduleList.topDependency += [dumpGraph]





            ## Merge all synthesis boundaries using a tree?  The tree reduces
            ## the number of connections merged in a single compilation, allowing
            ## us to support larger systems.
            use_tree_build = moduleList.getAWBParam('wrapper_gen_tool', 'USE_BUILD_TREE')
            if use_tree_build:
                moduleList.moduleList += self.setup_tree_build(moduleList, topo)
        
            ##
            ## Generate the global string table.  Bluespec-generated global
            ## strings are stored in files by the compiler.
            ##
            ## The global string file will be generated in the top-level
            ## .bsc directory and a link to it will be added to the
            ## top-level directory.
            ##
            all_str_src = []
            for module in topo + [moduleList.topModule]:
                all_str_src.extend(module.moduleDependency['STR'])
            bsc_str = moduleList.env.Command(self.TMP_BSC_DIR + '/' + moduleList.env['DEFS']['APM_NAME'] + '.str',
                                             all_str_src,
                                             [ 'cat $SOURCES > $TARGET'])
            strDep = moduleList.env.Command(moduleList.env['DEFS']['APM_NAME'] + '.str',
                                            bsc_str,
                                            [ 'ln -fs ' + self.TMP_BSC_DIR + '/$TARGET $TARGET' ])
            moduleList.topDependency += [strDep]


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
            for module in topo + [moduleList.topModule]:
                deps += self.compute_dependence(moduleList, module)

            moduleList.env.Alias('depends-init', deps)


    ##
    ## compute_dependence --
    ##   Build rules for computing intra-Bluespec file dependence.
    ##
    def compute_dependence(self, moduleList, module):
        MODULE_PATH =  get_build_path(moduleList, module) 

        targets = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/' + get_wrapper(module) ]
        if (module.name != moduleList.topModule.name):
            targets.append(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/'+ get_log(module))

        # We must depend on all sythesis boundaries. They can be instantiated anywhere.
        surrogate_children = moduleList.synthBoundaries()
        SURROGATE_BSVS = ''
        for child in surrogate_children:
            # Make sure module doesn't self-depend
            if (child.name != module.name):
                SURROGATE_BSVS += moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + child.buildPath +'/' + child.name + '.bsv '

        if (SURROGATE_BSVS != ''):
            DERIVED = ' -derived "' + SURROGATE_BSVS + '"'
        else:
            DERIVED = ''

        depends_bsv = MODULE_PATH + '/.depends-bsv'
        moduleList.env.NoCache(depends_bsv)
        compile_deps = 'leap-bsc-mkdepend -ignore ' + MODULE_PATH + '/.ignore' + ' -bdir ' + self.TMP_BSC_DIR + DERIVED + ' -p +:' + self.ROOT_DIR_HW_INC + ':' + self.ROOT_DIR_HW_INC + '/awb/provides:' + self.ALL_LIB_DIRS_FROM_ROOT + ' ' + ' '.join(targets) + ' > ' + depends_bsv

        # Delete depends_bsv if it is empty under the assumption that something
        # went wrong when creating it.  An empty dependence file would never be
        # rebuilt without this.
        try:
            if (os.path.getsize(depends_bsv) == 0):
                os.unlink(depends_bsv)
        except:
            None

        dep = moduleList.env.Command(depends_bsv,
                                     targets +
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
        if (self.pipeline_debug != 0):
            print "Working on " + module.name
        MODULE_PATH =  get_build_path(moduleList, module) 
        env = moduleList.env
        BSVS = moduleList.getSynthBoundaryDependencies(module, 'GIVEN_BSVS')
        # each submodel will have a generated BSV
        GEN_BSVS = moduleList.getSynthBoundaryDependencies(module, 'GEN_BSVS')
        APM_FILE = moduleList.env['DEFS']['APM_FILE']
        BSC = moduleList.env['DEFS']['BSC']

        ##
        ## Load intra-Bluespec dependence already computed.  This information will
        ## ultimately drive the building of Bluespec modules.
        ##
        env.ParseDepends(MODULE_PATH + '/.depends-bsv',
                         must_exist = not moduleList.env.GetOption('clean'))

        if not os.path.isdir(self.TMP_BSC_DIR):
            os.mkdir(self.TMP_BSC_DIR)

        ##
        ## Cleaning?  There are a few somewhat unpredictable files generated by bsc
        ## depending on the source files.  Delete them here instead of parsing the
        ## source files and generating scons dependence rules.
        ##
        if env.GetOption('clean'):
            os.system('cd '+ MODULE_PATH + '/' + self.TMP_BSC_DIR + '; rm -f *.ba *.c *.h *.sched')

        self.setup_module_build(moduleList, MODULE_PATH)

        moduleList.env.VariantDir(MODULE_PATH + '/' + self.TMP_BSC_DIR, '.', duplicate=0)

        bsc_builds = []
        for bsv in BSVS + GEN_BSVS:
            bsc_builds += env.BSC(MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''), MODULE_PATH + '/' + bsv)

        # This should not be a for loop.
        for bsv in [get_wrapper(module)]:
            ##
            ## First pass just generates a log file to figure out cross synthesis
            ## boundary soft connection array sizes.
            ##
            ## All but the top level build need the log build pass to compute
            ## the size of the external soft connection vector.  The top level has
            ## no exposed connections and can generate the log file, needed
            ## for global strings, during the final build.
            ##
            logfile = get_logfile(moduleList, module)
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
                wrapper_bo = env.BSC(MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''), MODULE_PATH + '/' + bsv)
                moduleList.env.Depends(wrapper_bo, stub)
                module.moduleDependency['BO'] = [wrapper_bo]
            else:
                ## Top level build can generate the log in a single pass since no
                ## connections are exposed
                wrapper_bo = env.BSC_LOG(MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''),
                                         MODULE_PATH + '/' + bsv)
                ## SCons doesn't deal well with logfile as a 2nd target to BSC_LOG rule,
                ## failing to derive dependence correctly.
                module.moduleDependency['BSV_BO'] = [wrapper_bo]
                env.Command(logfile, wrapper_bo, '')
                env.Precious(logfile)

                ## In case Bluespec build is the end of the build pipeline.
                moduleList.topDependency += [logfile]
                
                ## The toplevel bo also depends on the on the synthesis of the build tree from log files.

            ##
            ## Meta-data written during compilation to separate files.
            ##
            glob_str = env.Command(MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.str'),
                                   wrapper_bo,
                                   '')
            env.Precious(glob_str)
            module.moduleDependency['STR'] += [glob_str]

            ## All but the top level build need the log build pass to compute
            ## the size of the external soft connection vector.  The top level has
            ## no exposed connections and needs no log build pass.
            ##
            if (module.name != moduleList.topModule.name):
                if (self.pipeline_debug != 0):
                    print 'wrapper_bo: ' + str(wrapper_bo)
                    print 'stub: ' + str(stub)

                synth_stub_path = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/'
                synth_stub = synth_stub_path + module.name +'_synth.bsv'
                env.Command(synth_stub, # target
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
            ext_gen_v = []
            for v in moduleList.getSynthBoundaryDependencies(module, 'GEN_VS'):
                ext_gen_v += [MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + v]

            ##
            ## Generated Verilog (indicated with %generated in an AWB file) will
            ## be created by the compilation of some Bluespec file.  We just don't
            ## know which one.  Claim that all generated Verilog files are produced
            ## by the module compilation, which is sufficient for SCons to compute
            ## dependence.
            ##
            for v in moduleList.getSynthBoundaryDependencies(module, 'GEN_VERILOGS'):
                ext_gen_v += [MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + v]

            # Add the dependence for all Verilog noted above
            bld_v = env.Command([MODULE_PATH + '/' + self.TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.v')] + ext_gen_v,
                                MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.bo'),
                                '')
            env.Precious(bld_v)

            if (moduleList.getAWBParam('bsv_tool', 'BUILD_VERILOG') == 1):
                module.moduleDependency['VERILOG'] += [bld_v] + [ext_gen_v]

            if (self.pipeline_debug != 0):
                print "Name: " + module.name

            # each synth boundary will produce a ba
            bld_ba = [env.Command([MODULE_PATH + '/' + self.TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.ba')],
                                  MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.bo'),
                                  '')]

            ##
            ## We also generate all this synth boundary's GEN_BAS. This is a
            ## little different because we must dependent on awb module bo rather
            ## than the synth boundary bo
            ##
            descendents = moduleList.getSynthBoundaryDescendents(module)
            for descendent in descendents:
                if (self.pipeline_debug != 0):
                    print "BA: working on " + descendent.name

                gen_ba = moduleList.getDependencies(descendent, 'GEN_BAS')

                # Dress them with the correct directory. Really the ba's depend on
                # their specific bo.
                ext_gen_ba = []
                for ba in gen_ba:
                    if (self.pipeline_debug != 0):
                        print "BA: " + descendent.name + " generates " + MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + ba
                    ext_gen_ba += [MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + ba]    
                
                ##
                ## Do the same for .ba
                ##
                bld_ba += [env.Command(ext_gen_ba,
                                       MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + descendent.name + '.bo',
                                       '')]

            module.moduleDependency['BA'] += bld_ba 
            env.Precious(bld_ba)

            ##
            ## Build the Xst black-box stub.
            ##
            bb = self.stubGenCommand(MODULE_PATH, bsv, bld_v)

            # Only the subordinate modules have stubs.
            if(module.name != moduleList.topModule.name):
                moduleList.topModule.moduleDependency['VERILOG_STUB'] += [bb]

            return [bb] #This doesn't seem to do anything. 


    ##
    ## As of Bluespec 2008.11.C the -bdir target is put at the head of the search path
    ## and the compiler complains about duplicate path entries.
    ##
    ## This code removes the local build target from the search path.
    ##
    def __bsc_bdir_prune(self, str_in, sep, match):
        t = clean_split(str_in, sep)

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


    ## Define generic builders. We eventually need to bind these to a
    ## context to build specific modules.

    ##
    ## Older versions of Bluespec generated a .bi along with every .bo.
    ## This is how scons learns about them.
    ##
    def emitter_bo(self):
        def emitter_bo_closure(target, source, env):
            if (getBluespecVersion() < 26572):
                target.append(str(target[0]).replace('.bo', '.bi'))
                return target, source
            return emitter_bo_closure


    def compile_bo_bsc_base(self, target, module_path):
        bdir = os.path.dirname(str(target[0]))
        lib_dirs = self.__bsc_bdir_prune(module_path + ':' + self.ALL_LIB_DIRS_FROM_ROOT, ':', bdir)
        return self.moduleList.env['DEFS']['BSC'] + " " +  self.BSC_FLAGS + ' -p +:' + \
               self.ROOT_DIR_HW_INC + ':' + self.ROOT_DIR_HW_INC + '/asim/provides:' + \
               lib_dirs + ':' + self.TMP_BSC_DIR + ' -bdir ' + bdir + \
               ' -vdir ' + bdir + ' -simdir ' + bdir + ' -info-dir ' + bdir + \
               ' -fdir ' + bdir
    

    def compile_bo(self, module_path):
        def compile_bo_closure(source, target, env, for_signature):  
            cmd = ''
            if (str(source[0]) != get_build_path(self.moduleList, self.moduleList.topModule) + '/' + self.moduleList.topModule.name + '.bsv'): 
                cmd = self.compile_bo_bsc_base(target, module_path) + ' -D CONNECTION_SIZES_KNOWN ' + str(source[0])
            return cmd
        return compile_bo_closure  


    ## Builder for running the compiler and generating a log file with the
    ## compiler's messages.  These messages are used to note dangling 
    ## connections and to generate the global string table.
    ## Kill compilation as soon as all the log data is generated, since
    ## no binary is needed.
    def compile_log_only(self, module_path):
        def compile_log_only_closure(source, target, env, for_signature):
            cmd = self.compile_bo_bsc_base(target, module_path) + ' -KILLexpanded ' + str(source[0]) + \
                  ' 2>&1 | tee ' + str(target[0]) + ' ; test $${PIPESTATUS[0]} -eq 0'
            return cmd 
        return compile_log_only_closure


    ## Builder for generating a binary and a log file.
    def compile_bo_log(self, module_path):
        def compile_bo_log_closure(source, target, env, for_signature):
            cmd = self.compile_bo_bsc_base(target, module_path) + ' -D CONNECTION_SIZES_KNOWN ' + str(source[0]) + \
                  ' 2>&1 | tee ' + str(target[0]).replace('.bo', '.log') + ' ; test $${PIPESTATUS[0]} -eq 0'
            return cmd
        return compile_bo_log_closure
  

    def stubGenCommand(self, module_path, bsv, deps):
        return self.moduleList.env.Command(module_path + '/' + self.TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '_stub.v'),
                                           deps,
                                           'leap-gen-black-box -nohash $SOURCE > $TARGET')
  

    ## This function binds the Builder objects for a given module and inserts them into the 
    ## SCons environment.  One wonders if inserting them into the environment is necessary.
    def setup_module_build(self, moduleList, module_path):
        ## create builders for this particular module.  To do this, we bind module_path local
        ## to this module
        bsc = moduleList.env.Builder(generator = self.compile_bo(module_path), suffix = '.bo', src_suffix = '.bsv',
                                     emitter = self.emitter_bo())

        bsc_log = moduleList.env.Builder(generator = self.compile_bo_log(module_path), suffix = '.bo', src_suffix = '.bsv',
                                         emitter = self.emitter_bo())

        # This guy has to depend on children existing?
        # and requires a bash shell
        moduleList.env['SHELL'] = 'bash' # coerce commands to be spanwed under bash
        bsc_log_only = moduleList.env.Builder(generator = self.compile_log_only(module_path), suffix = '.log', src_suffix = '.bsv')
    
        moduleList.env.Append(BUILDERS = {'BSC' : bsc, 'BSC_LOG' : bsc_log, 'BSC_LOG_ONLY' : bsc_log_only})


    ##
    ## setup_tree_build --
    ##   Merge exposed soft connections using a tree of synthesis boundaries
    ##   instead of merging them all at once.  This reduces Bluespec
    ##   scheduling pressure and allows us to build larger systems.
    ##
    def setup_tree_build(self, moduleList, topo):
        env = moduleList.env
        tree_file_synth = get_build_path(moduleList, moduleList.topModule) + "/build_tree_synth.bsv"
        tree_file_synth_bo_path = get_build_path(moduleList, moduleList.topModule) + "/" + self.TMP_BSC_DIR +"/build_tree_synth"
        tree_file_wrapper = get_build_path(moduleList, moduleList.topModule) + "/build_tree_Wrapper.bsv"
        tree_file_wrapper_bo_path = get_build_path(moduleList, moduleList.topModule) + "/" + self.TMP_BSC_DIR + "/build_tree_Wrapper"

        boundary_logs = []
        for module in topo:
            boundary_logs.extend(module.moduleDependency['BSV_LOG'])

        pipeline_debug = self.pipeline_debug


        ##
        ## cut_tree_build does the heavy lifting as a build-time method when
        ## invoked in the 2nd pass of SCons.
        ##
        def cut_tree_build(target, source, env):
            liGraph = LIGraph(parseLogfiles(boundary_logs))     
            
            
            synth_handle = open(tree_file_synth,'w')
            wrapper_handle = open(tree_file_wrapper,'w')
            for tree_file in [synth_handle, wrapper_handle]:
                tree_file.write("//Generated by BSV.py\n")
                tree_file.write("`ifndef BUILD_TREE\n") # these may not be needed
                tree_file.write("`define BUILD_TREE\n")
                tree_file.write('import Vector::*;\n')
                tree_file.write('`include "asim/provides/smart_synth_boundaries.bsh"\n')
                tree_file.write('`include "asim/provides/soft_connections.bsh"\n')

            
            # include all the dependencies in the graph in the wrapper. 
            for module in liGraph.graph.nodes():
                wrapper_handle.write('import ' + module.name + '_Wrapper::*;\n')        
 
            wrapper_handle.write('module mk_Empty_Wrapper (SOFT_SERVICES_SYNTHESIS_BOUNDARY#(0,0,0,0,0)); return ?; endmodule\n')
            if (pipeline_debug != 0):
                print "LIGraph: " + str(liGraph)

            # Top module has a special, well-known name for stub gen.
            # unless there is only one module in the graph. 
            module_names = [ "__TREE_MODULE__" + str(id) for id in range(len(boundary_logs) - 2)] + ["build_tree"]
     
            # A recursive function for partitioning a latency
            # insensitive graph into a a tree of modules so as to
            # minimize the number of rules in the modules of the
            # tree.  This construction reduces the complexity of the
            # design as seen by the bluespec compiler.  The code
            # could be reorganized as two passes: the construction
            # of the tree representation and the generation of the
            # tree code.  
            #
            # Input: LIGraph representing the user program 
            # 
            # Output: LIModule repesenting the tree produced
            # by the function.  This tree may have unmatched
            # channels.
            def cutRecurse(subgraph, topModule):
                # doesn't make sense to cut up a null or size-one LIM
                # trivially return the base LI module to the caller
                if (len(subgraph.graph.nodes()) < 2):
                    if (not topModule):
                        return subgraph.graph.nodes()[0]
                    else:                        
                        # If there are fewer than two modules in
                        # the program, we need to dump out a wrapper
                        # module so that the information we told SCons
                        # and downstream tools during the graph
                        # assembly phase will be true. To create a
                        # wrapper, we need to figure out the type of
                        # the singleton by examining its channels.

                        # if we have no modules, we still need something.
                        single_module = LIModule("Empty", "Empty") 
                        if(len(subgraph.graph.nodes()) > 0):
                            single_module = subgraph.graph.nodes()[0]

                        wrapper_handle.write("\n\n(*synthesize*)\n") 
                        localModule = module_names.pop()

                        outgoing = 0
                        incoming = 0 
                        for channel in single_module.channels:
                            if (channel.isSource()):
                                outgoing = outgoing + 1    
                            else:
                                incoming = incoming + 1

                        wrapper_handle.write("module mk_" + localModule + "_Wrapper")
                        moduleType = "SOFT_SERVICES_SYNTHESIS_BOUNDARY#(" + str(incoming) +\
                             ", " + str(outgoing) + ", 0, 0, " + str(len(single_module.chains)) + ")"
                        wrapper_handle.write(" (" + moduleType +");\n")
                        wrapper_handle.write("    let m <- mk_" + single_module.name + "_Wrapper();\n")
                        wrapper_handle.write("    return m;\n")
                        wrapper_handle.write("endmodule\n")
                        single_module.name = localModule # sort of a hack, but it does save space
                        return single_module

                # do a min cut on the graph
                map = min_cut(subgraph.graph)

                if (pipeline_debug != 0):
                    print "Cut map: " + str(map)
                
                ## Now that we've got a cut, Build new li graphs from the sub components of
                ## original graph However, we must be careful
                ## because some modules may not have internal
                ## channels, only external channels.  Thus for each
                ## module we add an optional, dummy edge to ensure
                ## that the partitioned graphs are constructed
                ## correctly

                graph0Connections = []
                graph1Connections = []

                for connection in subgraph.getChannels() + subgraph.getChains():
                    connectionSet = graph0Connections
                    if (map[connection.module] == 1):
                        connectionSet = graph1Connections
                    connectionSet += [connection.copy()]
                  
                graph0 = LIGraph(graph0Connections)        
                graph1 = LIGraph(graph1Connections)        

                #Pick a name for the local module
                localModule = module_names.pop()

                num_child_exported_rules = 0

                # in order to build an LI module for this node in the tree,
                # we need to have the code for the subtrees 
                # below the current node.  And so we recurse.  If only one 
                # module remains in the cut graph, there is no need to recurse
                # and we just use that module. 
                submodule0 = graph0.modules.values()[0]
                if (len(graph0.modules) > 1):
                    submodule0 = cutRecurse(graph0, 0)
                    num_child_exported_rules += submodule0.numExportedRules

                submodule1 = graph1.modules.values()[0] 
                if (len(graph1.modules) > 1):
                    submodule1 = cutRecurse(graph1, 0)
                    num_child_exported_rules += submodule1.numExportedRules

                # we need to build a representation of the new liModule we are about to construct.
                treeModule = LIModule("FixMe", localModule)
                
                # In order to generate the module, we need a type, 
                # but we can only get it after analyzing the module pair
                # Thus we store the module body code for later consumption                  
                module_body = ""

                # Instantiate the submodules.
                for name in [submodule0.name, submodule1.name]:
                    module_body += "    let " + name + "_inst <- mk_" +\
                                   name + "_Wrapper();\n"                
                    module_body += "    let " + name + " = tpl_1(" +\
                                   name + "_inst.services);\n"


                # At this node in the tree, we can match channels from our two children.  
                # This matching is what reduces the bluespec compiler complexity, since matched
                # channels do not need to be propagated upward.

                matched = {} # Use a hash to detect matching

                # handle matching channels 
                for channel in submodule0.channels:                     
                    for partnerChannel in submodule1.channels:
                        if (channel.matches(partnerChannel)):
                            if (pipeline_debug != 0):
                                print "Found match with " + str(partnerChannel)
                            matched[channel.name] = channel
                        
                            if (channel.isSource()):
                                module_body += "    connectOutToIn(" + channel.module_name + ".outgoing[" + str(channel.module_idx) + "], " +\
                                    partnerChannel.module_name + ".incoming[" + str(partnerChannel.module_idx) + "]);// " + channel.name + "\n"
                            else:                                 
                                module_body += "    connectOutToIn(" + partnerChannel.module_name + ".outgoing[" + str(partnerChannel.module_idx) + "], " +\
                                    channel.module_name + ".incoming[" + str(channel.module_idx) + "]);// " + channel.name + "\n"                          
                                    
                #handle matching chains
                for chain in submodule0.chains:                    
                    for partnerChain in submodule1.chains:
                        if (chain.matches(partnerChain)):
                            if (pipeline_debug != 0):
                                print "Found match with " + str(partnerChain)
                            matched[chain.name] = chain
                            chain.sinkPartnerChain = partnerChain
                            chain.sourcePartnerChain = chain
                            module_body += "    connectOutToIn(" + chain.module_name + ".chains[" + str(chain.module_idx) + "].outgoing, " +\
                                partnerChain.module_name + ".chains[" + str(partnerChain.module_idx) + "].incoming);// " + chain.name + "\n"


                # Stick the remaining connections of child modules
                # into the interface of this new module.  Include
                # any chains.  we need to check chains for a match
                # so that we get the routing right.  if matched,
                # ingress will be module0 and egress will be module1

                incoming = 0
                outgoing = 0
                chains = 0
 
                # We need to propagate any remaining unmatched channels and chains up the tree,
                # To do this we populate the LI module representing this node with the unmatched 
                # channels of the child node. 
                if (pipeline_debug != 0):
                    for channel in submodule0.channels:
                        print "Channel in " + submodule0.name + " " + str(channel)
                    for channel in submodule1.channels:
                        print "Channel in " + submodule1.name + " " + str(channel)

                for channel in submodule0.channels + submodule1.channels:
                    channelCopy = channel.copy()
                   
                    if (not channel.name in matched):
                        if (channel.isSource()):
                            module_body += "    outgoingVec[" + str(outgoing) +"] = " + channel.module_name +\
                                           ".outgoing[" + str(channel.module_idx) + "];// " + channel.name + "\n"     
                            channelCopy.module_idx = outgoing
                            outgoing = outgoing + 1
                        else:
                            module_body += "    incomingVec[" + str(incoming) +"] = " + channel.module_name +\
                                           ".incoming[" + str(channel.module_idx) + "];// " + channel.name + "\n"     
                            channelCopy.module_idx =  incoming
                            incoming = incoming + 1

                        # override the module_name with the local
                        # module so that our parent will refer to us
                        # correctly
                        channelCopy.module_name = localModule
                        treeModule.addChannel(channelCopy) 

                # Chains are always propagated up, but they can also
                # be matched. In this case, we must use a portion of
                # each child module's chain.

                for chain in submodule0.chains + submodule1.chains:                      
                    chainCopy = chain.copy()                        
                    if (not (chain.name in matched)):
                        # need to add both incoming and outgoing
                        module_body += "    chainsVec[" + str(chains) +"] = PHYSICAL_CHAIN{incoming: " +\
                                       chain.module_name + ".chains[" + str(chain.module_idx) +\
                                       "].incoming, outgoing: " + chain.module_name + ".chains[" +\
                                       str(chain.module_idx) + "].outgoing};// " + chain.name + "\n"     
                        chainCopy.module_idx =  chains
                        chainCopy.module_name = localModule
                        treeModule.addChain(chainCopy)
                        chains = chains + 1
                                
                    else:   
                        # we see matched chains twice, but we should
                        # only emit code once.
                        if ((chain.module_name == submodule1.name)):
                            # need to get form a chain based on the
                            # combination of the two modules
                            chain0 = matched[chain.name]
                            module_body += "    chainsVec[" + str(chains) +"] = PHYSICAL_CHAIN{incoming: " +\
                                           chain0.module_name + ".chains[" + str(chain0.module_idx) +\
                                           "].incoming, outgoing: " + chain.module_name+ ".chains[" +\
                                           str(chain.module_idx) + "].outgoing};// " + chain.name + "\n"     
                            chainCopy.module_idx =  chains
                            chainCopy.module_name = localModule                              
                            treeModule.addChain(chainCopy) 
                            chains = chains + 1        

                ##
                ## Should this module be a synthesis boundary?  We could just
                ## make all the modules boundaries, but the Bluespec compiler
                ## is quite slow for boundaries.  Only generate a true
                ## synthesis boundary when the number of rules grows large
                ## enough to slow down the Bluespec scheduler.
                ##

                # Always generate a boundary for top level
                gen_synth_boundary = topModule

                # Threshold for Bluespec scheduler
                total_rules = len(treeModule.channels) + num_child_exported_rules
                if (total_rules > 250):
                    gen_synth_boundary = True
                    treeModule.setNumExportedRules(0)
                else:
                    treeModule.setNumExportedRules(total_rules)

                ##
                ## Now we can write out our modules.
                ##
                if (gen_synth_boundary):
                    wrapper_handle.write("\n\n(*synthesize*)") 

                wrapper_handle.write("\nmodule ")
                if (not gen_synth_boundary):
                    wrapper_handle.write("[Module] ")
                wrapper_handle.write("mk_" + localModule + "_Wrapper")
                moduleType = "SOFT_SERVICES_SYNTHESIS_BOUNDARY#(" + str(incoming) +\
                             ", " + str(outgoing) + ", 0, 0, " + str(chains) + ")"

                subinterfaceType = "WITH_CONNECTIONS#(" + str(incoming) + ", " +\
                                   str(outgoing) + ", 0, 0, " + str(chains) + ")"
                wrapper_handle.write(" (" + moduleType +")")
                if (gen_synth_boundary):
                    wrapper_handle.write(";\n")
                else:
                    wrapper_handle.write("\n")
                    wrapper_handle.write("    provisos (IsModule#(Module, Id__));\n\n")
                 
                    ##
                    ## Here is a hack:  we didn't know on the SCons first pass
                    ## whether a synthesis boundary would be generated for this
                    ## module.  Hence we had to assume that one might be and
                    ## dependence was added on the generated Verilog.  Now
                    ## that we know there is none, generate a dummy Verilog
                    ## file.
                    ##
                    v_path = "mk_" + localModule + "_Wrapper.v"
                    wrapper_handle.write("    // Hack to generate Verilog file to simulate the possible synthesis boundary\n")
                    wrapper_handle.write("    Handle hdl <- openFile(\"" + v_path + "\", WriteMode);\n")
                    wrapper_handle.write("    hPutStrLn(hdl, \"// Dummy\");\n")
                    wrapper_handle.write("    hClose(hdl);\n")

                #declare interface vectors
                wrapper_handle.write("    Vector#(" + str(incoming) + ", PHYSICAL_CONNECTION_IN)  incomingVec = newVector();\n")
                wrapper_handle.write("    Vector#(" + str(outgoing) + ", PHYSICAL_CONNECTION_OUT) outgoingVec = newVector();\n")
                wrapper_handle.write("    Vector#(" + str(chains) + ", PHYSICAL_CHAIN) chainsVec = newVector();\n")
        
                # lay down module body
                wrapper_handle.write(module_body)
                                
                # fill in external interface 
                #wrapper_handle.write("    let e0 <- mk_Empty_Wrapper();\n")
                #wrapper_handle.write("    let e1 <- mk_Empty_Wrapper();\n")
                #wrapper_handle.write("    let e2 <- mk_Empty_Wrapper();\n")
                wrapper_handle.write("    let clk <- exposeCurrentClock();\n")
                wrapper_handle.write("    let rst <- exposeCurrentReset();\n")

                wrapper_handle.write("    " + subinterfaceType + " moduleIfc = interface WITH_CONNECTIONS;\n")
                wrapper_handle.write("        interface incoming = incomingVec;\n")
                wrapper_handle.write("        interface outgoing = outgoingVec;\n")
                wrapper_handle.write("        interface chains = chainsVec;\n")                                   
                wrapper_handle.write("        interface incomingMultis = replicate(PHYSICAL_CONNECTION_IN_MULTI{try: ?, success: ?, clock: clk, reset: rst});\n")
                wrapper_handle.write("        interface outgoingMultis = replicate(PHYSICAL_CONNECTION_OUT_MULTI{notEmpty: ?, first: ?, deq: ?, clock: clk, reset: rst});\n")
                wrapper_handle.write("    endinterface;\n")
                                             
                wrapper_handle.write("    interface services = tuple3(moduleIfc,?,?);\n")
                wrapper_handle.write("    interface device = ?;//e2;\n")
                wrapper_handle.write("endmodule\n")

                if (pipeline_debug != 0):
                    for channel in treeModule.channels:
                        print "Channel in " + treeModule.name + " " + str(channel)

                return treeModule

            # partition the top level LIM graph to produce a tree of
            # latency insensitive modules.  If there is only a
            # single module, we need to add a vestigial empty module
            # to the graph. This situation only occurs in a handful
            # of multifpga modules.

            top_module = cutRecurse(liGraph, 1)            

            # In multifpga builds, we may have some leftover modules
            # due to the way that the LIM compiler currently
            # operates. We emit dummy modules here to make
            # downstream tools happy.  This can be removed once we
            # reorganize the multifpga compiler.

            for module in module_names:
                wrapper_handle.write("\n\n(*synthesize*)\n")
                wrapper_handle.write("module mk_" + module + "_Wrapper (Reg#(Bit#(1)));\n")
                wrapper_handle.write("    let m <- mkRegU();\n")
                wrapper_handle.write("    return m;\n")
                wrapper_handle.write("endmodule\n")

            # we need to create a top level wrapper module to
            # re-monadize the soft connections so that the platform
            # compiles correctly

            # however the synth file depends only on the build tree wrapper
            # if we have a single module, it will be the case that
            # this module and not a tree build will be returned. Handle both.
            synth_handle.write('import ' + top_module.name + '_Wrapper::*;\n')        

            synth_handle.write("\n\nmodule [Connected_Module] mkBuildTree();\n")
            synth_handle.write("    let tree <- liftModule(mk_" + top_module.name + "_Wrapper());\n")
            synth_handle.write("    let connections = tpl_1(tree.services);\n")

            # these strings should probably made functions in the
            # liChannel code
            for channel in top_module.channels:
                ch_reg_stmt = 'registerRecv'
                ch_type = 'LOGICAL_RECV_INFO'
                ch_src = 'incoming'
                if (channel.isSource()):
                    ch_reg_stmt = 'registerSend'
                    ch_type = 'LOGICAL_SEND_INFO'
                    ch_src = 'outgoing'

                synth_handle.write('    ' + ch_reg_stmt + '("' + channel.name + '", ' + ch_type +\
                                ' { logicalType: "' + channel.raw_type +\
                                '", computePlatform: "' + channel.platform + '", optional: ' +\
                                str(channel.optional) + ', ' + ch_src + ': connections.' + ch_src +'[' +\
                                str(channel.module_idx) + '], bitWidth:' + str(channel.bitwidth) +\
                                ', moduleName: "' + channel.module_name + '"});\n')   

            for chain in top_module.chains:
                synth_handle.write('    registerChain(LOGICAL_CHAIN_INFO { logicalName: "' +\
                                chain.name + '", logicalType: "' + chain.raw_type +\
                                '", computePlatform: "' + chain.platform +\
                                '", incoming: connections.chains[' + str(chain.module_idx) +\
                                '].incoming, outgoing: connections.chains[' + str(chain.module_idx) +\
                                '].outgoing, bitWidth:' + str(chain.bitwidth) +\
                                ', moduleNameIncoming: "' + chain.module_name +\
                                '",  moduleNameOutgoing: "' + chain.module_name + '"});\n')   

            synth_handle.write("endmodule\n")
 
            for tree_file in [synth_handle, wrapper_handle]: 
                tree_file.write("`endif\n")
                tree_file.close()

            return None

        ##
        ## Back to SCons configuration (first) pass...
        ##

        ## This produces the treeNode BSV. It must wait for the
        ## compilation of the log files, which it will read to form the
        ## LIM graph
        ##
        ## We do two operations during this phase.  First, we dump a
        ## representation of the user program. This representation is
        ## used by the LIM compiler to create heterogeneous
        ## executables.  We then do a local modification to the build
        ## tree to reduce Bluespec compilation time. 
        tree_components = env.Command([tree_file_wrapper, tree_file_synth],
                                      boundary_logs,
                                      cut_tree_build)



        ## The top level build depends on the compilation of the tree components 
        ## into bo/ba/v files. 

        ## One wonders if we're going to build a build pipeline Module for the build 
        ## tree whether or not we should just invoke build synth boundary on it.  
        ## The difficulty is that the dependency checker won't work because the code 
        ## doesn't actually exist. 
        tree_file_wrapper_bo = env.BSC(tree_file_wrapper_bo_path, tree_components[0])
        
        # the tree_file_wrapper build needs all the wrapper bo from the user program,
        # but not the top level build.  
        top_bo = moduleList.topModule.moduleDependency['BSV_BO']
        all_bo = moduleList.getAllDependencies('BO')
        
        env.Depends(tree_file_wrapper_bo, all_bo)

        tree_file_synth_bo = env.BSC(tree_file_synth_bo_path, tree_components[1])
        env.Depends(tree_file_synth_bo, tree_file_wrapper_bo)

        env.Depends(top_bo, tree_file_synth_bo)
        env.Depends(moduleList.topModule.moduleDependency['BSV_LOG'],
                    tree_file_synth_bo)

        # need to generate a stub file for the build tree module.
        # note that in some cases, there will be only one module in
        # the graph, usually in a multifpga build.  In this case,
        # the build_tree module will be vestigal, but since we can't
        # predict this statically we'll have to build it anyway.
        
        top_module_path = get_build_path(moduleList, moduleList.topModule)
        bb = self.stubGenCommand(top_module_path, "build_tree_Wrapper.bsv", top_module_path + '/' + self.TMP_BSC_DIR + "/mk_build_tree_Wrapper.v")
        env.Depends(top_module_path + '/' + self.TMP_BSC_DIR + "/mk_build_tree_Wrapper.v", tree_file_wrapper_bo)
        oldStubs =  moduleList.topModule.moduleDependency['VERILOG_STUB']
        moduleList.topModule.moduleDependency['VERILOG_STUB'] = [bb] # top level only depends on the build tree
        
        ## We have now generated a completely new module. Let's throw it
        ## into the list.  Although we are building it seperately, this
        ## module is an extension to the build tree.
        verilog_deps = [ "__TREE_MODULE__" + str(id) for id in range(len(boundary_logs) - 2)] 
        tree_module = Module( 'build_tree', ["mkBuildTree"], moduleList.topModule.buildPath,\
                             moduleList.topModule.computePlatform, moduleList.topModule.name,\
                             [], moduleList.topModule.name, [], \
                             {'GEN_VERILOGS': [ "mk_" + vlog + "_Wrapper.v"  for vlog in verilog_deps],\
                              'GEN_BAS': [  "mk_" + vlog + "_Wrapper.ba" for vlog in verilog_deps],
                              'VERILOG': [],
                              'VERILOG_STUB': oldStubs})

        return [tree_module]
