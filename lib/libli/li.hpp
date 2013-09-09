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
// @file libli.hpp
// @brief LI headers
//
// @author Daniel Lustig
//

#ifndef _LIBLI_LI_HPP_
#define _LIBLI_LI_HPP_

#include <list>
#include <map>
#include <set>
#include <iostream>
#include <sstream>
#include <typeinfo>

#include "tbb/concurrent_queue.h"
#include "tbb/atomic.h"
#include "tbb/task.h"

#define LINC_QUEUE_DEPTH 1

namespace li
{
	/* Forward Declarations for Public API */

	extern std::stringstream verbose;
	extern std::stringstream messages;
	extern std::stringstream warnings;
	extern std::stringstream errors;

	// Base Classes
	class Context;
	template <class T> class LINC_SEND;
	template <class T> class LINC_RECV;
	template <class M> class Scheduler;

	// Derived Classes
	class StandardContext;
	template <class M> class StaticPriorityScheduler;

	/* Single Global Context */

	extern Context *context;

	/* Public API */

	class Context
	{
		public:
			Context();
			virtual ~Context() = 0;
			template<class T> void Connect(LINC_SEND<T> *t1, LINC_RECV<T> *t2);
			template<class T> void Name(LINC_SEND<T> *t, const char *name);
			template<class T> void Name(LINC_RECV<T> *t, const char *name);
			template<class T> void AddScheduler(Scheduler<T> *s);
			virtual void Elaborate() = 0;
			void Route();
			void Execute();
			void Quiesce();
			bool Quiescing() const;
			void Finish();
			bool Finished() const;
		// Internal:
			void IncrementModuleCount();
			void DecrementModuleCount();
		private:
			std::set<void (*)()> typed_linc_maps_routers;
			std::set<void (*)()> typed_scheduler_set_spawners;
			tbb::atomic<int> active_modules;
			bool globally_quiescing;
			bool globally_finished;
	};

	class StandardContext : public Context
	{
		public:
			StandardContext();
			virtual ~StandardContext() = 0;
			virtual void Elaborate() = 0;
	};

	template <class T> class LINCMap;
	template <class T> class LINC_RECV
	{
		friend class Context;
		friend class LINCMap<T>;

		public:
			LINC_RECV();
			T Peek();
			void Dequeue();
			bool IsEmpty() const;
		protected:
			tbb::concurrent_bounded_queue<T> *queue;
			bool head_valid;
			T head;
	};

	template <class T> class LINC_SEND
	{
		friend class Context;
		friend class LINCMap<T>;

		public:
			LINC_SEND();
			void Enqueue(T value);
			bool IsFull() const;
		protected:
			tbb::concurrent_bounded_queue<T> *queue;
			bool head_valid;
			T head;
	};

	template <class M>
	class Scheduler
	{
		public:
			Scheduler(M *module);
			virtual ~Scheduler() = 0;

			// rule_can_fire_t is a member function of type void -> bool (const)
			typedef bool (M::*Guard)() const;

			// rule_fire_t is a member function of type void -> void
			typedef void (M::*Action)();

			struct Rule
			{
				Guard guard;
				Action action;
			};

			void RegisterRule(Guard guard, Action action);

			void Spawn();
			virtual void Execute() = 0;
			void Finish();

		protected:
			M *module;
			std::list<Rule> rules;
			bool finished;

			unsigned long long execution_count;
			unsigned long long stalled_count;
	};

	template <class M>
	class StaticPriorityScheduler : public Scheduler<M>
	{
		public:
			StaticPriorityScheduler(M *m);
			~StaticPriorityScheduler();
			void Execute();
	};

	template<class T> void Connect(LINC_SEND<T> &t1, LINC_RECV<T> &t2);
	template<class T> void Connect(LINC_RECV<T> &t1, LINC_SEND<T> &t2);

	template<class T> void Name(LINC_SEND<T> &t, const char *name);
	template<class T> void Name(LINC_RECV<T> &t, const char *name);

	void Elaborate();
	void Route();
	void Execute();
	void Quiesce();
	void Finish();










	/**********************************************************************/
	/* Implementation                                                     */
	/**********************************************************************/

