// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {ExtendedNetworkUnfrozen} from "../../../src/lib/LibRainDeployMechanism.sol";
import {CloneNetworks, LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PerNetworkCloneDeploys,
    etchPerNetworkCloneRelease,
    onlyFirstRecordedNetworkSuites,
    perNetworkCloneReleaseAddress,
    perNetworkCloneReleaseAddresses
} from "../../abstract/PerNetworkCloneDeploys.sol";

/// @title RainDeployVerifyChainClonePerNetworkUnrecordedTest
/// @notice The chain matrix over a per-network clone release cut when the repo supported Arbitrum
/// One alone, in a repo that now supports Polygon too.
contract RainDeployVerifyChainClonePerNetworkUnrecordedTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// Puts the release's dependencies, and its clone at the address for each network, on every
    /// fork.
    function setUp() external {
        etchPerNetworkCloneRelease(vm, releasedSuites()[0], perNetworkCloneReleaseAddresses());
    }

    /// External wrapper for `checkDeployedOnNetworks`.
    /// @param networks The networks to check on.
    /// @param suites The suites to check.
    function externalCheckDeployedOnNetworks(SupportedNetwork[] memory networks, DeploySuite[] memory suites) external {
        checkDeployedOnNetworks(networks, suites);
    }

    /// External wrapper for `checkDeployedOnSupportedNetworks`.
    /// @param suites The suites to check.
    function externalCheckDeployedOnSupportedNetworks(DeploySuite[] memory suites) external {
        checkDeployedOnSupportedNetworks(suites);
    }

    /// The release, recording Arbitrum One alone.
    /// @return It, as the one suite to check.
    function arbitrumOnlyRelease() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = onlyFirstRecordedNetworkSuites(releasedSuites()[0]);
        CloneNetworks memory clones = abi.decode(suites[0].mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, 1);
        assertEq(clones.networks[0].chainId, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        assertEq(
            clones.networks[0].deployedAddress, perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID)
        );
        return suites;
    }

    /// The release is refused on Polygon as unfrozen, naming the Polygon init data's address, whether
    /// its clone is there or that address is empty: the frozen check runs before the code check.
    function testUnrecordedNetworkIsRefusedAsUnfrozenWhetherOrNotItsCloneIsLive() external {
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        address polygonAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector, "per-network-clone@0_0_1", LibRainDeploy.POLYGON, polygonAddress
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);

        vm.etch(polygonAddress, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector, "per-network-clone@0_0_1", LibRainDeploy.POLYGON, polygonAddress
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// The recorded network, checked alone, is still checked at its recorded address.
    function testRecordedNetworkIsStillCheckedAtItsRecordedAddress() external {
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        address arbitrumAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        vm.etch(arbitrumAddress, hex"");
        string[] memory arbitrum = new string[](1);
        arbitrum[0] = LibRainDeploy.ARBITRUM_ONE;
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, arbitrumAddress
            )
        );
        this.externalCheckDeployedOnNetworks(LibRainDeploy.declaredNetworkConfigs(arbitrum), suites);
    }

    /// A release no candidate is named by takes no network from one.
    function testReleaseNoCandidateNamesIsRefusedOnItsUnrecordedNetworkBeforeAnyFork() external {
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        suites[0].suite = "other-clone@0_0_1";
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployClone.CloneNetworkUndeclared.selector, PER_NETWORK_CLONE_POLYGON_CHAIN_ID
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);

        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        assertFalse(forked, "the matrix forked a network before refusing the unrecorded one");
    }

    /// An unrecorded network the release does not declare is refused as unfrozen before any network is forked.
    function testUnrecordedNetworkIsRefusedAsUnfrozenBeforeAnyFork() external {
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector,
                "per-network-clone@0_0_1",
                LibRainDeploy.POLYGON,
                perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID)
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);

        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        assertFalse(forked, "the matrix forked a network before refusing the unfrozen one");
    }
}
