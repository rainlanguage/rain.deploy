// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";

import {RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";
import {LibConfigRegistryRegister} from "../src/lib/LibConfigRegistryRegister.sol";

/// @title RegisterConfig
/// @notice Binds `CONFIG_REGISTRY_NAME` to `CONFIG_REGISTRY_VALUE` in the
/// `ConfigRegistry` on every network the declaration supports, or on the
/// comma-separated subset `CONFIG_REGISTRY_NETWORKS` names, signed by
/// `CONFIG_REGISTRY_ROOT` on a Trezor.
///
/// Local only. Root is a hardware wallet, so nothing in CI can sign this, and
/// nothing in CI runs it. The README's "Managing the config registry" section
/// carries the commands and what the device shows.
///
/// `run()` binds, and is a dry run on forks unless forge is given
/// `--broadcast`. `verify()` is the confirmed check, a run of its own once the
/// binds are mined. The signer is forge's `--sender`, which is what a script's
/// `msg.sender` is; `--trezor` is what makes the device that account's wallet.
/// `LibConfigRegistryRegister` carries every guard.
contract RegisterConfig is RegistryDeploySuites, Script {
    /// The environment variable holding the name, as a consumer writes it
    /// before hashing.
    string constant NAME_VAR = "CONFIG_REGISTRY_NAME";

    /// The environment variable holding the value to bind the name to, as
    /// `0x`-prefixed hex of its ABI encoding: an address is
    /// `cast abi-encode "f(address)" <account>`.
    string constant VALUE_VAR = "CONFIG_REGISTRY_VALUE";

    /// The environment variable narrowing the networks, comma separated.
    string constant NETWORKS_VAR = "CONFIG_REGISTRY_NETWORKS";

    /// The networks to act on: `CONFIG_REGISTRY_NETWORKS` if set, otherwise
    /// every network the declaration supports — the set the registry itself is
    /// deployed to.
    /// @return The network names, as `[rpc_endpoints]` aliases.
    function selectedNetworks() internal view returns (string[] memory) {
        return vm.envOr(NETWORKS_VAR, ",", supportedNetworks());
    }

    /// Binds the name on every selected network where it is not already bound
    /// to the value.
    /// @return The fork each selected network was simulated on.
    function run() external returns (uint256[] memory) {
        return LibConfigRegistryRegister.registerOnNetworks(
            vm, selectedNetworks(), supportedNetworks(), msg.sender, vm.envString(NAME_VAR), vm.envBytes(VALUE_VAR)
        );
    }

    /// Reads every selected network fresh and reverts unless the name resolves
    /// to the value on each.
    function verify() external {
        LibConfigRegistryRegister.checkRegisteredOnNetworks(
            vm, selectedNetworks(), supportedNetworks(), vm.envString(NAME_VAR), vm.envBytes(VALUE_VAR)
        );
    }
}