	template <class T>
	class TypedSchedulerSet
	{
		public:
			static void Add(Scheduler<T> *s);
			static void Spawn();
		private:
			static std::set<Scheduler<T> *> schedulers;
	};

	template <class T> std::set<Scheduler<T> *>
		TypedSchedulerSet<T>::schedulers;

	template <class T>
	void TypedSchedulerSet<T>::Add(Scheduler<T> *s)
	{
		schedulers.insert(s);
	}

	template <class T>
	void TypedSchedulerSet<T>::Spawn()
	{
		typename std::set<Scheduler<T> *>::iterator iter;
		for (iter = schedulers.begin(); iter != schedulers.end(); iter++)
		{
			(*iter)->Spawn();
		}
	}

	/**********************************************************************/

	template<class T>
	void Context::Connect(LINC_SEND<T> *t1, LINC_RECV<T> *t2)
	{
		// check for multicast/merge
		if (t1->queue && t2->queue)
		{
			errors << "Trying to connect two already-connected LINCs" <<
				std::endl;
		}
		else if (t1->queue)
		{
			// Multicast
			messages << "Multicasting LINC" << std::endl;
			verbose << "Multicasting LINC " << t1 << " to " << t2 << std::endl;
			t2->queue = t1->queue;
		}
		else if (t2->queue)
		{
			// Merge
			messages << "Merging LINC" << std::endl;
			verbose << "Merging LINC " << t1 << " to " << t2 << std::endl;
			t1->queue = t2->queue;
		}
		else
		{
			// New connection
			tbb::concurrent_bounded_queue<T> *q =
				new tbb::concurrent_bounded_queue<T>;
			q->set_capacity(LINC_QUEUE_DEPTH);
			t1->queue = q;
			t2->queue = q;
			verbose << "Connected LINCs " << t1 << " and " << t2 << std::endl;
		}
	}

	template<class T>
	void Context::Name(LINC_SEND<T> *t, const char *name)
	{
		LINCMap<T>::Add(t, name);
		typed_linc_maps_routers.insert(&LINCMap<T>::Route);
	}

	template<class T>
	void Context::Name(LINC_RECV<T> *t, const char *name)
	{
		LINCMap<T>::Add(t, name);
	}

	template <class T>
	void Context::AddScheduler(Scheduler<T> *t)
	{
		TypedSchedulerSet<T>::Add(t);
		typed_scheduler_set_spawners.insert(&TypedSchedulerSet<T>::Spawn);
	}

	/**********************************************************************/

	template <class T>
	LINC_RECV<T>::LINC_RECV() : queue(NULL), head_valid(false)
	{
		LINCMap<T>::Add(this);
	}

	template<class T> T LINC_RECV<T>::Peek()
	{
		if (!head_valid && queue)
		{
			queue->pop(head);
			head_valid = true;
		}
		return head;
	}

	template<class T> void LINC_RECV<T>::Dequeue()
	{
		if (head_valid)
		{
			head_valid = false;
		}
		else
		{
			T dummy;
			queue->pop(dummy);
		}
	}

	template<class T> bool LINC_RECV<T>::IsEmpty() const
	{
		if (!queue)
		{
			std::cerr << "WARNING: Checking if dangling LINC_RECV is empty\n";
			usleep(1000000);
		}
		return !queue || (queue->size() == 0);
	}

	/**********************************************************************/

	template <class T>
	class Unbounded_LINC_RECV : public LINC_RECV<T>
	{
		public:
			Unbounded_LINC_RECV();
	};

	template <class T>
	Unbounded_LINC_RECV<T>::Unbounded_LINC_RECV() : LINC_RECV<T>()
	{
		this->queue = new tbb::concurrent_bounded_queue<T>;
	}

	/**********************************************************************/

	template <class T>
	LINC_SEND<T>::LINC_SEND() : queue(NULL), head_valid(false)
	{
		LINCMap<T>::Add(this);
	}

	template<class T> void LINC_SEND<T>::Enqueue(T value)
	{
		// XXX: silent drop for dangling queues
		if (queue)
			queue->push(value);
	}

