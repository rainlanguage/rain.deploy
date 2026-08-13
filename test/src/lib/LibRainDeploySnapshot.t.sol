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
