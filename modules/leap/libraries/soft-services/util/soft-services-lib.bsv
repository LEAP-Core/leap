//
// Copyright (C) 2010 Massachusetts Institute of Technology
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//

import HList::*;
import ModuleContext::*;


// Generally useful definitions

// Typeclass to describe individual contexts i.e. SoftClock, SoftConnections
// This requires two types: 
// A) the context, 
// B) the intermediate interface at synth boundaries

typeclass SOFT_SERVICE#(type t_CONTEXT);

    // Initialize a context. This is a module so it can expose resets and clocks.
    module initializeServiceContext (t_CONTEXT);

    // At the top-level synthesis boundary this is invoked. 
    module finalizeServiceContext#(t_CONTEXT data) ();

endtypeclass

typeclass SYNTHESIZABLE_SOFT_SERVICE#(type t_CONTEXT, type t_INTERMEDIATE_IFC)
    dependencies (t_CONTEXT determines t_INTERMEDIATE_IFC);

    // At a smart synthesis boundary, convert the context into an intermediate interface.
    // Presumably this also uses messageM to output data which is parsed by leap-connect.
    module exposeServiceContext#(t_CONTEXT data) (t_INTERMEDIATE_IFC);
    
    // After a smart sythesis boundary, take the interface from exposeContext, plus the
    // data generated by leap-connect, and turn it back into a context.
    // NOTE: This job is handled by leap-connect, so this function doesn't need to exist.
    //module [SOFT_SERVICES_MODULE] buryServiceContext#(t_INTERMEDIATE_IFC ifc, t_REBURY data) ();

endtypeclass

interface WITH_SERVICES#(parameter type t_INTERMEDIATE_IFC, parameter type t_IFC);

    interface t_INTERMEDIATE_IFC services;
    interface t_IFC device;

endinterface

module [t_CONTEXT] instantiateWithConnections#(ModuleContext#(t_SS_CTX, Empty) m) 
    // interface: 
        ()
    provisos
        (SOFT_SERVICE#(t_SS_CTX),
         IsModule#(t_CONTEXT, t_DUMMY),
         ContextRun#(t_CONTEXT, t_SS_CTX, t_SS_CTX));

    t_SS_CTX ctx <- initializeServiceContext();
    // By convention m_final is Empty.
    match {.final_ctx, .m_final} <- runWithContext(ctx, m);
    finalizeServiceContext(final_ctx);

endmodule

module [t_CONTEXT] instantiateSmartBoundary#(ModuleContext#(t_SS_CTX, t_IFC) m) 
    // interface:
        (WITH_SERVICES#(t_INTERMEDIATE_IFC, t_IFC))
    provisos 
        (SYNTHESIZABLE_SOFT_SERVICE#(t_SS_CTX, t_INTERMEDIATE_IFC),
         SOFT_SERVICE#(t_SS_CTX),
         IsModule#(t_CONTEXT, t_DUMMY),
         ContextRun#(t_CONTEXT, t_SS_CTX, t_SS_CTX));

    // Instantiate the module and get the resulting context.
    t_SS_CTX ctx <- initializeServiceContext();
    match {.final_ctx, .m_final} <- runWithContext(ctx, m);
    t_INTERMEDIATE_IFC service_ifc <- exposeServiceContext(final_ctx);

    interface services = service_ifc;
    interface device = m_final;

endmodule


// Any HList can be a soft service, assuming the members of the list are.
instance SOFT_SERVICE#(HCons#(t_CONTEXT, t_REST_OF_LIST))
    provisos 
        (SOFT_SERVICE#(t_CONTEXT),
         SOFT_SERVICE#(t_REST_OF_LIST));

    module initializeServiceContext (HCons#(t_CONTEXT, t_REST_OF_LIST) ctx_list);
      t_CONTEXT context1 <- initializeServiceContext();
      t_REST_OF_LIST ctx_rest <- initializeServiceContext();
      return hCons(context1, ctx_rest);
    endmodule

    module finalizeServiceContext#(HCons#(t_CONTEXT, t_REST_OF_LIST) ctx_list) ();
        t_CONTEXT ctx = hHead(ctx_list);
        finalizeServiceContext(ctx);
        finalizeServiceContext(hTail(ctx_list));
    endmodule

endinstance

// HNil is the tail case of the HList. 
// It's an empty soft service.

instance SOFT_SERVICE#(HNil);

    module initializeServiceContext (HNil data);
    endmodule

    module finalizeServiceContext#(HNil data) ();
    endmodule

endinstance

// We can synthesize any HList by replacing every HCons with Tuple2.

instance SYNTHESIZABLE_SOFT_SERVICE#(HCons#(t_CONTEXT, t_REST_OF_LIST), Tuple2#(t_INTERMEDIATE_IFC, t_REST_IFC))
    provisos (SYNTHESIZABLE_SOFT_SERVICE#(t_CONTEXT, t_INTERMEDIATE_IFC),
              SYNTHESIZABLE_SOFT_SERVICE#(t_REST_OF_LIST, t_REST_IFC));

    module exposeServiceContext#(HCons#(t_CONTEXT, t_REST_OF_LIST) ctx_list) (Tuple2#(t_INTERMEDIATE_IFC, t_REST_IFC));
        t_CONTEXT ctx = hHead(ctx_list);
        t_INTERMEDIATE_IFC ifc1 <- exposeServiceContext(ctx);
        t_REST_IFC ifc_rest <- exposeServiceContext(hTail(ctx_list));
        return tuple2(ifc1, ifc_rest);
    endmodule

endinstance

// HNil is the tail case of the HList. 
// It has no intermediate interface.

instance SYNTHESIZABLE_SOFT_SERVICE#(HNil, Empty);

    module exposeServiceContext#(HNil data) (Empty);
    endmodule

endinstance
