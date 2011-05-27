//
// Copyright (C) 2011 Intel Corporation
//
//
// Copyright c 2003-2007 by Accellera
// scemi.h - SCE-MI C++ Interface
//
#ifndef INCLUDED_SCEMI
#define INCLUDED_SCEMI

#ifdef _WIN32

#ifdef VICO_FW_MAIN
#define EXT_SYM __declspec(dllexport)
#else
#define EXT_SYM __declspec(dllimport)
#endif

#else
#define EXT_SYM
#endif

class SceMiParameters;
class SceMiMessageData;
class SceMiMessageInPortProxy;
class SceMiMessageOutPortProxy;

#define SCEMI_MAJOR_VERSION 2
#define SCEMI_MINOR_VERSION 0
#define SCEMI_PATCH_VERSION 0
#define SCEMI_VERSION_STRING "2.0.0"

/* 32 bit unsigned word type for building and reading messages */
typedef unsigned int SceMiU32;

/* 64 bit unsigned word used for CycleStamps */
typedef unsigned long long SceMiU64;

extern "C" {
typedef int (*SceMiServiceLoopHandler)(void* context, int pending);
};

/*
 * struct SceMiEC - SceMi Error Context
 */

typedef enum {
    SceMiOK,
    SceMiError
} SceMiErrorType;

typedef struct {
    const char* Culprit;   /* The offending function */
    const char* Message;   /* Descriptive message describing problem */
    SceMiErrorType Type;   /* Error code describing the nature of the error */
    int Id;                /* A code to uniquely identify each error */
 
} SceMiEC;

extern "C" {
typedef void (*SceMiErrorHandler)(void* context, SceMiEC* ec);
};

/*
 * struct SceMiIC - SceMi Informational Message Context
 */

typedef enum {
    SceMiInfo,
    SceMiWarning,
    SceMiNonFatalError
} SceMiInfoType;

typedef struct {
    const char* Originator;
    const char* Message;
    SceMiInfoType Type;
    int Id;
} SceMiIC;

extern "C" {
typedef void (*SceMiInfoHandler)(void* context, SceMiIC* ic);
};

/*
 * struct SceMiMessageInPortBinding
 *
 * Description
 * -----------
 * This structure defines a tray of callback functions that support
 * propagation of message input readiness back to the software.
 *
 * If an input ready callback is registered (optionally) on a given
 * input port, the port will dispatch the callback whenever becomes
 * ready for more input.
 *
 * Note: All callbacks must take their data and return promptly as they
 * are called possibly deep down in a non-preemptive thread.  Typically,
 * the callback might to some minor manipulation to the context object
 * then return and let a suspended thread resume and do the main processing
 * of the received transaction.
 */

extern "C" {
typedef struct {
    /*
     * This is the user's context object pointer.
     * The application is free to use this pointer for any purposes it
     * wishes.  Neither the class SceMi nor class MessageInputPortProxy do
     * anything with this pointer other than store it and pass it when
 
     * calling functions.
     */
    void* Context; 

    /*
     * Receive a response transaction.  This function is called when data
     * from the message output port arrives.  This callback acts as a proxy
     * for the message output port of the transactor.
     */
    void (*IsReady)(
        void* context);

    /*
     * This function is called from the MessageInputPortProxy destructor
     * to notify the user code that the reference to the 'context' pointer
     * has been deleted.
     */
    int (*Close)(
        void* context);

} SceMiMessageInPortBinding;
};

/*
 * struct SceMiMessageOutPortBinding
 *
 * Description
 * -----------
 * This structure defines a tray of callback functions are passed to the class
 * SceMi when the application model binds to a message output port proxy and
 * which are called on message receipt and close notification.  It is the means
 * by which the MessageOutputPort forwards received transactions to the C model.
 *
 * Note: All callbacks must take their data and return promptly as they
 * are called possibly deep down in a non-preemptive thread.  Typically,
 * the callback might to some minor manipulation to the context object
 * then return and let a suspended thread resume and do the main processing
 * of the received transaction.
 *
 * Additionally, the message data passed into the receive callback is
 * not guaranteed to remain the same once the callback returns.  All
 * data therein then must be processed while inside the callback.
 */

extern "C" {
typedef struct {
    /*
     * This is the user's context object pointer.
     * The application is free to use this pointer for any purposes it
 
     * wishes.  Neither the class SceMi nor class SceMiMessageOutPortProxy do
     * anything with this pointer other than store it and pass it when
     * calling callback functions Receive and Close.
     */
    void* Context;

    /*
     * Receive a response transaction.  This function is called when data
     * from the message output port arrives.  This callback acts as a proxy
     * for the message output port of the transactor.
     */
    void (*Receive)(
        void* context,
        const SceMiMessageData* data);

    /*
     * This function is called from the MessageOutputPortProxy destructor
     * to notify the user code that the reference to the 'context' pointer
     * has been deleted.
     */
    int (*Close)(
        void* context);

} SceMiMessageOutPortBinding;
};

