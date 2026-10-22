// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";

import {IRegistryDelegatesV1} from "../interface/IRegistryDelegatesV1.sol";
import {LibRegistryDelegates} from "./LibRegistryDelegates.sol";
import {LibConfigRegistryRegister} from "./LibConfigRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "./LibRainDeploy.sol";

/// A registry `LibRegistryDelegatesApprove` drives through
/// `IRegistryDelegatesV1`, which every registry implements identically.
/// @param registry The pinned registry.
/// @param codehash Its pinned code hash.
struct RegistryDelegation {
    address registry;
    bytes32 codehash;
}

/// @title LibRegistryDelegatesApprove
/// @notice An account's delegation side of a registry with
/// `IRegistryDelegatesV1` delegation: approves one delegate for one scope under
/// the account on every network it is given, or revokes it, signed by the
/// account itself, and reads the approval back. The registry is a
/// `RegistryDelegation`: `LibConfigRegistryApprove` and
/// `LibMigrationRegistryApprove` each build one, and their scripts say how they
/// are run.
///
/// The scope and the networks are taken and refused exactly as
/// `LibConfigRegistryRegister` takes a name and networks, through its
/// `nameHash` and `selectNetworks`, so an approval lands on the scope a
/// consumer hashes the same way.
///
/// ## The guards
///
/// Approving and revoking act under the caller, so the sender is the account:
/// a delegate cannot approve another, and a sender that is not the account
/// approves under itself, which no consumer reads. `checkInputs` refuses that,
/// a zero delegate, a non-canonical scope and a bad network selection before
/// any fork. Per network, once it is forked and before anything is recorded,
/// the chain id is the catalogue's and the registry holds the pinned code
/// hash. A script that reverts signs nothing.
///
/// ## Simulation and confirmation
///
/// `approveOnNetworks` returns the forks it simulated on,
/// `checkApprovalOnForks` reads those, and `checkApprovalOnNetworks` forks
/// every network fresh, as a run of its own once the transactions have been
/// mined.
library LibRegistryDelegatesApprove {
    /// Thrown when the account that would sign is not the authority.
    /// Approving and revoking act under the caller, so this would set an
    /// approval under the sender, which no consumer of the authority reads: a
    /// wrong derivation path, most likely.
    /// @param sender The account that would sign.
    /// @param authority The account the run approves under.
    error SenderNotAuthority(address sender, address authority);

    /// Thrown when a network's registry does not hold the expected approval.
    /// @param network The network read.
    /// @param authority The account the approval was read under.
    /// @param scope The hashed scope.
    /// @param delegate The delegate asked about.
    /// @param expected Whether it should be approved.
    error UnexpectedApproval(string network, address authority, bytes32 scope, address delegate, bool expected);

    /// Thrown when the selected chain's registry does not hold its pinned code
    /// hash.
    /// @param registry The registry.
    /// @param expected The pinned code hash.
    /// @param actual The code hash there.
    error UnexpectedRegistryCodeHash(address registry, bytes32 expected, bytes32 actual);

    /// Reverts unless the selected chain is the network's and its registry is
    /// the pinned one.
    /// @param r The registry.
    /// @param vm The Vm the chain id is read through, so the read follows the
    /// selected fork.
    /// @param network The catalogue entry of the selected chain.
    function checkChain(RegistryDelegation memory r, Vm vm, SupportedNetwork memory network) internal view {
        uint256 chainId = vm.getChainId();
        if (chainId != network.chainId) {
            revert LibConfigRegistryRegister.UnexpectedChainId(network.name, network.chainId, chainId);
        }
        if (r.registry.codehash != r.codehash) {
            revert UnexpectedRegistryCodeHash(r.registry, r.codehash, r.registry.codehash);
        }
    }

    /// The record of a run's inputs, printed before any network: everything
    /// the account's device is asked to sign, exactly as it will be signed.
    /// @param r The registry.
    /// @param vm The Vm instance to format with.
    /// @param scope The scope as a consumer writes it.
    /// @param authority The account that signs.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    /// @return The record, one field per line.
    function describeInputs(
        RegistryDelegation memory r,
        Vm vm,
        string memory scope,
        address authority,
        address delegate,
        bool approve
    ) internal pure returns (string memory) {
        bytes32 hashed = LibConfigRegistryRegister.nameHash(scope);
        return string.concat(
            "Scope: ",
            scope,
            "\nScope hash (keccak256 of the scope): ",
            vm.toString(hashed),
            "\nAuthority (signer): ",
            vm.toString(authority),
            "\nDelegate: ",
            vm.toString(delegate),
            "\nTarget: ",
            approve ? "approved" : "revoked",
            describeSigned(r, vm, hashed, delegate, approve)
        );
    }

    /// The registry and calldata lines of `describeInputs`: where the
    /// transaction goes and what it carries.
    /// @param r The registry.
    /// @param vm The Vm instance to format with.
    /// @param scope The hashed scope.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    /// @return The two lines, each led by a newline.
    function describeSigned(RegistryDelegation memory r, Vm vm, bytes32 scope, address delegate, bool approve)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "\nRegistry: ",
            vm.toString(r.registry),
            "\nCalldata: ",
            vm.toString(LibRegistryDelegates.approveCalldata(scope, delegate, approve))
        );
    }

    /// The record of one network: its chain id, the delegate's code size, the
    /// current approval, and what the run does to it — `SKIP` when it is in the
    /// target state already, `APPROVE` or `REVOKE` otherwise.
    /// @param vm The Vm instance to format with.
    /// @param network The network's name.
    /// @param chainId The chain the network forked.
    /// @param delegateCodeSize The size of the code at the delegate.
    /// @param approved Whether the delegate is approved now.
    /// @param approve The target state.
    /// @return The record, one field per line.
    function describeNetwork(
        Vm vm,
        string memory network,
        uint256 chainId,
        uint256 delegateCodeSize,
        bool approved,
        bool approve
    ) internal pure returns (string memory) {
        string memory action;
        if (approved == approve) {
            action = approve ? "SKIP: already approved" : "SKIP: already not approved";
        } else {
            action = approve ? "APPROVE" : "REVOKE";
        }
        return string.concat(
            "Network: ",
            network,
            "\n  chain id: ",
            vm.toString(chainId),
            "\n  delegate code: ",
            delegateCodeSize == 0 ? "none" : string.concat(vm.toString(delegateCodeSize), " bytes"),
            "\n  current: ",
            approved ? "approved" : "not approved",
            "\n  ",
            action
        );
    }

    /// Sets the approval of `delegate` for `scope` under `authority` on the
    /// selected chain to `approve`, signed by `authority`, unless it is in that
    /// state there already. Logs the current approval and what is about to
    /// happen to it.
    /// @param r The registry.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The catalogue entry of the selected chain.
    /// @param authority The account that signs.
    /// @param scope The hashed scope.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    /// @return Whether a transaction was broadcast.
    /// @return The record logged.
    function approveOnSelectedChain(
        RegistryDelegation memory r,
        Vm vm,
        SupportedNetwork memory network,
        address authority,
        bytes32 scope,
        address delegate,
        bool approve
    ) internal returns (bool, string memory) {
        checkChain(r, vm, network);
        bool approved = IRegistryDelegatesV1(r.registry).approvedV3(authority, scope, delegate);

        string memory record =
            describeNetwork(vm, network.name, network.chainId, delegate.code.length, approved, approve);
        console2.log(record);
        bool sends = approved != approve;
        if (sends) {
            vm.startBroadcast(authority);
            if (approve) {
                IRegistryDelegatesV1(r.registry).approveV3(scope, delegate);
            } else {
                IRegistryDelegatesV1(r.registry).revokeV3(scope, delegate);
            }
            vm.stopBroadcast();
        }
        return (sends, record);
    }

    /// Every input refusal of `approveOnNetworks`, in order — the sender, the
    /// delegate, the scope, then the networks.
    /// @param selected The networks to act on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs.
    /// @param authority The account to approve under.
    /// @param scope The scope as a consumer writes it.
    /// @param delegate The delegate.
    /// @return The hashed scope.
    /// @return The selected networks' catalogue entries.
    function checkInputs(
        string[] memory selected,
        string[] memory declared,
        address sender,
        address authority,
        string memory scope,
        address delegate
    ) internal pure returns (bytes32, SupportedNetwork[] memory) {
        if (sender != authority) {
            revert SenderNotAuthority(sender, authority);
        }
        if (delegate == address(0)) {
            revert IRegistryDelegatesV1.ZeroDelegate();
        }
        bytes32 hashed = LibConfigRegistryRegister.nameHash(scope);
        SupportedNetwork[] memory networks = LibConfigRegistryRegister.selectNetworks(selected, declared);
        return (hashed, networks);
    }

    /// Sets the approval of `delegate` for `scope` under `authority` to
    /// `approve` on every selected network, signed by `sender`.
    ///
    /// Every input refusal comes before the first fork, and every network is
    /// forked before any is selected, as `LibRainDeploy.createForks` requires.
    /// @param r The registry.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param selected The networks to act on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs: the authority.
    /// @param authority The account to approve under.
    /// @param scope The scope as a consumer writes it.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    /// @return The fork each selected network was simulated on, for
    /// `checkApprovalOnForks`.
    /// @return The `describeInputs` record logged.
    function approveOnNetworks(
        RegistryDelegation memory r,
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address sender,
        address authority,
        string memory scope,
        address delegate,
        bool approve
    ) internal returns (uint256[] memory, string memory) {
        // slither-disable-next-line unused-return
        checkInputs(selected, declared, sender, authority, scope, delegate);
        string memory record = describeInputs(r, vm, scope, authority, delegate, approve);
        console2.log(record);

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, selected);
        approveOnForks(r, vm, selected, declared, forkIds, sender, authority, scope, delegate, approve);
        return (forkIds, record);
    }

    /// `approveOnNetworks` on forks the caller made, after the input refusals
    /// of `checkInputs`.
    /// @param r The registry.
    /// @param vm The Vm instance to select forks and broadcast with.
    /// @param selected The networks the forks are of.
    /// @param declared The networks the declaration supports.
    /// @param forkIds The fork of each selected network, positionally paired.
    /// @param sender The account that signs: the authority.
    /// @param authority The account to approve under.
    /// @param scope The scope as a consumer writes it.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    function approveOnForks(
        RegistryDelegation memory r,
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        address sender,
        address authority,
        string memory scope,
        address delegate,
        bool approve
    ) internal {
        (bytes32 hashed, SupportedNetwork[] memory networks) =
            checkInputs(selected, declared, sender, authority, scope, delegate);
        if (forkIds.length != networks.length) {
            revert LibRainDeploy.ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            approveOnSelectedChain(r, vm, networks[i], authority, hashed, delegate, approve);
        }
    }

    /// Reverts unless the selected chain is the network's and its registry
    /// holds the approval of `delegate` for `scope` under `authority` in the
    /// state `approve`.
    /// @param r The registry.
    /// @param vm The Vm the chain id is read through.
    /// @param network The catalogue entry of the selected chain.
    /// @param authority The account to read under.
    /// @param scope The hashed scope.
    /// @param delegate The delegate.
    /// @param approve Whether it must be approved.
    function checkApprovalOnSelectedChain(
        RegistryDelegation memory r,
        Vm vm,
        SupportedNetwork memory network,
        address authority,
        bytes32 scope,
        address delegate,
        bool approve
    ) internal view {
        checkChain(r, vm, network);
        if (IRegistryDelegatesV1(r.registry).approvedV3(authority, scope, delegate) != approve) {
            revert UnexpectedApproval(network.name, authority, scope, delegate, approve);
        }
    }

    /// Reverts unless every given fork's registry holds the approval in the
    /// state `approve`, logging each network checked.
    /// @param r The registry.
    /// @param vm The Vm instance to select forks with.
    /// @param selected The networks the forks are of.
    /// @param declared The networks the declaration supports.
    /// @param forkIds The fork of each selected network, positionally paired.
    /// @param authority The account to read under.
    /// @param scope The scope as a consumer writes it.
    /// @param delegate The delegate.
    /// @param approve Whether it must be approved.
    function checkApprovalOnForks(
        RegistryDelegation memory r,
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        address authority,
        string memory scope,
        address delegate,
        bool approve
    ) internal {
        bytes32 hashed = LibConfigRegistryRegister.nameHash(scope);
        SupportedNetwork[] memory networks = LibConfigRegistryRegister.selectNetworks(selected, declared);
        if (forkIds.length != networks.length) {
            revert LibRainDeploy.ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            checkApprovalOnSelectedChain(r, vm, networks[i], authority, hashed, delegate, approve);
            console2.log(string.concat(approve ? "Approved on " : "Not approved on ", networks[i].name));
        }
    }

    /// `checkApprovalOnForks` on a fresh fork of every selected network: the
    /// confirmed check, run on its own once the transactions have been mined.
    /// @param r The registry.
    /// @param vm The Vm instance to fork with.
    /// @param selected The networks to check.
    /// @param declared The networks the declaration supports.
    /// @param authority The account to read under.
    /// @param scope The scope as a consumer writes it.
    /// @param delegate The delegate.
    /// @param approve Whether it must be approved.
    function checkApprovalOnNetworks(
        RegistryDelegation memory r,
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address authority,
        string memory scope,
        address delegate,
        bool approve
    ) internal {
        // Refused before anything is forked; the returns are not needed here.
        // slither-disable-next-line unused-return
        LibConfigRegistryRegister.nameHash(scope);
        // slither-disable-next-line unused-return
        LibConfigRegistryRegister.selectNetworks(selected, declared);
        checkApprovalOnForks(
            r, vm, selected, declared, LibRainDeploy.createForks(vm, selected), authority, scope, delegate, approve
        );
    }
}
