#include "PrjFSUser.hpp"
#include <CoreFoundation/CFDictionary.h>
#include <IOKit/IOKitLib.h>
#include <iostream>
#include <mach/mach_port.h>
#include <sys/utsname.h>
#include <dlfcn.h>

struct DarwinVersion
{
    unsigned long major, minor, revision;
};

typedef decltype(IODataQueueDequeue)* ioDataQueueDequeueFunctionPtr;
static ioDataQueueDequeueFunctionPtr ioDataQueueDequeueFunction = nullptr;
typedef decltype(IODataQueuePeek)* ioDataQueuePeekFunctionPtr;
static ioDataQueuePeekFunctionPtr ioDataQueuePeekFunction = nullptr;

static void InitDataQueueFunctions();


io_connect_t PrjFSService_ConnectToDriver(enum PrjFSServiceUserClientType clientType)
{
    CFDictionaryRef matchDict = IOServiceMatching(PrjFSServiceClass);
    io_service_t prjfsService = IOServiceGetMatchingService(kIOMasterPortDefault, matchDict); // matchDict consumed

    io_connect_t connection = IO_OBJECT_NULL;
    
    if (prjfsService == IO_OBJECT_NULL)
    {
        std::cerr << "Failed to find instance of service class " PrjFSServiceClass << std::endl;
        return IO_OBJECT_NULL;
    }
    
    // Check kernel's interface version matches ours or we're asking for trouble
    CFTypeRef kextVersionObj = IORegistryEntryCreateCFProperty(prjfsService, CFSTR(PrjFSKextVersionKey), kCFAllocatorDefault, 0);
    CFStringRef kextVersionString;
    if (nullptr == kextVersionObj || CFStringGetTypeID() != CFGetTypeID(kextVersionObj))
    {
        std::cerr << "PrjFS kernel service does not advertise valid kext version property\n";
        goto CleanupAndFail;
    }
    
    kextVersionString = static_cast<CFStringRef>(kextVersionObj);
    if (kCFCompareEqualTo != CFStringCompare(kextVersionString, CFSTR(PrjFSKextVersion), 0 /* options: case sensitive */))
    {
        const char* kextVersion = CFStringGetCStringPtr(kextVersionString, kCFStringEncodingUTF8) ?: "???";
        std::cerr << "PrjFS kernel service interface version mismatch. Kernel: " << kextVersion << ", this library expects: " << PrjFSKextVersion << std::endl;
        goto CleanupAndFail;
    }
    else
    {
        CFRelease(kextVersionString);
        
        // Version matches, connect to kernel service
        kern_return_t result = IOServiceOpen(prjfsService, mach_task_self(), clientType, &connection);
        IOObjectRelease(prjfsService);
        if (kIOReturnSuccess != result || IO_OBJECT_NULL == connection)
        {
            std::cerr << "Failed to open connection to kernel service: 0x" << std::hex << result << ", connection 0x" << std::hex << connection << std::endl;
            connection = IO_OBJECT_NULL;
        }
    }
    
    return connection;

CleanupAndFail:
    if (IO_OBJECT_NULL != prjfsService)
    {
        IOObjectRelease(prjfsService);
    }
    
    if (nullptr != kextVersionObj)
    {
        CFRelease(kextVersionObj);
    }
    
    return IO_OBJECT_NULL;
}

bool PrjFSService_DataQueueInit(
    DataQueueResources* outQueue,
    io_connect_t connection,
    uint32_t clientPortType,
    uint32_t clientMemoryType,
    dispatch_queue_t eventHandlingQueue)
{
    IOReturn result;
    
    memset(outQueue, 0, sizeof(*outQueue));
    
    outQueue->notificationPort = IODataQueueAllocateNotificationPort();
    if (outQueue->notificationPort == MACH_PORT_NULL)
    {
        goto CleanupAndFail;
    }
    
    result = IOConnectSetNotificationPort(connection, clientPortType, outQueue->notificationPort, 0);
    if (kIOReturnSuccess != result)
    {
        goto CleanupAndFail;
    }
    
    IOConnectMapMemory64(
        connection,
        clientMemoryType,
        mach_task_self(),
        &outQueue->queueMemoryAddress,
        &outQueue->queueMemorySize,
        kIOMapAnywhere);
    if (0 == outQueue->queueMemoryAddress)
    {
        goto CleanupAndFail;
    }
    
    outQueue->queueMemory = reinterpret_cast<IODataQueueMemory*>(outQueue->queueMemoryAddress);
    outQueue->dispatchSource = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_MACH_RECV,
        outQueue->notificationPort,
        0, // mask, not used by mach port sources
        eventHandlingQueue);
    return true;
    
