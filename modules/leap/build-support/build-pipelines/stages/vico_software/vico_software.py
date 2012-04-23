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

        #
        # This section is need to build VICO dynamic library
        #
        cc_flags += ' -DVICO_TIMINGS '
        cc_flags += ' -fPIC ' 
        #ln -s /p/vip/cad/ViCo/latest/release/lib/libvico.so libvico.so

        if (getDebug(moduleList)):
            copt_flags = '-ggdb3 '
        else:
            copt_flags = '-g -O2 '



        # CPPPATH defines both gcc include path and dependence path for
        # SCons.  The '#' forces paths to be relative to the root of the build.
        sw_env = moduleList.env.Clone(CCFLAGS = copt_flags + cc_flags,
                                      LINKFLAGS = copt_flags + ' -shared',
                                      CPPPATH = [ '#/' + moduleList.rootDirInc,
                                                  '#/' + moduleList.rootDirSw,
                                                  '#/iface/build/include',
                                                  '.' ] + inc_paths)

        sw_env['DEFS']['CWD_REL'] = sw_env['DEFS']['ROOT_DIR_SW_MODEL']

        moduleList.env.Export('sw_env')
        sw_build_dir = sw_env['DEFS']['ROOT_DIR_SW'] + '/obj/'
        sw_objects = moduleList.env.SConscript([moduleList.rootDirSw + '/SConscript'],
                                               build_dir = sw_build_dir,
                                               duplicate = 0)


        moduleList.env.Depends(sw_objects,moduleList.topModule.moduleDependency['IFACE_HEADERS'])

        #
        # Linker options in case of ViCo build
        #
        sw_libpath = [ '.' ]
        sw_link_tgt   = sw_build_dir + moduleList.apmName + '_sw.so'
        # change moduleList.swExeOrTarget used after in XILINX_LOADER.py
        moduleList.swExeOrTarget = sw_link_tgt
        moduleList.swExe[0] = sw_link_tgt

        # to make sw build relocable, we are replacing absolute lib paths by local links
        for i in xrange(len(libs)):
            if (os.path.splitext(libs[i])[1] ==  ".so" ):
                if  not os.path.exists(os.path.basename(libs[i])):
                    os.symlink(libs[i], os.path.basename(libs[i]))
                libs[i] = os.path.basename(libs[i])

        ##
        ## Put libs on the list of objects twice as a hack to work around the
        ## inability to specify the order of %library declarations across separate
        ## awb files.  Unix ld only searches libraries in command line order.
        ##
        sw_exe = sw_env.Program(sw_link_tgt, sw_objects + libs + libs, LIBPATH=sw_libpath)

        ##
        ## There ought to be a way to tell SCons to include whole libraries as
        ## part of the link step.  There currently is not.
        ##

        #if (whole_libs != []):
        #    sw_env.Append(LINKFLAGS=['-Wl,--whole-archive'] + whole_libs + ['-Wl,--no-whole-archive'])


    moduleList.topDependency = moduleList.topDependency + [sw_exe]
