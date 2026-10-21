// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {ICloneableFactoryV4} from "rain-factory-0.2.4/src/interface/deprecated/ICloneableFactoryV4.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {CloneNetworks} from "../../../src/lib/LibRainDeployClone.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PerNetworkCloneDeploys,
    etchPerNetworkCloneRelease,
    onlyFirstRecordedNetwork,
    onlyFirstRecordedNetworkSuites,
    perNetworkCloneInitData
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {
    UpgradedPerNetworkCloneDeploys,
    upgradedPerNetworkClone
} from "../../abstract/UpgradedPerNetworkCloneDeploys.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// @title RainDeployVerifyChainClonePerNetworkSubsetTest
/// @notice The chain matrix, on local forks, over a per-network release recording Arbitrum One alone, in a repo whose
/// candidate has moved to another implementation, checked on a subset of networks.
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

    /// Puts the release's dependencies, and its clone at every recorded address, on every fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        etchPerNetworkCloneRelease(vm, release, LibRainDeployMechanism.deployedAddresses(release));
        sForkVm = new LocalForkVm();
    }

    /// The matrix on local forks over the given networks, over the release recording Arbitrum One alone.
    /// @param networks The networks to check on.
    function externalCheckOnLocalForks(string[] memory networks) external {
        DeploySuite[] memory suites = onlyFirstRecordedNetworkSuites(releasedSuites()[0]);
        checkDeployedOnNetworks(Vm(address(sForkVm)), LibRainDeploy.declaredNetworkConfigs(networks), suites);
    }

    /// On Arbitrum One alone the candidate's Polygon is out of play, so the release passes and Polygon is never deployed
    /// locally or forked.
    function testSubsetTakesNoOutOfPlayCandidateNetwork() external {
        CloneNetworks memory release =
            abi.decode(onlyFirstRecordedNetwork(releasedSuites()[0]).mechanismData, (CloneNetworks));
        assertNotEq(release.implementation, upgradedPerNetworkClone().implementation);

        string[] memory arbitrum = new string[](1);
        arbitrum[0] = LibRainDeploy.ARBITRUM_ONE;
        vm.expectCall(address(sForkVm), abi.encodeCall(LocalForkVm.createFork, (LibRainDeploy.POLYGON)), 0);
        vm.expectCall(address(sForkVm), abi.encodeCall(LocalForkVm.createFork, (LibRainDeploy.ARBITRUM_ONE)), 1);
        vm.expectCall(
            release.factory,
            abi.encodeCall(
                ICloneableFactoryV4.cloneDeterministicOpenSalt,
                (release.implementation, perNetworkCloneInitData(PER_NETWORK_CLONE_POLYGON_CHAIN_ID), release.salt)
            ),
            0
        );
        vm.expectCall(
            release.factory,
            abi.encodeCall(
                ICloneableFactoryV4.cloneDeterministicOpenSalt,
                (release.implementation, perNetworkCloneInitData(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID), release.salt)
            ),
            1
        );
        this.externalCheckOnLocalForks(arbitrum);
    }
}
