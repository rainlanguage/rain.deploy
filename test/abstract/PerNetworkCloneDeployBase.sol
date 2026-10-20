// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {StdConstants} from "forge-std-1.17.0/src/StdConstants.sol";
import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {CloneNetwork} from "../../src/lib/LibRainDeployClone.sol";
import {LibRainDeployExtendedNetworks} from "../../src/lib/LibRainDeployExtendedNetworks.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {LibExtendedNetworksFixture} from "../lib/LibExtendedNetworksFixture.sol";
import {ExternalCloneDeploySuites} from "./ExternalCloneDeploySuites.sol";
import {ExternalDeploySuites} from "./ExternalDeploySuites.sol";

/// @title PerNetworkCloneDeployBase
/// @notice `RainDeployBroadcast` with settable extended networks and external wrappers,
/// so a plain `Test` contract can drive a per-network clone declaration under it.
abstract contract PerNetworkCloneDeployBase is ExternalCloneDeploySuites, ExternalDeploySuites, RainDeployBroadcast {
    /// The suite `sExtendedNetworks` is declared for.
    string internal sExtendedSuite;

    /// The networks `extendedNetworks` declares for `sExtendedSuite`. Empty by default.
    CloneNetwork[] internal sExtendedNetworks;

    /// The record root `extendedNetworksRoot` gives once `setExtendedNetworks` has run.
    string internal sExtendedRoot;

    /// Sets what `extendedNetworks` declares, and records it as the build would under its own fixture root, after
    /// removing whatever an earlier run left there.
    /// @param label The fixture root's directory under `fixture-lib/extended-networks`, one per test.
    /// @param suite The release's suite key.
    /// @param networks The networks it declares for that release.
    function setExtendedNetworks(string memory label, string memory suite, CloneNetwork[] memory networks) external {
        declareExtendedNetworks(label, suite, networks);
        LibRainDeployExtendedNetworks.writeExtendedNetworks(StdConstants.VM, sExtendedRoot, suite, networks);
    }

    /// `setExtendedNetworks` without the record: the fixture root holds none.
    /// @param label The fixture root's directory under `fixture-lib/extended-networks`, one per test.
    /// @param suite The release's suite key.
    /// @param networks The networks it declares for that release.
    function declareExtendedNetworks(string memory label, string memory suite, CloneNetwork[] memory networks) public {
        sExtendedRoot =
            LibExtendedNetworksFixture.freshRoot(StdConstants.VM, "fixture-lib/extended-networks", label, suite);
        sExtendedSuite = suite;
        delete sExtendedNetworks;
        for (uint256 i = 0; i < networks.length; i++) {
            sExtendedNetworks.push(networks[i]);
        }
    }

    /// `sExtendedRoot` once `setExtendedNetworks` has run, else the repo's own record.
    /// @return The record root.
    function extendedNetworksRoot() internal view virtual override returns (string memory) {
        if (bytes(sExtendedRoot).length == 0) {
            return LibRainDeploySnapshot.LIB_FS_ROOT;
        }
        return sExtendedRoot;
    }

    /// `sExtendedNetworks` for `sExtendedSuite`, else none.
    /// @param suite The release's suite key.
    /// @return The networks.
    function extendedNetworks(string memory suite) internal view virtual override returns (CloneNetwork[] memory) {
        if (keccak256(bytes(suite)) != keccak256(bytes(sExtendedSuite))) {
            return new CloneNetwork[](0);
        }
        return sExtendedNetworks;
    }

    /// External wrapper for `broadcastSuite`.
    /// @param suite The suite to broadcast.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @return Where the suite is on each network.
    /// @return The fork each network was deployed on.
    function externalBroadcastSuite(DeploySuite memory suite, string[] memory networks, uint256 deployerPrivateKey)
        external
        returns (address[] memory, uint256[] memory)
    {
        return broadcastSuite(suite, networks, deployerPrivateKey);
    }
}
