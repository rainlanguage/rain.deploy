// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {InitDataReaderUndeclared} from "../../../src/lib/LibRainDeployMechanism.sol";
import {CloneNetworks} from "../../../src/lib/LibRainDeployClone.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PerNetworkCloneDeploys,
    onlyFirstRecordedNetwork,
    perNetworkCloneReleaseAddress
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {
    UpgradedPerNetworkCloneDeploys,
    upgradedPerNetworkClone
} from "../../abstract/UpgradedPerNetworkCloneDeploys.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// @title RainDeployVerifyChainClonePerNetworkSubsetTest
/// @notice The chain matrix, on local forks, over a per-network release recording Arbitrum One alone, in a repo whose
/// candidate has moved to another implementation and declares no init data reader, checked on a subset of networks.
contract RainDeployVerifyChainClonePerNetworkSubsetTest is UpgradedPerNetworkCloneDeploys, RainDeployVerifyChain {
    /// The fork cheatcodes the matrix runs against.
    LocalForkVm internal sForkVm;

    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// None.
    /// @param suite The candidate's suite key.
    /// @return No implementations.
    function initDataReaders(string memory suite)
        internal
        pure
        override(UpgradedPerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (address[] memory)
    {
        (suite);
        return new address[](0);
    }

    /// Puts the release's dependencies, and its clone at its Arbitrum One address, on every fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        for (uint256 i = 0; i < release.dependencies.length; i++) {
            vm.etch(release.dependencies[i].deployedAddress, release.dependencies[i].runtimeCode);
            vm.makePersistent(release.dependencies[i].deployedAddress);
        }
        address arbitrumAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        vm.etch(arbitrumAddress, release.storedRuntimeCode);
        vm.makePersistent(arbitrumAddress);
        sForkVm = new LocalForkVm();
    }

    /// The matrix on local forks over the given networks, over the release recording Arbitrum One alone.
    /// @param networks The networks to check on.
    function externalCheckOnLocalForks(string[] memory networks) external {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = onlyFirstRecordedNetwork(releasedSuites()[0]);
        checkDeployedOnNetworks(Vm(address(sForkVm)), LibRainDeploy.declaredNetworkConfigs(networks), suites);
    }

    /// On Arbitrum One alone the candidate's Polygon is out of play, so the release needs no init data reader and
    /// Polygon is never forked; on every supported network the candidate's Polygon is taken and refused.
    function testSubsetTakesNoOutOfPlayCandidateNetwork() external {
        CloneNetworks memory release =
            abi.decode(onlyFirstRecordedNetwork(releasedSuites()[0]).mechanismData, (CloneNetworks));
        assertNotEq(release.implementation, upgradedPerNetworkClone().implementation);

        string[] memory arbitrum = new string[](1);
        arbitrum[0] = LibRainDeploy.ARBITRUM_ONE;
        vm.expectCall(address(sForkVm), abi.encodeCall(LocalForkVm.createFork, (LibRainDeploy.POLYGON)), 0);
        vm.expectCall(address(sForkVm), abi.encodeCall(LocalForkVm.createFork, (LibRainDeploy.ARBITRUM_ONE)), 1);
        this.externalCheckOnLocalForks(arbitrum);

        vm.expectRevert(
            abi.encodeWithSelector(InitDataReaderUndeclared.selector, "per-network-clone@0_0_1", release.implementation)
        );
        this.externalCheckOnLocalForks(supportedNetworks());
    }
}
