// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {PerNetworkCloneDeploys} from "../../abstract/PerNetworkCloneDeploys.sol";

/// @title RainDeployVerifyChainClonePerNetworkUndeclaredTest
/// @notice A repo verified on a network its per-network clone declares no init
/// data for. The matrix refuses it naming that network's chain id, and before
/// any endpoint is touched: a network the declaration says nothing about has
/// no address to check, and checking some other network's address there would
/// be checking a clone nobody declared for it.
///
/// The undeclared network is switched on by the refusal test alone, so the
/// inherited `testSuitesLiveOnEverySupportedNetwork` runs over the clone's own
/// two networks — with the release etched at each one's address — and passes,
/// and the refusal is measured against a matrix that otherwise accepts.
contract RainDeployVerifyChainClonePerNetworkUndeclaredTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// Base's chain id, as a fact of the world.
    uint256 constant BASE_CHAIN_ID = 8453;

    /// Whether Base, which the clone has no entry for, is a supported network.
    bool internal sIncludeBase;

    /// Puts the released clone at its address for each network, on every fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        address[] memory addresses = LibRainDeployMechanism.deployedAddresses(release);
        for (uint256 i = 0; i < addresses.length; i++) {
            vm.etch(addresses[i], release.storedRuntimeCode);
            vm.makePersistent(addresses[i]);
        }
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev The clone's two networks, then Base once `sIncludeBase` is set.
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory networks)
    {
        networks = new string[](sIncludeBase ? 3 : 2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        if (sIncludeBase) {
            networks[2] = LibRainDeploy.BASE;
        }
    }

    /// The matrix refuses the undeclared network by chain id, and has forked
    /// nothing when it does.
    function testUndeclaredNetworkIsRefusedBeforeAnyFork() external {
        sIncludeBase = true;
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.CloneNetworkUndeclared.selector, BASE_CHAIN_ID));
        this.testSuitesLiveOnEverySupportedNetwork();

        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        assertFalse(forked, "the matrix forked a network before refusing the undeclared one");
    }
}
