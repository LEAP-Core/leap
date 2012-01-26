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
                              
