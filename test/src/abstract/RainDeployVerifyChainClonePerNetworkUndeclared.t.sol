// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {
    NoPerNetworkCloneAdmin,
    PerNetworkCloneDeploys,
    etchPerNetworkCloneRelease
} from "../../abstract/PerNetworkCloneDeploys.sol";

/// @title RainDeployVerifyChainClonePerNetworkUndeclaredTest
/// @notice A repo verified on a network its per-network clone's `initData` has no init data for.
contract RainDeployVerifyChainClonePerNetworkUndeclaredTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// Base's chain id, as a fact of the world.
    uint256 constant BASE_CHAIN_ID = 8453;

    /// Whether Base, which the clone has no entry for, is a supported network.
    bool internal sIncludeBase;

    /// Puts the release's dependencies, and its clone at its address for each network, on every
    /// fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        etchPerNetworkCloneRelease(vm, release, LibRainDeployMechanism.deployedAddresses(release));
    }

    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        string[] memory networks = new string[](sIncludeBase ? 3 : 2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        if (sIncludeBase) {
            networks[2] = LibRainDeploy.BASE;
        }
        return networks;
    }

    /// The matrix refuses the network with the declaration's refusal of its chain id, and has
    /// forked nothing when it does.
    function testUndeclaredNetworkIsRefusedBeforeAnyFork() external {
        sIncludeBase = true;
        vm.expectRevert(abi.encodeWithSelector(NoPerNetworkCloneAdmin.selector, BASE_CHAIN_ID));
        this.testSuitesLiveOnEverySupportedNetwork();

        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        assertFalse(forked, "the matrix forked a network before refusing the undeclared one");
    }
}
