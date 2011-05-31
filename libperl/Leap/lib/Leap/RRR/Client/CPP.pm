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

package Leap::RRR::Client::CPP;

use warnings;
use strict;
use re 'eval';

use Leap::RRR::Client::Base;
use Leap::RRR::Method::Base;

# inherit from Client
our @ISA = qw(Leap::RRR::Client::Base);

##
## constructor
##
sub new
{
    # get name of class
    my $class = shift;

    # get pointer to untyped client
    my $client = shift;

    # get list of untyped methods
    my @methodlist = @_;

    # typecast and insert the method list
    _addmethods($client, @methodlist);

    # typecast the object itself
    bless ($client, $class);

    # return typed object
    return $client;
}

##
## take a method list, create a CPP-type method from each of these,
## and add the typed methods to the client's method list
##
sub _addmethods
{
    my $client     = shift;
    my @methodlist = @_;

    # initialize client's methodlist
    @{ $client->{methodlist} } = ();

    # for each method in given list
    foreach my $method (@methodlist)
    {
        # create a new CPP-type method
        my $cpp_method = Leap::RRR::Method::CPP->new($method, $client->{name});

        # add the typed method to the client's list
        push(@{ $client->{methodlist} }, $cpp_method);
    }
}

##
## print stub into a given file in cpp
##
sub print_stub
{
    # capture params
    my $self   = shift;
    my $file   = shift;

    # make sure it's a Bluespec target
    if ($self->{lang} ne "cpp")
    {
        die "CPP client asked to print non-CPP stub: " . $self->{lang};
    } 

    # determine if we should write stub at all
    if ($#{ $self->{methodlist} } == -1)
    {
        return;
    }

    # defines and includes
    print $file "#ifndef __" . $self->name() . "_CLIENT_STUB__\n";
    print $file "#define __" . $self->name() . "_CLIENT_STUB__\n";
    print $file "\n";

    print $file "#include \"awb/provides/low_level_platform_interface.h\"\n";
    print $file "#include \"awb/provides/rrr.h\"\n";
    print $file "#include \"awb/rrr/service_ids.h\"\n";
    print $file "\n";
    
    # assign method IDs
    my $methodID = 0;
    foreach my $method (@{ $self->{methodlist} })
    {
        print $file "#define " . $self->name() . "_METHOD_ID_" . $method->name() . " $methodID\n";
        $methodID = $methodID + 1;
    }
    print $file "\n";

    # other generic stuff
    print $file "using namespace std;\n";
    print $file "\n";

    # print types
    foreach my $method (@{ $self->{methodlist} })
    {
        $method->print_types($file);
    }
    print $file "\n";

    # start creating the client class
    print $file "typedef class " . $self->name() . "_CLIENT_STUB_CLASS* " . $self->name() . "_CLIENT_STUB;\n";
    print $file "class " . $self->name() . "_CLIENT_STUB_CLASS: public PLATFORMS_MODULE_CLASS\n";
    print $file "{\n";
    print $file "\n";

    print $file "  private:\n";
    print $file "\n";

    print $file "  public:\n";
    print $file "\n";

    # constructor
    print $file "    " . $self->name() . "_CLIENT_STUB_CLASS(PLATFORMS_MODULE p) :\n";
    print $file "            PLATFORMS_MODULE_CLASS(p)\n";
    print $file "    {\n";
    print $file "    }\n";
    print $file "\n";

    # destructor
    print $file "    ~" . $self->name() . "_CLIENT_STUB_CLASS()\n";
    print $file "    {\n";
    print $file "    }\n";

    # client methods
    foreach my $method (@{ $self->{methodlist} })
    {
        print $file "\n";
        $method->print_client_definition($file, "    ");
    }

    # close the class
    print $file "};\n";
    print $file "\n";

    # end the stub file
    print $file "#endif\n";
}


##
## print stub into a given file in cpp
##
sub print_stub_vico
{
    # capture params
    my $self   = shift;
    my $file   = shift;

    # make sure it's a Bluespec target
    if ($self->{lang} ne "cpp")
    {
        die "CPP client asked to print non-CPP stub: " . $self->{lang};
    } 

    # determine if we should write stub at all
    if ($#{ $self->{methodlist} } == -1)
    {
        return;
    }

    # defines and includes
    print $file "#ifndef __" . $self->name() . "_CLIENT_STUB__\n";
    print $file "#define __" . $self->name() . "_CLIENT_STUB__\n";
    print $file "\n";

    print $file "#include \"asim/restricted/vico_rrr_layer.h\"\n";
    print $file "\n";

    print $file "VICO_RRR_CLIENT_START_TDEFS(" . $self->name() . ")\n";
    
    # print types
    foreach my $method (@{ $self->{methodlist} })
    {
        $method->print_types($file);
    }
    print $file "\n";
    print $file "VICO_RRR_CLIENT_END_TDEFS(" . $self->name() . ")\n";

    # start creating the client class
    print $file "VICO_RRR_CLIENT_START_CLASS(" . $self->name() . ")\n";

    # client methods
    foreach my $method (@{ $self->{methodlist} })
    {
        print $file "\n";
        $method->print_client_definition_vico($file, "    ");
    }

    print $file "VICO_RRR_CLIENT_START_METHODS_LIST(" . $self->name() . ")\n";
    foreach my $method (@{ $self->{methodlist} })
    {
        $method->print_client_list_entry_vico($file, "    ");
    }
    print $file "VICO_RRR_CLIENT_END_METHODS_LIST(" . $self->name() . ")\n";

    # close the class
    print $file "VICO_RRR_CLIENT_END_CLASS(" . $self->name() . ")\n";

    # end the stub file
    print $file "#endif\n";
}

1;
