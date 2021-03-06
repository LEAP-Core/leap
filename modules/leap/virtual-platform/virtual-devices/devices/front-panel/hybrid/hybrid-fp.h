#ifndef __HYBRID_FRONT_PANEL__
#define __HYBRID_FRONT_PANEL__

#include "awb/provides/rrr.h"
#include "tbb/atomic.h"
#include "command-switches.h"

#include "awb/rrr/client_stub_FRONT_PANEL.h"

#define SELECT_TIMEOUT      1000
#define DIALOG_PACKET_SIZE  4
#define STDIN               0
#define STDOUT              1

typedef class FRONT_PANEL_COMMAND_SWITCHES_CLASS* FRONT_PANEL_COMMAND_SWITCHES;
class FRONT_PANEL_COMMAND_SWITCHES_CLASS : public COMMAND_SWITCH_OPTIONAL_STRING_CLASS
{
    private:

        bool showFrontPanel;
        bool showLEDsOnStdOut;
    
    public:
        FRONT_PANEL_COMMAND_SWITCHES_CLASS();
        ~FRONT_PANEL_COMMAND_SWITCHES_CLASS();
        
        void ProcessSwitchVoid();
        void ProcessSwitchString(const char *switch_arg);
        void ShowSwitch(std::ostream& ostr, const string& prefix);

        bool ShowFrontPanel()   { return showFrontPanel; }
        bool ShowLEDsOnStdOut() { return showLEDsOnStdOut; }
};

typedef class FRONT_PANEL_SERVER_CLASS* FRONT_PANEL_SERVER;
class FRONT_PANEL_SERVER_CLASS: public RRR_SERVER_CLASS,
                                public PLATFORMS_MODULE_CLASS
{
  private:
    // self-instantiation
    static FRONT_PANEL_SERVER_CLASS instance;
    
    // command-line switches
    FRONT_PANEL_COMMAND_SWITCHES_CLASS fpSwitch;
    
    // stubs
    FRONT_PANEL_CLIENT_STUB clientStub;
    RRR_SERVER_STUB         serverStub;
    
    // other data
    int     dialogpid;
    int     child_to_parent[2];
    int     parent_to_child[2];
    
    UINT32  inputCache;
    bool    inputDirty;
    UINT32  outputCache;
    bool    outputDirty;
    
    class tbb::atomic<bool> initialized;

    volatile bool active;
    
    // internal methods
    void    syncInputs();
    void    syncOutputs();
    
    void    syncInputsConsole();
    void    syncOutputsConsole();
    
  public:
    FRONT_PANEL_SERVER_CLASS();
    ~FRONT_PANEL_SERVER_CLASS();
    
    void    Init(PLATFORMS_MODULE);
    void    Uninit();
    bool    Poll();

    void    UpdateLEDs(UINT8 state);
};

#include "awb/rrr/server_stub_FRONT_PANEL.h"

#endif