class EXT_SYM SceMiParameters {

  public:
    // CREATORS

    //
    // This constructor initializes some parameters from the
    // parameters file in the config directory, and some other
    // parameters directly from the config file.
    //
    SceMiParameters(
        const char* paramsfile,
        SceMiEC* ec = 0);

    ~SceMiParameters();

    // ACCESSORS

    //
    // This accessor returns the number of instances of objects of
    // the specified objectKind name.
    //
    unsigned int NumberOfObjects(
        const char* objectKind,    // Input: Object kind name.
        SceMiEC* ec = 0) const; // Input/Output: Error status.

    //
 
    // These accessors return an integer or string attribute values of the
    // given object kind.  It is considered an error if the index > number
    // returned by ::NumberOfObjects() or the objectKind and attributeName
    // arguments are unrecognized.
    //
    int AttributeIntegerValue(
        const char* objectKind,    // Input: Object kind name.
        unsigned int index,        // Input: Index of object instance.
        const char* attributeName, // Input: Name of attribute being read.
        SceMiEC* ec = 0) const;    // Input/Output: Error status.

    const char* AttributeStringValue(
        const char* objectKind,    // Input: Object kind name.
        unsigned int index,        // Input: Index of object instance.
        const char* attributeName, // Input: Name of attribute being read.
        SceMiEC* ec = 0) const;    // Input/Output: Error status.

    // MANIPULATORS

    //
    // These manipulators override an integer or string attribute values of the
    // given object kind.  It is considered an error if the index > number
    // returned by ::NumberOfObjects(). or the objectKind and attributeName
    // arguments are unrecognized.
    //
    void OverrideAttributeIntegerValue(
        const char* objectKind,    // Input: Object kind name.
        unsigned int index,        // Input: Index of object instance.
        const char* attributeName, // Input: Name of attribute being read.
        int value,                 // Input: New integer value of attribute.
        SceMiEC* ec = 0);          // Input/Output: Error status.

    void OverrideAttributeStringValue(
        const char* objectKind,    // Input: Object kind name.
        unsigned int index,        // Input: Index of object instance.
        const char* attributeName, // Input: Name of attribute being read.
        const char* value,         // Input: New string value of attribute.
        SceMiEC* ec = 0);          // Input/Output: Error status.
};

//
// class SceMiMessageInPortProxy
//
// Description
// -----------
// The class SceMiMessageInPortProxy presents a C++ proxy for a transactor
// message input port.  The input channel to that transactor is represented
// by the Send() method.
//

class EXT_SYM SceMiMessageInPortProxy {
 
  public:
    // ACCESSORS
    const char* TransactorName() const;
    const char* PortName() const;
    unsigned int PortWidth() const;

    //
    // This method sends message to the transactor input port.
    //
    void Send(
        const SceMiMessageData &data, // Message payload to be sent.
        SceMiEC* ec = 0);

    //
    // Replace port binding.
    // The binding argument represents a callback function and context
    // pointer tray (see comments in scemicommontypes.h for struct
    // SceMiMessageInPortBinding).
    //
    void ReplaceBinding(
        const SceMiMessageInPortBinding* binding = 0,
        SceMiEC* ec = 0);
};

//
// class SceMiMessageOutPortProxy
//
// Description
// -----------
// The class SceMiMessageOutPortProxy presents a C++ proxy for a transactor
// message output port.
//
class EXT_SYM SceMiMessageOutPortProxy {
  public:
    // ACCESSORS
    const char* TransactorName() const;
    const char* PortName() const;
    unsigned int PortWidth() const;

    //
    // Replace port binding.
    // The binding argument represents a callback function and context
    // pointer tray (see comments in scemicommontypes.h for struct
    // SceMiMessageOutPortBinding).
    //
    void ReplaceBinding(
        const SceMiMessageOutPortBinding* binding = 0,
        SceMiEC* ec = 0);
};

//
// class SceMiMessageData
//
 
// Description
// -----------
// The class SceMiMessageData represents a fixed length array of data which
// is transferred between models.
//
class EXT_SYM SceMiMessageData {
//*** Functionality part *****
  protected:
  void* message_data;
  SceMiMessageData() {}
//****************************

  public:
    // CREATORS

    //
    // Constructor: The message in port proxy for which
    // this message data object must be suitably sized.
    //
    SceMiMessageData(
        const SceMiMessageInPortProxy& messageInPortProxy,
        SceMiEC* ec = 0);

    ~SceMiMessageData();

    // Return size of vector in bits
    unsigned int WidthInBits() const;

    // Return size of array in 32 bit words.
    unsigned int WidthInWords() const;

