#ifndef __COMMAND_SWITCHES_H__
#define __COMMAND_SWITCHES_H__

#include <vector>
#include <getopt.h>
#include <ostream>
#include <string>
#include<map>

#include <boost/tokenizer.hpp>
#include <boost/lexical_cast.hpp>
#include <boost/algorithm/string.hpp>

#include "asim/syntax.h"
#include "asim/mesg.h"
#include "asim/trace.h"
#include "asim/param.h"
#include "asim/atoi.h"
#include "asim/syntax.h"

// COMMAND_SWITCH

// superclass for all command switches.

typedef class COMMAND_SWITCH_CLASS* COMMAND_SWITCH;
class COMMAND_SWITCH_CLASS
{
    private:
        COMMAND_SWITCH nextProcessor;
        const char* switchName;
        int argType;

    public:
        static COMMAND_SWITCH switchProcessors;

        COMMAND_SWITCH_CLASS(const char* switch_name, int arg_type);
        ~COMMAND_SWITCH_CLASS() {}

        const char* GetSwitchName() { return switchName; }
        int GetArgType() { return argType; }
        COMMAND_SWITCH GetNextProcessor() { return nextProcessor; }

        virtual void ProcessSwitch(const char *arg) {}
        virtual void ShowSwitch(std::ostream& ostr, const string& prefix) {}
};

// COMMAND_SWITCH_VOID

// a flag which is either present or not.
// It takes no arguments from the user.

class COMMAND_SWITCH_VOID_CLASS : public COMMAND_SWITCH_CLASS
{
    public:
        COMMAND_SWITCH_VOID_CLASS(const char* switch_name) : COMMAND_SWITCH_CLASS(switch_name, no_argument) {}
        ~COMMAND_SWITCH_VOID_CLASS() {}

        void ProcessSwitch(const char *arg) { ProcessSwitchVoid(); }
        virtual void ProcessSwitchVoid() {}
};

// COMMAND_SWITCH_INT

// A command switch which must be accompanied by an integer number.

class COMMAND_SWITCH_INT_CLASS : public COMMAND_SWITCH_CLASS
{
    public:
        COMMAND_SWITCH_INT_CLASS(const char* switch_name) : COMMAND_SWITCH_CLASS(switch_name, required_argument) {}
        ~COMMAND_SWITCH_INT_CLASS() {}

        void ProcessSwitch(const char *arg) { ProcessSwitchInt(atoi_general_unsigned(arg)); }
        virtual void ProcessSwitchInt(int arg_val) = 0;
};

// COMMAND_SWITCH_UINT64

// A command switch which must be accompanied by an integer number.

class COMMAND_SWITCH_UINT64_CLASS : public COMMAND_SWITCH_CLASS
{
    public:
        COMMAND_SWITCH_UINT64_CLASS(const char* switch_name) : COMMAND_SWITCH_CLASS(switch_name, required_argument) {}
        ~COMMAND_SWITCH_UINT64_CLASS() {}

        void ProcessSwitch(const char *arg) { ProcessSwitchInt(atoi_general_unsigned(arg)); }
        virtual void ProcessSwitchInt(UINT64 arg_val) = 0;
};

// COMMAND_SWITCH_FP

// A command switch which must be accompanied by a floating point value.

class COMMAND_SWITCH_FP_CLASS : public COMMAND_SWITCH_CLASS
{
    public:
        COMMAND_SWITCH_FP_CLASS(const char* switch_name) : COMMAND_SWITCH_CLASS(switch_name, required_argument) {}
        ~COMMAND_SWITCH_FP_CLASS() {}

        void ProcessSwitch(const char *arg) { ProcessSwitchFp(atof(arg)); }
        virtual void ProcessSwitchFp(double arg_val) {}
};

// COMMAND_SWITCH_STRING

// A command switch which must be accompanied by a single string.

class COMMAND_SWITCH_STRING_CLASS : public COMMAND_SWITCH_CLASS
{
    public:
        COMMAND_SWITCH_STRING_CLASS(const char* switch_name) : COMMAND_SWITCH_CLASS(switch_name, required_argument) {}
        ~COMMAND_SWITCH_STRING_CLASS() {}

        void ProcessSwitch(const char *arg) { ProcessSwitchString(arg); }
        virtual void ProcessSwitchString(const char *arg_val) {}
};

// COMMAND_SWITCH_OPTIONAL_INT

