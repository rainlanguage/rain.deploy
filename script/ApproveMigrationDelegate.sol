// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";
import {LibMigrationRegistryApprove} from "../src/lib/LibMigrationRegistryApprove.sol";
import {LibRegistryDelegatesApprove} from "../src/lib/LibRegistryDelegatesApprove.sol";

/// @title ApproveMigrationDelegate
/// @notice Approves `MIGRATION_DELEGATE_ADDRESS` to write
/// `MIGRATION_DELEGATE_WRITER`'s line in `MIGRATION_DELEGATE_NAMESPACE` in the
/// `MigrationRegistry` on every network the declaration supports, or on the
/// comma-separated subset `MIGRATION_DELEGATE_NETWORKS` names, signed on a Trezor by that writer.
/// `MIGRATION_DELEGATE_APPROVED=false` revokes instead.
///
/// Local only, for the same reason as `ApproveConfigDelegate`: the signer is a
/// hardware wallet. The README's "Managing the migration registry" section
/// carries the commands.
///
/// `run()` approves, and is a dry run on forks unless forge is given
/// `--broadcast`. `verify()` is the confirmed check, a run of its own once the
/// transactions are mined. The signer is forge's `--sender`, which is the
/// script's `msg.sender`, and `run()` refuses it unless it is the writer.
/// `LibRegistryDelegatesApprove` carries every guard.
contract ApproveMigrationDelegate is RegistryDeploySuites, Script {
    /// The environment variable holding the writer: the account that signs
    /// and the account whose line the delegate writes.
    string constant WRITER_VAR = "MIGRATION_DELEGATE_WRITER";

    /// The environment variable holding the namespace, as a consumer writes
    /// it before hashing.
    string constant NAMESPACE_VAR = "MIGRATION_DELEGATE_NAMESPACE";

    /// The environment variable holding the delegate to approve or revoke.
    string constant DELEGATE_VAR = "MIGRATION_DELEGATE_ADDRESS";

    /// The environment variable holding the target state, `true` unless set:
    /// `false` revokes.
    string constant APPROVED_VAR = "MIGRATION_DELEGATE_APPROVED";

    /// The environment variable narrowing the networks, comma separated.
    string constant NETWORKS_VAR = "MIGRATION_DELEGATE_NETWORKS";

    /// The networks to act on: `MIGRATION_DELEGATE_NETWORKS` if set, otherwise
    /// every network the declaration supports.
    /// @return The network names, as `[rpc_endpoints]` aliases.
    function selectedNetworks() internal view returns (string[] memory) {
        return vm.envOr(NETWORKS_VAR, ",", supportedNetworks());
    }

    /// The target state: `MIGRATION_DELEGATE_APPROVED` if set, otherwise true.
    /// @return Whether the delegate is to be approved.
    function targetApproved() internal view returns (bool) {
        return vm.envOr(APPROVED_VAR, true);
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
            LibMigrationRegistryApprove.delegation(),
            forkVm(),
            selectedNetworks(),
            supportedNetworks(),
            msg.sender,
            vm.envAddress(WRITER_VAR),
            vm.envString(NAMESPACE_VAR),
            vm.envAddress(DELEGATE_VAR),
            targetApproved()
        );
        return forkIds;
    }

    /// Reads every selected network fresh and reverts unless the approval is
    /// in the target state on each.
    function verify() external {
        LibRegistryDelegatesApprove.checkApprovalOnNetworks(
            LibMigrationRegistryApprove.delegation(),
            forkVm(),
            selectedNetworks(),
            supportedNetworks(),
            vm.envAddress(WRITER_VAR),
            vm.envString(NAMESPACE_VAR),
            vm.envAddress(DELEGATE_VAR),
            targetApproved()
        );
    }
}
