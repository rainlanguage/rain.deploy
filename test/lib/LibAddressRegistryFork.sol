// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {AddressRegistry} from "../../src/concrete/AddressRegistry.sol";
import {IAddressRegistryV2} from "../../src/interface/IAddressRegistryV2.sol";
import {LibAddressRegistry} from "../../src/lib/LibAddressRegistry.sol";
import {LibAddressRegistryDeploy} from "../../src/lib/LibAddressRegistryDeploy.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";

/// @title LibAddressRegistryFork
/// @notice What the fork tests need to say about the candidate registry on a
/// live chain, where it is deployed only once a release carrying it has been
/// deployed. Between a candidate change and that deploy the pinned address is
/// empty on every network, and the register loops refuse it on the code hash
/// before reading anything.
library LibAddressRegistryFork {
    /// Whether the selected chain holds the pinned registry.
    /// @return True when the code at the pinned address hashes to the pin.
    function isDeployed() internal view returns (bool) {
        return LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash
            == LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH;
    }

    /// The revert a resolve of `name` gives on the selected chain when `name` is
    /// bound nowhere: the registry's own `NameNotRegistered` where the pinned
    /// registry is deployed, and the code-hash refusal, naming what is there,
    /// where it is not.
    /// @param name The unbound name.
    /// @return The revert data.
    function unboundResolveRevert(bytes32 name) internal view returns (bytes memory) {
        if (isDeployed()) {
            return abi.encodeWithSelector(IAddressRegistryV2.NameNotRegistered.selector, name);
        }
        return abi.encodeWithSelector(
            LibAddressRegistry.UnexpectedAddressRegistryCodeHash.selector,
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS.codehash
        );
    }

    /// Deploys the candidate registry on the selected chain through the Zoltu
    /// factory unless it is already there: the state a release deploy leaves.
    /// @param vm The Vm instance to etch the factory with.
    function ensureDeployed(Vm vm) internal {
        if (!isDeployed()) {
            LibRainDeploy.etchAndDeployZoltu(vm, type(AddressRegistry).creationCode);
        }
    }
}
