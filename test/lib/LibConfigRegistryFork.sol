// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {ConfigRegistry} from "../../src/concrete/ConfigRegistry.sol";
import {IConfigRegistryV1} from "../../src/interface/IConfigRegistryV1.sol";
import {LibConfigRegistry} from "../../src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "../../src/lib/LibConfigRegistryDeploy.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";

/// @title LibConfigRegistryFork
/// @notice What the fork tests need to say about the candidate registry on a
/// live chain, where it is deployed only once a release carrying it has been
/// deployed. Between a candidate change and that deploy the pinned address is
/// empty on every network, and the register loops refuse it on the code hash
/// before reading anything.
library LibConfigRegistryFork {
    /// Whether the selected chain holds the pinned registry.
    /// @return True when the code at the pinned address hashes to the pin.
    function isDeployed() internal view returns (bool) {
        return LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.codehash
            == LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH;
    }

    /// The revert a resolve of `name` under `authority` gives on the selected
    /// chain when `authority` has bound `name` nowhere: the registry's own `NameNotRegistered` where the pinned
    /// registry is deployed, and the code-hash refusal, naming what is there,
    /// where it is not.
    /// @param authority The authority read under.
    /// @param name The unbound name.
    /// @return The revert data.
    function unboundResolveRevert(address authority, bytes32 name) internal view returns (bytes memory) {
        if (isDeployed()) {
            return abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, authority, name);
        }
        return abi.encodeWithSelector(
            LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS.codehash
        );
    }

    /// Deploys the candidate registry on the selected chain through the Zoltu
    /// factory unless it is already there: the state a release deploy leaves.
    /// @param vm The Vm instance to etch the factory with.
    function ensureDeployed(Vm vm) internal {
        if (!isDeployed()) {
            LibRainDeploy.etchAndDeployZoltu(vm, type(ConfigRegistry).creationCode);
        }
    }
}
