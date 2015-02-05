# -*-Python-*-
import os
import ProjectDependency 
import CommandLine
import Source
import Utils

class Module(ProjectDependency.ProjectDependency):

  # Global counter for generating synthesis boundary UIDs
  lastSynthId = 0

  def dump(self):
    print "Module: " + self.name + "\n"
    print "\tBuildPath: " + self.buildPath + "\n"
    ProjectDependency.ProjectDependency.dump(self)
 
  
  def __init__(self, name, synthBoundary, buildPath, parent, childArray, synthParent, synthChildArray, sources, platformModule=False):
    self.name = name
    self.buildPath = buildPath
    self.parent = parent
    self.childArray = childArray
    self.liIgnore = False
    self.platformModule = platformModule
    self.dependsFile = '.depends-bsv'
    self.interfaceType = 'Empty'
    self.extraImports = []

    self.attributes = {}

    self.isSynthBoundary = (synthBoundary != [])
    if(self.isSynthBoundary):
      self.synthBoundaryModule = synthBoundary[0]

      # Generate a UID for the synthesis boundary.  Top level is
      # always 0.  this UID assignment is a little bit broken. It
      # needs to consider the UID variables passed in from the top
      # level.
      if (parent == '' or platformModule):
        self.synthBoundaryUID = 0
      else:
        Module.lastSynthId += 1
        self.synthBoundaryUID = Module.lastSynthId

    else:
      self.synthBoundaryModule = ""

    self.synthParent = synthParent
    self.synthChildArray = synthChildArray
    ProjectDependency.ProjectDependency.__init__(self)
    # grab the deps from source lists. 
    # we don't insert the special generated files that awb 
    # seems to generate.  these should be inserted by
    # downstream tools 
    self.moduleDependency = sources 


    # Annotate source objects with path information
    for sourceType in self.moduleDependency:
        for source in self.moduleDependency[sourceType]:
            if (isinstance(source, Source.Source)):
                source.attributes['buildPath'] = buildPath
          
    # Make empty EMPTY_params_override Bluespec and C files.  When a module
    # has no overrides, its override file will link to this file.  We could
    # have simply linked to /dev/null, but tar --dereference simply eliminates
    # files linked to /dev/null.  We sometimes want to tar a build tree and
    # send it to Bluespec.
    empty_path = 'hw/include/awb/provides/EMPTY_params_override.bsh'
    if not os.path.exists(empty_path):
      f = open(empty_path, 'w')
      f.close()
    empty_path = 'sw/include/awb/provides/EMPTY_params_override.h'
    if not os.path.exists(empty_path):
      f = open(empty_path, 'w')
      f.close()

  def getDependencies(self, key):
    # we must check to see if the dependencies actually exist.                                                                                                                                                                              
    # generally we have to make sure to remove duplicates                                                                                                                                                                                   
    allDeps = []
    if(self.moduleDependency.has_key(key)):
      for dep in self.moduleDependency[key]:
        if(allDeps.count(dep) == 0):
          allDeps.extend(dep if isinstance(dep, list) else [dep])

    # Return a list of unique entries, in the process converting SCons                                                                                                                                                                      
    # dependence entries to strings.                                                                  
    return list(set([dep for dep in ProjectDependency.convertDependencies(allDeps)]))


  def wrapperName(self):
    if('WRAPPER_NAME' in self.attributes):
        return self.attributes['WRAPPER_NAME']
    return 'mk_' + self.name + '_Wrapper'


  def putAttribute(self, key, value):
      self.attributes[key] = value

  def appendAttribute(self, key, value):
      Utils.dictionary_list_create_append(self.attributes,key,value)
      
  def getAttribute(self, key):
      if(key in self.attributes):
          return self.attributes[key]
      else:
          return None

  def moduleDependencyCopy(self):
      newModuleDependency = {}
      for depType in self.moduleDependency:
          newModuleDependency[depType] = []
          for dep in self.moduleDependency[depType]:
              newModuleDependency[depType].append(dep)
      return newModuleDependency
                              
  ##
  ## parseAWBParams --
  ##   AWB parameters are stored in leap-configure in each module's config.py.
  ##   Load them here as a dictionary, allow for replacement of parameter
  ##   values on the build command line.
  ##
  def parseAWBParams(self):
    found_override = False;
    hw_path = 'hw/include/awb/provides/' + self.name + '_params_override.bsh'
    sw_path = 'sw/include/awb/provides/' + self.name + '_params_override.h'

    try:
      p = __import__(self.name + '.config')

      # Replace with command line arguments
      for k, v in p.config.awbParams.iteritems():
        if k in arguments and v != arguments[k]:
          # Force the type of the override to match the type of the original
          if type(v) is str:
            new_val = str(arguments[k])
          else:
            new_val = int(arguments[k])

          # Generate the header files if this is the first override
          # for the module.
          if not found_override:
            found_override = self.initOverrideFiles(hw_path, sw_path)

          # Replace the old value with the new one
          p.config.awbParams[k] = new_val
          self.overrideAWBParam(k, new_val, type(v) is str)

      params = p.config.awbParams

    except ImportError:
      # Should check whether module exists or whether it is some other error
      params = {}

    if not found_override and emitOverrideFiles:
      self.linkToEmptyOverrideFile('EMPTY_params_override.bsh', hw_path)
      self.linkToEmptyOverrideFile('EMPTY_params_override.h', sw_path)

    return params

  def cleanAWBParams(self):    
    hw_path = 'hw/include/awb/provides/' + self.name + '_params_override.bsh'
    sw_path = 'sw/include/awb/provides/' + self.name + '_params_override.h'
    # on a clean kill the override files.
    os.system('rm -f ' + hw_path)
    os.system('rm -f ' + sw_path)



  ##
  ## linkToEmptyOverrideFile --
  ##   For files with no overrides we link to an empty file instead of generating
  ##   a unique empty file for each module.  This reduces file caching pressure.
  ##
  def linkToEmptyOverrideFile(self, empty_path, path):
    # Already exists from last build?
    if os.path.lexists(path):
      # Empty?  If not, it is wrong.
      st_size = 1
      try:
        st_size = os.stat(path).st_size
      except:
        None

      if st_size > 0:
        os.unlink(path)
        os.symlink(empty_path, path)
    else:
      os.symlink(empty_path, path)


  ##
  ## initOverrideFiles --
  ##   Initialize override include files for a single module.
  ##
  def initOverrideFiles(self, hw_path, sw_path):
    if not emitOverrideFiles:
      return False

    # Don't override build pipeline parameters in order to avoid rebuilding
    # sources.  We don't want to force recompilation due to the
    # BUILD_PIPELINE_DEBUG switch change.
    if self.name == 'build_pipeline':
      return False

    # Generate parameter override header files
    try:
      os.unlink(hw_path)
    except:
      None
    param_bsh = open(hw_path, 'w')
    param_bsh.write('//\n')
    param_bsh.write('// AWB parameter overrides generated by Module.py Python build rules\n')
    param_bsh.write('//\n\n')
    param_bsh.close()

    try:
      os.unlink(sw_path)
    except:
      None
    param_h = open(sw_path, 'w')
    param_h.write('//\n')
    param_h.write('// AWB parameter overrides generated by Module.py Python build rules\n')
    param_h.write('//\n\n')
    param_h.close()

    return True


  ##
  ## overrideAWBParam --
  ##   AWB parameter value was overridden on the SCons command line.  Add the
  ##   new value to the override include files.
  ##
  def overrideAWBParam(self, param, value, is_str):
    if not emitOverrideFiles:
      return

    # Don't override build pipeline parameters in order to avoid rebuilding
    # sources.  We don't want to force recompilation due to the
    # BUILD_PIPELINE_DEBUG switch change.
    if self.name == 'build_pipeline':
      return

    # Make sure string is quoted
    value = str(value)
    if is_str:
      if (value[0] != '"' or value[-1] != '"'):
        value = '"' + value + '"'

    print 'Overriding AWB parameter ' + self.name + '.' + param + ': ' + value

    param_bsh = open('hw/include/awb/provides/' + self.name + '_params_override.bsh', 'a')
    param_bsh.write('`undef ' + param + '\n')
    param_bsh.write('`undef ' + param + '_Z\n')
    param_bsh.write('`define ' + param + ' ' + value + '\n')
    if (value == 0 or value == '0'):
      param_bsh.write('`define ' + param + '_Z 0\n')
    param_bsh.close()

    param_h = open('sw/include/awb/provides/' + self.name + '_params_override.h', 'a')
    param_h.write('#undef ' + param + '\n')
    param_h.write('#define ' + param + ' ' + value + '\n')
    param_h.close()

  ## Base object methods
  def __str__(self): return str(self.name)

  def __lt__(self, other): return self.name <  other.name
  def __le__(self, other): return self.name <= other.name
  def __eq__(self, other): return self.name == other.name
  def __ne__(self, other): return self.name != other.name
  def __gt__(self, other): return self.name >  other.name
  def __ge__(self, other): return self.name >= other.name  

  def __hash__(self): return self.name.__hash__()


##
## initAWBParamParser --
##   Perpare for AWB parameter parsing.
##
def initAWBParamParser(args, emit_override_files):
  global arguments
  arguments = args

  global emitOverrideFiles
  emitOverrideFiles = emit_override_files


