//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

//
// @file libli.cpp
// @brief LI implementation
//
// @author Daniel Lustig
//

#include <cstdlib>
#include <iostream>
#include <fstream>
#include <ctime>
#include <li.hpp>

/*
int main()
{
	if (!li::context)
		exit(1);

	// Have the library connect any named LINCs, and validate the result
	li::Elaborate();

	// Perform the user-defined instantiation and connections
	li::Route();

	// Launch the module schedulers, and run until the workload completes
	li::Execute();
}
*/
namespace li
{
	std::stringstream verbose;
	std::stringstream messages;
	std::stringstream warnings;
	std::stringstream errors;

	/**********************************************************************/

	Context::Context() : globally_quiescing(false), globally_finished(false)
	{
		active_modules = 0;
	}

	Context::~Context()
	{
	}

	void Context::Route()
	{
		std::set<void (*)()>::iterator iter;
		for (iter = typed_linc_maps_routers.begin();
				iter != typed_linc_maps_routers.end(); iter++)
		{
			(*iter)();
		}

		std::ofstream log("libli-runtime.log", std::ofstream::app);

		if (!log.good())
		{
			std::cerr << "[LIBLI] Could not open log file" << std::endl;
			return;
		}

		std::cerr << "[LIBLI] Logging to libli-runtime.log" << std::endl;

		time_t current_time;
		time(&current_time);
		log << "LIBLI Log for " << ctime(&current_time) << '\n';

		if (errors.str().size())
			log << "Errors:\n" << errors.str() << '\n';
		if (warnings.str().size())
			log << "Warnings:\n" << warnings.str() << '\n';
		if (messages.str().size())
			log << "Messages:\n" << messages.str() << '\n';
		if (verbose.str().size()) {}
			log << "Verbose Messages:\n" << verbose.str() << '\n';

		log << "\nEnd of Elaboration Messages for elaboration starting at " <<
			ctime(&current_time) << std::endl;
	}

	void Context::Execute()
	{
		std::cerr << "[LIBLI] Beginning Execution" << std::endl;

		std::set<void (*)()>::iterator iter;
		for (iter = typed_scheduler_set_spawners.begin();
				iter != typed_scheduler_set_spawners.end(); iter++)
		{
			(*iter)();
		}

		while (active_modules > 0)
		{
			std::cerr << "[LIBLI]" << active_modules << " active modules" << std::endl;
			usleep(1000000);
		}

		std::cerr << "[LIBLI]Ending Execution" << std::endl;
	}

	void Context::Quiesce()
	{
		globally_quiescing = true;
	}

	bool Context::Quiescing() const
	{
		return globally_quiescing;
	}

	void Context::Finish()
	{
		globally_finished = true;
	}

	bool Context::Finished() const
	{
		return globally_finished;
	}

	void Context::IncrementModuleCount()
	{
		active_modules++;
	}

	void Context::DecrementModuleCount()
	{
		active_modules--;
	}

	/**********************************************************************/

	void Elaborate()
	{
		context->Elaborate();
	}

	void Route()
	{
		context->Route();
	}

	void Execute()
	{
		context->Execute();
	}

	void Quiesce()
	{
		context->Quiesce();
	}

	void Finish()
	{
		context->Finish();
	}

	/**********************************************************************/

	class Printer
	{
		public:
			Printer(std::ostream &out, const char *name, bool active = true) :
				out(out), active(active)
			{
				li::Scheduler<Printer> *s =
					new StaticPriorityScheduler<Printer>(this);
				s->RegisterRule(&Printer::CanPrint, &Printer::DoPrint);

				li::Name(messages, name);
			}

		private:
			bool CanPrint() const
			{
				return !messages.IsEmpty();
			}

			void DoPrint()
			{
				if (active)
					out << messages.Peek() << std::endl;
				messages.Dequeue();
			}

			li::Unbounded_LINC_RECV<std::string> messages;
			std::ostream &out;
			bool active;
	};

	/**********************************************************************/

	StandardContext::StandardContext() : Context()
	{
		li::context = this;

		char *libli_debug  = getenv("LIBLI_DEBUG");
		bool libli_debug_enabled = libli_debug && !strcmp(libli_debug, "1");
		Printer *stdout_printer = new Printer(std::cout, "STDOUT");
		Printer *stderr_printer = new Printer(std::cerr, "STDERR",
				libli_debug_enabled);

		(void)stdout_printer;
		(void)stderr_printer;
	}

	StandardContext::~StandardContext()
	{
	}
}

