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
{
    vfs_context_t context;
    const char* repoPath;
    const char* filePath;
    const char* dirPath;
    PrjFSProviderUserClient dummyClient;
    pid_t dummyClientPid;
    shared_ptr<mount> testMount;
    shared_ptr<vnode> repoRootVnode;
    shared_ptr<vnode> testFileVnode;
    shared_ptr<vnode> testDirVnode;
}

- (void) setUp
{
    kern_return_t initResult = VirtualizationRoots_Init();
    XCTAssertEqual(initResult, KERN_SUCCESS);
    context = vfs_context_create(NULL);
    dummyClientPid = 100;

    // Create Vnode Tree
    repoPath = "/Users/test/code/Repo";
    filePath = "/Users/test/code/Repo/file";
    dirPath = "/Users/test/code/Repo/dir";
    testMount = mount::Create();
    repoRootVnode = testMount->CreateVnodeTree(repoPath, VDIR);
    testFileVnode = testMount->CreateVnodeTree(filePath);
    testDirVnode = testMount->CreateVnodeTree(dirPath, VDIR);

    // Register provider for the repository path (Simulate a mount)
    VirtualizationRootResult result = VirtualizationRoot_RegisterProviderForPath(&dummyClient, dummyClientPid, repoPath);
    XCTAssertEqual(result.error, 0);
    vnode_put(s_virtualizationRoots[result.root].rootVNode);
}

- (void) tearDown
{
    testMount.reset();
    repoRootVnode.reset();
    testFileVnode.reset();
    testDirVnode.reset();
    VirtualizationRoots_Cleanup();
    vfs_context_rele(context);
    MockVnodes_CheckAndClear();
    MockCalls::Clear();
    callCount = 0;
}

- (void) testReadDataFileEmpty {
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
}

- (void) testReadDataFileHydrated {
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
}

- (void) testDeleteFile {
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
}

- (void) testDeleteDir {
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
}

/*
Is Directory
                KAUTH_VNODE_LIST_DIRECTORY |
                KAUTH_VNODE_SEARCH |
                KAUTH_VNODE_READ_SECURITY |
                KAUTH_VNODE_READ_ATTRIBUTES |
                KAUTH_VNODE_READ_EXTATTRIBUTES |
                KAUTH_VNODE_DELETE))

Else

                KAUTH_VNODE_READ_ATTRIBUTES |
                KAUTH_VNODE_WRITE_ATTRIBUTES |
                KAUTH_VNODE_READ_EXTATTRIBUTES |
                KAUTH_VNODE_WRITE_EXTATTRIBUTES |
                KAUTH_VNODE_READ_DATA |
                KAUTH_VNODE_WRITE_DATA |
                KAUTH_VNODE_EXECUTE |
                KAUTH_VNODE_DELETE))
   // KAUTH_VNODE_WRITE_DATA (Placeholder/Not a placeholder)
*/
@end