// A command switch which may or may not be accompanied by a number
// If the flag is present, but no argument given, ProcessSwitchVoid
// is invoked. Otherwise ProcessSwitchInt is invoked.

class COMMAND_SWITCH_OPTIONAL_INT_CLASS : public COMMAND_SWITCH_CLASS
{
    public:
        COMMAND_SWITCH_OPTIONAL_INT_CLASS(const char* switch_name) : COMMAND_SWITCH_CLASS(switch_name, optional_argument) {}
        ~COMMAND_SWITCH_OPTIONAL_INT_CLASS() {}

        void ProcessSwitch(const char *arg) { if (arg == NULL) ProcessSwitchVoid(); else ProcessSwitchInt(atoi_general_unsigned(arg)); }

        virtual void ProcessSwitchVoid() {}
        virtual void ProcessSwitchInt(int arg_val) {}
};

// COMMAND_SWITCH_OPTIONAL_STRING

// A command switch which may or may not be accompanied by a string.
// If the flag is present, but no argument given, ProcessSwitchVoid
// is invoked. Otherwise ProcessSwitchString is invoked.

class COMMAND_SWITCH_OPTIONAL_STRING_CLASS : public COMMAND_SWITCH_CLASS
{
    public:
        COMMAND_SWITCH_OPTIONAL_STRING_CLASS(const char* switch_name) : COMMAND_SWITCH_CLASS(switch_name, optional_argument) {}
        ~COMMAND_SWITCH_OPTIONAL_STRING_CLASS() {}

        void ProcessSwitch(const char *arg) { if (arg == NULL) ProcessSwitchVoid(); else ProcessSwitchString(arg); }

        virtual void ProcessSwitchVoid() {}
        virtual void ProcessSwitchString(const char *arg_val) {}
};

// COMMAND_SWITCH_LIST

// A command switch which requires a quoted list of arguments.
// These arguments are parsed into a new argc/argv structure
// and passed into ProcessStringList.

class COMMAND_SWITCH_LIST_CLASS : public COMMAND_SWITCH_CLASS
{
    private:
        // internal list processing function.
        vector<string> ParseStringToArgs(const string& line);

    public:
        COMMAND_SWITCH_LIST_CLASS(const char* switch_name) : COMMAND_SWITCH_CLASS(switch_name, required_argument) {}
        ~COMMAND_SWITCH_LIST_CLASS() {}

        void ProcessSwitch(const char *arg);

        virtual void ProcessSwitchList(int switch_argc, char **switch_argv) {}
};

// 
//  BASIC SWITCH IMPLEMENTATIONS
//
//  The most obvious thing for a switch to do is return its value.  The
//  following classes provide this functionality. This is an incomplete 
//  set.  Feel free to add implementations as necessary.  There is a 
//  refactoring around the help string, but that can wait for a different 
//  day.
//  

// BASIC_COMMAND_SWITCH_VOID

// A basic interface to the command switch void. Provides a single function which 
// tests the presence of the switch.

typedef class BASIC_COMMAND_SWITCH_VOID_CLASS* BASIC_COMMAND_SWITCH_VOID;
class BASIC_COMMAND_SWITCH_VOID_CLASS : COMMAND_SWITCH_VOID_CLASS
{
 private:
  bool switchPresent;
  string helpString;
  string nameString;

 public:
  BASIC_COMMAND_SWITCH_VOID_CLASS(const char* name, const char* help) :
  COMMAND_SWITCH_VOID_CLASS(name),
    helpString(help),  
    nameString(name)
  {
      switchPresent = false; 
  };

  BASIC_COMMAND_SWITCH_VOID_CLASS(const char* name) :
    COMMAND_SWITCH_VOID_CLASS(name),
    helpString("No help provided"),
    nameString(name)
  {
      switchPresent = false; 
  };

  ~BASIC_COMMAND_SWITCH_VOID_CLASS() {};

  void ProcessSwitchVoid() { switchPresent = true; };
  void ShowSwitch(std::ostream& ostr, const string& prefix)
  {
      ostr << prefix << "[--" << nameString << "]          " << helpString << endl;
  }

  bool SwitchPresent() { return switchPresent; }
};

// BASIC_COMMAND_SWITCH_STRING

// A basic interface to the command switch string. Returns NULL if no string present. 

typedef class BASIC_COMMAND_SWITCH_STRING_CLASS* BASIC_COMMAND_SWITCH_STRING;
class BASIC_COMMAND_SWITCH_STRING_CLASS : COMMAND_SWITCH_STRING_CLASS
{
 private:
  string *switchValue;
  string helpString;
  string nameString;

