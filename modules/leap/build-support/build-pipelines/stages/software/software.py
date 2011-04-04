import os
import sys
import re
import SCons.Script
from model import  *

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
        cc_flags += ' ' + cpp_events_flag
        if (getDebug(moduleList)):
            cc_flags += ' -DASIM_ENABLE_ASSERTIONS -DDEBUG'
        if (getTrace(moduleList)):
            cc_flags += ' -DASIM_ENABLE_TRACE'
        cc_flags += ' -DAPM_NAME=\\"' + moduleList.apmName + '\\"'
    
        if (DEBUG):
            copt_flags = '-ggdb3 '
        else:
            copt_flags = '-g -O2 '

        ##
        ## These will be defined if the m5 simulator is part of the model
        ##
        M5_BUILD_DIR = moduleList.m5BuildDir
        if (M5_BUILD_DIR != ''):
            # m5 needs Python library
            inc_paths += [ os.path.join(sys.exec_prefix, 'include', 'python' + sys.version[:3]) ]

            cc_flags += ' -DTRACING_ON=1'
            if (moduleList.env['DEFS']['SIMULATED_ISA'] != ''):
                cc_flags += ' -DTHE_ISA=' + moduleList.env['DEFS']['SIMULATED_ISA'] + '_ISA'

            ##
            ## The whole m5 library must be embedded in the final binary because
            ## the Python code is included as arrays initialized by static
            ## constructores.
            ##

            if (getDebug(moduleList)):
                # First, remove the m5 library from the main list of libraries
                m5_lib = ''
                tmp_libs = []
                for lib in libs:
                    if (os.path.basename(lib) == 'libm5_opt.a'):
                        m5_lib = lib
                    else:
                        tmp_libs += [ lib ]
                libs = tmp_libs
    
                # Second, store the m5 library in whole_libs
                if (m5_lib != ''):
                    if (DEBUG):
                        # Swap the optimized m5 library for a debugging one
                        m5_lib = os.path.join(os.path.dirname(m5_lib), 'libm5_debug.a')
                    whole_libs += [ m5_lib ]


        # CPPPATH defines both gcc include path and dependence path for
        # SCons.  The '#' forces paths to be relative to the root of the build.
        sw_env = moduleList.env.Clone(CCFLAGS = copt_flags + cc_flags,
                                      LINKFLAGS = copt_flags,
                                      CPPPATH = [ '#/' + moduleList.rootDirInc,
                                                  '#/' + moduleList.rootDirSw,
                                                  '#/iface/build/include',
                                                  '.' ] + inc_paths)
    
        sw_env['DEFS']['CWD_REL'] = sw_env['DEFS']['ROOT_DIR_SW_MODEL']
    
        moduleList.env.Export('sw_env')
        sw_build_dir = sw_env['DEFS']['ROOT_DIR_SW'] + '/obj'
        sw_objects = moduleList.env.SConscript([moduleList.rootDirSw + '/SConscript'],
                                               build_dir = sw_build_dir,
                                               duplicate = 0)
    
        sw_libpath = [ '.' ]
        sw_link_libs = [ 'pthread', 'dl' ]
    
        sw_link_tgt = moduleList.swExe
    
    
        ##
        ## m5 needs libraries
        ##
        if (M5_BUILD_DIR != ''):
            sw_link_libs += [ 'z' ]
    
            # m5 needs python
            sw_libpath += [ os.path.join(sys.exec_prefix, 'lib') ]
            sw_link_libs += [ 'python' + sys.version[:3] ]
    
    
        ##
        ## Put libs on the list of objects twice as a hack to work around the
        ## inability to specify the order of %library declarations across separate
        ## awb files.  Unix ld only searches libraries in command line order.
        ##
        sw_exe = sw_env.Program(sw_link_tgt, sw_objects + libs + libs, LIBPATH=sw_libpath, LIBS=sw_link_libs)
    
        ##
        ## There ought to be a way to tell SCons to include whole libraries as
        ## part of the link step.  There currently is not.
        ##
        if (whole_libs != []):
            sw_env.Append(LINKFLAGS=['-Wl,--whole-archive'] + whole_libs + ['-Wl,--no-whole-archive'])


    moduleList.topDependency = moduleList.topDependency + [sw_exe]     
