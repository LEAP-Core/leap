# -*-Python-*-
import ProjectDependency 

class Module(ProjectDependency.ProjectDependency):

  # Global counter for generating synthesis boundary UIDs
  lastSynthId = 0

  def dump(self):
    print "Module: " + self.name + "\n"
    print "\tBuildPath: " + self.buildPath + "\n"
    ProjectDependency.ProjectDependency.dump(self)

  
  def __init__(self, name, synthBoundary, buildPath, computePlatform, parent, childArray, synthParent, synthChildArray, sources):
    self.name = name
    self.buildPath = buildPath
    self.parent = parent
    self.childArray = childArray
    self.isSynthBoundary = (synthBoundary != [])
    if(self.isSynthBoundary):
      self.synthBoundaryModule = synthBoundary[0]

      # Generate a UID for the synthesis boundary.  Top level is always 0.
      if (parent == ''):
        self.synthBoundaryUID = 0
      else:
        Module.lastSynthId += 1
        self.synthBoundaryUID = Module.lastSynthId
    else:
      self.synthBoundaryModule = ""
    self.synthParent = synthParent
    self.synthChildArray = synthChildArray
    self.computePlatform = computePlatform
    ProjectDependency.ProjectDependency.__init__(self)
    # grab the deps from source lists. 
    # we don't insert the special generated files that awb 
    # seems to generate.  these should be inserted by
    # downstream tools 
    self.moduleDependency = sources 
          

  def wrapperName(self):
    return 'mk_' + self.name + '_Wrapper'
                              
  ##
  ## parseAWBParams --
  ##   AWB parameters are stored in leap-configure in each module's config.py.
  ##   Load them here as a dictionary, allow for replacement of parameter
  ##   values on the build command line.
  ##
  def parseAWBParams(self):
    self.initOverrideFile()

    try:
      p = __import__(self.name + '.config')

      # Replace with command line arguments
      for k, v in p.config.awbParams.iteritems():
        if k in arguments and v != arguments[k]:
          if type(v) is str:
            new_val = str(arguments[k])
          else:
            new_val = int(arguments[k])

          p.config.awbParams[k] = new_val
          self.overrideAWBParam(k, new_val, type(v) is str)

      return p.config.awbParams

    except ImportError:
      # Should check whether module exists or whether it is some other error
      return {}


  ##
  ## initOverrideFile --
  ##   Initialize override include files for a single module.
  ##
  def initOverrideFile(self):
    if not emitOverrideFiles:
      return

    # Generate parameter override header files
    param_bsh = open('hw/include/awb/provides/' + self.name + '_params_override.bsh', 'w')
    param_bsh.write('//\n')
    param_bsh.write('// AWB parameter overrides generated by Module.py Python build rules\n')
    param_bsh.write('//\n\n')
    param_bsh.close()

    param_h = open('sw/include/awb/provides/' + self.name + '_params_override.h', 'w')
    param_h.write('//\n')
    param_h.write('// AWB parameter overrides generated by Module.py Python build rules\n')
    param_h.write('//\n\n')
    param_h.close()


  ##
  ## overrideAWBParam --
  ##   AWB parameter value was overridden on the SCons command line.  Add the
  ##   new value to the override include files.
  ##
  def overrideAWBParam(self, param, value, is_str):
    if not emitOverrideFiles:
      return

    # Make sure string is quoted
    value = str(value)
    if is_str:
      if (value[0] != '"' or value[-1] != '"'):
        value = '"' + value + '"'

    print 'Overriding AWB parameter ' + param + ': ' + value

    param_bsh = open('hw/include/awb/provides/' + self.name + '_params_override.bsh', 'a')
    param_bsh.write('`undef ' + param + '\n')
    param_bsh.write('`undef ' + param + '_Z\n')
    param_bsh.write('`define ' + param + ' ' + value + '\n')
    if (value == 0):
      param_bsh.write('`define ' + param + '_Z 0\n')
    param_bsh.close()

    param_h = open('sw/include/awb/provides/' + self.name + '_params_override.h', 'a')
    param_h.write('#undef ' + param + '\n')
    param_h.write('#define ' + param + ' ' + value + '\n')
    param_h.close()


##
## initAWBParamParser --
##   Perpare for AWB parameter parsing.
##
def initAWBParamParser(args, emit_override_files):
  global arguments
  arguments = args

  global emitOverrideFiles
  emitOverrideFiles = emit_override_files
