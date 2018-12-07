using GVFS.Common.Git;
using GVFS.Common.Tracing;
using System.IO;

namespace GVFS.Common.Maintenance
{
    public class GitPackMaintenanceStep : GitMaintenanceStep
    {
        private const string MultiPackIndexLock = "multi-pack-index.lock";
        private const uint BatchSizeInMB = 3 * 1024; // Do not exceed 4GB, or Git will not understand the size

        public GitPackMaintenanceStep(GVFSContext context, GitObjects gitObjects)
            : base(context, gitObjects, requireObjectCacheLock: true)
        {
        }

        public override string Area => "GitPackMaintenanceStep";

        protected override bool PerformMaintenance()
        {
            // TODO: test if it has been long enough since last run

            long totalSize;
            int numPacksBefore;
            EventMetadata metadata = this.CreateEventMetadata();

            this.GetSizeOfPackDirectory(out totalSize, out numPacksBefore);
            metadata["TotalSizeBefore"] = totalSize;
            metadata["NumPacksBefore"] = numPacksBefore;
            this.Context.Tracer.RelatedEvent(EventLevel.Informational, this.Area, metadata);

            using (ITracer activity = this.Context.Tracer.StartActivity("ExpireMultiPackIndex", EventLevel.Informational, Keywords.Telemetry, metadata: null))
            {
                string multiPackIndexLockPath = Path.Combine(this.Context.Enlistment.GitPackRoot, MultiPackIndexLock);
                this.Context.FileSystem.TryDeleteFile(multiPackIndexLockPath);

                this.RunGitCommand((process) => process.ExpireMultiPackIndex(this.Context.Enlistment.GitObjectsRoot));
            }

            this.GetSizeOfPackDirectory(out totalSize, out numPacksBefore);
            metadata["TotalSizeAfterExpire"] = totalSize;
            metadata["NumPacksAfterExpire"] = numPacksBefore;
            this.Context.Tracer.RelatedEvent(EventLevel.Informational, this.Area, metadata);

            using (ITracer activity = this.Context.Tracer.StartActivity("RepackMultiPackIndex", EventLevel.Informational, Keywords.Telemetry, metadata: null))
            {
                this.RunGitCommand((process) => process.RepackMultiPackIndex(this.Context.Enlistment.GitObjectsRoot, BatchSizeInMB));
            }

            this.GetSizeOfPackDirectory(out totalSize, out numPacksBefore);
            metadata["TotalSizeAfterRepack"] = totalSize;
            metadata["NumPacksAfterRepack"] = numPacksBefore;
            this.Context.Tracer.RelatedEvent(EventLevel.Informational, this.Area, metadata);

            return true;
        }

        private void GetSizeOfPackDirectory(out long totalSize, out int numPacks)
        {
            string[] paths = this.Context.FileSystem.GetFiles(this.Context.Enlistment.GitPackRoot, "*.pack");
            numPacks = paths.Length;

            totalSize = 0;
            foreach (string path in paths)
            {
                totalSize += this.Context.FileSystem.GetFileProperties(path).Length;
            }
        }
    }
}
