namespace GVFS.FunctionalTests
{
    public static class Categories
    {
        public const string ExtraCoverage = "ExtraCoverage";
        public const string FastFetch = "FastFetch";
        public const string GitCommands = "GitCommands";

        public const string WindowsOnly = "WindowsOnly";
        public const string MacOnly = "MacOnly";

        public static class MacTODO
        {
            // The FailsOnBuildAgent category is for tests that pass on dev
            // machines but not on the build agents
            public const string FailsOnBuildAgent = "FailsOnBuildAgent";

            // Tests that require #360 (detecting/handling new empty folders)
            public const string NeedsNewFolderCreateNotification = "NeedsNewFolderCreateNotification";

            // Tests that require the Status Cache to be built
            public const string NeedsStatusCache = "NeedsStatusCache";

            // Tests that rquire Repair to be built (SHOULD WORK)
            public const string NeedsRepair = "NeedsRepair";

            // Tests that require Config to be built (JAMESON/AHMEEN may know status)
            public const string NeedsConfig = "NeedsConfig";

            // Tests that require VFS Service  (JAMESON/AHMEEN may know status)
            public const string NeedsServiceVerb = "NeedsServiceVerb";

            // Not sure
            public const string NeedsDehydrate = "NeedsDehydrate";

            // Tests requires code updates so that we lock the file instead of looking for a .lock file
            public const string TestNeedsToLockFile = "TestNeedsToLockFile";

            // Not sure
            public const string NotSure = "NotSure";

            // Tests that have been flaky on build servers and need additional logging and\or
            // investigation
            public const string FlakyTest = "MacFlakyTest";
        }
    }
}
