#ifndef __DEFAULT_SWITCHES_H__
#define __DEFAULT_SWITCHES_H__

#include "command-switches.h"


class MODEL_DIR_SWITCH_CLASS : public COMMAND_SWITCH_STRING_CLASS
{
    public:
        MODEL_DIR_SWITCH_CLASS();
        ~MODEL_DIR_SWITCH_CLASS() {}
        const char* ModelDir() { return modelDir; }

        void ProcessSwitchString(const char* arg);
        bool ShowSwitch(char* buff);
    private:
        const char* modelDir;

};

class WORKLOAD_SWITCH_CLASS : public COMMAND_SWITCH_STRING_CLASS
{
    public:
        WORKLOAD_SWITCH_CLASS();
        ~WORKLOAD_SWITCH_CLASS() {}
        const char* Workload() { return workload; }

        void ProcessSwitchString(const char* arg);
        bool ShowSwitch(char* buff);
    private:
        const char* workload;

};

class FUNCP_SWITCH_CLASS : public COMMAND_SWITCH_LIST_CLASS
{
    public:
        FUNCP_SWITCH_CLASS();
        ~FUNCP_SWITCH_CLASS() {}
        int FuncPlatformArgc() { return funcpArgc; }
        char** FuncPlatformArgv() { return funcpArgv; }

        void ProcessSwitchList(int argv, char** argc);
        bool ShowSwitch(char* buff);
    private:
        int funcpArgc;
        char** funcpArgv;

};

class DYN_PARAM_SWITCH_CLASS : public COMMAND_SWITCH_STRING_CLASS
{
    public:
        DYN_PARAM_SWITCH_CLASS();
        ~DYN_PARAM_SWITCH_CLASS() {}

        void ProcessSwitchString(const char* arg);
        bool ShowSwitch(char* buff);
};

class LISTPARAM_SWITCH_CLASS : public COMMAND_SWITCH_VOID_CLASS
{
    public:
        LISTPARAM_SWITCH_CLASS();
        ~LISTPARAM_SWITCH_CLASS() {}

        void ProcessSwitchVoid();
        bool ShowSwitch(char* buff);
};

class HASIM_TRACE_FLAG_CLASS : public COMMAND_SWITCH_STRING_CLASS
{
    public:
        HASIM_TRACE_FLAG_CLASS();
        ~HASIM_TRACE_FLAG_CLASS() {}

        void ProcessSwitchString(const char* arg);
        bool ShowSwitch(char* buff);
};

typedef class GLOBAL_ARGS_CLASS* GLOBAL_ARGS;
class GLOBAL_ARGS_CLASS
{
  public:
    const char *ModelDir() { return modelDirSwitch.ModelDir(); };
    const char *Workload() { return workloadSwitch.Workload(); };
    int FuncPlatformArgc() { return funcpSwitch.FuncPlatformArgc(); }
    char **FuncPlatformArgv() { return funcpSwitch.FuncPlatformArgv(); }

    void SetExecutableName(const char* name) { executableName = name; }
    const char* ExecutableName() { return executableName; }

    GLOBAL_ARGS_CLASS();
    ~GLOBAL_ARGS_CLASS();

  private:
    const char* executableName; // Name of executable (argv[0])
    MODEL_DIR_SWITCH_CLASS modelDirSwitch; // Model (pm) directory
    WORKLOAD_SWITCH_CLASS  workloadSwitch; // Name of the workload (affects stats file name)

    // Functional platform arguments
    FUNCP_SWITCH_CLASS funcpSwitch;

    // Dynamic parameters
    DYN_PARAM_SWITCH_CLASS dynParamSwitch;
    LISTPARAM_SWITCH_CLASS listParamSwitch;

    HASIM_TRACE_FLAG_CLASS traceFlagParser;
};

#endif