	template<class T> bool LINC_SEND<T>::IsFull() const
	{
		// XXX: silent drop for dangling queues
		return queue ? (queue->size() >= LINC_QUEUE_DEPTH) : false;
	}

	/**********************************************************************/

	template <class T>
	class LINCMap
	{
		public:
			static void Add(LINC_SEND<T> *t);
			static void Add(LINC_RECV<T> *t);
			static void Add(LINC_SEND<T> *t, const char *name);
			static void Add(LINC_RECV<T> *t, const char *name);
			static void Route();
		private:
			static std::map<std::string, std::set<LINC_SEND<T> *> >
				named_linc_sends;
			static std::map<std::string, std::set<LINC_RECV<T> *> >
				named_linc_recvs;
			static std::set<LINC_SEND<T> *> unnamed_linc_sends;
			static std::set<LINC_RECV<T> *> unnamed_linc_recvs;
	};

	template <class T> typename std::set<LINC_SEND<T> *>
		LINCMap<T>::unnamed_linc_sends;
	template <class T> typename std::set<LINC_RECV<T> *>
		LINCMap<T>::unnamed_linc_recvs;
	template <class T> typename std::map<std::string, std::set<LINC_SEND<T> *> >
		LINCMap<T>::named_linc_sends;
	template <class T> typename std::map<std::string, std::set<LINC_RECV<T> *> >
		LINCMap<T>::named_linc_recvs;

	/**********************************************************************/

	template <class T> class SchedulerTask;

	template <class M>
	Scheduler<M>::Scheduler(M *module) : module(module), finished(false),
		execution_count(0), stalled_count(0)
	{
		context->AddScheduler(this);
	}

	template <class M>
	Scheduler<M>::~Scheduler()
	{
	}

	template <class M>
	void Scheduler<M>::RegisterRule(Guard guard, Action action)
	{
		Rule rule;
		rule.guard = guard;
		rule.action = action;

		rules.push_back(rule);
	}

	template <class T>
	void Scheduler<T>::Spawn()
	{
		SchedulerTask<T> *t = new (tbb::task::allocate_root())
			SchedulerTask<T>(this);
		tbb::task::enqueue(*t); // at the back of the queue

		context->IncrementModuleCount();
	}

	template <class T>
	void Scheduler<T>::Finish()
	{
		finished = true;
	}

	/**********************************************************************/

	template <class T>
	class SchedulerTask : public tbb::task
	{
		public:
			SchedulerTask(Scheduler<T> *s);
			tbb::task *execute();
		private:
			Scheduler<T> *s;
	};

	template <class T>
	SchedulerTask<T>::SchedulerTask(Scheduler<T> *s) : s(s)
	{
	}

	template <class T>
	tbb::task *SchedulerTask<T>::execute()
	{
		s->Execute();

		if (!(li::context->Finished()) && !(li::context->Quiescing()))
		{
			SchedulerTask<T> *t = new (tbb::task::allocate_root())
				SchedulerTask<T>(s);
			tbb::task::enqueue(*t); // at the back of the queue
		}
		else
		{
			li::context->DecrementModuleCount();
		}
		return NULL;
	}

	/**********************************************************************/

	template <class M>
	StaticPriorityScheduler<M>::StaticPriorityScheduler(M *m) :
		Scheduler<M>(m)
	{
	}

	template <class M>
	StaticPriorityScheduler<M>::~StaticPriorityScheduler()
	{
	}

	template <class M>
	void StaticPriorityScheduler<M>::Execute()
	{
		while(!(li::context->Finished()) && !this->finished)
		{
			this->execution_count++;

			typename std::list<typename Scheduler<M>::Rule>::iterator iter;
			for(iter = this->rules.begin(); iter != this->rules.end(); iter++)
			{
				typename Scheduler<M>::Guard guard = iter->guard;
				typename Scheduler<M>::Action action = iter->action;

				if ((this->module->*guard)())
				{
					(this->module->*action)();
					this->stalled_count = 0;
					break; // go back to the first rule
				}
			}

			if (iter == this->rules.end())
			{
				this->stalled_count++;
				/*
				if (this->stalled_count == 10000)
				{
					std::stringstream s;
					s << "WARNING: module " << typeid(this).name() <<
						" stalled" << std::endl;
					std::cerr << s.str() << std::endl;
					usleep(100000);
				}
				*/
				break; // if no rule fired, yield to others
			}
		}
	}

