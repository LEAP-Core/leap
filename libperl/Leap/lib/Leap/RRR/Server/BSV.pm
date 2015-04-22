# *****************************************************************************
# * BSV.pm
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

package Leap::RRR::Server::BSV;

use warnings;
use strict;
use re 'eval';

use Leap::RRR::Server::Base;
use Leap::RRR::Method::Base;
use Leap::RRR::Method::BSV;

# inherit from Server
our @ISA = qw(Leap::RRR::Server::Base);

my $debug = 1;

##
## constructor
##
sub new
{
    # get name of class
    my $class = shift;

    # get pointer to untyped server
    my $server = shift;

    # get list of untyped methods
    my @methodlist = @_;

    # typecast and insert the method list
    _addmethods($server, @methodlist);

    # typecast the object itself
    bless ($server, $class);

    # return typed object
    return $server;
}

##
## take a method list, create a BSV-type method from each of these,
## and add the typed methods to the server's method list
##
sub _addmethods
{
    my $server     = shift;
    my @methodlist = @_;

    # initialize server's methodlist
    @{ $server->{methodlist} } = ();

    # for each method in given list
    foreach my $method (@methodlist)
    {
        # create a new BSV-type method
        my $bsv_method = Leap::RRR::Method::BSV->new($method);

        # add the typed method to the server's list
        push(@{ $server->{methodlist} }, $bsv_method);
    }
}