 public:
  BASIC_COMMAND_SWITCH_STRING_CLASS(const char* name, const char* help) :
    COMMAND_SWITCH_STRING_CLASS(name),
    helpString(help),
    nameString(name)
  {
      switchValue = NULL;
  };

  BASIC_COMMAND_SWITCH_STRING_CLASS(const char* name) :
    COMMAND_SWITCH_STRING_CLASS(name),
    helpString("No help provided"),
    nameString(name)
  {
      switchValue = NULL;
  };
 
  ~BASIC_COMMAND_SWITCH_STRING_CLASS() 
   { 
       if(switchValue != NULL) 
       {
           delete switchValue; 
       }
   };

  void ProcessSwitchString(const char *arg_val) 
  { 
      if(arg_val != NULL) 
      {
          switchValue = new std::string(arg_val); 
      }
  };

  void ShowSwitch(std::ostream& ostr, const string& prefix)
  {
      ostr << prefix << "[--" << nameString << "]          " << helpString << endl;
  }

  const string * SwitchValue() { return switchValue; }
};


// COMMAND_SWITCH_DICTIONARY_CLASS

// Permits dictionaries to be described on the command line.  
// Format is --dictionaryName fooDict=foo1:foo1Val;foo2=foo2Val;.... <-space terminates the list. 

typedef class COMMAND_SWITCH_DICTIONARY_CLASS* COMMAND_SWITCH_DICTIONARY;
class COMMAND_SWITCH_DICTIONARY_CLASS : COMMAND_SWITCH_STRING_CLASS
{
  private:
    std::map<string,string*> parameterDictionary;
    string *switchValue;
    string helpString;
    string nameString;

  public:
    COMMAND_SWITCH_DICTIONARY_CLASS(const char* name, const char* help) :
      COMMAND_SWITCH_STRING_CLASS(name),
      helpString(help),
      nameString(name),
      parameterDictionary()
    {
        switchValue = NULL;
    };

    COMMAND_SWITCH_DICTIONARY_CLASS(const char* name) :
      COMMAND_SWITCH_STRING_CLASS(name),
      helpString("No help provided"),
      nameString(name),
      parameterDictionary()
    {
        switchValue = NULL;
    };
   
    ~COMMAND_SWITCH_DICTIONARY_CLASS() 
     { 
         if(switchValue != NULL) 
         {
             delete switchValue; 
         }
     };

    void ProcessSwitchString(const char *arg_val) 
    { 
        if(arg_val != NULL) 
        {
            switchValue = new std::string(arg_val);

            // We need two tokenizers, one for the parameter set list, and one
            // for the parameters themselves.
            string separatorSemicolon(",");
            string emptyEscape(""); // boost requires us to specify escape characters
            boost::escaped_list_separator<char> elSemicolon(emptyEscape, separatorSemicolon, emptyEscape);    
            typedef boost::tokenizer<boost::escaped_list_separator<char> >  tok_t;
            
            string separatorColon(":");
            string separatorQuote("\"");
            boost::escaped_list_separator<char> elColon(emptyEscape, separatorColon, separatorQuote);    

                      
            tok_t semicolonTok(*switchValue, elSemicolon);
            for(tok_t::iterator parameterSets (semicolonTok.begin());
                parameterSets != semicolonTok.end();
                ++parameterSets)
            {
                vector<string> parameterList;            
                std::string set(*parameterSets);
                boost::trim(set);
                tok_t colonTok(set, elColon);
                
                for(tok_t::iterator parameters (colonTok.begin());

                    parameters != colonTok.end();
                    ++parameters)
                {
                    std::string parameter(*parameters);
                    boost::trim(parameter);               
                    parameterList.push_back(parameter);
                }
                 
                if(parameterList.size() == 2)
                {                      
                    parameterDictionary.insert(make_pair(parameterList[0], new string(parameterList[1])));
                }

            }
        }
    };

    void ShowSwitch(std::ostream& ostr, const string& prefix)
    {
        ostr << prefix << "[--" << nameString << "]          " << helpString << endl;
    }

    const string *SwitchValue(string key) 
    {  
       if(parameterDictionary.find(key) != parameterDictionary.end());
       {
           //element found; 
         return parameterDictionary.find(key)->second;
       }
        
       // Otherwise, return a null pointer.
       return NULL;
    }
    
};



#endif

