# *****************************************************************************
# * Collection.pm
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
#

package Leap::RRR::Collection;

use warnings;
use strict;
use re 'eval';

use Leap::RRR::Method::Base;

# regex: parsing a collection is relatively easy since
# it is at the leaf-level of a balanced-braces hierarchy
my $REGEX = qr/
                  \s*?
                  server \s*?
                  (\S+)
                  \s*? \( \s*?
                  (\S+)
                  \s*? , \s*?
                  (\S+)
                  \s*? \) \s*? <- \s*?
                  (\S+)
                  \s*? \( \s*?
                  (\S+)
                  \s*? , \s*?
                  (\S+)
                  \s*? \) \s*?
                  \{
                  (.*?)
                  \}
                  \s*?
                  ;
                  \s*?
              /x;

# constructor: this is an unusual constructor. It returns
# not a single object of type Collection, but a list of objects
# of type Collection. All other member functions operate on a
# single object.
sub new
{
    # get name of class
    my $class = shift;

    # get string to parse
    my $string = shift;

    # parse string into multiple methods
    my @objlist = _parse($string);

    # typecast each entry in list
    foreach my $obj (@objlist)
    {
        bless ($obj, $class);
    }

    # return list of objects
    return @objlist;
}

# accept a string and parse it into a list of Collections
sub _parse
{
    # string
    my $string = shift;

    # create an empty list of collections
    my @collectionlist = ();

    # parse
    while ($string =~ /$REGEX/g)
    {
        # create a new collection
        my $collection;

        # set targets
        $collection->{server_target} = $1;
        $collection->{server_lang} = $2;
        $collection->{server_ifc}  = $3;

        $collection->{client_target} = $4;
        $collection->{client_lang} = $5;
        $collection->{client_ifc}  = $6;

        # parse body of collection into list of methods
        push(@{ $collection->{methodlist} }, Leap::RRR::Method::Base->new($7));

        # add collection to list
        push(@collectionlist, $collection);
    }
    
    # return list
    return @collectionlist;
}

# return the server target name
sub server_target
{
    my $self = shift;

    return $self->{server_target};
}

# return the server implementation language
sub server_lang
{
    my $self = shift;

    return $self->{server_lang};
}

# return the server interface type
sub server_ifc
{
    my $self = shift;

    return $self->{server_ifc};
}

# return the client target name
sub client_target
{
    my $self = shift;

    return $self->{client_target};
}

# return the client implementation language
sub client_lang
{
    my $self = shift;

    return $self->{client_lang};
}

# return the client interface type
sub client_ifc
{
    my $self = shift;

    return $self->{client_ifc};
}

# return the list of methods
sub methodlist
{
    my $self = shift;

    return $self->{methodlist};
}

1;