	/**********************************************************************/

	template <class T>
	void LINCMap<T>::Add(LINC_SEND<T> *t)
	{
		if (unnamed_linc_sends.find(t) != unnamed_linc_sends.end())
			warnings << "Already added LINC_SEND" << std::endl;

		unnamed_linc_sends.insert(t);
	}

	template <class T>
	void LINCMap<T>::Add(LINC_RECV<T> *t)
	{
		if (unnamed_linc_recvs.find(t) != unnamed_linc_recvs.end())
			warnings << "Already added LINC_RECV" << std::endl;

		unnamed_linc_recvs.insert(t);
	}

	template <class T>
	void LINCMap<T>::Add(LINC_SEND<T> *t, const char *name)
	{
		if (unnamed_linc_sends.find(t) == unnamed_linc_sends.end())
		{
			errors << "Could not locate LINC_SEND to give name " <<
				name << std::endl;
		}

		if (named_linc_sends.find(name) != named_linc_sends.end())
		{
			messages << "Duplicate LINC_SEND name \"" << name << "\"" <<
				std::endl; 
		}

		unnamed_linc_sends.erase(t);
		named_linc_sends[name].insert(t);
	}

	template <class T>
	void LINCMap<T>::Add(LINC_RECV<T> *t, const char *name)
	{
		if (unnamed_linc_recvs.find(t) == unnamed_linc_recvs.end())
		{
			errors << "Could not locate LINC_RECV to give name " <<
				name << std::endl;
		}

		if (named_linc_recvs.find(name) != named_linc_recvs.end())
		{
			messages << "Duplicate LINC_RECV name \"" << name << "\"" <<
				std::endl; 
		}

		unnamed_linc_recvs.erase(t);
		named_linc_recvs[name].insert(t);
	}

	template <class T>
	void LINCMap<T>::Route()
	{
		/* std::map is sorted by key, so we can traverse both lists
		 * sequentially */
		typename std::map<std::string, std::set<LINC_SEND<T> *> >::iterator
			linc_sends_iter = named_linc_sends.begin();
		typename std::map<std::string, std::set<LINC_RECV<T> *> >::iterator
			linc_recvs_iter = named_linc_recvs.begin();

		verbose << "Route: trying to match " << named_linc_sends.size() <<
			" named LINC_SENDs with " << named_linc_recvs.size() <<
			" named LINC_RECVs of type " << typeid(T).name() << std::endl;

		while(linc_sends_iter != named_linc_sends.end() &&
				linc_recvs_iter != named_linc_recvs.end())
		{
			verbose << "Route: comparing named LINC_SEND \"" <<
				linc_sends_iter->first << "\" and LINC_RECV \"" <<
				linc_recvs_iter->first << "\"" << std::endl;

			// If the keys (the names) are equal, connect the LINCs
			if (linc_sends_iter->first == linc_recvs_iter->first)
			{
				verbose << "Connecting LINCs named \"" <<
					linc_sends_iter->first << "\"" << std::endl;
				for (typename std::set<LINC_SEND<T> *>::iterator
						linc_send_iter = linc_sends_iter->second.begin();
						linc_send_iter != linc_sends_iter->second.end();
						linc_send_iter++)
				{
					for (typename std::set<LINC_RECV<T> *>::iterator
							linc_recv_iter = linc_recvs_iter->second.begin();
							linc_recv_iter != linc_recvs_iter->second.end();
							linc_recv_iter++)
					{
						verbose << "\tConnect LINCs" << std::endl;
						context->Connect(*linc_send_iter, *linc_recv_iter);
					}
				}
				linc_sends_iter++;
				linc_recvs_iter++;
			}
			else if (linc_sends_iter->first < linc_recvs_iter->first)
			{
				warnings << "Named LINC_SEND<" << typeid(T).name() << "> \"" <<
					linc_sends_iter->first << "\" is dangling" << std::endl;
				linc_sends_iter++;
			}
			else if (linc_sends_iter->first > linc_recvs_iter->first)
			{
				warnings << "Named LINC_RECV<" << typeid(T).name() << "> \"" <<
					linc_recvs_iter->first << "\" is dangling" << std::endl;
				linc_recvs_iter++;
			}
		}

		while (linc_sends_iter != named_linc_sends.end())
		{
			warnings << "Named LINC_SEND<" << typeid(T).name() << "> \"" <<
				linc_sends_iter->first << "\" is dangling" << std::endl;
			linc_sends_iter++;
		}

		while (linc_recvs_iter != named_linc_recvs.end())
		{
			warnings << "Named LINC_RECV<" << typeid(T).name() << "> \"" <<
				linc_recvs_iter->first << "\" is dangling" << std::endl;
			linc_recvs_iter++;
		}

		int count = 0;
		for (typename std::set<LINC_SEND<T> *>::iterator iter =
				unnamed_linc_sends.begin();
				iter != unnamed_linc_sends.end();
				iter++)
		{
			if (!(*iter)->queue)
				count++;
		}

		if (count)
		{
			warnings << "There are " << count <<
				" unconnected unnamed LINC_SENDs" << std::endl;
		}

		count = 0;
		for (typename std::set<LINC_RECV<T> *>::iterator iter =
				unnamed_linc_recvs.begin();
				iter != unnamed_linc_recvs.end();
				iter++)
		{
			if (!(*iter)->queue)
				count++;
		}

		if (count)
		{
			warnings << "There are " << count <<
				" unconnected unnamed LINC_RECVs" << std::endl;
		}
	}

