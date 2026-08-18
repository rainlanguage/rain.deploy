// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
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

    /// PROPERTY: `run()` regenerates everything and freezes NOTHING.
    ///
    /// This is the entry point CI calls on every push. A `run()` that cut a
    /// release would freeze whatever a branch happened to compile under the
    /// repo's current tag, and that tag can then never be cut again for real.
    ///
    /// The lib marker also carries the order: the libs are written after the
    /// snapshots, from a record that holds no release.
    function testRunRegeneratesAndFreezesNothing() external {
        BuildScriptHarness harness = new BuildScriptHarness(RUN_FIXTURE_ROOT, FIXTURE_CONTRACT);
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
        BuildScriptHarness harness = new BuildScriptHarness(LIBS_FIXTURE_ROOT, FIXTURE_CONTRACT);
        harness.cutRelease();

        // Read while the fixture is still there, asserted once it is gone.
        string memory libs = vm.readFile(harness.libsPath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(LIBS_FIXTURE_ROOT, true);

        assertEq(libs, harness.libsMarker(1, true));
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
