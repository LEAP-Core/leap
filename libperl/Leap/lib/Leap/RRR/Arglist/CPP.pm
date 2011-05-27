# *****************************************************************************
# * CPP.pm
# *
# * Copyright (C) 2008 Intel Corporation
# *
# * This program is free software; you can redistribute it and/or
# * modify it under the terms of the GNU General Public License
# * as published by the Free Software Foundation; either version 2
# * of the License, or (at your option) any later version.
# *
# * This program is distributed in the hope that it will be useful,
# * but WITHOUT ANY WARRANTY; without even the implied warranty of
# * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# * GNU General Public License for more details.
# *
# * You should have received a copy of the GNU General Public License
# * along with this program; if not, write to the Free Software
# * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
# *
# *****************************************************************************

#
# Author:  Angshuman Parashar
#          Roman Khvatov      (added ViCo mode support)
#

package Leap::RRR::Arglist::CPP;

use warnings;
use strict;
use re 'eval';

use Leap::RRR::Arglist::Base;

# inherit from Arglist
our @ISA = qw(Leap::RRR::Arglist::Base);

##
## constructor
##
sub new
{
    # get name of class
    my $class = shift;

    # get pointer to untyped arglist
    my $arglist = shift;

    # create a new typed method
    my $typed_arglist = _semi_deep_copy($arglist);

    # typecast the object
    bless ($typed_arglist, $class);

    # return typed object
    return $typed_arglist;
}

##
## create a new arglist hash by copying over the contents
## of the input hash
##
sub _semi_deep_copy
{
    my $source = shift;

    # copy all fields. Note that in many cases we are merely
    # copying the references to the objects in the original hash,
    # which is exactly what we want.
    my $target;

    $target->{direction} = $source->{direction};
    if (defined(@{ $source->{args} }))
    {
        push(@{ $target->{args} }, @{ $source->{args} });
    }

    return $target;
}


##
## return true if type is simple (not structure)
##
sub is_singletype
{
    my $self = shift;
    return ($#{ $self->{args} } == 0);
}


##
## return a type string for the lone element in the arg list
## (only applicable to arg lists with 1 entry)
##
sub singletype
{
    my $self = shift;

    # 1 arg in list
    if ($#{ $self->{args} } == 0)
    {
        # return raw arg without packing it into a struct
        my ($arg, @rest) = @{ $self->{args} };
        return $arg->type()->string_cpp();
    }
    else
    {
        return "void";
    }
}

##
## create a struct out of the elements in the arglist
##
sub makestruct
{
    my $self = shift;

    # 0 args in list
    if ($#{ $self->{args} } < 1)
    {
        die "makestruct called on arglist with < 2 arguments";
    }

    # pack into a struct
    my $string = "struct\n" .
                 "{\n";
    
    foreach my $arg (@{ $self->{args} })
    {
        $string = $string . "    " . $arg->string_cpp() . ";\n";
    }

    $string = $string . "}\n";

    return $string;
}

##
## create a string with the list of args
##
sub makelist
{
    my $self = shift;

    my $string = "";

    if ($#{ $self->{args} } >= 0)
    {
        # first argument
        my ($first, @rest) = @{ $self->{args} };
        
        $string = $first->string_cpp();

        # remainder
        foreach my $arg (@rest)
        {
            $string = $string . ", " . $arg->string_cpp();
        }
    }

    return $string;
}

##
## create a string with the list of args without types
##
sub makecalllist
{
    my $self = shift;

    my $string = "";

    if ($#{ $self->{args} } >= 0)
    {
        # first argument
        my ($first, @rest) = @{ $self->{args} };
        
        $string = $first->name()->string();

        # remainder
        foreach my $arg (@rest)
        {
            $string = $string . ", " . $arg->name()->string();
        }
    }

    return $string;
}

##
## crerate a string with unpack code (ViCo)
##
sub makeunp_vico
{
    my $self = shift;
    my $dlm  = shift;

    my @rv;
    my $acc_width=0;
    my $total_width=$self->bitsize();

    foreach my $arg (@{ $self->{args} })
    {
    	my $width = $arg->type()->size_bsv();
    	push(@rv,$arg->string_cpp() ."= VICO_RRR_UNP($width,$acc_width,$total_width);");
    	$acc_width+=$width;
    }
    return join($dlm,@rv);
}

##
## crerate a string with cpy code (ViCo)
##
sub makecpy_vico
{
    my $self = shift;
    my $pref = shift;
    my $dlm  = shift;

    my @rv;

    if ($self->is_singletype())
    {
        	push(@rv,$pref." = ".$self->{args}->[0]->name()->string());
    }
    else
    {
        foreach my $arg (@{ $self->{args} })
        {
        	push(@rv,$pref.'.'.$arg->name()->string() ." = ". $arg->name()->string().";");
        }
    }
    return join($dlm,@rv);
}

sub makepck_vico
{
    my $self = shift;
    my $pref = shift;
    my $dlm  = shift;

    my @rv;
    my $acc_width=0;
    my $total_width=$self->bitsize();

    foreach my $arg (@{ $self->{args} })
    {
    	my $width = $arg->type()->size_bsv();
    	unless ($pref)
    	{
	    	push(@rv,'VICO_RRR_PCK('.$arg->name()->string().",$width,$acc_width,$total_width);");
    	}
    	elsif ($self->is_singletype())
    	{
	    	push(@rv,"VICO_RRR_PCK($pref,$width,$acc_width,$total_width);");
    	}
    	else
    	{
	    	push(@rv,"VICO_RRR_PCK($pref.".$arg->name()->string().",$width,$acc_width,$total_width);");
	    }
    	$acc_width+=$width;
    }
    return join($dlm,@rv);
}

##
## return the total size of args
##
sub size
{
    my $self = shift;

    my $size = 0;
    foreach my $arg (@{ $self->{args} })
    {
        $size = $size + $arg->type()->size_cpp();
    }

    return $size;
}

1;