	/**********************************************************************/

	template<class T>
	void Connect(LINC_SEND<T> &t1, LINC_RECV<T> &t2)
	{
		context->Connect(&t1, &t2);
	}

	template<class T>
	void Connect(LINC_RECV<T> &t1, LINC_SEND<T> &t2)
	{
		context->Connect(&t2, &t1);
	}

	template<class T>
	void Name(LINC_SEND<T> &t, const char *name)
	{
		context->Name(&t, name);
	}

	template<class T>
	void Name(LINC_RECV<T> &t, const char *name)
	{
		context->Name(&t, name);
	}

	/**********************************************************************/

	template <class T>
	class ReadStreamer
	{
		public:
			typedef std::pair<bool, T> bool_plus_T;

			ReadStreamer(T *baseAddr, int xNum, int yNum = 1,
					ssize_t xStride = sizeof(T), ssize_t yStride = 0,
					bool active = true, bool send_eos_message = true) :
				baseAddr(baseAddr), xNum(xNum), yNum(yNum), xStride(xStride),
				yStride(yStride), active(active),
				xCur(0), yCur(0),
				sent_finished_message(!active)
			{
				scheduler = new StaticPriorityScheduler<ReadStreamer>(this);
				scheduler->RegisterRule(&ReadStreamer::CanRead,
						&ReadStreamer::DoRead);
				scheduler->RegisterRule(&ReadStreamer::CanSendFinishedMessage,
						&ReadStreamer::DoSendFinishedMessage);
			}

			LINC_SEND<bool_plus_T> data;

		private:
			bool CanRead() const
			{
				return active && !data.IsFull();
			}

			void DoRead()
			{
				T value = *(T*)(baseAddr + (xCur * xStride) + (yCur * yStride));
				xCur++;
				if (xCur >= xNum)
				{
					xCur = 0;
					yCur++;
					if (yCur >= yNum)
					{
						yCur = 0;
						active = false;
					}
				}

				data.Enqueue(std::make_pair(false, value));
			}

			bool CanSendFinishedMessage() const
			{
				return !active && send_eos_message && !sent_finished_message &&
					!data.IsFull();
			}

			void DoSendFinishedMessage()
			{
				static T dummy; // use default, don't care
				data.Enqueue(std::make_pair(true, dummy));
				scheduler->Finish();
			}

			li::Scheduler<ReadStreamer> *scheduler;

			T *baseAddr;
			int xNum;
			int yNum;
			ssize_t xStride;
			ssize_t yStride;
			bool active;
			bool send_eos_message;

			int xCur;
			int yCur;
			bool sent_finished_message;
	};
}
#endif // _LIBLI_LI_HPP_

