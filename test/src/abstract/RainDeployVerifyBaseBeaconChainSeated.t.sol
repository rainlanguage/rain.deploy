// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {BeaconSeatedOwner} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {ChainBeacon} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {MockChainSeatedBeacon} from "../../concrete/MockChainSeatedBeacon.sol";
import {LibBeaconDeclarations} from "../../lib/LibBeaconDeclarations.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";
import {BeaconVerifyFixture} from "../../abstract/BeaconVerifyFixture.sol";

/// @title RainDeployVerifyBaseBeaconChainSeatedTest
/// @notice `RainDeployVerifyBase.checkSeatedState` deploys a beacon suite on the beacon's own network.
contract RainDeployVerifyBaseBeaconChainSeatedTest is BeaconVerifyFixture {
    using LibBeaconDeclarations for ChainBeacon[];

    /// The owner the chain-seated beacon suite seats on every chain but Arbitrum One.
    address constant ELSEWHERE_OWNER = address(0xE15E);

    /// @inheritdoc BeaconVerifyFixture
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory fixture = super.releasedSuites();
        DeploySuite[] memory released = new DeploySuite[](fixture.length + 1);
        for (uint256 i = 0; i < fixture.length; i++) {
            released[i] = fixture[i];
        }
        released[fixture.length] = LibBeaconTest.zoltuSuite(
            "chain-beacon@0_0_1",
            abi.encodePacked(
                type(MockChainSeatedBeacon).creationCode,
                abi.encode(
                    LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode), OWNER, ELSEWHERE_OWNER, 42161
                )
            ),
            type(MockChainSeatedBeacon).runtimeCode,
            "test/concrete/MockChainSeatedBeacon.sol:MockChainSeatedBeacon"
        );
        return released;
    }

    /// External wrapper for `resolveBeacons`, counting what it resolves.
    /// @param networks The networks whose beacons to resolve.
    /// @return How many beacons resolved.
    function externalResolvedCount(SupportedNetwork[] memory networks) external returns (uint256) {
        return resolveBeacons(networks).length;
    }

    function testBeaconSuiteSeatingItsNetworksOwnerResolves() external {
        sBeacons.declare(42161, bySuite("chain-beacon@0_0_1", OWNER));
        assertEq(this.externalResolvedCount(arbitrum()), 1);
    }

    function testBeaconSuiteSeatingAnotherNetworksOwnerIsRefused() external {
        sBeacons.declare(8453, bySuite("chain-beacon@0_0_1", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSeatedOwner.selector, 8453, 0, abi.encode(ELSEWHERE_OWNER)));
        this.externalResolvedCount(networksNamed(LibRainDeploy.BASE, ""));
    }

    function testSeatedStateCheckRestoresTheChainId() external {
        uint256 chainId = block.chainid;
        sBeacons.declare(42161, bySuite("chain-beacon@0_0_1", OWNER));
        this.externalResolvedCount(arbitrum());
        assertEq(block.chainid, chainId);
    }
}
