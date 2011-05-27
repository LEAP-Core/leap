# *****************************************************************************
# * Service.pm
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

package Leap::RRR::Service;

use warnings;
use strict;
use re 'eval';

use Text::Balanced;

use Leap::RRR::Collection;
use Leap::RRR::Server::Base;
use Leap::RRR::Client::Base;

# regex
my $REGEX = qr/
                  .*?
                  service \s*
                  (\S+?)
                  \s*
                  (\{)
                  (.*)
              /x;

##
## constructor: this is an unusual constructor. It returns
## not a single object of type Service, but a list of objects
## of type Service. All other member functions operate on a
## single object.
##
sub new
{
    # get name of class
    my $class = shift;

    # get string to parse
    my $string = shift;

    # parse string into multiple services
    my @objlist = _parse($string);

    # typecast each entry in list
    foreach my $obj (@objlist)
    {
        bless ($obj, $class);
    }

    # return list of objects
    return @objlist;
}

##
## accept a string and parse it into a list of services
##
sub _parse
{
    # string
    my $string = shift;

    # create an empty list of services
    my @servicelist = ();

    # parse
    while ($string =~ /$REGEX/) # note: NOT /$REGEX/g
    {
        # create a new service
        my $service;

        # extract a service name
        $service->{name} = $1;

        # capture the remainder of the string
        my $remainder = $2 . $3;

        # extract one service body, destroying $remainder in the
        # process and leaving all code after the captured service
        # body in the new $remainder
        my $body = Text::Balanced::extract_bracketed($remainder, '{}');

        # parse body into a list of collections 
        my @collectionlist = Leap::RRR::Collection->new($body);

        # re-arrange collections into a lists of clients and servers
        my @serverlist = Leap::RRR::Server::Base->new($service->{name}, @collectionlist);
        my @clientlist = Leap::RRR::Client::Base->new($service->{name}, @collectionlist);

        # add client and server lists to service
        push (@{ $service->{serverlist} }, @serverlist);
        push (@{ $service->{clientlist} }, @clientlist);

        # add service to service list
        push(@servicelist, $service);

        # set residue as the new string to parse, and continue
        $string = $remainder;
    }

    # return service list
    return @servicelist;
}

##
## return the name
##
sub name
{
    my $self = shift;

    return $self->{name};
}

##
## return the list of servers
##
sub serverlist
{
    my $self = shift;

    return $self->{serverlist};
}

##
## return the list of clients
##
sub clientlist
{
    my $self = shift;

    return $self->{clientlist};
}

######################################
#       SERVER STUB GENERATION       #
######################################

##
## print server stub for a given target into a given file
##
sub print_server_stub
{
    # capture params
    my $self   = shift;
    my $file   = shift;
    my $target = shift;

    # for each entry in my list of servers...
    foreach my $server (@{ $self->{serverlist} })
    {
        # look for the specified target name. It is guaranteed that
        # each server in this list will have a unique target name.
        if ($server->target() eq $target)
        {
            # ask the server to print out a stub
            $server->print_stub($file);
        }

        # NOTE: we are guaranteed to only print one stub
        # for a given target
    }
}

##
## print server stub for a given target into a given file (ViCo mode)
##
sub print_server_stub_vico
{
    # capture params
    my $self   = shift;
    my $file   = shift;
    my $target = shift;

    # for each entry in my list of servers...
    foreach my $server (@{ $self->{serverlist} })
    {
        # look for the specified target name. It is guaranteed that
        # each server in this list will have a unique target name.
        if ($server->target() eq $target)
        {
            # ask the server to print out a stub
            $server->print_stub_vico($file);
        }

        # NOTE: we are guaranteed to only print one stub
        # for a given target
    }
}

##
## do we need to generate a server connections for this service and target?
##
sub needs_server_connections
{
    # capture params
    my $self   = shift;
    my $target = shift;

    # for each entry in my list of servers...
    foreach my $server (@{ $self->{serverlist} })
    {
        # look for the specified target name. It is guaranteed that
        # each server in this list will have a unique target name.
        if ($server->target() eq $target)
        {
            # now check type of server interface
            if ($server->interface() eq "connection")
            {
                return 1;
            }
            else
            {
                return 0;
            }
        }

        # NOTE: we are guaranteed to only print one stub
        # for a given target
    }

    # no match found, return false
    return 0;
}   

##
## print server connections for a given target into a given file
##
sub print_server_connections
{
    my $self   = shift;
    my $file   = shift;
    my $indent = shift;
    my $target = shift;

    # for each entry in my list of servers...
    foreach my $server (@{ $self->{serverlist} })
    {
        # look for the specified target name. It is guaranteed that
        # each server in this list will have a unique target name.
        if ($server->target() eq $target && $server->interface() eq "connection")
        {
            # ask the server to print out a connection instantiation
            $server->print_connections($file, $indent);
        }

        # NOTE: we are guaranteed to only print one connection
        # for a given target
    }
}

##
## print server link rules for a given target into a given file
##
sub print_server_link_rules
{
    my $self   = shift;
    my $file   = shift;
    my $indent = shift;
    my $target = shift;

    # for each entry in my list of servers...
    foreach my $server (@{ $self->{serverlist} })
    {
        # look for the specified target name. It is guaranteed that
        # each server in this list will have a unique target name.
        if ($server->target() eq $target && $server->interface() eq "connection")
        {
            # ask the server to print out a wrapper rule
            $server->print_link_rules($file, $indent);
        }

        # NOTE: we are guaranteed to only print one rule
        # for a given target
    }
}

######################################
#       CLIENT STUB GENERATION       #
######################################

##
## print client stub for a given target into a given file
##
sub print_client_stub
{
    # capture params
    my $self   = shift;
    my $file   = shift;
    my $target = shift;

    # for each entry in my list of clients...
    foreach my $client (@{ $self->{clientlist} })
    {
        # look for the specified target name. It is guaranteed that
        # each client in this list will have a unique target name.
        if ($client->target() eq $target)
        {
            # ask the client to print out a stub
            $client->print_stub($file);
        }

        # NOTE: we are guaranteed to only print one stub
        # for a given target
    }
}

##
## print client stub for a given target into a given file
##
sub print_client_stub_vico
{
    # capture params
    my $self   = shift;
    my $file   = shift;
    my $target = shift;

    # for each entry in my list of clients...
    foreach my $client (@{ $self->{clientlist} })
    {
        # look for the specified target name. It is guaranteed that
        # each client in this list will have a unique target name.
        if ($client->target() eq $target)
        {
            # ask the client to print out a stub
            $client->print_stub_vico($file);
        }

        # NOTE: we are guaranteed to only print one stub
        # for a given target
    }
}

##
## do we need to generate a client connections for this service and target?
##
sub needs_client_connections
{
    # capture params
    my $self   = shift;
    my $target = shift;

    # for each entry in my list of clients...
    foreach my $client (@{ $self->{clientlist} })
    {
        # look for the specified target name. It is guaranteed that
        # each client in this list will have a unique target name.
        if ($client->target() eq $target)
        {
            # now check type of client interface
            if ($client->interface() eq "connection")
            {
                return 1;
            }
            else
            {
                return 0;
            }
        }

        # NOTE: we are guaranteed to only print one stub
        # for a given target
    }

    # no match found, return false
    return 0;
}   

##
## print client connections for a given target into a given file
##
sub print_client_connections
{
    my $self   = shift;
    my $file   = shift;
    my $indent = shift;
    my $target = shift;

    # for each entry in my list of clients...
    foreach my $client (@{ $self->{clientlist} })
    {
        # look for the specified target name. It is guaranteed that
        # each client in this list will have a unique target name.
        if ($client->target() eq $target && $client->interface() eq "connection")
        {
            # ask the client to print out a connection instantiation
            $client->print_connections($file, $indent);
        }

        # NOTE: we are guaranteed to only print one connection
        # for a given target
    }
}

##
## print client link rules for a given target into a given file
##
sub print_client_link_rules
{
    my $self   = shift;
    my $file   = shift;
    my $indent = shift;
    my $target = shift;

    # for each entry in my list of clients...
    foreach my $client (@{ $self->{clientlist} })
    {
        # look for the specified target name. It is guaranteed that
        # each client in this list will have a unique target name.
        if ($client->target() eq $target && $client->interface() eq "connection")
        {
            # ask the client to print out a wrapper rule
            $client->print_link_rules($file, $indent);
        }

        # NOTE: we are guaranteed to only print one rule
        # for a given target
    }
}

1;
