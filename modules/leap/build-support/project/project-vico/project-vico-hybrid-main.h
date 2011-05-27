#ifndef __PROJECT_MAIN_H__
#define __PROJECT_MAIN_H__

#include "hardware-done.h"

#include <string>

// FuncSim command-line argument storage
// set() should be called once in main() function 
class FuncSimParams {
    static FuncSimParams *s_instance;
    std::string s; // real storage

  public:
    // returns arguments 
    std::string get() const { return s; }

    // sets arguments
    void set(std::string s) {
       this->s = s;
    }

    static FuncSimParams *instance() {
        if (!s_instance)
          s_instance = new FuncSimParams;
        return s_instance;
    }
};

#endif
