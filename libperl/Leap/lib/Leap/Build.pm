
# *****************************************************************
# *                                                               *
# *   Copyright (c) (Fill in here)                                *
# *                                                               *
# *****************************************************************

#
# Author:  Martha Mercaldi
#

package Leap::Build;

use Asim;
use Asim::Module;
use Asim::Module::Source;

use Leap::Util;

use warnings;
use strict;
use File::Basename;

############################################################
# scons file functions
#
sub get_scons_root_template {
    my $model = shift;
    my $category = shift;

    my $root = $model->modelroot();

    return get_scons_template($root, $category);
}

sub get_scons_hw_sub_template {
    my $model = shift;
    my $module = shift;
    my $root = $model->modelroot();

    return get_scons_template($root, 'hw');
}

# This is an ugly way to get the library files, but I guess this is the best way??
sub get_scons_private {
    my $module = shift;
    return get_scons_subclass($module,'private');
}

sub get_scons_library {
    my $module = shift;
    return get_scons_subclass($module,'library');
}

sub get_scons_subclass {
    my $module = shift;
    my $subclass = shift;
    
    my @libraries = $module->scons($subclass);

    my @resolved_library;
    foreach my $library (@libraries) {
        my $library_path = Asim::resolve(Leap::Util::path_append($module->base_dir(),$library));
        push(@resolved_library, $library_path);
        # check for existence
        unless(-e $library_path) {
           my $module_name = $module->name; 
           print "Failed to find python library in module ${module_name}: ${library}, does it exist?\n";
           exit 0;
	}

    }
 
    return @resolved_library;
}

sub get_scons_template($$) {
    my $module = shift;
    my $category = shift;

    my $template; 

    ($template) = $module->scons($category);
    return undef if (! defined($template));

    return Asim::resolve(Leap::Util::path_append($module->base_dir(),$template));
}

############################################################
# get_makefile_include_template
sub get_makefile_include_template {
    my $model = shift;
    my $root = $model->modelroot();

    if (num_makefile_templates($root) == 1) {
        # Only a top template specified
        return undef;
    }

    if (num_makefile_templates($root) != 3) {
	Leap::Util::WARN_AND_DIE("In Leap, root module must specify three Makefile templates.");
    }

    return get_makefile_template($root,0);
}

############################################################
# get_makefile_top_template
sub get_makefile_top_template {
    my $model = shift;
    my $root = $model->modelroot();

    my $tNum = 0;
    if (num_makefile_templates($root) > 1) {
        $tNum = 1;
    }

    return get_makefile_template($root, $tNum);
}

############################################################
# get_makefile_sub_template
sub get_makefile_sub_template {
    my $model = shift;
    my $module = shift;
    my $root = $model->modelroot();

    if (num_makefile_templates($root) == 1) {
        # Only a top template specified
        return undef;
    }

    # if $module is root, or has no override. . .
    if ($module->issame($root) || num_makefile_templates($module) == 0) {
	return get_makefile_template($root,2);
    }

    return get_makefile_template($module,0);
}

