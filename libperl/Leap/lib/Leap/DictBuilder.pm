package Leap::DictBuilder;

#
# Copyright (C) 2008 Intel Corporation
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
# 
#

#
# Author: Michael Adler
#

use strict;
use warnings;

sub new($) {
    my $self = {};
    my $name = shift;

    $self->{NAME} = $name;
    $self->{DEFS} = undef;
    $self->{SUBDICTS} = undef;
    $self->{BASE_IDX} = -1;
    $self->{TOTAL_BITS} = 0;
    $self->{TOTAL_ENTRIES} = 0;

    bless($self);
    return $self;
}

sub GetName($) {
    my $self = shift;
    return $self->{NAME};
}

sub GetSortedEntries($) {
    my $self = shift;
    my @entries;

    return sort keys %{$self->{DEFS}};
}

sub GetDefinition($$) {
    my $self = shift;
    my $entry = shift;

    if (exists($self->{DEFS}{$entry})) {
        return $self->{DEFS}{$entry};
    }
    else {
        return undef;
    }
}

sub GetSortedDictionaryNames($) {
    my $self = shift;
    my @names;

    return sort keys %{$self->{SUBDICTS}};
}

sub GetDictionary($$) {
    my $self = shift;
    my $name = shift;

    if (exists($self->{SUBDICTS}{$name})) {
        return $self->{SUBDICTS}{$name}
    }
    else {
        return undef;
    }
}

##
## GetNumEntries --
##   Return the number of entries for the given dictionary.
##
sub GetNumEntries($) {
    my $self = shift;

    my @e = keys %{$self->{DEFS}};
    return (scalar @e);
}

##
## GetNumDictionariesInTree --
##   Return the total number of subdictionaries under the given dictionary.
##
sub GetNumDictionariesInTree($) {
    my $self = shift;

    my $n = 1;
    foreach my $subName (keys %{$self->{SUBDICTS}}) {
        my $sd = $self->GetDictionary($subName);
        $n += $sd->GetNumDictionariesInTree();
    }

    return $n;
}

sub GetBaseIdx($) {
    my $self = shift;
    return $self->{BASE_IDX};
}

sub GetTotalNumBits($) {
    my $self = shift;
    return $self->{TOTAL_BITS};
}

sub GetTotalNumEntries($) {
    my $self = shift;
    return $self->{TOTAL_ENTRIES};
}

sub GetOrAddDictionary($$) {
    my $self = shift;
    my $name = shift;

    my $d = $self->GetDictionary($name);
    if (! defined($d)) {
        $d = new($name);
        $self->AddDictionary($d);
    }

    return $d;
}

sub AddDictionary($$) {
    my $self = shift;
    my $dict = shift;

    my $name = $dict->GetName();
    if (exists($self->{SUBDICTS}{$name})) {
        return -1;
    }

    $self->{SUBDICTS}{$name} = $dict;
    return 0;
}

sub AddDefinition($$$) {
    my $self = shift;
    my $entry = shift;
    my $value = shift;

    if (exists($self->{DEFS}{$entry})) {
        # Error -- entry already exists
        return -1;
    }

    $self->{DEFS}{$entry} = $value;
    return 0;
}

sub SetBaseIdx($$) {
    my $self = shift;
    my $uid = shift;

    $self->{BASE_IDX} = $uid;
}

sub SetTotalNumBits($$) {
    my $self = shift;
    my $bits = shift;

    $self->{TOTAL_BITS} = $bits;
}

sub SetTotalNumEntries($$) {
    my $self = shift;
    my $e = shift;

    $self->{TOTAL_ENTRIES} = $e;
}

1;

=head1 NAME

DictBuilder class supporting building of Leap dictionaries

=head1 SYNOPSIS

    use Leap::DictBuilder;

    #################
    # Class Methods #
    #################
    $ob = Leap::DictBuilder->new("<dictionary name>");

    #######################
    # Object Data Methods #
    #######################

    ### Get Versions ###
    $name = $ob->GetName();
    @entries = $ob->GetSortedEntries();
    $def = $ob->GetDefinition("<entry>");
    @subdict = $ob->GetSortedDictionaryNames();
    $dict = $ob->GetDictionary("<name>");
    $uid = $ob->GetBaseIdx();
    $n = $ob->GetTotalNumBits();

    ### Set/Get Versions (Add entry if one isn't already present) ###
    $dict = $ob->GetOrAddDictionary("<name>");

    ### Set Versions ###
    $ob->AddDictionary($sub_ob);
    $ob->AddDefinition("<entry>", "<value>");
    $ob->SetBaseIdx(<integer uid>);
    $ob->SetTotalNumBits(<min bits for storing entry id>);

=head1 DESCRIPTION

The dictionary builder class is used by the leap-dict script.  The class
simplifies the internal storage while building hierarchical dictionaries.
