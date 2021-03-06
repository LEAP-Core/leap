
#include <string.h>

#include "default-switches.h"


GLOBAL_ARGS globalArgs;

MODEL_DIR_SWITCH_CLASS::MODEL_DIR_SWITCH_CLASS() :
    modelDir("."),
    COMMAND_SWITCH_STRING_CLASS("modeldir")
{
}

void
MODEL_DIR_SWITCH_CLASS::ProcessSwitchString(const char *arg)
{
    modelDir = strdup(arg);
}

void
MODEL_DIR_SWITCH_CLASS::ShowSwitch(std::ostream& ostr, const string& prefix)
{
    ostr << prefix << "[--modeldir=<dir>]      Model directory" << endl;
}

WORKLOAD_SWITCH_CLASS::WORKLOAD_SWITCH_CLASS() :
    workload(APM_NAME),
    COMMAND_SWITCH_STRING_CLASS("workload")
{
}

void
WORKLOAD_SWITCH_CLASS::ProcessSwitchString(const char *arg)
{
    workload = strdup(arg);
}

void
WORKLOAD_SWITCH_CLASS::ShowSwitch(std::ostream& ostr, const string& prefix)
{
    ostr << prefix << "[--workload=\"<args>\"]   Workload name (affects .stats file name)" << endl;
}

FUNCP_SWITCH_CLASS::FUNCP_SWITCH_CLASS() :
    funcpArgc(0),
    funcpArgv(new char* [1]),
    COMMAND_SWITCH_LIST_CLASS("funcp")
{
    funcpArgv[0] = NULL;
}

void
FUNCP_SWITCH_CLASS::ProcessSwitchList(int switch_argc, char **switch_argv)
{
    funcpArgc = switch_argc;
    delete[] funcpArgv;
    funcpArgv = switch_argv;
}

void
FUNCP_SWITCH_CLASS::ShowSwitch(std::ostream& ostr, const string& prefix)
{
    ostr << prefix << "[--funcp=\"<args>\"]      Arguments for the functional platform" << endl;
}

DYN_PARAM_SWITCH_CLASS::DYN_PARAM_SWITCH_CLASS() :
    COMMAND_SWITCH_STRING_CLASS("param")
{
}

void
DYN_PARAM_SWITCH_CLASS::ProcessSwitchString(const char *arg)
{
    char *name = strdup(arg);
    char *eq = index(name, '=');
    if ( ! eq )
    {
        ASIMERROR("Invalid parameter specification in '"
                  << "--param " << name << "'" << endl
                  << "    Correct syntax: -param <name>=<value>" << endl);
    }
    else
    {
        char *value = eq + 1;
        *eq = '\0';
        if ( ! SetParam(name, value))
        {
            *eq = '=';
            ASIMERROR("Don't know about dynamic parameter "
                      << name << endl);
        }
        *eq = '=';
    }
    free(name);
}

void
DYN_PARAM_SWITCH_CLASS::ShowSwitch(std::ostream& ostr, const string& prefix)
{
    ostr << prefix << "[--param NAME=VALUE]    Set a dynamic parameter" << endl;
}


LISTPARAM_SWITCH_CLASS::LISTPARAM_SWITCH_CLASS() :
    COMMAND_SWITCH_VOID_CLASS("listparam")
{
}

void
LISTPARAM_SWITCH_CLASS::ProcessSwitchVoid()
{
    ListParams();
    exit(0);
}

void
LISTPARAM_SWITCH_CLASS::ShowSwitch(std::ostream& ostr, const string& prefix)
{
    ostr << prefix << "[--listparam]           List dynamic parameters" << endl;
}


// ========================================================================
//
// --tr
//
// ========================================================================

HASIM_TRACE_FLAG_CLASS::HASIM_TRACE_FLAG_CLASS() :
    COMMAND_SWITCH_STRING_CLASS("tr")
{
}

void
HASIM_TRACE_FLAG_CLASS::ProcessSwitchString(const char *command) 
{
    string regex;
    int level;

    if (command == NULL)
    {
        // no regex given, match every name
        regex = ".*";
        level = 1;
    }
    else
    {
        regex = command;
        int pos = regex.size() - 1;
        // the last char should be '0', '1', or '2'
        if (regex[pos] != '0' && regex[pos] != '1' && regex[pos] != '2') 
        {
            // If a level was not given, defaul to 1.
            level = 1;
        } 
        else 
        {
            level = regex[pos] - '0';
            pos--;

            if ((pos >= 0) && regex[pos] != '=')
            {
                cerr << "\nExpected -tr=[/regex/[=012]]" << endl;
                exit(1);
            }
            pos--;
        }

        // remove the '/' at front and back
        if ((pos >= 0) && (regex[pos] != '/' || regex[0] != '/'))
        {
            cerr << "\nExpected -tr=[/regex/[=012]]" << endl;
            exit(1);
        }

        if (pos <= 1)
        {
            // Empty regular expression.  Use default.
            regex = ".*";
        }
        else
        {
            // Drop everything but the text inside the slashes.
            regex.erase(pos);
            regex.erase(0,1);
        }
        
    }

    TRACEABLE_CLASS::EnableTraceByRegex(regex, level);
}

void
HASIM_TRACE_FLAG_CLASS::ShowSwitch(std::ostream& ostr, const string& prefix)
{
    ostr << prefix << "[--tr=[</regex/[=012]]] Set trace level by regular expression. Can be given" << endl
         << prefix << "                        multiple times.  If not specified, the trace level" << endl
         << prefix << "                        will default to 1 and the regex to .*" << endl;
}


// ========================================================================
//
// Wrap all the global arguments.
//
// ========================================================================

GLOBAL_ARGS_CLASS::GLOBAL_ARGS_CLASS() :
    modelDirSwitch(),
    workloadSwitch(),
    funcpSwitch(),
    dynParamSwitch(),
    listParamSwitch()
{
}

GLOBAL_ARGS_CLASS::~GLOBAL_ARGS_CLASS()
{
}
