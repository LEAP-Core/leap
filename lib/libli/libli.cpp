//
// Copyright (C) 2013 Intel Corporation
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

