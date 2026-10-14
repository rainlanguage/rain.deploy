// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    FrozenSnapshotNotReleased,
    RainDeployVerifySnapshotBase
} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {
    EXAMPLE_CLONE_RECORD_ROOT,
    ExampleCloneDeploys,
    exampleCloneRelease
} from "../../abstract/ExampleCloneDeploys.sol";

/// @title RainDeployVerifySnapshotBaseCloneTest
/// @notice The snapshot group over a clone deploy repo.
contract RainDeployVerifySnapshotBaseCloneTest is ExampleCloneDeploys, RainDeployVerifySnapshotBase {
    /// @param paths The frozen record paths.
    /// @param released The released suites.
    function externalCheckFrozenSnapshotsReleased(string[] memory paths, DeploySuite[] memory released) external view {
        checkFrozenSnapshotsReleased(paths, released);
    }

    /// The frozen release sits at a clone address and not at the Zoltu address of its creation
    /// code, so a consistency check that derived it as Zoltu would fail it rather than pass it.
    function testFrozenCloneReleaseIsNotAtItsZoltuAddress() external view {
        DeploySuite memory release = releasedSuites()[0];
        assertEq(release.storedDeployedAddress, LibRainDeployMechanism.deployedAddresses(release)[0]);
        assertNotEq(release.storedDeployedAddress, LibRainDeploy.zoltuAddress(release.creationCode));
        assertEq(
            release.storedDeployedAddress,
            LibRainDeployMechanism.cloneCandidate(exampleCloneRelease(), new uint256[](0)).snapshot
                .storedDeployedAddress
        );
    }

    /// The committed clone record is accounted for by the clone release declared from it.
    function testFrozenCloneRecordIsReleased() external view {
        string[] memory paths = LibRainDeploySnapshot.frozenSnapshotPaths(vm, EXAMPLE_CLONE_RECORD_ROOT);
        assertEq(paths.length, 1, "the fixture record holds one release");
        checkFrozenSnapshotsReleased(paths, releasedSuites());
    }

    /// A frozen clone record that nothing declares is refused, and so is one whose only
    /// declarations are the candidates.
    function testFrozenCloneRecordWithoutItsReleaseIsRefused() external {
        string[] memory paths = LibRainDeploySnapshot.frozenSnapshotPaths(vm, EXAMPLE_CLONE_RECORD_ROOT);
        assertEq(paths.length, 1, "the fixture record holds one release");

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, paths[0]));
        this.externalCheckFrozenSnapshotsReleased(paths, new DeploySuite[](0));

        DeploySuite[] memory candidates = new DeploySuite[](candidateSuites().length);
        for (uint256 i = 0; i < candidates.length; i++) {
            candidates[i] = candidateSuites()[i].snapshot;
        }
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, paths[0]));
        this.externalCheckFrozenSnapshotsReleased(paths, candidates);
    }
}
