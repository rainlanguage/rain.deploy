// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployDeclaration, DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ChainBeacon, DeployBeacon} from "../../src/lib/LibRainDeployBeacon.sol";
import {LibBeaconDeclarations} from "../lib/LibBeaconDeclarations.sol";
import {ExampleDeployScript} from "./ExampleDeployScript.sol";
import {MockOriginOwned} from "../concrete/MockOriginOwned.sol";

/// @title BeaconOwnerDeployScript
/// @notice `ExampleDeployScript` with the beacons a test declares, and `broadcastSuite` exposed.
abstract contract BeaconOwnerDeployScript is ExampleDeployScript {
    using LibBeaconDeclarations for ChainBeacon[];

    /// The beacons `beaconOwnerDeclaration()` declares.
    ChainBeacon[] internal sBeacons;

    /// @return The exemplar declaration with the beacons a test declared.
    function beaconOwnerDeclaration() internal view returns (DeployDeclaration memory) {
        DeployDeclaration memory declared = exampleDeclaration();
        declared.beacons = sBeacons;
        return declared;
    }

    /// @param chainId The beacon's network.
    /// @param beacon The beacon.
    function declareBeacon(uint256 chainId, DeployBeacon memory beacon) external {
        sBeacons.declare(chainId, beacon);
    }

    /// @param suite The suite to broadcast.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    function externalBroadcastSuite(DeploySuite memory suite, string[] memory networks, uint256 deployerPrivateKey)
        external
    {
        broadcastSuite(suite, networks, deployerPrivateKey);
    }

    /// @param suite The suite to check.
    /// @param networks The networks the broadcast reaches.
    /// @param deployer The deploy key's address.
    function externalCheckSeatsNoDeployKey(DeploySuite memory suite, string[] memory networks, address deployer)
        external
    {
        checkSeatsNoDeployKey(suite, networks, deployer);
    }

    /// @param suite The suite to check.
    /// @param networks The networks the broadcast reaches.
    /// @param deployer The deploy key's address.
    /// @return The origin of a contract this deploy creates once the check returns.
    function externalCheckSeatsNoDeployKeyThenOrigin(
        DeploySuite memory suite,
        string[] memory networks,
        address deployer
    ) external returns (address) {
        checkSeatsNoDeployKey(suite, networks, deployer);
        return new MockOriginOwned().owner();
    }
}
