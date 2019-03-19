#include "../PrjFSKext/kernel-header-wrappers/vnode.h"
#include "../PrjFSKext/KauthHandlerTestable.hpp"
#include "../PrjFSKext/VirtualizationRoots.hpp"
#include "../PrjFSKext/PrjFSProviderUserClient.hpp"
#include "../PrjFSKext/VirtualizationRootsTestable.hpp"
#include "../PrjFSKext/PerformanceTracing.hpp"
#include "../PrjFSKext/public/Message.h"
#include "../PrjFSKext/ProviderMessaging.hpp"
#include "../PrjFSKext/public/PrjFSXattrs.h"
#import <XCTest/XCTest.h>
#import <sys/stat.h>
#include "KextMockUtilities.hpp"
#include "MockVnodeAndMount.hpp"
#include "MockProc.hpp"

using std::shared_ptr;

class PrjFSProviderUserClient
{
};

MessageType expectedMessageType[3];
int callCount = 0;
bool ProviderMessaging_TrySendRequestAndWaitForResponse(
    VirtualizationRootHandle root,
    MessageType messageType,
    const vnode_t vnode,
    const FsidInode& vnodeFsidInode,
    const char* vnodePath,
    int pid,
    const char* procname,
    int* kauthResult,
    int* kauthError)
{
    assert(expectedMessageType[callCount] = messageType);
    callCount++;
    
    MockCalls::RecordFunctionCall(
        ProviderMessaging_TrySendRequestAndWaitForResponse,
        root,
        messageType,
        vnode,
        vnodeFsidInode,
        vnodePath,
        pid,
        procname,
        kauthResult,
        kauthError);
    
    return true;
}

@interface HandleVnodeOperationTests : XCTestCase
@end

@implementation HandleVnodeOperationTests

- (void) tearDown
{
    MockVnodes_CheckAndClear();
}

- (void)testHandleVnodeOpEvent {
    // Setup
    kern_return_t initResult = VirtualizationRoots_Init();
    XCTAssertEqual(initResult, KERN_SUCCESS);

    // Parameters
    const char* repoPath = "/Users/test/code/Repo";
    const char* filePath = "/Users/test/code/Repo/file";
    const char* dirPath = "/Users/test/code/Repo/dir";
    vfs_context_t _Nonnull context = vfs_context_create(NULL);
    //PerfTracer perfTracer;
    PrjFSProviderUserClient dummyClient;
    pid_t dummyClientPid=100;

    // Create Vnode Tree
    shared_ptr<mount> testMount = mount::Create();
    shared_ptr<vnode> repoRootVnode = testMount->CreateVnodeTree(repoPath, VDIR);
    shared_ptr<vnode> testFileVnode = testMount->CreateVnodeTree(filePath);
    shared_ptr<vnode> testDirVnode = testMount->CreateVnodeTree(dirPath, VDIR);

    // Register provider for the repository path (Simulate a mount)
    VirtualizationRootResult result = VirtualizationRoot_RegisterProviderForPath(&dummyClient, dummyClientPid, repoPath);
    XCTAssertEqual(result.error, 0);
    vnode_put(s_virtualizationRoots[result.root].rootVNode);
    
    // Read a file that has not been hydrated yet
    expectedMessageType[0] = MessageType_KtoU_HydrateFile;
    testFileVnode->attrValues.va_flags = FileFlags_IsEmpty | FileFlags_IsInVirtualizationRoot;
    HandleVnodeOperation(
        nullptr,
        nullptr,
        KAUTH_VNODE_READ_DATA,
        reinterpret_cast<uintptr_t>(context),
        reinterpret_cast<uintptr_t>(testFileVnode.get()),
        0,
        0);
    XCTAssertTrue(MockCalls::DidCallFunction(ProviderMessaging_TrySendRequestAndWaitForResponse));
    MockCalls::Clear();
    callCount = 0;

    // Ensure a file without an IsEmpty tag is not hydrated
    testFileVnode->attrValues.va_flags = FileFlags_IsInVirtualizationRoot;
    HandleVnodeOperation(
        nullptr,
        nullptr,
        KAUTH_VNODE_READ_DATA,
        reinterpret_cast<uintptr_t>(context),
        reinterpret_cast<uintptr_t>(testFileVnode.get()),
        0,
        0);
    XCTAssertFalse(MockCalls::DidCallFunction(ProviderMessaging_TrySendRequestAndWaitForResponse));
    MockCalls::Clear();

    // Ensure a file is Deleted
    expectedMessageType[0] = MessageType_KtoU_NotifyFilePreDelete;
    testFileVnode->attrValues.va_flags = FileFlags_IsInVirtualizationRoot;
    HandleVnodeOperation(
        nullptr,
        nullptr,
        KAUTH_VNODE_DELETE,
        reinterpret_cast<uintptr_t>(context),
        reinterpret_cast<uintptr_t>(testFileVnode.get()),
        0,
        0);
    XCTAssertTrue(MockCalls::DidCallFunction(ProviderMessaging_TrySendRequestAndWaitForResponse));
    MockCalls::Clear();
    callCount = 0;

    // Ensure a directory is Deleted
    expectedMessageType[0] = MessageType_KtoU_NotifyDirectoryPreDelete;
    expectedMessageType[1] = MessageType_KtoU_RecursivelyEnumerateDirectory;
    testDirVnode->attrValues.va_flags = FileFlags_IsInVirtualizationRoot;
    HandleVnodeOperation(
        nullptr,
        nullptr,
        KAUTH_VNODE_DELETE,
        reinterpret_cast<uintptr_t>(context),
        reinterpret_cast<uintptr_t>(testDirVnode.get()),
        0,
        0);
    XCTAssertTrue(MockCalls::DidCallFunction(ProviderMessaging_TrySendRequestAndWaitForResponse));
    MockCalls::Clear();
    callCount = 0;

    // Teardown
    VirtualizationRoots_Cleanup();
    vfs_context_rele(context);
}

@end