    void Set( unsigned i, SceMiU32 word, SceMiEC* ec = 0);

    void SetBit( unsigned i, int bit, SceMiEC* ec = 0);

    void SetBitRange(
        unsigned int i, unsigned int range, SceMiU32 bits, SceMiEC* ec = 0);

    SceMiU32 Get( unsigned i, SceMiEC* ec = 0) const;

    int GetBit( unsigned i, SceMiEC* ec = 0) const;

    SceMiU32 GetBitRange(
        unsigned int i, unsigned int range, SceMiEC* ec = 0) const;

    SceMiU64 CycleStamp() const;
};

//
// class SceMi
//
// Description
// -----------
// This file defines the public interface to class SceMi.
//

class EXT_SYM SceMi {
  public:
 
    //
    // Check version string against supported versions.
    // Returns -1 if passed string not supported.
    // Returns interface version # if it is supported.
    // This interface version # can be passed to SceMi::Init().
    //
    static int Version(
        const char* versionString);

    //
    // This function wraps constructor of class SceMi.  If an instance
    // of class SceMi has been established on a prior call to the
    // SceMi::Init() function, that pointer is returned since a single
    // instance of class SceMi is reusable among all C models.
    // Returns NULL if error occurred, check ec for status or register
    // an error callback.
    //
    // The caller is required to pass in the version of SceMi it is
    // expecting to work with.  Call SceMi::Version to convert a version
    // string to an integer suitable for this version's "version" argument.
    //
    // The caller is also expected to have instantiated a SceMiParameters
    // object, and pass a pointer to that object into this function.
    //
    static SceMi* 
    Init(
        int version,
        const SceMiParameters* parameters,
        SceMiEC* ec = 0);

    // This accessor returns a pointer to the SceMi object constructed in a 
    // previous call to SceMi::Init. The return argument is a pointer to an 
    // object of class SceMi on which all other methods can be called.  
    //
    // If the SceMi::Init method has not yet been called, 
    // SceMi::Pointer will return NULL.  

    static SceMi *
    Pointer( 
    	SceMiEC *ec=0 ); 

    //
    // Shut down the SCEMI interface.
    //
    static void
    Shutdown(
        SceMi* mct,
        SceMiEC* ec = 0);

    //
    // Create proxy for message input port.
    //
    // Pass in the instance name in the bridge netlist of
    // the transactor and port to which binding is requested.
    //
    // The binding argument is a callback function and context
    // pointer tray.  For more details, see the comments in
    // scemicommontypes.h by struct SceMiMessageInPortBinding.
    //
    SceMiMessageInPortProxy* 
    BindMessageInPort(
        const char* transactorName,
        const char* portName,
        const SceMiMessageInPortBinding* binding = 0,
 
        SceMiEC* ec = 0);

    //
    // Create proxy for message output port.
    //
    // Pass in the instance name in the bridge netlist of
    // the transactor and port to which binding is requested.
    //
    // The binding argument is a callback function and context
    // pointer tray.  For more details, see the comments in
    // scemicommontypes.h by struct SceMiMessageOutPortBinding.
    //
    SceMiMessageOutPortProxy* 
    BindMessageOutPort(
        const char* transactorName,
        const char* portName,
        const SceMiMessageOutPortBinding* binding = 0,
        SceMiEC* ec = 0);

    //
    // Service arriving transactions from the portal.
    // Messages enqueued by SceMiMessageOutPortProxy methods, or which are
    // are from output transactions that pending dispatch to the
    // SceMiMessageOutPortProxy callbacks, may not be handled until
    // ServiceLoop() is called.  This function returns the # of output
    // messages that were dispatched.
    //
    // Regarding the service loop handler (aka "g function"):
    // If g is NULL, check for transfers to be performed and
    // dispatch them returning immediately afterwards.  If g is
    // non-NULL, enter into a loop of performing transfers and
    // calling 'g'.  When 'g' returns 0 return from the loop.
    // When 'g' is called, an indication of whether there is at
    // least 1 message pending will be made with the 'pending' flag.
    //
    // The user context object pointer is uninterpreted by 
    // ServiceLoop() and is passed straight to the 'g' function.
    //
    int
    ServiceLoop(
        SceMiServiceLoopHandler g = 0,
        void* context = 0,
        SceMiEC* ec = 0);

    //
    // Register an error handler which is called in the event
    // that an error occurs.  If no handler is registered, the
    // default error handler is called.
    //
    static void
    RegisterErrorHandler(
        SceMiErrorHandler errorHandler,
        void* context);

 
    //
    // Register an info handler which is called in the event
    // that a text message needs to be issued.  If no handler
    // is registered, the message is printed to stdout in
    // Ikos message format.
    //
    static void
    RegisterInfoHandler(
        SceMiInfoHandler infoHandler,
        void* context);
};

#endif