##
## print stub into a given file in bsv
##
sub print_stub
{
    # capture params
    my $self   = shift;
    my $file   = shift;

    # make sure it's a Bluespec target
    if ($self->{lang} ne "bsv")
    {
        die "BSV server asked to print non-BSV stub: " . $self->{lang};
    }

    # determine if we should write stub at all
    if ($#{ $self->{methodlist} } == -1)
    {
        return;
    }

    # header, defines and includes
    print $file "//\n";
    print $file "// Synthesized server stub file\n";
    print $file "//\n";
    print $file "\n";

    print $file "`ifndef _" . $self->{name} . "_SERVER_STUB_\n";
    print $file "`define _" . $self->{name} . "_SERVER_STUB_\n";
    print $file "\n";

    print $file "import Vector::*;\n";

    if ($self->{ifc} eq "connection")
    {
        print $file "`include \"awb/provides/soft_connections.bsh\"\n";
    }
    print $file "`include \"awb/provides/librl_bsv_base.bsh\"\n";
    print $file "`include \"awb/provides/rrr_common.bsh\"\n";
    print $file "`include \"awb/provides/umf.bsh\"\n";
    print $file "\n";
    print $file "`include \"awb/rrr/service_ids.bsh\"\n";
    print $file "\n";

    # compute max request and response bitwidths
    my $maxinsize = 0;
    my $maxoutsize = 0;
    my @list = @{ $self->{methodlist} };
    foreach my $method (@list)
    {
        if ($method->inargs()->size() > $maxinsize)
        {
            $maxinsize = $method->inargs()->size();
        }
        
        if ($method->outargs()->size() > $maxoutsize)
        {
            $maxoutsize = $method->outargs()->size();
        }
    }

    # helper definition for service ID
    print $file "`define SERVICE_ID `" . $self->{name} ."_SERVICE_ID\n";
    print $file "\n";

    # types for each method
    foreach my $method (@{ $self->{methodlist} })
    {
        $method->print_types($file);
    }

    # interface ...
    print $file "interface ServerStub_" . $self->{name} . ";\n";

    # indent
    my $indent = "    ";

    # interface entry for each method
    foreach my $method (@{ $self->{methodlist} })
    {
        $method->print_accept_request_declaration($file, $indent, $self->{ifc});
        $method->print_send_response_declaration($file, $indent, $self->{ifc});
    }
    
    # expose a debug interface.
    print $file "`ifndef ENABLE_RRR_DEBUG_INTERFACE_Z\n";
    print $file "    interface RRR_SERVER_DEBUG debug;\n";
    print $file "`endif\n";
    print $file "\n";

    # endinterface
    print $file "endinterface\n";

    # module mk...
    if ($self->{ifc} eq "connection")
    {
        print $file "module [CONNECTED_MODULE] mkServerStub_" . $self->{name};
    }
    else
    {
        print $file "module mkServerStub_" . $self->{name} . "#(RRR_SERVER server)";
    }
    print $file " (ServerStub_" . $self->{name} . ")\n";
    print $file "\n";
    
    # print out provisos
    print $file "provisos(\n";
 
    # Each incoming method has a number of chunks which it needs use for truncation
    foreach my $method (@{ $self->{methodlist} })
    {
        $method->print_server_provisos($file, $indent);
    }

    print $file "\tDiv#($maxinsize,SizeOf#(UMF_CHUNK), n_CHUNKS));\n";

    # global state
    $self->_print_state($file, $maxinsize, $maxoutsize);
    
    my $totalMethods = scalar(@{ $self->{methodlist} });
    # print the total number of methods, for debugging. 
    print $file $indent . "Integer total_methods = $totalMethods;\n";    
    print $file $indent . "Integer method_chunks[$totalMethods];\n";    

    # per-method state and definitions
    my $methodID = 0;
    foreach my $method (@{ $self->{methodlist} })
    {
        $method->print_server_state($file, $indent, $methodID);
        $methodID = $methodID + 1;
    }

    print $file "\n";    
                            
    # global (i.e., not RRR-method-specific) rules
    $self->_print_request_rules($file);
    if ($maxoutsize != 0)
    {
        $self->_print_response_rules($file);
    }

    # method definitions
    foreach my $method (@{ $self->{methodlist} })
    {
        $method->print_accept_request_definition($file, $indent, $self->{ifc});
        $method->print_send_response_definition($file, $indent, $self->{ifc});
    }
    
    # debug interface
    print $file "`ifndef ENABLE_RRR_DEBUG_INTERFACE_Z\n";
    print $file "    interface RRR_SERVER_DEBUG debug;\n";
    print $file "        method RRR_DEMARSHALLER_STATE demarshallerState();\n";
    print $file "            return dem.getState();\n";
    print $file "        endmethod\n";
    print $file "\n";
    print $file "        method Bool notEmpty();\n";
    print $file "            return dem.notEmpty();\n";
    print $file "        endmethod\n";
    print $file "\n";
    print $file "        method UMF_METHOD_ID methodID();\n";
    print $file "            return mid;\n";
    print $file "        endmethod\n";
    print $file "\n";
    print $file "        method Bool misroutedPacket();\n";
    print $file "            return misroutedPacketReg;\n";
    print $file "        endmethod\n";
    print $file "\n";
    print $file "        method Bool illegalMethod();\n";
    print $file "            return illegalMethodReg;\n";
    print $file "        endmethod\n";
    print $file "\n";
    print $file "        method Bool incorrectLength();\n";
    print $file "            return incorrectLengthReg;\n";
    print $file "        endmethod\n";
    print $file "\n";
    print $file "        method String serviceName();\n";
    print $file "            return \"" . $self->{name}."\";\n";
    print $file "        endmethod\n";
    print $file "    endinterface\n";
    print $file "\n";
    print $file "`endif\n";
    print $file "\n";

    # endmodule
    print $file "endmodule\n";
    print $file "\n";

    # closing stamements
    print $file "`endif\n";
    print $file "\n";
}

#
# print global stub module state
#
sub _print_state
{
    my $self = shift;
    my $file = shift;

    my $maxinsize  = shift;
    my $maxoutsize = shift;

    if ($self->{ifc} eq "connection")
    {
        print $file "    Connection_Receive#(UMF_PACKET) link_req  <- mkConnection_Receive(\"rrr_server_" .
            $self->{name} . "_req\");\n";
        print $file "    Connection_Send#(UMF_PACKET)    link_resp <- mkConnection_Send(\"rrr_server_" .
            $self->{name} . "_resp\");\n";
        print $file "\n";
    }

    print $file "    RRR_DEMARSHALLER#(UMF_CHUNK, Vector#(n_CHUNKS,UMF_CHUNK)) dem <- mkRRRDemarshaller();\n";
    if ($maxoutsize != 0)
    {
        print $file "    MARSHALLER_N#(UMF_CHUNK, Bit#($maxoutsize)) mar <- mkSimpleMarshallerN(True);\n";
    }
    print $file "\n";
    print $file "    Reg#(UMF_METHOD_ID) mid <- mkReg(0);\n";

    print $file "    Reg#(Bool) misroutedPacketReg  <- mkReg(False);\n";
    print $file "    Reg#(Bool) illegalMethodReg    <- mkReg(False);\n";
    print $file "    Reg#(Bool) incorrectLengthReg  <- mkReg(False);\n";

}

#
# print global request rules for a service module
#
sub _print_request_rules
{
    my $self = shift;
    my $file = shift;

    print $file "    rule startRequest (True);\n";
    if ($self->{ifc} eq "connection")
    {
        print $file "        UMF_PACKET packet = link_req.receive();\n";
        print $file "        link_req.deq();\n";
    }
    else
    {
        print $file "        UMF_PACKET packet <- server.requestPorts[`SERVICE_ID].read();\n";
    }

    # Add some sanity checks, in case we have breakage.        
    print $file "        if(packet.UMF_PACKET_header.serviceID != `SERVICE_ID)\n";
    print $file "        begin\n";
    print $file "            \$display(\"Misrouted Packet at service %d: %h\", `SERVICE_ID, packet);\n\n";
    print $file "            misroutedPacketReg <= True;\n";
    print $file "            \$finish;\n";
    print $file "        end\n";

    print $file "        if(packet.UMF_PACKET_header.methodID >= fromInteger(total_methods))\n";
    print $file "        begin\n";
    print $file "            \$display(\"Illegal Method ID %d at service %d: %h\", packet.UMF_PACKET_header.methodID, `SERVICE_ID, packet);\n\n";
    print $file "            illegalMethodReg <= True;\n";
    print $file "            \$finish;\n";
    print $file "        end\n";

    print $file "        if(packet.UMF_PACKET_header.numChunks != fromInteger(method_chunks[packet.UMF_PACKET_header.methodID]))\n";
    print $file "        begin\n";
    print $file "            \$display(\"Unexpected packet size Method ID %d at service %d. Size was %d, expected %d: %h\", packet.UMF_PACKET_header.methodID, `SERVICE_ID, packet.UMF_PACKET_header.numChunks, method_chunks[packet.UMF_PACKET_header.methodID], packet);\n\n";
    print $file "            incorrectLengthReg <= True;\n";
    print $file "            \$finish;\n";
    print $file "        end\n";


    print $file "        mid <= packet.UMF_PACKET_header.methodID;\n";
    print $file "        dem.start(packet.UMF_PACKET_header.numChunks);\n";
    print $file "    endrule\n";
    print $file "\n";
    
    print $file "    rule continueRequest (True);\n";
    if ($self->{ifc} eq "connection")
    {
        print $file "        UMF_PACKET packet = link_req.receive();\n";
        print $file "        link_req.deq();\n";        
    }
    else
    {
        print $file "        UMF_PACKET packet <- server.requestPorts[`SERVICE_ID].read();\n";
    }
    print $file "        dem.insert(packet.UMF_PACKET_dataChunk);\n";
    print $file "    endrule\n";
    print $file "\n";
}

#
# print global response rules for a service module
#
sub _print_response_rules
{
    my $self = shift;
    my $file = shift;

    print $file "    rule continueResponse (True);\n";
    print $file "        UMF_CHUNK chunk = mar.first();\n";
    print $file "        mar.deq();\n";
    if ($self->{ifc} eq "connection")
    {
        print $file "        link_resp.send(tagged UMF_PACKET_dataChunk chunk);\n";
    }
    else
    {
        print $file "        server.responsePorts[`SERVICE_ID].write(tagged UMF_PACKET_dataChunk chunk);\n";
    }
    print $file "    endrule\n";
    print $file "\n";
}

#
# print connection instantiations for wrapper server_connections module
# in platform interface
#
sub print_connections
{
    my $self   = shift;
    my $file   = shift;
    my $indent = shift;

    # verify that RRR file requested a connection for this server
    if ($self->{ifc} eq "connection")
    {
        my $name = $self->{name};

        # request connection
        print $file "$indent Connection_Send#(UMF_PACKET)    link_server_$name\_req  <- " .
                    "mkConnection_Send(\"rrr_server_$name\_req\");\n";

        # response connection
        print $file "$indent Connection_Receive#(UMF_PACKET) link_server_$name\_resp <- " .
                    "mkConnection_Receive(\"rrr_server_$name\_resp\");\n";
    }
    else
    {
        # error
        die "cannot print connections for \"method\" type servers";
    }
}

#
# print link rules
#
sub print_link_rules
{
    my $self   = shift;
    my $file   = shift;
    my $indent = shift;

    # check if RRR file requested a connection for this server
    if ($self->{ifc} eq "connection")
    {
        my $name = $self->{name};

        print $file "$indent rule server_$name\_req (True);\n";
        print $file "$indent     let chunk <- server.requestPorts[`$name\_SERVICE_ID].read();\n";
        print $file "$indent     link_server_$name\_req.send(chunk);\n";
        print $file "$indent endrule\n";
        print $file "\n";

        print $file "$indent rule server_$name\_resp (True);\n";
        print $file "$indent     server.responsePorts[`$name\_SERVICE_ID].write(link_server_$name\_resp.receive());\n";
        print $file "$indent     link_server_$name\_resp.deq();\n";
        print $file "$indent endrule\n";
        print $file "\n";
    }
}

1;
