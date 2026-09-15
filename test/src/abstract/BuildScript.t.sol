// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployConfig} from "../../../src/lib/LibRainDeployConfig.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {BuildScriptHarness} from "../../concrete/BuildScriptHarness.sol";

/// @title BuildScriptTest
/// @notice The split between the two entry points every deploy repo inherits.
///
/// The contract this repo compiles is not what these run against: a
/// `cutRelease()` here cuts THIS repo's tag, and `src/generated/` is
/// append-only, so each test drives a harness over a fixture record of its own.
/// A shared root would have the second test refused as a re-cut of the first.
contract BuildScriptTest is Test {
    /// The contract the fixture snapshots describe.
    string constant FIXTURE_CONTRACT = "Fixture";

    /// Where the `run()` fixture's record is built.
    string constant RUN_FIXTURE_ROOT = "test/generated-buildscript-run";

    /// Where the freeze fixture's record is built.
    string constant CUT_FIXTURE_ROOT = "test/generated-buildscript-cut";

    /// Where the lib-ordering fixture's record is built.
    string constant LIBS_FIXTURE_ROOT = "test/generated-buildscript-libs";

    /// Where the `run()` config fixture's record is built.
    string constant RUN_CONFIG_FIXTURE_ROOT = "test/generated-buildscript-run-config";

    /// Where the `cutRelease()` config fixture's record is built. Its own root,
    /// like every other fixture here: forge runs the tests in a contract in
    /// parallel, so a root two of them share is one deleting the tree the other
    /// is midway through reading.
    string constant CUT_CONFIG_FIXTURE_ROOT = "test/generated-buildscript-cut-config";

    /// Clears a fixture record an earlier failure left behind.
    ///
    /// A cheatcode write is not undone by a revert, so a failing test leaves
    /// its markers on disk and the next run reads THOSE — an assertion about
    /// the previous run rather than about this one.
    /// @param root The fixture record root to clear.
    function resetFixture(string memory root) internal {
        if (vm.exists(root)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(root, true);
        }
    }

    /// PROPERTY: `run()` regenerates everything and freezes NOTHING.
    ///
    /// This is the entry point CI calls on every push. A `run()` that cut a
    /// release would freeze whatever a branch happened to compile under the
    /// repo's current tag, and that tag can then never be cut again for real.
    ///
    /// The lib marker also carries the order: the libs are written after the
    /// snapshots, from a record that holds no release.
    function testRunRegeneratesAndFreezesNothing() external {
        resetFixture(RUN_FIXTURE_ROOT);
        BuildScriptHarness harness = new BuildScriptHarness(RUN_FIXTURE_ROOT, FIXTURE_CONTRACT);
        harness.seedConfig();
        harness.run();

        // Read while the fixture is still there, asserted once it is gone.
        string memory rolling = vm.readFile(harness.rollingPath());
        string memory libs = vm.readFile(harness.libsPath());
        string[] memory record = LibRainDeploySnapshot.frozenSnapshotPaths(vm, RUN_FIXTURE_ROOT);
        bool frozenExists = vm.exists(harness.frozenPath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(RUN_FIXTURE_ROOT, true);

        assertEq(rolling, harness.regeneratedSnapshot());
        assertEq(libs, harness.libsMarker(0, true));
        assertEq(record.length, 0);
        assertFalse(frozenExists);
    }

    /// PROPERTY: `cutRelease()` freezes the snapshot its OWN regeneration
    /// wrote, not the one that was on disk when it was called.
    ///
    /// The regeneration reaches `freeze` as an internal function pointer taken
    /// in the base, so what a release records is what the DERIVED hook writes.
    /// A pointer that resolved anywhere else freezes the stale bytes, and a
    /// release recording bytes its own deploy did not produce is silent
    /// afterwards — the immutability guard only fires on a re-cut.
    function testCutReleaseFreezesTheRegeneratedSnapshot() external {
        resetFixture(CUT_FIXTURE_ROOT);
        BuildScriptHarness harness = new BuildScriptHarness(CUT_FIXTURE_ROOT, FIXTURE_CONTRACT);
        string memory stale = harness.marker("stale");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(LibRainDeploySnapshot.dirForSnapshot(CUT_FIXTURE_ROOT, LibRainDeploySnapshot.CANDIDATE), true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(harness.rollingPath(), stale);

        harness.cutRelease();

        // Read while the fixture is still there, asserted once it is gone.
        bool frozenExists = vm.exists(harness.frozenPath());
        string memory frozen = frozenExists ? vm.readFile(harness.frozenPath()) : "";
        string memory rolling = vm.readFile(harness.rollingPath());
        string[] memory record = LibRainDeploySnapshot.frozenSnapshotPaths(vm, CUT_FIXTURE_ROOT);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(CUT_FIXTURE_ROOT, true);

        assertTrue(frozenExists);
        assertEq(frozen, harness.regeneratedSnapshot());
        assertNotEq(frozen, stale);
        assertEq(rolling, harness.regeneratedSnapshot());
        assertEq(record.length, 1);
    }

    /// PROPERTY: `cutRelease()` regenerates the libs AFTER the freeze, so a lib
    /// emitted from the record holds the release being cut.
    ///
    /// Libs written before the freeze describe the record as it was one release
    /// ago, and the release publishes a declaration that omits itself — which
    /// every check downstream then reads as a release nobody ever made.
    function testCutReleaseRegeneratesLibsFromTheRecordJustCut() external {
        resetFixture(LIBS_FIXTURE_ROOT);
        BuildScriptHarness harness = new BuildScriptHarness(LIBS_FIXTURE_ROOT, FIXTURE_CONTRACT);
        harness.cutRelease();

        // Read while the fixture is still there, asserted once it is gone.
        string memory libs = vm.readFile(harness.libsPath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(LIBS_FIXTURE_ROOT, true);

        assertEq(libs, harness.libsMarker(1, true));
    }

    /// PROPERTY: `run()` rewrites both `foundry.toml` network blocks and the
    /// `.env.example` block from the roster, leaving everything outside the
    /// markers where it was.
    ///
    /// This is the wiring, not the emission: what the sections SAY is pinned
    /// against string literals in `LibRainDeployConfigTest`, over a fixture
    /// roster no real network is named in. What is asserted here is that the
    /// entry point CI runs on every push reaches the config at all — without
    /// it the sections would exist, be correct, and be written nowhere, and
    /// `Git is clean` would pass a tree whose config had drifted from the
    /// roster it pins.
    function testRunRegeneratesTheNetworkConfig() external {
        resetFixture(RUN_CONFIG_FIXTURE_ROOT);
        BuildScriptHarness harness = new BuildScriptHarness(RUN_CONFIG_FIXTURE_ROOT, FIXTURE_CONTRACT);
        harness.seedConfig();
        harness.run();

        // Read while the fixture is still there, asserted once it is gone.
        string memory config = vm.readFile(harness.externalConfigPath());
        string memory envExample = vm.readFile(harness.externalEnvExamplePath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(RUN_CONFIG_FIXTURE_ROOT, true);

        assertEq(
            config,
            string.concat(
                "# hand written\n",
                "# rain-deploy:generated:rpc_endpoints:begin\n",
                LibRainDeployConfig.rpcEndpointsSection(vm, LibRainDeploy.supportedNetworkConfigs()),
                "# rain-deploy:generated:rpc_endpoints:end\n",
                "# rain-deploy:generated:etherscan:begin\n",
                LibRainDeployConfig.etherscanSection(vm, LibRainDeploy.supportedNetworkConfigs()),
                "# rain-deploy:generated:etherscan:end\n"
            )
        );
        assertEq(
            envExample,
            string.concat(
                "# hand written\n",
                "# rain-deploy:generated:env:begin\n",
                LibRainDeployConfig.envExampleSection(vm, LibRainDeploy.supportedNetworkConfigs()),
                "# rain-deploy:generated:env:end\n"
            )
        );
    }

    /// PROPERTY: `cutRelease()` leaves the config exactly as it found it.
    ///
    /// The config is not part of a release record. A `cutRelease()` that
    /// rewrote it would put a config change inside the one operation that can
    /// never be repeated, where `run()` is the entry point every push already
    /// runs and the only one `Git is clean` currency checks.
    function testCutReleaseLeavesTheConfigAlone() external {
        resetFixture(CUT_CONFIG_FIXTURE_ROOT);
        BuildScriptHarness harness = new BuildScriptHarness(CUT_CONFIG_FIXTURE_ROOT, FIXTURE_CONTRACT);
        harness.seedConfig();
        harness.cutRelease();

        // Read while the fixture is still there, asserted once it is gone.
        string memory config = vm.readFile(harness.externalConfigPath());
        string memory envExample = vm.readFile(harness.externalEnvExamplePath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(CUT_CONFIG_FIXTURE_ROOT, true);

        assertEq(config, harness.configSeed());
        assertEq(envExample, harness.envExampleSeed());
    }

    /// PROPERTY: a repo that overrides nothing freezes into its OWN record.
    ///
    /// The root is overridable only so a release can be cut somewhere a test
    /// may leave one. The default is the tree `RegistryDeploySuites` reads its
    /// releases from, and a default pointing anywhere else writes releases
    /// nothing enumerates.
    function testRecordRootDefaultsToTheRepoRecord() external {
        BuildScriptHarness harness = new BuildScriptHarness("", FIXTURE_CONTRACT);
        assertEq(harness.externalRecordRoot(), LibRainDeploySnapshot.LIB_FS_ROOT);
    }
}
