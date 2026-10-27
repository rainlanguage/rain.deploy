// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";
import {LibRegistryDelegatesApprove, RegistryDelegation} from "../src/lib/LibRegistryDelegatesApprove.sol";
import {LibRegistryAuthority} from "../src/lib/LibRegistryAuthority.sol";

/// @title ApproveRegistryDelegate
/// @notice Approves `<PREFIX>_ADDRESS` to write under
/// `LibRegistryAuthority.ROOT_AUTHORITY`
/// within `<PREFIX>_SCOPE` in a registry, on every network the declaration
/// supports or on the comma-separated subset `<PREFIX>_NETWORKS` names,
/// signed on a Trezor by that authority. `<PREFIX>_APPROVED=false` revokes
/// instead. Each registry's script names its prefix and its registry.
///
/// Local only: the signer is a hardware wallet. The README's sections on
/// managing the registries carry the commands.
///
/// `run()` approves, and is a dry run on forks unless forge is given
/// `--broadcast`. `verify()` is the confirmed check, a run of its own once the
/// transactions are mined. The signer is forge's `--sender`, which is the
/// script's `msg.sender`, and `run()` refuses it unless it is the authority.
/// `LibRegistryDelegatesApprove` carries every guard.
abstract contract ApproveRegistryDelegate is RegistryDeploySuites, Script {
    /// @return The environment variable prefix.
    function envPrefix() internal pure virtual returns (string memory);

    /// @return The registry approved in.
    function delegation() internal pure virtual returns (RegistryDelegation memory);

    /// @param suffix The variable's name after the prefix.
    /// @return The variable's full name.
    function envName(string memory suffix) internal pure returns (string memory) {
        return string.concat(envPrefix(), "_", suffix);
    }

    /// The networks to act on: `<PREFIX>_NETWORKS` if set, otherwise every
    /// network the declaration supports.
    /// @return The network names, as `[rpc_endpoints]` aliases.
    function selectedNetworks() internal view returns (string[] memory) {
        return vm.envOr(envName("NETWORKS"), ",", supportedNetworks());
    }

    /// The target state: `<PREFIX>_APPROVED` if set, otherwise true.
    /// @return Whether the delegate is to be approved.
    function targetApproved() internal view returns (bool) {
        return vm.envOr(envName("APPROVED"), true);
    }

    /// The Vm `run()` and `verify()` fork, select and broadcast with.
    /// @return The cheatcodes.
    function forkVm() internal view virtual returns (Vm) {
        return vm;
    }

    /// Sets the approval on every selected network where it is not already in
    /// the target state.
    /// @return The fork each selected network was simulated on.
    function run() external returns (uint256[] memory) {
        (uint256[] memory forkIds,) = LibRegistryDelegatesApprove.approveOnNetworks(
            delegation(),
            forkVm(),
            selectedNetworks(),
            supportedNetworks(),
            msg.sender,
            LibRegistryAuthority.ROOT_AUTHORITY,
            vm.envString(envName("SCOPE")),
            vm.envAddress(envName("ADDRESS")),
            targetApproved()
        );
        return forkIds;
    }

    /// Reads every selected network fresh and reverts unless the approval is
    /// in the target state on each.
    function verify() external {
        LibRegistryDelegatesApprove.checkApprovalOnNetworks(
            delegation(),
            forkVm(),
            selectedNetworks(),
            supportedNetworks(),
            LibRegistryAuthority.ROOT_AUTHORITY,
            vm.envString(envName("SCOPE")),
            vm.envAddress(envName("ADDRESS")),
            targetApproved()
        );
    }
}
