// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {BuildRecordRootHarness} from "../concrete/BuildRecordRootHarness.sol";

/// @title BuildRecordRootTest
/// @notice Where `script/Build.sol` writes when `recordRoot()` is overridden —
/// the one thing `BuildScript` documents the root as being overridable for.
///
/// A contract of its own because this one WRITES, and `BuildTest` states that
/// nothing in it does. What is asserted here is which tree the write lands in,
/// so the write is the subject rather than a side effect: it goes under this
/// contract's own fixture root, and the committed record it would otherwise
/// have gone into is read and left alone.
contract BuildRecordRootTest is Test {
    string constant FIXTURE_ROOT = "test/generated-build-record-root";

    /// A cheatcode write is not undone by a revert, so a failure leaves
    /// generated sources on disk and the next run reads THOSE.
    function resetFixture(string memory root) internal {
        if (vm.exists(root)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(root, true);
        }
    }

    /// PROPERTY: `Build`'s regeneration writes every rolling snapshot — the
    /// suites' and the parameterised contracts' — under
    /// `recordRoot()`.
    ///
    /// `cutRelease()` freezes each contract from `pathForSnapshot(recordRoot(),
    /// CANDIDATE, name)`, so a regeneration that ignores the root hands the
    /// freeze a record nothing wrote — `NothingToFreeze` for any repo that
    /// overrides the root — and rewrites the real `src/generated/candidate/` on
    /// the way to that revert, which is the tree the override exists to keep a
    /// caller's hands off.
    ///
    /// The bytes are the committed candidate's, read from the real record: the
    /// regeneration is a function of what this repo compiles and the committed
    /// snapshot is what it last compiled to, so an equal file under the fixture
    /// root is the whole snapshot having moved rather than a file having been
    /// created there.
    function testRegenerateSnapshotsWritesUnderTheRecordRoot() external {
        resetFixture(FIXTURE_ROOT);
        BuildRecordRootHarness harness = new BuildRecordRootHarness(FIXTURE_ROOT);
        string[] memory suiteNames = harness.externalSnapshotContractNames();
        string[] memory parameterisedNames = harness.externalParameterisedContractNames();
        string[] memory names = new string[](suiteNames.length + parameterisedNames.length);
        for (uint256 i = 0; i < names.length; i++) {
            names[i] = i < suiteNames.length ? suiteNames[i] : parameterisedNames[i - suiteNames.length];
        }

        harness.externalRegenerateSnapshots();

        // Read while the fixture is still there, asserted once it is gone.
        bool[] memory written = new bool[](names.length);
        string[] memory regenerated = new string[](names.length);
        string[] memory committed = new string[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            string memory path =
                LibRainDeploySnapshot.pathForSnapshot(FIXTURE_ROOT, LibRainDeploySnapshot.CANDIDATE, names[i]);
            written[i] = vm.exists(path);
            regenerated[i] = written[i] ? vm.readFile(path) : "";
            committed[i] = vm.readFile(LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, names[i]));
        }

        resetFixture(FIXTURE_ROOT);

        assertTrue(names.length > 0, "no contract is generated, so nothing was asserted");
        for (uint256 i = 0; i < names.length; i++) {
            assertTrue(written[i], string.concat("regeneration wrote nothing under the record root: ", names[i]));
            assertEq(
                regenerated[i],
                committed[i],
                string.concat("snapshot under the record root is not the committed one: ", names[i])
            );
        }
    }

    /// PROPERTY: the record `cutRelease()` freezes is the WHOLE candidate: every
    /// file the regeneration writes to `<root>/candidate/` is frozen, byte for
    /// byte, into `<root>/<tag>/`, and nothing else is.
    ///
    /// The release guard refuses a tag whose frozen record differs from the
    /// freshly regenerated candidate, so a freeze that leaves a candidate file
    /// out cuts a release that can never publish.
    function testFreezeRecordsTheWholeCandidate() external {
        string memory root = string.concat(FIXTURE_ROOT, "-freeze");
        resetFixture(root);
        BuildRecordRootHarness harness = new BuildRecordRootHarness(root);

        harness.externalFreeze();

        string memory tag = LibRainDeploySnapshot.deployTag(vm);
        Vm.DirEntry[] memory candidate = vm.readDir(string.concat(root, "/", LibRainDeploySnapshot.CANDIDATE));
        Vm.DirEntry[] memory frozen = vm.readDir(string.concat(root, "/", tag));
        string[] memory candidateBytes = new string[](candidate.length);
        string[] memory frozenBytes = new string[](candidate.length);
        bool[] memory isFrozen = new bool[](candidate.length);
        for (uint256 i = 0; i < candidate.length; i++) {
            candidateBytes[i] = vm.readFile(candidate[i].path);
            string memory frozenPath = string.concat(root, "/", tag, "/", fileName(candidate[i].path));
            isFrozen[i] = vm.exists(frozenPath);
            frozenBytes[i] = isFrozen[i] ? vm.readFile(frozenPath) : "";
        }

        resetFixture(root);

        assertTrue(candidate.length > 0, "the regeneration wrote no candidate");
        assertEq(frozen.length, candidate.length, "the frozen record and the candidate hold different file counts");
        for (uint256 i = 0; i < candidate.length; i++) {
            assertTrue(isFrozen[i], string.concat("candidate file not frozen: ", candidate[i].path));
            assertEq(frozenBytes[i], candidateBytes[i], string.concat("frozen bytes differ: ", candidate[i].path));
        }
    }

    /// The last path component.
    /// @param path The path.
    /// @return The file name.
    function fileName(string memory path) internal pure returns (string memory) {
        string[] memory parts = vm.split(path, "/");
        return parts[parts.length - 1];
    }
}
