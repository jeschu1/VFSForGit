using GVFS.Common;
using GVFS.Common.Git;
using GVFS.Tests.Should;
using NUnit.Framework;

namespace GVFS.UnitTests.Common
{
    [TestFixture]
    public class GVFSEnlistmentTests
    {
        [TestCase]
        public void TestGetIds()
        {
            MockGVFSEnlistment enlistment = new MockGVFSEnlistment("enlistment", "repoUrl", "gitBinPath", "gvfsHooksRoot", new GitAuthentication(null, null));

            enlistment.GetEnlistmentId().ShouldEqual("gvfs.enlistment-id-returned");
            enlistment.GetMountId().ShouldEqual("gvfs.mount-id-returned");
        }

        public class MockGVFSEnlistment : GVFSEnlistment
        {
            public MockGVFSEnlistment(string enlistmentRoot, string repoUrl, string gitBinPath, string gvfsHooksRoot, GitAuthentication authentication)
                : base(enlistmentRoot, repoUrl, gitBinPath, gvfsHooksRoot, authentication)
            {
            }

            protected override GitProcess GetGitProcess()
            {
                return new MockGitProcess();
            }
        }

        public class MockGitProcess : GitProcess
        {
            public MockGitProcess()
                : base("gitBinPath", "workingDirRoot", "gvfsHooksRoot")
            {
            }

            public override ConfigResult GetFromLocalConfig(string settingName)
            {
                return new ConfigResult(
                        new Result(
                            stdout: settingName + "-returned",
                            stderr: string.Empty,
                            exitCode: 0),
                        configName: settingName);
            }
        }
    }
}
