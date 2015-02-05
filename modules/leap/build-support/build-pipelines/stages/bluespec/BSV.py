import os
import sys
import re
import string
import cPickle as pickle
import SCons.Script
import SCons.Node.FS

import model
from model import Module, Source, get_build_path
import iface_tool 
import treeModule
import li_module
from li_module import LIGraph, LIModule
import wrapper_gen_tool
import bsv_tool

import pygraph
try:
    from pygraph.classes.digraph import digraph
except ImportError:
    # don't need to do anything
    print "\n"



# construct full path to BAs
def modify_path_ba(moduleList, path):
    array = path.split('/')
    file = array.pop()
    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
    return  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + '/'.join(array) + '/' + TMP_BSC_DIR + '/' + file

def getUserModules(liGraph):
    if(liGraph is None):
        return []
    return [module for module in liGraph.modules.values() if (module.getAttribute('PLATFORM_MODULE') is None)]

def getPlatformModules(liGraph):
    if(liGraph is None):
        return []
    return [module for module in liGraph.modules.values() if not ((module.getAttribute('PLATFORM_MODULE') is None))]

#this might be better implemented as a 'Node' in scons, but
#I want to get something working before exploring that path
# This is going to recursively build all the bsvs
class BSV():

    def __init__(self, moduleList):
        # some definitions used during the bsv compilation process
        env = moduleList.env
        self.moduleList = moduleList

        self.hw_dir = env.Dir(moduleList.env['DEFS']['ROOT_DIR_HW'])

        self.TMP_BSC_DIR = env['DEFS']['TMP_BSC_DIR']
        synth_modules = moduleList.synthBoundaries()

        self.USE_TREE_BUILD = moduleList.getAWBParam('wrapper_gen_tool', 'USE_BUILD_TREE')

        # all_module_dirs: a list of all module directories in the build tree
        self.all_module_dirs = [self.hw_dir.Dir(moduleList.topModule.buildPath)]
        for module in synth_modules:
            if (module.buildPath != moduleList.topModule.buildPath):
                self.all_module_dirs += [self.hw_dir.Dir(module.buildPath)]

        # all_build_dirs: the build (.bsc) sub-directory of all module directories
        self.all_build_dirs = [d.Dir(self.TMP_BSC_DIR) for d in self.all_module_dirs]

        # Include iface directories
        self.all_module_dirs += iface_tool.getIfaceIncludeDirs(moduleList)
        self.all_build_dirs += iface_tool.getIfaceLibDirs(moduleList)

        # Add the top level build directory
        self.all_build_dirs += [env.Dir(self.TMP_BSC_DIR)]

        self.all_module_dirs += [self.hw_dir.Dir('include'),
                                 self.hw_dir.Dir('include/awb/provides')]

        # Full search path: all module and build directories
        self.all_lib_dirs = self.all_module_dirs + self.all_build_dirs

        all_build_dir_paths = [d.path for d in self.all_build_dirs]
        self.ALL_BUILD_DIR_PATHS = ':'.join(all_build_dir_paths)

        all_lib_dir_paths = [d.path for d in self.all_lib_dirs]
        self.ALL_LIB_DIR_PATHS = ':'.join(all_lib_dir_paths)

        # we need to annotate the module list with the
        # bluespec-provided library files. Do so here.
        if(not moduleList.getAWBParamSafe('synthesis_tool', 'USE_VIVADO_SOURCES') is None):
            bsv_tool.decorateBluespecLibraryCodeVivado(moduleList)
        else:
            bsv_tool.decorateBluespecLibraryCodeBaseline(moduleList)

        self.TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
        self.BUILD_LOGS_ONLY = moduleList.getAWBParam('bsv_tool', 'BUILD_LOGS_ONLY')
        self.USE_BVI = moduleList.getAWBParam('bsv_tool', 'USE_BVI')

        self.pipeline_debug = model.getBuildPipelineDebug(moduleList)

        # Should we be building in events?
        if (model.getEvents(moduleList) == 0):
            bsc_events_flag = ' -D HASIM_EVENTS_ENABLED=False '
        else:
            bsc_events_flag = ' -D HASIM_EVENTS_ENABLED=True '

        self.BSC_FLAGS = moduleList.getAWBParam('bsv_tool', 'BSC_FLAGS') + bsc_events_flag

        moduleList.env.VariantDir(self.TMP_BSC_DIR, '.', duplicate=0)
        moduleList.env['ENV']['BUILD_DIR'] = moduleList.env['DEFS']['BUILD_DIR']  # need to set the builddir for synplify


        topo = moduleList.topologicalOrderSynth()
        topo.reverse()

        # Cleaning? Wipe out module temporary state. Do this before
        # the topo pop to ensure that we don't leave garbage around at
        # the top level.
        if moduleList.env.GetOption('clean'):
            for module in topo:
                MODULE_PATH =  get_build_path(moduleList, module)
                os.system('cd '+ MODULE_PATH + '/' + self.TMP_BSC_DIR + '; rm -f *.ba *.c *.h *.sched *.log *.v *.bo *.str')

        topo.pop() # get rid of top module.

        ## Python module that generates a wrapper to connect the exposed
        ## wires of all synthesis boundaries.
        tree_builder = bsv_tool.BSVSynthTreeBuilder(self)

        ##
        ## Is this a normal build or a build in which only Bluespec dependence
        ## is computed?
        ##

        if not moduleList.isDependsBuild:
            ##
            ## Normal build.
            ##

            ##
            ## Now that the "depends-init" build is complete we can
            ## continue with accurate inter-Bluespec file dependence.
            ## This build only takes place for the first pass object
            ## code generation.  If the first pass li graph exists, it
            ## subsumes awb-style synthesis boundary generation.
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
            do_dump_lim_graph = self.BUILD_LOGS_ONLY
            if do_dump_lim_graph:
                lim_logs = []
                lim_stubs = []
                for module in topo:
                    # scrub tree build/platform, which are redundant.
                    lim_logs.extend(module.moduleDependency['BSV_LOG'])
                    lim_stubs.extend(module.moduleDependency['GEN_VERILOG_STUB'])

                li_graph = moduleList.env['DEFS']['APM_NAME'] + '.li'

                ## dump a LIM graph for use by the LIM compiler.  here
                ## we wastefully contstruct (or reconstruct, depending on your
                ## perspective, a LIM graph including the platform channels.
                ## Probably this result could be acheived with the mergeGraphs
                ## function.
                def dump_lim_graph(target, source, env):
                    # Find the subset of sources that are log files and parse them
                    logs = [s for s in source if (str(s)[-4:] == '.log')]
                    fullLIGraph = LIGraph(li_module.parseLogfiles(logs))

                    # annotate modules with relevant object code (useful in
                    # LIM compilation)
                    # this is not technically a part of the tree cut methodology, but we need to do this

                    # For the LIM compiler, we must also annotate those
                    # channels which are coming out of the platform code.

                    for module in moduleList.synthBoundaries():
                        modulePath = module.buildPath
  
                        print "MODULE_LIST: " + module.name

                        # Wrap the real findBuildPath() so it can be invoked
                        # later by map().
                        def __findBuildPath(path):
                            return Source.findBuildPath(path, modulePath)

                        # User area groups add a wrinkle. We need to
                        # keep them around, but they don't have LI
                        # channels
  
                        if(not module.getAttribute('AREA_GROUP') is None):
                            # We now need to create and integrate an
                            # LI Module for this module
                            newModule = LIModule(module.name, module.name)
                            fullLiGraph.mergeModules([newModule])
                            print "Adding module " + module.name

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
                                convertedDeps = model.convertDependencies(depList)
                                relativeDeps = map(__findBuildPath, convertedDeps)
                                fullLIGraph.modules[module.name].putObjectCode(objectType, relativeDeps)

                    for module in topo:
                        if(module.name in fullLIGraph.modules):
                            # annotate platform module with local mapping.
                            if(module.name == moduleList.localPlatformName + '_platform'):
                                # The platform module is special.
                                fullLIGraph.modules[module.name].putAttribute('MAPPING', moduleList.localPlatformName)
                                fullLIGraph.modules[module.name].putAttribute('PLATFORM_MODULE', True)

                    # Decorate LI modules with type
                    for module in fullLIGraph.modules.values():
                        module.putAttribute("EXECUTION_TYPE","RTL")

                    # dump graph representation.
                    pickleHandle = open(str(target[0]), 'wb')
                    pickle.dump(fullLIGraph, pickleHandle, protocol=-1)
                    pickleHandle.close()

                    if (self.pipeline_debug != 0):
                        print "Initial Graph is: " + str(fullLIGraph) + ": " + sys.version +"\n"

                # Setup the graph dump Although the graph is built
                # from only LI modules, the top wrapper contains
                # sizing information. Also needs stubs.
                dumpGraph = env.Command(li_graph,
                                        lim_logs + lim_stubs,
                                        dump_lim_graph)

                moduleList.topModule.moduleDependency['LIM_GRAPH'] = [li_graph]

                # dumpGraph depends on most other top level builds since it
                # walks the set of generated files.
                moduleList.env.Depends(dumpGraph, moduleList.topDependency)
                moduleList.topDependency = [dumpGraph]


            ## Merge all synthesis boundaries using a tree?  The tree reduces
            ## the number of connections merged in a single compilation, allowing
            ## us to support larger systems.
            if self.USE_TREE_BUILD:
                tree_builder.setupTreeBuild(moduleList, topo)

            ##
            ## Generate the global string table.  Bluespec-generated global
            ## strings are stored in files by the compiler.
            ##
            ## The global string file will be generated in the top-level
            ## .bsc directory and a link to it will be added to the
            ## top-level directory.
            ##
            all_str_src = []
            #for module in topo + [moduleList.topModule]:
            for module in moduleList.moduleList + topo + [moduleList.topModule]:
                if('STR' in module.moduleDependency):
                    all_str_src.extend(module.moduleDependency['STR'])

            if (self.BUILD_LOGS_ONLY == 0):
                bsc_str = moduleList.env.Command(self.TMP_BSC_DIR + '/' + moduleList.env['DEFS']['APM_NAME'] + '.str',
                                                 all_str_src,
                                                 [ 'cat $SOURCES > $TARGET'])
                strDep = moduleList.env.Command(moduleList.env['DEFS']['APM_NAME'] + '.str',
                                                bsc_str,
                                                [ 'ln -fs ' + self.TMP_BSC_DIR + '/`basename $TARGET` $TARGET' ])
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

            # We need to calculate some dependencies for the build
            # tree.  We could be clever and put this code somewhere
            # rather than replicate it.
            if self.USE_TREE_BUILD:

                buildTreeDeps = {}
                buildTreeDeps['GEN_VERILOGS'] = []
                buildTreeDeps['GEN_BAS'] = []
                #This is sort of a hack.
                buildTreeDeps['WRAPPER_BSHS'] = ['awb/provides/soft_services.bsh']
                buildTreeDeps['GIVEN_BSVS'] = []
                buildTreeDeps['BA'] = []
                buildTreeDeps['STR'] = []
                buildTreeDeps['VERILOG'] = []
                buildTreeDeps['BSV_LOG'] = []
                buildTreeDeps['VERILOG_STUB'] = []

                tree_module = Module( 'build_tree', ["mkBuildTree"], moduleList.topModule.buildPath,\
                             moduleList.topModule.name,\
                             [], moduleList.topModule.name, [], buildTreeDeps, platformModule=True)

                tree_module.dependsFile = '.depends-build-tree'

                moduleList.insertModule(tree_module)
                tree_file_bo = get_build_path(moduleList, moduleList.topModule) + "/build_tree.bsv"
                # sprinkle files to get dependencies right
                bo_handle = open(tree_file_bo,'w')

                # mimic AWB/leap-configure

                bo_handle.write('//\n')
                bo_handle.write('// Synthesized compilation file for module: build_tree\n')
                bo_handle.write('//\n')
                bo_handle.write('//   This file was created by BSV.py\n')
                bo_handle.write('//\n')

                bo_handle.write('`define BUILDING_MODULE_build_tree\n')
                bo_handle.write('`include "build_tree_Wrapper.bsv"\n')

                bo_handle.close()

                # Calling generateWrapperStub will write out default _Wrapper.bsv
                # and _Log.bsv files for build tree. However, these files
                # may already exists, and, in the case of build_tree_Wrapper.bsv,
                # have meaningful content.  Fortunately, generateWrapperStub
                # will not over write existing files.
                wrapper_gen_tool.generateWrapperStub(moduleList, tree_module)
                wrapper_gen_tool.generateAWBCompileWrapper(moduleList, tree_module)
                topo.append(tree_module)


            deps = []

            useDerived = True
            first_pass_LI_graph = wrapper_gen_tool.getFirstPassLIGraph()
            if (not first_pass_LI_graph is None):
                useDerived = False
                # we also need to parse the platform_synth file in th
                platform_synth = get_build_path(moduleList, moduleList.topModule) + "/" +  moduleList.localPlatformName + "_platform_synth.bsv"
                platform_deps = ".depends-platform"
                deps += self.compute_dependence(moduleList, moduleList.topModule, useDerived, fileName=platform_deps, targetFiles=[platform_synth])

                # If we have an LI graph, we need to construct and compile
                # several LI wrappers.  do that here.
                # include all the dependencies in the graph in the wrapper.
                li_wrappers = []
                tree_base_path = get_build_path(moduleList, moduleList.topModule)
                liGraph = LIGraph([])
                firstPassGraph = first_pass_LI_graph
                # We should ignore the 'PLATFORM_MODULE'
                liGraph.mergeModules(getUserModules(firstPassGraph))
                for module in sorted(liGraph.graph.nodes(), key=lambda module: module.name):
                    wrapper_import_path = tree_base_path + '/' + module.name + '_Wrapper.bsv'
                    li_wrappers.append(module.name + '_Wrapper.bsv')
                    wrapper_import_handle = open(wrapper_import_path, 'w')
                    wrapper_import_handle.write('import Vector::*;\n')
                    wrapper_gen_tool.generateWellKnownIncludes(wrapper_import_handle)
                    wrapper_gen_tool.generateBAImport(module, wrapper_import_handle)
                    wrapper_import_handle.close()
                    platform_deps = ".depends-" + module.name
                    deps += self.compute_dependence(moduleList, moduleList.topModule, useDerived, fileName=platform_deps, targetFiles=[wrapper_import_path])

            for module in topo + [moduleList.topModule]:
                # for object import builds no Wrapper code will be included. remove it.
                deps += self.compute_dependence(moduleList, module, useDerived, fileName=module.dependsFile)

            moduleList.topDependsInit += deps


    ##
    ## compute_dependence --
    ##   Build rules for computing intra-Bluespec file dependence.
    ##
    def compute_dependence(self, moduleList, module, useDerived, fileName='.depends-bsv', targetFiles=[]):
        MODULE_PATH =  get_build_path(moduleList, module)

        #allow caller to override dependencies.  If the caller does
        #not, then we should use the baseline
        if (len(targetFiles) == 0):
            targetFiles = [ moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/' + model.get_wrapper(module) ]
            if (module.name != moduleList.topModule.name):
                targetFiles.append(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/'+ model.get_log(module))

        # We must depend on all sythesis boundaries. They can be instantiated anywhere.
        surrogate_children = moduleList.synthBoundaries()
        SURROGATE_BSVS = ''
        for child in surrogate_children:
            # Make sure module doesn't self-depend
            if (child.name != module.name):
                SURROGATE_BSVS += moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + child.buildPath +'/' + child.name + '.bsv '

        if (useDerived and SURROGATE_BSVS != ''):
            DERIVED = ' -derived "' + SURROGATE_BSVS + '"'
        else:
            DERIVED = ''

        depends_bsv = MODULE_PATH + '/' + fileName
        moduleList.env.NoCache(depends_bsv)
        compile_deps = 'leap-bsc-mkdepend -ignore ' + MODULE_PATH + '/.ignore' + ' -bdir ' + self.TMP_BSC_DIR + DERIVED + ' -p +:' + self.ALL_LIB_DIR_PATHS + ' ' + ' '.join(targetFiles) + ' > ' + depends_bsv

        # Delete depends_bsv if it is empty under the assumption that something
        # went wrong when creating it.  An empty dependence file would never be
        # rebuilt without this.
        try:
            if (os.path.getsize(depends_bsv) == 0):
                os.unlink(depends_bsv)
        except:
            None

        dep = moduleList.env.Command(depends_bsv,
                                     targetFiles +
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

        env = moduleList.env
        BSVS = moduleList.getSynthBoundaryDependencies(module, 'GIVEN_BSVS')
        # each submodel will have a generated BSV
        GEN_BSVS = moduleList.getSynthBoundaryDependencies(module, 'GEN_BSVS')
        APM_FILE = moduleList.env['DEFS']['APM_FILE']
        BSC = moduleList.env['DEFS']['BSC']

        MODULE_PATH =  get_build_path(moduleList, module)

        ##
        ## Load intra-Bluespec dependence already computed.  This information will
        ## ultimately drive the building of Bluespec modules.
        ##
        env.ParseDepends(MODULE_PATH + '/' + module.dependsFile,
                         must_exist = not moduleList.env.GetOption('clean'))


        # This function is responsible for creating build rules for
        # subdirectories.  It must be called or no subdirectory builds
        # will happen since scons won't have the recipe.
        self.setup_module_build(moduleList, MODULE_PATH)

        if not os.path.isdir(self.TMP_BSC_DIR):
            os.mkdir(self.TMP_BSC_DIR)

        moduleList.env.VariantDir(MODULE_PATH + '/' + self.TMP_BSC_DIR, '.', duplicate=0)

        # set up builds for the various bsv of this synthesis
        # boundary.  One wonders if we could handle this as a single
        # global operation.
        bsc_builds = []
        for bsv in BSVS + GEN_BSVS:
            bsc_builds += env.BSC(MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''), MODULE_PATH + '/' + bsv)


        # if we got object code and we're not the top level,
        # we can return now.
        if ((module.name != moduleList.topModule.name) and (not wrapper_gen_tool.getFirstPassLIGraph() is None)):
            return

        # This should not be a for loop.
        for bsv in [model.get_wrapper(module)]:
            if env.GetOption('clean'):
                os.system('rm -f ' + MODULE_PATH + '/' + bsv.replace('Wrapper.bsv', 'Log.bsv'))
                os.system('rm -f ' + MODULE_PATH + '/' + bsv.replace('.bsv', '_con_size.bsh'))

            ##
            ## First pass just generates a log file to figure out cross synthesis
            ## boundary soft connection array sizes.
            ##
            ## All but the top level build need the log build pass to compute
            ## the size of the external soft connection vector.  The top level has
            ## no exposed connections and can generate the log file, needed
            ## for global strings, during the final build.
            ##
            logfile = model.get_logfile(moduleList, module)
            module.moduleDependency['BSV_LOG'] += [logfile]
            module.moduleDependency['GEN_LOGS'] = [logfile]
            if (module.name != moduleList.topModule.name):
                log = env.BSC_LOG_ONLY(logfile, MODULE_PATH + '/' + bsv.replace('Wrapper.bsv', 'Log'))

                ##
                ## Parse the log, generate a stub file
                ##

                stub_name = bsv.replace('.bsv', '_con_size.bsh')

                def build_con_size_bsh_closure(target, source, env):
                    liGraph = LIGraph(li_module.parseLogfiles(source))
                    # Should have only one module...
                    if(len(liGraph.modules) == 0):
                        bshModule = LIModule(module.name, module.name)
                    else:
                        bshModule = liGraph.modules.values()[0]
                    bsh_handle = open(str(target[0]), 'w')
                    wrapper_gen_tool.generateConnectionBSH(bshModule, bsh_handle)
                    bsh_handle.close()

                stub = env.Command(MODULE_PATH + '/' + stub_name, log, build_con_size_bsh_closure)

            ##
            ## Now we are ready for the real build
            ##
            if (module.name != moduleList.topModule.name):
                wrapper_bo = env.BSC(MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''), MODULE_PATH + '/' + bsv)
                moduleList.env.Depends(wrapper_bo, stub)
                module.moduleDependency['BO'] = [wrapper_bo]
                if (self.BUILD_LOGS_ONLY):
                    model_dir = self.hw_dir.Dir(moduleList.env['DEFS']['ROOT_DIR_MODEL'])

                    module.moduleDependency['BSV_SCHED'] = \
                        [moduleList.env.Command(MODULE_PATH + '/' + self.TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.ba.sched'),
                                                wrapper_bo,
                                                'bluetcl ' + model_dir.File('sched.tcl').path + ' -p ' + self.ALL_BUILD_DIR_PATHS + ' --m mk_' + module.name + '_Wrapper > $TARGET')]

                    module.moduleDependency['BSV_PATH'] = \
                        [moduleList.env.Command(MODULE_PATH + '/' + self.TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.ba.path'),
                                                wrapper_bo,
                                                'bluetcl ' + model_dir.File('path.tcl').path + ' -p ' + self.ALL_BUILD_DIR_PATHS + ' --m mk_' + module.name + '_Wrapper > $TARGET')]

                    moduleList.topDependency += \
                        module.moduleDependency['BSV_SCHED'] + module.moduleDependency['BSV_PATH']

                    module.moduleDependency['BSV_IFC'] = \
                        [moduleList.env.Command(MODULE_PATH + '/' + self.TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.ba.ifc'),
                                                wrapper_bo,
                                                'bluetcl ' + model_dir.File('interfaceType.tcl').path + ' -p ' + self.ALL_BUILD_DIR_PATHS + ' --m mk_' + module.name + '_Wrapper | python site_scons/model/PythonTidy.py > $TARGET')]

                    moduleList.topDependency += module.moduleDependency['BSV_IFC']




            else:
                ## Top level build can generate the log in a single pass since no
                ## connections are exposed
                wrapper_bo = env.BSC_LOG(MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''),
                                         MODULE_PATH + '/' + bsv)

                ## SCons doesn't deal well with logfile as a 2nd target to BSC_LOG rule,
                ## failing to derive dependence correctly.
                module.moduleDependency['BSV_BO'] = [wrapper_bo]
                log = env.Command(logfile, wrapper_bo, '')
                env.Precious(logfile)

                ## In case Bluespec build is the end of the build pipeline.
                if (not self.BUILD_LOGS_ONLY):
                    moduleList.topDependency += [log]

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
                # This stub may be needed in certain compilation flows.  Note its presence here.
                module.moduleDependency['BSV_SYNTH'] = [module.name +'_synth.bsv']
                module.moduleDependency['BSV_SYNTH_BSH'] = [module.name +'_Wrapper_con_size.bsh']

                def build_synth_stub(target, source, env):
                    liGraph = LIGraph(li_module.parseLogfiles(source))
                    # Should have only one module...
                    if(len(liGraph.modules) == 0):
                        synthModule = LIModule(module.name, module.name)
                    else:
                        synthModule = liGraph.modules.values()[0]

                    synth_handle = open(target[0].path, 'w')
                    wrapper_gen_tool.generateSynthWrapper(synthModule,
                                                          synth_handle,
                                                          moduleType=module.interfaceType,
                                                          extraImports=module.extraImports)
                    synth_handle.close()

                env.Command(synth_stub, # target
                            logfile,
                            build_synth_stub)

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


            # Add the dependence for all Verilog noted above
            bld_v = env.Command([MODULE_PATH + '/' + self.TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.v')] + ext_gen_v,
                                MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.bo'),
                                '')
            env.Precious(bld_v)

            if (moduleList.getAWBParam('bsv_tool', 'BUILD_VERILOG') == 1):
                module.moduleDependency['VERILOG'] += [bld_v] + [ext_gen_v]

                module.moduleDependency['GEN_WRAPPER_VERILOGS'] = [os.path.basename('mk_' + bsv.replace('.bsv', '.v'))]

            if (self.pipeline_debug != 0):
                print "Name: " + module.name

            # each synth boundary will produce a ba
            bld_ba = [env.Command([MODULE_PATH + '/' + self.TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.ba')],
                                  MODULE_PATH + '/' + self.TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.bo'),
                                  '')]

            module.moduleDependency['BA'] += bld_ba
            env.Precious(bld_ba)

            ##
            ## Build the Xst black-box stub.
            ##
            bb = self.stubGenCommand(MODULE_PATH, bsv, bld_v)

            # Only the subordinate modules have stubs.
            # The platform module should not be enumerated here. This is a false dependency.
            if (module.name != moduleList.topModule.name):
                moduleList.topModule.moduleDependency['VERILOG_STUB'] += [bb]
                module.moduleDependency['GEN_VERILOG_STUB'] = [bb]

            return [bb] #This doesn't seem to do anything.


    ##
    ## As of Bluespec 2008.11.C the -bdir target is put at the head of the search path
    ## and the compiler complains about duplicate path entries.
    ##
    ## This code removes the local build target from the search path.
    ##
    def __bsc_bdir_prune(self, str_in, sep, match):
        t = model.clean_split(str_in, sep)

        # Make the list unique to avoid Bluespec complaints about duplicate paths.
        seen = set()
        t = [e for e in t if e not in seen and not seen.add(e)]

        if (bsv_tool.getBluespecVersion() >= 15480):
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
    ## Older versions of Bluespec generated a .bi along with every
    ## .bo.  This is how scons learns about them.  We also tag module
    ## .bo with any generated BA/VERILOG that they have declared.
    ##
    def emitter_bo(self):
        def emitter_bo_closure(target, source, env):
            baseName = os.path.basename(str(target[0])).replace('.bo', '')
            dirName = os.path.dirname(str(target[0]))
            def appendDirName(fileName):
                return dirName + '/' + fileName
            if (bsv_tool.getBluespecVersion() < 26572):
                target.append(str(target[0]).replace('.bo', '.bi'))

            # Find Emitted BA/Verilog, but only for module_name.bsv (an awb module)
            if(baseName in self.moduleList.modules):
                target.append(map(appendDirName, self.moduleList.getDependencies(self.moduleList.modules[baseName], 'GEN_BAS')))
                target.append(map(appendDirName, self.moduleList.getDependencies(self.moduleList.modules[baseName], 'GEN_VPI_HS')))
                target.append(map(appendDirName, self.moduleList.getDependencies(self.moduleList.modules[baseName], 'GEN_VPI_CS')))
                target.append(map(appendDirName, self.moduleList.getDependencies(self.moduleList.modules[baseName], 'GEN_VERILOGS')))

            return target, source
        return emitter_bo_closure


    def compile_bo_bsc_base(self, target, module_path, vdir=None):
        # When invoked as a build rule, target[] is a list of SCons File objects.
        # When invoked just to build a string for generating a Command object
        # target may be a string.
        if (isinstance(target[0], basestring)):
            target[0] = self.moduleList.env.File(target[0])

        bdir = target[0].get_dir()

        # allows us to override vdir, useful in hacking around
        # Bluespec's automatically generated verilog search path.
        if (vdir):
            vdir_path = vdir.path
        else:
            vdir_path = bdir.path

        # compile bo_bsc_base gets some bogus .bsh targets..
        if (not bdir.exists()):
            return ''

        # Bluespec complains if the same path is specified in both -p and -bdir
        all_lib_dirs_list = [d for d in self.all_lib_dirs if d != bdir]
        all_lib_dirs = ':'.join([d.path for d in all_lib_dirs_list])

        # Emit an include path file.  This indirection is necessary to
        # fool scons into thinking that our command line doesn't
        # change.
        lib_dirs_file = target[0].path.replace('.bo','.libs')
        lib_dirs_file = lib_dirs_file.replace('.bsh','.libs')
        lib_dirs_file = lib_dirs_file.replace('.log','.libs')
        lib_dirs_handle = open(lib_dirs_file,'w')
        lib_dirs_handle.write(all_lib_dirs)
        lib_dirs_handle.close()

        bdir_path = bdir.path

        return self.moduleList.env['DEFS']['BSC'] + " " +  self.BSC_FLAGS + \
               ' -p +:`cat ' + lib_dirs_file + '`' + \
               ' -bdir ' + bdir_path + ' -vdir ' + vdir_path + \
               ' -simdir ' + bdir_path + ' -info-dir ' + bdir_path + \
               ' -fdir ' + bdir_path


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

        bsc_log = moduleList.env.Builder(generator = self.compile_bo_log(module_path), suffix = '.bo', src_suffix = '.bsv')

        # This guy has to depend on children existing?
        # and requires a bash shell
        moduleList.env['SHELL'] = 'bash' # coerce commands to be spanwed under bash
        bsc_log_only = moduleList.env.Builder(generator = self.compile_log_only(module_path), suffix = '.log', src_suffix = '.bsv')

        moduleList.env.Append(BUILDERS = {'BSC' : bsc, 'BSC_LOG' : bsc_log, 'BSC_LOG_ONLY' : bsc_log_only})
