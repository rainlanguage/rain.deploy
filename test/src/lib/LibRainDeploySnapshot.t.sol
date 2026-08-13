// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {
    LibRainDeploySnapshot,
    SnapshotScratchDirCollision,
    UnreleasableVersion
} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title LibRainDeploySnapshotTest
/// @notice The guards on the release machinery every deploy repo inherits.
///
/// These are the paths that only run when something has already gone wrong, so
/// nothing else exercises them — and a guard nobody has seen fire is a guard
/// nobody knows works. Each is driven here directly.
contract LibRainDeploySnapshotTest is Test {
    /// External wrapper so `vm.expectRevert` lands at the right call depth.
    /// @param version The version to convert.
    /// @return The tag.
    function externalTagForVersion(string memory version) external pure returns (string memory) {
        return LibRainDeploySnapshot.tagForVersion(version);
    }

    /// External wrapper so `vm.expectRevert` lands at the right call depth.
    /// @param outputRoot Where the snapshot should end up.
    /// @param dir The snapshot directory.
    /// @return The path written.
    function externalWriteSnapshot(string memory outputRoot, string memory dir) external returns (string memory) {
        return
            LibRainDeploySnapshot.writeSnapshot(
                vm, outputRoot, dir, "MockDeployable", type(MockDeployable).creationCode
            );
    }

    /// Where the record fixture is built. NOT `src/generated`: the inherited
    /// record check reads that root, in other contracts, which forge runs in
    /// parallel with this one — a fixture release there would be a release
    /// those contracts have to fail on, for as long as it exists.
    string constant FIXTURE_ROOT = "test/generated";

    /// Writes one file into the fixture record.
    ///
    /// Carries a licence header because a run that fails midway leaves it
    /// behind, and an unlicensed file in the tree is a second failure on top of
    /// the first.
    /// @param path The file to write, under `FIXTURE_ROOT`.
    function writeFixture(string memory path) internal {
        string[] memory components = vm.split(path, "/");
        string memory dir = components[0];
        for (uint256 i = 1; i < components.length - 1; i++) {
            dir = string.concat(dir, "/", components[i]);
        }
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(dir, true);
        // Split so `reuse lint` reads this as a fixture rather than as this
        // file's own license declaration -- an SPDX identifier in a string
        // literal is indistinguishable from a real one to a line scanner.
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, string.concat("// SPDX-License", "-Identifier: LicenseRef-DCL-1.0\n"));
    }

    /// Whether `paths` holds `path`. The walk's order is the filesystem's, so
    /// membership is the only thing worth asserting about it.
    /// @param paths The paths returned by the walk.
    /// @param path The path to look for.
    /// @return Whether it is there.
    function holdsPath(string[] memory paths, string memory path) internal pure returns (bool) {
        for (uint256 i = 0; i < paths.length; i++) {
            if (keccak256(bytes(paths[i])) == keccak256(bytes(path))) {
                return true;
            }
        }
        return false;
    }

    /// A release tag is what `tagForVersion` produces and nothing else, so
    /// exactly the directories a freeze can write are the ones the record
    /// counts. The rolling `candidate/` is excluded by that same rule rather
    /// than by name.
    function testIsTagAcceptsWhatAFreezeCanWrite() external pure {
        assertTrue(LibRainDeploySnapshot.isTag(LibRainDeploySnapshot.tagForVersion("0.1.7")));
        assertTrue(LibRainDeploySnapshot.isTag("0_0_0"));
        assertTrue(LibRainDeploySnapshot.isTag("10_20_30"));

        assertFalse(LibRainDeploySnapshot.isTag(LibRainDeploySnapshot.CANDIDATE));
        assertFalse(LibRainDeploySnapshot.isTag("0_1"));
        assertFalse(LibRainDeploySnapshot.isTag("0_1_7-rc1"));
        assertFalse(LibRainDeploySnapshot.isTag("0.1.7"));
        assertFalse(LibRainDeploySnapshot.isTag("_1_7"));
        assertFalse(LibRainDeploySnapshot.isTag("0_1_"));
        assertFalse(LibRainDeploySnapshot.isTag(""));
        assertFalse(LibRainDeploySnapshot.isTag("collision-guard"));
    }

    /// EVERY version a freeze accepts MUST produce a directory the record
    /// recognises as a release. A version that could be frozen to a directory
    /// the record then ignores is exactly the orphan snapshot
    /// `UnreleasableVersion` exists to prevent, and it is what two spellings of
    /// the version rule would eventually produce.
    function testEveryFreezableVersionIsATagTheRecordFinds(uint8 major, uint8 minor, uint8 patch) external pure {
        string memory version = string.concat(
            vm.toString(uint256(major)), ".", vm.toString(uint256(minor)), ".", vm.toString(uint256(patch))
        );

        assertTrue(LibRainDeploySnapshot.isStrictTriple(version, "."));
        assertTrue(LibRainDeploySnapshot.isTag(LibRainDeploySnapshot.tagForVersion(version)));
    }

    /// The record is every file inside a release-tag directory, and only those.
    ///
    /// The whole point of reading the tree is that it is the one description of
    /// what a repo has released that cannot fall behind, so a walk that quietly
    /// found nothing would leave exactly the hole it is here to close. Driven
    /// against a directory that really has releases in it.
    function testFrozenSnapshotPathsFindsEveryReleaseAndNothingElse() external {
        writeFixture(string.concat(FIXTURE_ROOT, "/0_0_1/MockDeployable.sol"));
        writeFixture(string.concat(FIXTURE_ROOT, "/0_0_2/MockDeployableV2.sol"));
        writeFixture(string.concat(FIXTURE_ROOT, "/0_0_2/Second.sol"));
        // Not releases: the rolling snapshot, a version no freeze could have
        // written, a file loose in the root, and a file too deep to be a record.
        writeFixture(string.concat(FIXTURE_ROOT, "/", LibRainDeploySnapshot.CANDIDATE, "/MockDeployable.sol"));
        writeFixture(string.concat(FIXTURE_ROOT, "/0_0_3-rc1/MockDeployable.sol"));
        writeFixture(string.concat(FIXTURE_ROOT, "/Loose.sol"));
        writeFixture(string.concat(FIXTURE_ROOT, "/0_0_1/nested/TooDeep.sol"));

        string[] memory paths = LibRainDeploySnapshot.frozenSnapshotPaths(vm, FIXTURE_ROOT);

        assertTrue(holdsPath(paths, string.concat(FIXTURE_ROOT, "/0_0_1/MockDeployable.sol")));
        assertTrue(holdsPath(paths, string.concat(FIXTURE_ROOT, "/0_0_2/MockDeployableV2.sol")));
        assertTrue(holdsPath(paths, string.concat(FIXTURE_ROOT, "/0_0_2/Second.sol")));
        assertEq(paths.length, 3);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(FIXTURE_ROOT, true);
    }

    /// A root that is not there at all MUST read as a repo that has released
    /// nothing, not as a failure. That is the state of every deploy repo before
    /// its first release, including this one.
    function testFrozenSnapshotPathsOnAMissingRoot() external view {
        assertFalse(vm.exists(FIXTURE_ROOT));
        assertEq(LibRainDeploySnapshot.frozenSnapshotPaths(vm, FIXTURE_ROOT).length, 0);
    }

    /// The rolling snapshot MUST NOT be in this repo's own record. It is the
    /// only directory in `src/generated/` today, and a walk that returned it
    /// would make the candidate a release that has to be declared and deployed.
    function testFrozenSnapshotPathsExcludesTheRollingSnapshot() external view {
        assertTrue(vm.exists(LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "AddressRegistry")));
        assertFalse(
            holdsPath(
                LibRainDeploySnapshot.frozenSnapshotPaths(vm, LibRainDeploySnapshot.LIB_FS_ROOT),
                LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "AddressRegistry")
            )
        );
    }

    /// A strict `X.Y.Z` version MUST become its directory form.
    function testTagForVersionConvertsDots() external pure {
        assertEq(LibRainDeploySnapshot.tagForVersion("0.1.7"), "0_1_7");
        assertEq(LibRainDeploySnapshot.tagForVersion("10.20.30"), "10_20_30");
        assertEq(LibRainDeploySnapshot.tagForVersion("0.0.0"), "0_0_0");
    }

    /// Anything that is not strict `X.Y.Z` MUST be refused rather than mapped
    /// to a directory the append-only gate ignores forever.
    function testTagForVersionRefusesNonStrict() external {
        string[9] memory bad = ["0.1.7-rc1", "0.1", "0.1.7.1", "", "a.b.c", ".1.7", "0..7", "0.1.", "0.1.7 "];
        for (uint256 i = 0; i < bad.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(UnreleasableVersion.selector, bad[i]));
            this.externalTagForVersion(bad[i]);
        }
    }

    /// The tag read from `foundry.toml` MUST go through the same guard, so a
    /// repo cannot reach a release path with a version the guard would refuse.
    function testDeployTagUsesTheGuardedConversion() external view {
        assertEq(
            LibRainDeploySnapshot.deployTag(vm),
            LibRainDeploySnapshot.tagForVersion(vm.parseTomlString(vm.readFile("foundry.toml"), ".package.version"))
        );
    }

    /// Snapshot paths MUST agree with `LibFs`, which is what writes them.
    function testSnapshotPathsAgreeWithTheWriter() external pure {
        assertEq(LibRainDeploySnapshot.dirForSnapshot("0_1_7"), "src/generated/0_1_7");
        assertEq(LibRainDeploySnapshot.snapshotName("0_1_7", "Foo"), "0_1_7/Foo");
        assertEq(LibRainDeploySnapshot.pathForSnapshot("0_1_7", "Foo"), "src/generated/0_1_7/Foo.sol");
    }

    /// Generating to a non-default root stages through `src/generated/<dir>`
    /// and REMOVES it afterwards. So it MUST refuse a directory that already
    /// exists: that removal is under the directory frozen releases live in, and
    /// a colliding `dir` would destroy one.
    function testWriteSnapshotRefusesAnExistingScratchDir() external {
        string memory dir = "collision-guard";
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(LibRainDeploySnapshot.dirForSnapshot(dir), true);

        vm.expectRevert(
            abi.encodeWithSelector(SnapshotScratchDirCollision.selector, dir, LibRainDeploySnapshot.dirForSnapshot(dir))
        );
        this.externalWriteSnapshot("test/generated", dir);

        // The guard must leave it alone, not remove it.
        assertTrue(vm.exists(LibRainDeploySnapshot.dirForSnapshot(dir)));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(LibRainDeploySnapshot.dirForSnapshot(dir), true);
    }

    /// Generating to the DEFAULT root does not stage, so it MUST NOT refuse an
    /// existing directory — that is the ordinary case of regenerating a
    /// snapshot that is already there.
    function testWriteSnapshotAllowsAnExistingDirWithoutStaging() external {
        string memory dir = "no-staging-guard";
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(LibRainDeploySnapshot.dirForSnapshot(dir), true);

        assertEq(
            this.externalWriteSnapshot(LibRainDeploySnapshot.LIB_FS_ROOT, dir),
            LibRainDeploySnapshot.pathForSnapshot(dir, "MockDeployable")
        );

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(LibRainDeploySnapshot.dirForSnapshot(dir), true);
    }
}
