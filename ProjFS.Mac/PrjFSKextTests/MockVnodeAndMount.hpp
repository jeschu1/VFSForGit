#pragma once

#include "../PrjFSKext/kernel-header-wrappers/vnode.h"
#include "../PrjFSKext/kernel-header-wrappers/mount.h"
#include "../PrjFSKext/public/FsidInode.h"
#include <memory>
#include <string>

typedef std::shared_ptr<mount> MountPointer;
typedef std::shared_ptr<vnode> VnodePointer;
typedef std::weak_ptr<vnode> VnodeWeakPointer;

struct mount
{
private:
    vfsstatfs statfs;
    uint64_t nextInode;
    
public:
    static MountPointer Create(const char* fileSystemTypeName, fsid_t fsid, uint64_t initialInode);
    
    inline fsid_t GetFsid() const { return this->statfs.f_fsid; }
    
    friend struct vnode;
    friend vfsstatfs* vfs_statfs(mount_t mountPoint);
    friend FsidInode Vnode_GetFsidAndInode(vnode_t vnode, vfs_context_t vfsContext);
};

struct vnode
{
private:
    VnodeWeakPointer weakSelfPointer;
    MountPointer mountPoint;
    
    uint64_t inode;
    uint32_t vid;
    int32_t ioCount = 0;
    bool isRecycling = false;
    
    errno_t getPathError = 0;
    
    vtype type = VREG;
    
    std::string path;
    const char* name;
    int attr = 0;
    int vnodeGetAttrReturnCode = 0;
    
    void SetPath(const std::string& path);

    explicit vnode(const MountPointer& mount);
    
    vnode(const vnode&) = delete;
    vnode& operator=(const vnode&) = delete;
    
public:
    static VnodePointer Create(const MountPointer& mount, const char* path, vtype vnodeType = VREG);
    static VnodePointer Create(const MountPointer& mount, const char* path, vtype vnodeType, uint64_t inode);
    ~vnode();
    
    uint64_t GetInode() const { return this->inode; }
    uint32_t GetVid() const { return this->vid; }
    void SetAttr(int attr);
    void SetGetAttrReturnCode(int code);
    void SetGetPathError(errno_t error);
    void StartRecycling();

    friend int vnode_isrecycled(vnode_t vnode);
    friend uint32_t vnode_vid(vnode_t vnode);
    friend const char* vnode_getname(vnode_t vnode);
    friend vtype vnode_vtype(vnode_t vnode);
    friend mount_t vnode_mount(vnode_t vnode);
    friend int vnode_get(vnode_t vnode);
    friend int vnode_put(vnode_t vnode);
    friend int vnode_getattr(vnode_t vp, struct vnode_attr *vap, vfs_context_t ctx);
    friend errno_t vnode_lookup(const char* path, int flags, vnode_t* foundVnode, vfs_context_t vfsContext);
    friend int vn_getpath(vnode_t vnode, char* pathBuffer, int* pathLengthInOut);
    friend FsidInode Vnode_GetFsidAndInode(vnode_t vnode, vfs_context_t vfsContext);
};


void MockVnodes_CheckAndClear();

