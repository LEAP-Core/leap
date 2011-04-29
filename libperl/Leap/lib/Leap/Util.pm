
# *****************************************************************
# *                                                               *
# *   Copyright (c) (Fill in here)                                *
# *                                                               *
# *****************************************************************

#
# Author:  Martha Mercaldi
#

package Leap::Util;

use warnings;
use strict;

############################################################
# path_append: simple utility to directory paths
sub path_append {
    my @parts = @_;

    my $result = "";
    foreach my $part (@parts) {
	if (! defined($result) || ($result eq "")) {
	    $result = $part;
	} elsif ($part eq "") {
	    # skip this part
	} else {
	    $result = $result . "/" . $part;
	}
    }

    return $result;
}

############################################################
# empty_hash_ref: produce a ref to a new empty hash table
sub empty_hash_ref {
    my %hash = ();
    return \%hash;
}

############################################################
# hash_set: set a key,value pair in given hash table
sub hash_set {
    my $hash_r = shift;
    my $key = shift;
    my $value = shift;

    $hash_r->{$key} = $value;

    return 1;
}

############################################################
# hash_append: append a value to the value already present
#              in the given hash table (using the given 
#              separator)
sub hash_append {
    my $hash_r = shift;
    my $separator = shift;
    my $key = shift;
    my $value = shift;
    
    if (exists $hash_r->{$key}) { 
	$hash_r->{$key} = $hash_r->{$key} . $separator . $value;
    } else {
	$hash_r->{$key} = $value;
    }

    return 1;
}



############################################################
# common_replacements: Replacement strings common
#     to all levels of makefiles.
sub common_replacements($$) {
    my $model = shift;
    my $replacements_r = shift;

    __hash_module_parameters($model->modelroot(), $replacements_r);

    # @WORKSPACE_ROOT@
    my $workspace_root = `awb-resolver --config=workspace`;
    chomp($workspace_root);
    Leap::Util::hash_set($replacements_r,'@WORKSPACE_ROOT@',$workspace_root);

    # @APM_NAME@
    my $apm = Leap::Build::get_model_name($model);
    Leap::Util::hash_set($replacements_r,'@APM_NAME@',$apm);

    # @TMP_XILINX_DIR@
    Leap::Util::hash_set($replacements_r,'@TMP_XILINX_DIR@',$Leap::Xilinx::tmp_xilinx_dir);

    # @TMP_BSC_DIR@
    Leap::Util::hash_set($replacements_r,'@TMP_BSC_DIR@',$Leap::Bluespec::tmp_bsc_dir);

    # @CONNECTION_SCRIPT@
#    hash_set($replacements_r,'@CONNECTION_SCRIPT@',Asim::resolve("tools/scripts/leap-connect"));

    # @APM_FILE@
    Leap::Util::hash_set($replacements_r,'@APM_FILE@',$model->filename());

    # @BSC@
    Leap::Util::hash_set($replacements_r,'@BSC@','bsc');

    # remove-dollar kills simulation builds
    Leap::Util::hash_set($replacements_r,'@BSC_FLAGS_VERILOG@',
                          ' -steps 10000000 +RTS -K1000M -RTS -keep-fires -aggressive-conditions -wait-for-license -no-show-method-conf -no-opt-bool -licenseWarning 7 -elab -show-schedule -verilog -remove-dollar ');

    # remove-dollar kills simulation builds
    Leap::Util::hash_set($replacements_r,'@BSC_FLAGS_SIM@',
                          ' -steps 10000000 +RTS -K1000M -RTS -keep-fires -aggressive-conditions -wait-for-license -no-show-method-conf -no-opt-bool -licenseWarning 7 -elab -show-schedule ');


}

# Add all parameters from the model to replacement strings
sub __hash_module_parameters {
    my $module = shift;
    my $replacements_r = shift;

    #
    # Walk down the module tree BEFORE adding this modules parameters.  That
    # way definitions higher in the tree override lower ones.
    #
    foreach my $child ($module->submodules()) {
	__hash_module_parameters($child, $replacements_r);
    }

    my @p = ();
    push(@p, $module->parameters());
    foreach my $p (@p) {
        my $v = $p->value();
        # Strip quotation marks surrounding strings
        $v =~ s/^"(.*)"$/$1/;
        Leap::Util::hash_set($replacements_r, '@' . $p->name() . '@', $v);
    }
}


############################################################
# WARN
sub WARN {
    my $msg = shift;
    my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask) = caller(2);
    print STDERR "${package}::${subroutine}: (called from ${filename}:${line}): ${msg}\n";
}

############################################################
# WARN_AND_DIE
sub WARN_AND_DIE {
    my $msg = shift;
    WARN("\n\n$msg\n");
    die;
}

return 1;
