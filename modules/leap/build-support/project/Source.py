# -*-Python-*-

##
## File pathname management class.
##

import os
import sys
import traceback
import SCons.Node.FS

import model

class Source():

    # Cache of path to root
    __to_root = None

    def __init__(self, fileName, attributes):
        # .file is the path from the top of the build tree
        self.file = fileName
        self.attributes = attributes 
        self.buildDir = model.buildDir

    ## Base object methods
    def __str__(self):
        #traceback.print_stack(file=sys.stdout)
        #print "Converting " + str(self.file) 
        return str(self.file)


    ## The working directory in pass 1 of SCons compilations is the
    ## sub-directory containing the SConstruct file.  The LIM compiler
    ## uses multiple phases and multiple subdirectories.  Return
    ## the path relative to some pass of the LIM flow.
    def from_bld(self):
        if (not self.__to_root):
            self.__to_root = '../' * len(model.buildDir.split(os.path.sep))

        if (os.path.isabs(str(self.file))):
            return str(self.file)
        elif (self.__to_root == ''):
            return str(self.file)
        else:
            return self.__to_root + self.from_root()

    ## The path from the top of the build tree in the LIM compiler flow.
    def from_root(self):
        if (self.buildDir == ''):
            return str(self.file)
        else:
            return str(self.buildDir) + '/' + str(self.file)

    def dump(self):
        return 'File: ' + str(self.file) + '\n' + \
               '\tAttributes: ' + str(self.attributes) + '\n' + \
               '\tbuildDir:   ' + str(self.buildDir)


##
## This function should be replaced by proper descriptions of paths in the
## first place.  Given a path it searches for places the path might be found
## and returns a SCons File object.
##
## An error is triggered if the path can't be found.
##
def findBuildPath(fileHandle, modulePath):
    env = model.env
    root_dir = model.rootDir
    root_dir_path = root_dir.get_path() + '/'

    if (isinstance(fileHandle, SCons.Node.FS.File)):
        # Handle is a SCons path.
        return Source(fileHandle.get_path(), None)

    if (isinstance(fileHandle, Source)):
        file_name = fileHandle.file
    else:
        file_name = fileHandle

    file_obj = None

    if (os.path.isabs(file_name)):
        file_obj = env.File(file_name)
    else:
        if (file_name == os.path.basename(file_name)):
            if (file_name.endswith('.dic')):
                file_obj = root_dir.File('iface/src/dict/' + file_name)
            else:
                # File is just a base name.  Where is it?  This
                # hack should go away and files should always
                # be specified with paths.  For now, we have a
                # search list.
                try_prefixes = [ env['DEFS']['ROOT_DIR_HW'] + '/' + modulePath,
                                 env['DEFS']['ROOT_DIR_HW'] + '/' + modulePath + '/' + env['DEFS']['TMP_BSC_DIR'],
                                 env['DEFS']['ROOT_DIR_SW'] + '/' + modulePath,
                                 'iface/src/rrr/' + modulePath]

                for p in try_prefixes:
                    n = p + '/' + file_name
                    if (os.path.exists(root_dir_path + n)):
                        file_obj = root_dir.File(n)
                        break

            if (not file_obj): raise FileNotFound(file_name)

        elif (file_name.startswith('awb/')):
            # awb files are in the include tree
            file_obj = root_dir.File(env['DEFS']['ROOT_DIR_HW'] + '/include/' + file_name)
        elif (not file_name.startswith(root_dir_path)):
            # Prepend the root directory if it isn't there already
            file_obj = root_dir.File(file_name)
        else:
            file_obj = env.File(file_name)

    if (not file_obj):
        raise FileNotFound(file_name)

    file_path = file_obj.get_path()

    # Input was a file handle.  Return an updated handle.
    if (isinstance(fileHandle, Source)):
        return Source(file_path, fileHandle.attributes)

    return Source(file_path, None)


class FileNotFound(Exception):
    def __init__(self, arg):
        self.msg = arg

    def __str__(self):
        return repr(self.msg)
