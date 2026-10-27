// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";
import {LibConfigRegistryRegister} from "../src/lib/LibConfigRegistryRegister.sol";

/// @title RegisterConfig
/// @notice Binds `CONFIG_REGISTRY_NAME` to `CONFIG_REGISTRY_VALUE` of type
/// `CONFIG_REGISTRY_VALUE_TYPE` under
/// `CONFIG_REGISTRY_AUTHORITY` in the `ConfigRegistry` on every network the
/// declaration supports, or on the comma-separated subset
/// `CONFIG_REGISTRY_NETWORKS` names, signed on a Trezor by that authority or
/// by a delegate it approved for the name with `approveV3` on every selected
/// network.
///
/// Local only. The signer this is written for is a hardware wallet, so
/// nothing in CI can sign this, and nothing in CI runs it. The README's
/// "Managing the config registry" section carries the commands and what the
/// device shows.
///
/// `run()` binds, and is a dry run on forks unless forge is given
/// `--broadcast`. `verify()` is the confirmed check, a run of its own once the
/// binds are mined. The signer is forge's `--sender`, which is what a script's
/// `msg.sender` is, and `run()` refuses it on each network unless it is the
/// authority or a delegate the authority approved there;
/// `--trezor` is what makes the device that account's wallet. Forge's
/// `--broadcast` is a second layer: it refuses, before sending anything, a
/// broadcast from an account none of its signers is (`BundledState::broadcast`
/// in foundry-rs/foundry `crates/script/src/broadcast.rs`).
/// `LibConfigRegistryRegister` carries every guard.
contract RegisterConfig is RegistryDeploySuites, Script {
    /// The environment variable holding the authority to bind under and read
    /// under: the account consumers resolve the name under.
    string constant AUTHORITY_VAR = "CONFIG_REGISTRY_AUTHORITY";

    /// The environment variable holding the name, as a consumer writes it
    /// before hashing.
    string constant NAME_VAR = "CONFIG_REGISTRY_NAME";

    /// The environment variable holding the value to bind the name to, as
    /// `0x`-prefixed hex of its ABI encoding: an address is
    /// `cast abi-encode "f(address)" <account>`.
    string constant VALUE_VAR = "CONFIG_REGISTRY_VALUE";

    /// The environment variable holding the ABI type string of the value's
    /// encoding, such as `address`.
    string constant VALUE_TYPE_VAR = "CONFIG_REGISTRY_VALUE_TYPE";

    /// The environment variable narrowing the networks, comma separated.
    string constant NETWORKS_VAR = "CONFIG_REGISTRY_NETWORKS";

    /// The networks to act on: `CONFIG_REGISTRY_NETWORKS` if set, otherwise
    /// every network the declaration supports. The default needs the registry
    /// on every one of them: the first without it reverts
    /// `UnexpectedConfigRegistryCodeHash`, so a partial rollout sets
    /// `CONFIG_REGISTRY_NETWORKS` to the networks it is deployed on.
    /// @return The network names, as `[rpc_endpoints]` aliases.
    function selectedNetworks() internal view returns (string[] memory) {
        return vm.envOr(NETWORKS_VAR, ",", supportedNetworks());
    }

    /// The Vm `run()` and `verify()` fork, select and broadcast with.
    /// @return The cheatcodes.
    function forkVm() internal view virtual returns (Vm) {
        return vm;
    }

    /// Binds the name under the authority on every selected network where it
    /// is not already bound to the value.
    /// @return The fork each selected network was simulated on.
    function run() external returns (uint256[] memory) {
        (uint256[] memory forkIds,) = LibConfigRegistryRegister.registerOnNetworks(
            forkVm(),
            selectedNetworks(),
            supportedNetworks(),
            msg.sender,
            vm.envAddress(AUTHORITY_VAR),
            vm.envString(NAME_VAR),
            vm.envString(VALUE_TYPE_VAR),
            vm.envBytes(VALUE_VAR)
        );
        return forkIds;
    }

    /// Reads every selected network fresh and reverts unless the name resolves
    /// to the value of the value type under the authority on each.
    function verify() external {
        LibConfigRegistryRegister.checkRegisteredOnNetworks(
            forkVm(),
            selectedNetworks(),
            supportedNetworks(),
            vm.envAddress(AUTHORITY_VAR),
            vm.envString(NAME_VAR),
            vm.envString(VALUE_TYPE_VAR),
            vm.envBytes(VALUE_VAR)
        );
    }
}
