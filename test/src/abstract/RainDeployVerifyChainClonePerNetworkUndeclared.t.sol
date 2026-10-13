// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {PerNetworkCloneDeploys} from "../../abstract/PerNetworkCloneDeploys.sol";

/// @title RainDeployVerifyChainClonePerNetworkUndeclaredTest
/// @notice A repo verified on a network its per-network clone declares no init
/// data for. The matrix refuses it naming that network's chain id, and before
/// any endpoint is touched: a network the declaration says nothing about has
/// no address to check, and checking some other network's address there would
/// be checking a clone nobody declared for it.
///
/// Its own contract because a contract has exactly one declaration.
contract RainDeployVerifyChainClonePerNetworkUndeclaredTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// Base's chain id, as a fact of the world.
    uint256 constant BASE_CHAIN_ID = 8453;

    /// @inheritdoc RainDeploySuitesBase
    /// @dev The clone's two networks, then Base, which it has no entry for.
    function supportedNetworks()
        internal
        pure
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory networks)
    {
        networks = new string[](3);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        networks[2] = LibRainDeploy.BASE;
    }

    /// The matrix refuses the undeclared network by chain id, and has forked
    /// nothing when it does.
    function testUndeclaredNetworkIsRefusedBeforeAnyFork() external {
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.CloneNetworkUndeclared.selector, BASE_CHAIN_ID));
        this.testSuitesLiveOnEverySupportedNetwork();

        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        assertFalse(forked, "the matrix forked a network before refusing the undeclared one");
    }
}
