import os
import sys
import re
import SCons.Script
import cPickle as pickle

from model import  *
from li_module import *

def host_defs():
    hostos = one_line_cmd('uname -s')
    hostmachine = one_line_cmd('uname -m')

    if (hostos == 'FreeBSD'):
        hflags = '-DHOST_FREEBSD'
    else:
        hflags = '-DHOST_LINUX'
        if (hostmachine == 'ia64'):
            hflags += ' -DHOST_LINUX_IA64'
        else:
            hflags += ' -DHOST_LINUX_X86'

    return hflags

# Baking out M5 at some point would be a good idea

class Software():

    def __init__(self, moduleList):

        self.pipeline_debug = getBuildPipelineDebug(moduleList)
        self.env = moduleList.env

        # set up trace flags
        if (getEvents(moduleList) == 0):       
           cpp_events_flag = ''
        else:
           cpp_events_flag = '-DHASIM_EVENTS_ENABLED'

        if moduleList.swExe != []:
            inc_paths = moduleList.swIncDir
            libs = moduleList.swLibs
            whole_libs = []
            cc_flags = host_defs()
            cc_flags += ' -fPIC -std=gnu++11 '
            cc_flags += ' ' + cpp_events_flag
            if (getDebug(moduleList)):
                cc_flags += ' -DASIM_ENABLE_ASSERTIONS -DDEBUG'
            if (getTrace(moduleList)):
                cc_flags += ' -DASIM_ENABLE_TRACE'
            cc_flags += ' -DAPM_NAME=\\"' + moduleList.apmName + '\\"'
        
            if (getDebug(moduleList)):
                copt_flags = '-ggdb3 '
            else:
                copt_flags = '-g -O2 '

            ##
            ## These will be defined if the m5 simulator is part of the model
            ##
            M5_BUILD_DIR = moduleList.m5BuildDir
            if (M5_BUILD_DIR != ''):
                ## m5 needs Python library.  The installed version of Python isn't
                ## necessarily the version used by SCons, so we must invoke Python
                ## to figure out the proper version.
                m5_python_ver = os.popen('echo "import sys\nsys.stdout.write(sys.version[:3])" | python').read()
                m5_python_exec_prefix = os.popen('echo "import sys\nsys.stdout.write(sys.exec_prefix)" | python').read()
                inc_paths += [ os.path.join(m5_python_exec_prefix, 'include', 'python' + m5_python_ver) ]

                cc_flags += ' -DTRACING_ON=1'
                if (self.env['DEFS']['SIMULATED_ISA'] != ''):
                    cc_flags += ' -DTHE_ISA=' + self.env['DEFS']['SIMULATED_ISA'] + '_ISA'

                ##
                ## The whole m5 library must be embedded in the final binary because
                ## the Python code is included as arrays initialized by static
                ## constructores.
                ##

                # First, remove the m5 library from the main list of libraries
                m5_lib = ''
                tmp_libs = []
                for lib in libs:
                    if (os.path.basename(lib) == 'libgem5_opt.a'):
                        m5_lib = lib
                    else:
                        tmp_libs += [ lib ]
                libs = tmp_libs

                # Second, store the m5 library in whole_libs
                if (m5_lib != ''):
                    if (getDebug(moduleList)):
                        # Swap the optimized m5 library for a debugging one
                        m5_lib = os.path.join(os.path.dirname(m5_lib), 'libgem5_debug.a')
                    whole_libs += [ m5_lib ]

            # CPPPATH defines both gcc include path and dependence path for
            # SCons.
            sw_inc = self.env.Dir(self.env['DEFS']['ROOT_DIR_SW_INC'])
            sw_model_inc = self.env.Dir(self.env['DEFS']['ROOT_DIR_SW_MODEL'])
            iface_inc = self.env.Dir('iface/build/include')
            sw_env = self.env.Clone(CCFLAGS = copt_flags + cc_flags,
                                    LINKFLAGS = copt_flags,
                                    CPPPATH = [ sw_inc,
                                                sw_model_inc,
                                                iface_inc,
                                                '.' ] + inc_paths)
        
            # Scons does not use the external environment. If an external environment 
            # variable is needed then it must be added to the $ENV construction variable
            if os.environ.has_key('CPLUS_INCLUDE_PATH'):
                sw_env.Append(ENV = {'CPLUS_INCLUDE_PATH' : os.environ['CPLUS_INCLUDE_PATH']})

            sw_env['DEFS']['CWD_REL'] = sw_env['DEFS']['ROOT_DIR_SW_MODEL']

            # this appears to be some secret sauce which works in x86 linux environments,
            # which do not appear to require PIC/relocatable code at link time.  The dynamic loader
            # can instead handle the relinking.  Scons may also have some bug in which it does not 
            # understand which libraries are actually relocatable. 

            sw_env['STATIC_AND_SHARED_OBJECTS_ARE_THE_SAME']=1
            self.env.Export('sw_env')
            sw_build_dir = sw_env['DEFS']['ROOT_DIR_SW'] + '/obj'
            sw_objects = self.env.SConscript([sw_model_inc.File('SConscript')],
                                             variant_dir = sw_build_dir,
                                             duplicate = 0)
        
            
            self.env.Depends(sw_objects,moduleList.topModule.moduleDependency['IFACE_HEADERS'])
            sw_libpath = [ '.' ]
            sw_link_libs = moduleList.swLinkLibs + [ 'pthread', 'rt', 'dl' ]
        
            sw_obj_path = self.env['DEFS']['ROOT_DIR_SW'] + '/obj/'
            sw_link_tgt = sw_obj_path + moduleList.apmName + '.so'
            exe_wrapper_cpp = sw_obj_path + moduleList.apmName + '_wrapper.cpp'
            sw_exe_libpath = [sw_obj_path]  
            sw_exe_link_libs = [moduleList.apmName]  
            sw_exe_tgt  = sw_obj_path + moduleList.apmName + '_sw.exe'


            ## 
            ## Sometimes a module hierarchy can include the same library
            ## multiple times. Scrub them here. 
            ##
     
            sw_link_libs = list(set(sw_link_libs))
            libs = list(set(libs))

            ##
            ## m5 appends its libraries to the executable.  To do this, we need to 
            ## do something special in the final m5-enabled executable environment.
            ## This special link will break the shared library, so we bake it out here.  
            ## 

            so_env = sw_env.Clone()
        
            ##
            ## m5 needs libraries
            ##
            if (M5_BUILD_DIR != ''):
                sw_exe_link_libs += [ 'z' ]
        
                # m5 needs python
                m5_python_libpath = os.path.join(m5_python_exec_prefix, 'lib')
                sw_exe_libpath += [ m5_python_libpath ]
                sw_exe_link_libs += [ 'python' + m5_python_ver ] + [ 'util' ]    
                sw_env.Append(RPATH=[m5_python_libpath])

            ##
            ## Generate a thin wrapper for the shared library
            ## invocation. This wrapper will be compiled against the main
            ## shared library during the second phase of compilation. 
            ## 
           
            def generate_exe_wrapper(target, source, env):
                
                wrapper_handle = open(str(target[0]),'w')

                wrapper_handle.write('#include "project-hybrid-init.h"\n')            
                wrapper_handle.write('#include "project-utils.h"\n')            
                wrapper_handle.write('#include <signal.h>\n')
                wrapper_handle.write('// =======================================\n')
                wrapper_handle.write('//           PROJECT MAIN\n')
                wrapper_handle.write('// =======================================\n')
                wrapper_handle.write('// A thin wrapper for the init function generated by the build pipeline.\n') 
                wrapper_handle.write('// main\n')
                wrapper_handle.write('int main(int argc, char *argv[])\n')
                wrapper_handle.write('{\n')
                wrapper_handle.write('\tsignal(SIGSEGV, signalHandler);\n')
                wrapper_handle.write('\treturn Init(argc, argv);\n')
                wrapper_handle.write('}\n')
                wrapper_handle.close()


            exe_wrapper = sw_env.Command(exe_wrapper_cpp,
                                         [], 
                                         generate_exe_wrapper)

            ##
            ## Put libs on the list of objects twice as a hack to work around the
            ## inability to specify the order of %library declarations across separate
            ## awb files.  Unix ld only searches libraries in command line order.
            ##

            sw_so = so_env.SharedLibrary(sw_link_tgt, sw_objects + libs + libs, LIBPATH=sw_libpath, LIBS=sw_link_libs)

            # We cannot give a relative path to a dynamic object to the
            # c++ linker, or we will lose the ability to move our final
            # executable.  Therefore, the sw_so object cannot be a direct
            # source of the sw_exe target.  Therefore, we must provide the
            # stripped .so name and express the dependecy explicity.

            sw_exe = sw_env.Program(sw_exe_tgt,
                                    exe_wrapper + libs + libs,
                                    LIBPATH=sw_exe_libpath+sw_libpath,
                                    LIBS=sw_exe_link_libs+sw_link_libs+[moduleList.apmName])
            sw_env.Depends(sw_exe, sw_so)  


            ##
            ## There ought to be a way to tell SCons to include whole libraries as
            ## part of the link step.  There currently is not.
            ##
            if (whole_libs != []):
                sw_env.Append(LINKFLAGS=['-Wl,--export-dynamic'] + ['-Wl,--whole-archive'] + whole_libs + ['-Wl,--no-whole-archive'])


            moduleList.topDependency = moduleList.topDependency + [sw_exe]     


       
        # Multifpga builds require us to dump a latency-insensitive
        # graph representation (.li file) specifying the latency
        # insensitive channels that we found. We don't yet have a way
        # of doing this programmatically, but we do have
        # programmer-provided logfiles.
        if(moduleList.getAWBParam('software_tool', 'DUMP_LIM_GRAPH')):        
            li_graph = self.env['DEFS']['APM_NAME'] + '.li'

            # build a list of logfiles.  Perhaps we should call these CPP logs or something?
            #all_logs = moduleList.getAllDependenciesWithPaths('GIVEN_LOGS')
            all_logs = map(lambda path: self.env['DEFS']['ROOT_DIR_HW']+ '/' + path, moduleList.getAllDependenciesWithPaths('GIVEN_LOGS'))

            # TODO: this code is very similar to the code in BSV.py.
            # Refactor is and put it in the LI library. 
            def dump_lim_graph(target, source, env):
                connections = []
                # filter out build_tree connections.  These are not real                                                                                                      

                logs = [Source.Source(str(s), None) for s in source]

                for connection in parseLogfiles(logs):
                    connections.append(connection)
                    # Currently, all connections come from this platform.
                    # TODO: Fix this assumption
                    platformName = moduleList.getAWBParam('physical_platform_defs', 'FPGA_PLATFORM_NAME')
                    connection.module_name = platformName
                

                fullLIGraph = LIGraph(connections)
                
                # Decorate LI modules with type
                for module in fullLIGraph.modules.values():
                    module.putAttribute("EXECUTION_TYPE","SOFTWARE")
                    module.putAttribute('MAPPING', moduleList.localPlatformName)
                    module.putAttribute('PLATFORM_MODULE', True)
                    # give module a pointer to its log files. 
                    # this works because all software logs at this time are given
                    module.putObjectCode('GIVEN_LOGS', logs)

                # dump graph representation. 
                pickleHandle = open(str(target[0]), 'wb')
                pickle.dump(fullLIGraph, pickleHandle, protocol=-1)
                pickleHandle.close()

                if (self.pipeline_debug != 0):
                    print "CPP Initial Graph is: " + str(fullLIGraph) + ": " + sys.version +"\n"

            # Setup the graph dump
            dumpGraph = self.env.Command(li_graph, all_logs, dump_lim_graph)

            moduleList.topDependency += [dumpGraph]
