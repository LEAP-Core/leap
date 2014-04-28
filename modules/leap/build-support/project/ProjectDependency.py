# -*-Python-*-
import SCons.Node
from compiler.ast import flatten


class ProjectDependency:

    def dump(self):
        print "Deps: \n"     
        for key in self.moduleDependency:
            print key + ": "
            #need to case on types here, I guess
            for dep in self.moduleDependency[key]:
                print dep      
            print "\n" 

    def __init__(self):
        # don't do anything here
        # but this is needed to make the inheritance happy 
        self.moduleDependency = {}

    

# This function is used to scrub the project dependency lists into a
# true list of file names.  It takes in a list of containing a mix of
# python base types and SCons types and attempts to distill these into
# a single list of files.
def convertDependencies(depList):

    # This function deals with nested types. It returns either an
    # empty list of a list containing a singleton string. Since types
    # can be recursive, this function is also recursive. 
    def filterRecursive(depObj):
        if(isinstance(depObj, list)):
            return map(filterRecursive, depObj)
        elif (isinstance(depObj, str)):
            return [depObj]
        elif (isinstance(depObj, SCons.Node.NodeList)):
            return map(filterRecursive, depObj)
        # A precursor to FS.Entry.
        elif (isinstance(depObj, SCons.Node.FS.Entry)):
            return [str(depObj)]        
        elif (isinstance(depObj, SCons.Node.FS.File)):
            return [str(depObj)]    
        else:
            print "I don't know what to do with " + str(depObj) + ' type ' + str(type(depObj))
            exit(0)        
        
    
    depList = map(filterRecursive, depList)
    depList = flatten(depList)

    return depList