############################################################
# num_makefile_templates 
sub num_makefile_templates {
    my $module = shift;
    my @templates = $module->makefile();
    return ($#templates + 1);
}

############################################################
# get_makefile_template
sub get_makefile_template {
    my $module = shift;
    my $idx = shift;

    my @templates = $module->makefile();

    if ($idx >= num_makefile_templates($module)) {
	Leap::Util::WARN_AND_DIE("No " . $idx . "-th makefile template in module with " . num_makefile_templates($module) . " templates.");
    }

    return Asim::resolve(Leap::Util::path_append($module->base_dir(),$templates[$idx]));
}

############################################################
# get_wrapper
sub get_wrapper {
    my $module = shift;
    
    if (! is_synthesis_boundary($module)) {
	Leap::Util::WARN_AND_DIE("Wrappers generated only for modules designated as synthesis boundaries.");
    }

    return ("mk_" . $module->provides . "_Wrapper");
}

############################################################
# check_submodules_defined: check that all submodules are
#                           defined in model
sub check_submodules_defined {
    my $module = shift;

    my @requires = $module->requires();
    my @submodules = $module->submodules();
    foreach my $index (0 .. $#requires) {
	my $m = $submodules[$index];
	my $r = $requires[$index];
	if (! defined($m)) {
	    Leap::Util::WARN("No implementation specified for module of type $r...");
	}
    }

    return 1;
}

############################################################
# get_module_build_dir: identify module's directory in the
#                       build tree (given parent directory path)
sub get_module_build_dir {
    my $module = shift;
    my $parent_dir = shift;
    my $my_dir;
    if (is_synthesis_boundary($module)) {
	$my_dir = Leap::Util::path_append($parent_dir, $module->provides());
    } else {
	$my_dir = $parent_dir;
    }
    return $my_dir;
}

############################################################
# get_module_build_dir: identify module's directory in the
#                       build tree (given parent directory path)
sub get_module_build_dir_from_module {
    my $module = shift;
    my $my_dir = "";

    #recurse
    if(!$module->isroot()) {
	$my_dir = get_module_build_dir_from_module($module->parent());
    }

    if (is_synthesis_boundary($module) || $module->isroot()) {
	$my_dir = Leap::Util::path_append($my_dir, $module->provides());
    } 
    
    return $my_dir;
}


############################################################
# get_synthesis_boundary_parent: identify the synthesis boundary 
#                                 directly above the module. 
#                                 
sub get_synthesis_boundary_parent {
    my $module = shift;

    if($module->isroot()) {
	return $module;
    }

    if (is_synthesis_boundary($module->parent())) {
	return $module->parent();
    } 
    
    return get_synthesis_boundary_parent($module->parent());
}

############################################################
# get_synthesis_boundary_children: identify the synthesis boundary 
#                                  children of a given module.
#                                  This only grabs direct descendents. 
#                                 
sub get_synthesis_boundary_children {
    my $module = shift;
    my @my_children = qw();

    foreach my $child ($module->submodules()) {
	if(is_synthesis_boundary($child)) {
	    push(@my_children,$child);
	} else {
            my @returnedChildren = get_synthesis_boundary_children($child); 
            foreach my $returnedChild (@returnedChildren) {
		push(@my_children, $returnedChild);
	    }
	}
    }

    return @my_children;
}

############################################################
# is_synthesis_boundary: reads Asim module's parameters to
#                        see if any Bluespec module is designated
#                        a synthesis boundary
sub is_synthesis_boundary {
    my $module = shift;

    foreach my $param_r ($module->parameters()) {
	my %param = %{$param_r};
	if ($param{'name'} eq "SYNTH_BOUNDARY") {
	    return 1;
	}
    }
    return 0;
}

############################################################
# get_compute_platform: reads Asim module's parameters to
#                       determine what synthesis boundary it belongs 
sub get_compute_platform {
    my $module = shift;
    
    if(!is_synthesis_boundary($module)) {
      Leap::Util::WARN_AND_DIE("get_compute_platform called on non-synthesis boundary module\n");
    }
    
    # Should default be used here?
    foreach my $param_r ($module->parameters()) {
        my %param = %{$param_r};
        if ($param{'name'} eq "COMPUTE_PLATFORM") {
            return $param{'default'};
        }
    }

    # otherwise return a special default value!
    return "Unknown";
}



############################################################
# synthesis_instances: How many copies of a synthesis boundary
#                      should be instantiated?
#
#                      Returns 0 if not specified.
sub synthesis_instances {
    my $module = shift;

    my @p = ();
    push(@p, $module->parameters());

    foreach my $p (@p) {
        if ($p->name() eq "SYNTH_INSTANCES") {
            return int($p->value());
        }
    }

    # Number of instances not specified
    return 0;
}

############################################################
# get_model_name
sub get_model_name {
    my $model = shift;
    my $apm_file = $model->filename();

    my @segments = split(/\//,$apm_file);
    my $name = $segments[$#segments];
    $name =~ s/.apm//g;

    return $name;
}

############################################################
# get_bdpi_names: reads awb Asim module's parameters and
#                 returns a list of BDPI-exported function
#                 names, if any
sub get_bdpi_names {
    my $module = shift;
    my @names = ();
    foreach my $param_r ($module->parameters()) {
        my %param = %{$param_r};
        if ($param{'name'} =~ "^BDPI_NAMES") {
            my @quotesstripped = split("\"", $param{'default'});
            push @names, split(" ", $quotesstripped[1]);
        }
    }
    return @names;
}

sub make_wrapper_name {
    my $name = shift;
  
    return $name . "_Wrapper";
}

sub make_instance_wrapper_name {
    my $name = shift;
    my $instance = shift;
  
    return "${name}_${instance}_Wrapper";
}

sub make_module_name {
    my $name = shift;
  
    return "mk_" . $name;
}

sub get_synthesis_boundary_name {
    my $module = shift;
    foreach my $param_r ($module->parameters()) {
	my %param = %{$param_r};
	if ($param{'name'} eq "SYNTH_BOUNDARY") {
	    return $param{'default'};
	}
    }

    Leap::Util::WARN_AND_DIE("get_synthesis_boundary_name called on non-synthesis boundary module\n");
}

sub get_synthesis_boundary_provides {
    my $module = shift;
    foreach my $param_r ($module->parameters()) {
	my %param = %{$param_r};
        my $name = $param{'name'};
        my $provides = $module->provides();

	if ($param{'name'} eq "${provides}_PROVIDES") {
            my $value = $param_r->value();
            my $info = "Checking $name against ${provides}_PROVIDES: $value\n";
            print STDERR $info;
	    return $value;
	}
    }

    return $module->provides();
}


####
#
# Convert module into nice string representation for python
# Unfortunately, I need to duplicate the code here due to the 
# generated/source differentiation.
#

sub pythonize_sources {
    my $module = shift;
    my $output = "{";

    # should I grab all the source?  I guess?
    # good target for refactoring
    foreach my $source_type ($module->sourcetypes()) {
        $output = $output . "\'GIVEN_${source_type}S\': [";
       
	my @sourceObjects = $module->sourceobjects($source_type,"*");
        my @sources_new = qw();
          
        for my $sourceObject (@sourceObjects) {

            my @sources = map { pythonize_canonical_sources($_, ${source_type}) }
                              $sourceObject->files();
   
            # do we have any attributes? If so, we need to output them here. 
            if(scalar(keys($sourceObject->getAllAttributes()))) {

                my @attributes = qw();

                while( my ($attributeKey, $attributeValue) = each $sourceObject->getAllAttributes() ) {
                    push(@attributes, "\'$attributeKey\': \'$attributeValue\' ");
                }

                my $attributesHash = "{" . join(", ", @attributes) . "}"; 

                for my $source (@sources) {
                    push(@sources_new, "Source.Source(\'".$source."\', " . $attributesHash . ")");
                } 

            } else {
                # No attributes, just emit an old-school file list, as
                # opposed to a new object.

                # dress up sources in quotes 
                for my $source (@sources) {
                    push(@sources_new, "\'".$source."\'");
                } 
                              
            }
        } 
         
        $output = $output . join(", ", @sources_new) . '],'; 
    }

    foreach my $source_type ($module->generatedtypes()) {
        $output = $output . "\'GEN_${source_type}S\': [";
	my @sources = $module->generated($source_type,"*");
        # dress up sources in quotes 
        my @sources_new = qw();
        for my $source (@sources) {
	    push(@sources_new, "\'".$source."\'");
        } 
        $output = $output . join(", ", @sources_new) . '],'; 
    }
    $output = $output . '}';

    return $output;
}


##
## Some final tweaks to correct paths. 
##
sub pythonize_canonical_sources {
    my $path = shift;
    my $source_type = shift;

    # For now we do nothing to the path
    return $path;
}

sub pythonize_module {
    my $module = shift;
 
    my $stringRepresentation = "Module( ";
  
    # dump name
    $stringRepresentation = $stringRepresentation . "\'" . $module->provides() ."\', ";   

    #if( is_synthesis_boundary($module)) {
    #    $stringRepresentation = $stringRepresentation . "\'" . get_synthesis_boundary_provides($module) ."\', ";
    #} else {
    #    $stringRepresentation = $stringRepresentation . "\'" . $module->provides() ."\', ";
    #}

    # Is it a synthesis boundary?

    if( is_synthesis_boundary($module)) {
	$stringRepresentation = $stringRepresentation . "[\"" . get_synthesis_boundary_name($module) ."\"], ";
    } else {
	$stringRepresentation = $stringRepresentation . "[], ";
    }

    # get build dir get_module_build_dir_from_module
    $stringRepresentation = $stringRepresentation . "\'" . get_module_build_dir_from_module($module) . "\', ";

    # all modules have parents/children.  We'll preserve this structure
    # because it will make life easier in the python
    # get parent synthesis boundary 
    if($module->isroot()) {
	$stringRepresentation = $stringRepresentation ."\'\'" .",";
    } 
    else {
	my $parent =  $module->parent();
	$stringRepresentation = $stringRepresentation . "\'" . $parent->provides() ."\',";
    }


    $stringRepresentation = $stringRepresentation . "[ ";

    my @children = $module->submodules();

    for(my $index = 0; $index < scalar(@children); $index = $index + 1) {      
	$stringRepresentation = $stringRepresentation . "\'" . $children[$index]->provides() ."\'"; 
	if($index + 1 < scalar(@children)) {
	    $stringRepresentation = $stringRepresentation . ",";
	}
    }
    $stringRepresentation = $stringRepresentation . " ], ";

    #synthesis boundaries are special

    if(is_synthesis_boundary($module)) {
	# get parent synthesis boundary 
	if($module->isroot()) {
	    $stringRepresentation = $stringRepresentation ."\'\'" .",";
	} 
	else {
	    my $parent =  get_synthesis_boundary_parent($module);
	    $stringRepresentation = $stringRepresentation . "\'" . $parent->provides() ."\',";
	}
	$stringRepresentation = $stringRepresentation . "[ ";
	
	my @children = get_synthesis_boundary_children($module);
	
	for(my $index = 0; $index < scalar(@children); $index = $index + 1) {      
	    $stringRepresentation = $stringRepresentation . "\'" . $children[$index]->provides() ."\'"; 
	    if($index + 1 < scalar(@children)) {
		$stringRepresentation = $stringRepresentation . ",";
	    }
	}
    
	$stringRepresentation = $stringRepresentation . " ] ";
    } else {
	$stringRepresentation = $stringRepresentation . "\'null\', []";
    }

    # now for the hard part  we must represent the source and generated files for the 
    # given module.  
    $stringRepresentation = $stringRepresentation . ", " . pythonize_sources($module);


    if( is_synthesis_boundary($module)) {
        $stringRepresentation = $stringRepresentation . ", boundaryName=\'" . get_synthesis_boundary_provides($module) ."\' ";
    } 

    $stringRepresentation = $stringRepresentation . " ), ";

    return $stringRepresentation;
}

####
#
#  Find the kind of host that we're on
#

sub host_defs {

    my $hostos = `uname -s`;
    my $hostmachine = `uname -m`;
    my $hflags = "";

    if ($hostos eq "FreeBSD") {
        $hflags = "-DHOST_FREEBSD";
    }
    else {
        $hflags = "-DHOST_LINUX";
	if ($hostmachine eq "ia64") {
            $hflags .= " -DHOST_LINUX_IA64";
	}
	else {
            $hflags .= " -DHOST_LINUX_X86";
	}
    }
    return $hflags;
}

return 1;
