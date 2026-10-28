// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {ChainBeacon} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {MockRevertingReadBeacon} from "../../concrete/MockRevertingReadBeacon.sol";
import {LibBeaconDeclarations} from "../../lib/LibBeaconDeclarations.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";
import {BeaconVerifyFixture} from "../../abstract/BeaconVerifyFixture.sol";

/// @title RainDeployVerifyBaseBeaconRevertingReadTest
/// @notice `RainDeployVerifyBase.checkSeatedState` leaves a seat read that reverts with data to the chain group.
contract RainDeployVerifyBaseBeaconRevertingReadTest is BeaconVerifyFixture {
    using LibBeaconDeclarations for ChainBeacon[];

    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory declared = fixtureDeclaration();
        declared.released = declaredReleased();
        return declared;
    }

    /// @return The fixture's releases and this test's.
    function declaredReleased() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory fixture = fixtureReleased();
        DeploySuite[] memory released = new DeploySuite[](fixture.length + 2);
        for (uint256 i = 0; i < fixture.length; i++) {
            released[i] = fixture[i];
        }
        released[fixture.length] = revertingReadSuite("owner-reverting-beacon@0_0_1", true);
        released[fixture.length + 1] = revertingReadSuite("implementation-reverting-beacon@0_0_1", false);
        return released;
    }

    /// @param key The suite key.
    /// @param ownerReverts Whether `owner()` reverts, else `implementation()` does.
    /// @return A beacon suite at the implementation suite, owned by `OWNER`, with one read reverting.
    function revertingReadSuite(string memory key, bool ownerReverts) internal pure returns (DeploySuite memory) {
        return LibBeaconTest.zoltuSuite(
            key,
            abi.encodePacked(
                type(MockRevertingReadBeacon).creationCode,
                abi.encode(LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode), OWNER, ownerReverts)
            ),
            type(MockRevertingReadBeacon).runtimeCode,
            "test/concrete/MockRevertingReadBeacon.sol:MockRevertingReadBeacon"
        );
    }

    /// External wrapper for `resolveBeacons`, counting what it resolves.
    /// @param networks The networks whose beacons to resolve.
    /// @return How many beacons resolved.
    function externalResolvedCount(SupportedNetwork[] memory networks) external returns (uint256) {
        return resolveBeacons(networks).length;
    }

    function testBeaconSuiteWhoseOwnerReadRevertsWithDataResolves() external {
        sBeacons.declare(42161, bySuite("owner-reverting-beacon@0_0_1", OWNER));
        assertEq(this.externalResolvedCount(arbitrum()), 1);
    }

    function testBeaconSuiteWhoseImplementationReadRevertsWithDataResolves() external {
        sBeacons.declare(42161, bySuite("implementation-reverting-beacon@0_0_1", OWNER));
        assertEq(this.externalResolvedCount(arbitrum()), 1);
    }
}