CleanupAndFail:
    if (0 != outQueue->queueMemoryAddress)
    {
        IOConnectUnmapMemory64(connection, clientMemoryType, mach_task_self(), outQueue->queueMemoryAddress);
    }
    
    if (MACH_PORT_NULL != outQueue->notificationPort)
    {
        mach_port_deallocate(mach_task_self(), outQueue->notificationPort);
    }
    
    memset(outQueue, 0, sizeof(*outQueue));
    return false;
}

IOReturn DataQueue_Dequeue(IODataQueueMemory* dataQueue, void* data, uint32_t* dataSize)
{
    if (nullptr == ioDataQueueDequeueFunction)
    {
        InitDataQueueFunctions();
    }
    return ioDataQueueDequeueFunction(dataQueue, data, dataSize);
}

IODataQueueEntry* DataQueue_Peek(IODataQueueMemory* dataQueue)
{
    if (nullptr == ioDataQueuePeekFunction)
    {
        InitDataQueueFunctions();
    }
    return ioDataQueuePeekFunction(dataQueue);
}


static bool GetDarwinVersion(DarwinVersion& outVersion)
{
    utsname unameInfo = {};
    if (0 != uname(&unameInfo))
    {
        return false;
    }
    
    char* fieldEnd = nullptr;
    unsigned long majorVersion = strtoul(unameInfo.release, &fieldEnd, 10);
    if (nullptr == fieldEnd || *fieldEnd != '.')
    {
        return false;
    }
    
    unsigned long minorVersion = strtoul(fieldEnd + 1, &fieldEnd, 10);
    if (nullptr == fieldEnd || (*fieldEnd != '.' && *fieldEnd != '\0'))
    {
        return false;
    }

    outVersion.major = majorVersion;
    outVersion.minor = minorVersion;
    outVersion.revision = 0;

    if (*fieldEnd != '\0')
    {
        unsigned long revision = strtoul(fieldEnd + 1, &fieldEnd, 10);
        if (nullptr == fieldEnd || (*fieldEnd != '.' && *fieldEnd != '\0'))
        {
            return false;
        }
        outVersion.revision = revision;
    }
    
    return true;
}

static void InitDataQueueFunctions()
{
    ioDataQueueDequeueFunction = &IODataQueueDequeue;
    ioDataQueuePeekFunction = &IODataQueuePeek;
    
    DarwinVersion osVersion = {};
    if (!GetDarwinVersion(osVersion))
    {
        return;
    }
    
    if ((osVersion.major == 17 && osVersion.minor >= 7) // macOS 10.13.6+
        || (osVersion.major == 18 && osVersion.minor == 0)) // macOS 10.14(.0) exactly
    {
        void* dataQueueLibrary = dlopen("libSharedDataQueue.dylib", RTLD_LAZY);
        if (nullptr == dataQueueLibrary)
        {
            fprintf(stderr, "Error opening data queue client library: %s\n", dlerror());
        }
        else
        {
            void* sym = dlsym(dataQueueLibrary, "IODataQueueDequeue");
            if (nullptr != sym)
            {
                ioDataQueueDequeueFunction = reinterpret_cast<ioDataQueueDequeueFunctionPtr>(sym);
            }
            
            sym = dlsym(dataQueueLibrary, "IODataQueuePeek");
            if (nullptr != sym)
            {
                ioDataQueuePeekFunction = reinterpret_cast<ioDataQueuePeekFunctionPtr>(sym);
            }
            
            // Allow the dataQueueLibrary handle to leak; if we called dlclose(),
            // the library would be unloaded, breaking our function pointers.
        }
    }
}
