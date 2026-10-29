// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Multicall} from "@openzeppelin-contracts-5.7.0/utils/Multicall.sol";
import {Address} from "@openzeppelin-contracts-5.7.0/utils/Address.sol";

import {IRegistryDelegatesV3} from "../interface/IRegistryDelegatesV3.sol";
import {LibRegistryDelegates} from "./LibRegistryDelegates.sol";
import {LibConfigRegistryRegister} from "./LibConfigRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "./LibRainDeploy.sol";

/// A registry `LibRegistryDelegatesApprove` drives through
/// `IRegistryDelegatesV3`, which every registry implements identically.
/// @param registry The pinned registry.
/// @param codehash Its pinned code hash.
struct RegistryDelegation {
    address registry;
    bytes32 codehash;
}

/// @title LibRegistryDelegatesApprove
/// @notice An account's delegation side of a registry with
/// `IRegistryDelegatesV3` delegation: approves one delegate for a list of
/// scopes under the account on every network it is given, or revokes it, in
/// one transaction per network signed by the account itself, and reads the
/// approvals back. A transaction carrying one call is that call; two or more
/// go as one `multicall`. The registry is a
/// `RegistryDelegation`: `LibConfigRegistryApprove` and
/// `LibMigrationRegistryApprove` each build one, and their scripts say how they
/// are run.
///
/// Each scope and the networks are taken and refused exactly as
/// `LibConfigRegistryRegister` takes a name and networks, through its
/// `nameHash` and `selectNetworks`, so an approval lands on the scope a
/// consumer hashes the same way.
///
/// ## The guards
///
/// Approving and revoking act under the caller, so the sender is the account:
/// a delegate cannot approve another, and a sender that is not the account
/// approves under itself, which no consumer reads. `checkInputs` refuses that,
/// a zero delegate, an empty scope list, a non-canonical scope and a bad
/// network selection before any fork. Per network, once it is forked and
/// before anything is recorded,
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

    /// Thrown when a run is given no scope and is not unscoped.
    error NoScopes();

    /// Thrown when a network's registry does not hold the expected unscoped
    /// approval.
    /// @param network The network read.
    /// @param authority The account the approval was read under.
    /// @param delegate The delegate asked about.
    /// @param expected Whether it should be approved.
    error UnexpectedUnscopedApproval(string network, address authority, address delegate, bool expected);

    /// Thrown when a run is given the same scope twice.
    /// @param scope The repeated scope.
    error DuplicateScope(string scope);

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

    /// The hash of each scope, refused unless the run asks for something —
    /// at least one scope, or unscoped — each scope is canonical and none
    /// repeats.
    /// @param scopes The scopes as a consumer writes them.
    /// @param unscoped Whether the run also sets the unscoped approval.
    /// @return The hashed scopes, in order.
    function hashScopes(string[] memory scopes, bool unscoped) internal pure returns (bytes32[] memory) {
        if (scopes.length == 0 && !unscoped) {
            revert NoScopes();
        }
        bytes32[] memory hashed = new bytes32[](scopes.length);
        for (uint256 i = 0; i < scopes.length; i++) {
            hashed[i] = LibConfigRegistryRegister.nameHash(scopes[i]);
            for (uint256 j = 0; j < i; j++) {
                if (hashed[j] == hashed[i]) {
                    revert DuplicateScope(scopes[i]);
                }
            }
        }
        return hashed;
    }

    /// The record of a run's inputs, printed before any network: every scope
    /// and its hash, whether it is unscoped, the signer, the delegate, the
    /// target and the registry.
    /// @param r The registry.
    /// @param vm The Vm instance to format with.
    /// @param scopes The scopes as a consumer writes them.
    /// @param unscoped Whether the run also sets the unscoped approval.
    /// @param authority The account that signs.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    /// @return The record, one field per line.
    function describeInputs(
        RegistryDelegation memory r,
        Vm vm,
        string[] memory scopes,
        bool unscoped,
        address authority,
        address delegate,
        bool approve
    ) internal pure returns (string memory) {
        bytes32[] memory hashed = hashScopes(scopes, unscoped);
        string memory record = "";
        for (uint256 i = 0; i < scopes.length; i++) {
            record = string.concat(
                record, "Scope: ", scopes[i], "\nScope hash (keccak256 of the scope): ", vm.toString(hashed[i]), "\n"
            );
        }
        if (unscoped) {
            record = string.concat(record, "Unscoped: yes\n");
        }
        return string.concat(
            record,
            "Authority (signer): ",
            vm.toString(authority),
            "\nDelegate: ",
            vm.toString(delegate),
            "\nTarget: ",
            approve ? "approved" : "revoked",
            "\nRegistry: ",
            vm.toString(r.registry)
        );
    }

    /// The head of one network's record: its chain id and the delegate's code
    /// size.
    /// @param vm The Vm instance to format with.
    /// @param network The network's name.
    /// @param chainId The chain the network forked.
    /// @param delegateCodeSize The size of the code at the delegate.
    /// @return The record, one field per line.
    function describeNetwork(Vm vm, string memory network, uint256 chainId, uint256 delegateCodeSize)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "Network: ",
            network,
            "\n  chain id: ",
            vm.toString(chainId),
            "\n  delegate code: ",
            delegateCodeSize == 0 ? "none" : string.concat(vm.toString(delegateCodeSize), " bytes")
        );
    }

    /// One scope's line of a network's record: its current approval and what
    /// the run does to it — `SKIP` when it is in the target state already,
    /// `APPROVE` or `REVOKE` otherwise.
    /// @param scope The scope as a consumer writes it.
    /// @param approved Whether the delegate is approved now.
    /// @param approve The target state.
    /// @return The line, led by a newline.
    function describeScope(string memory scope, bool approved, bool approve) internal pure returns (string memory) {
        string memory action;
        if (approved == approve) {
            action = approve ? "SKIP: already approved" : "SKIP: already not approved";
        } else {
            action = approve ? "APPROVE" : "REVOKE";
        }
        return string.concat("\n  ", scope, ": ", approved ? "approved" : "not approved", ", ", action);
    }

    /// Sets the approval of `delegate` for every scope, and unscoped when
    /// asked, under `authority` on the selected chain to `approve`, in one
    /// transaction signed by `authority` over the approvals not in that state
    /// there already: the call itself when there is one, a `multicall` when
    /// there are more. Logs each approval's current state, what is about to
    /// happen to it, and the calldata sent.
    /// @param r The registry.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The catalogue entry of the selected chain.
    /// @param authority The account that signs.
    /// @param scopes The scopes as a consumer writes them.
    /// @param hashed The hashed scopes, positionally paired with `scopes`.
    /// @param unscoped Whether the run also sets the unscoped approval.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    /// @return Whether a transaction was broadcast.
    /// @return The record logged.
    function approveOnSelectedChain(
        RegistryDelegation memory r,
        Vm vm,
        SupportedNetwork memory network,
        address authority,
        string[] memory scopes,
        bytes32[] memory hashed,
        bool unscoped,
        address delegate,
        bool approve
    ) internal returns (bool, string memory) {
        checkChain(r, vm, network);
        string memory record = describeNetwork(vm, network.name, network.chainId, delegate.code.length);
        bytes[] memory calls = new bytes[](hashed.length + 1);
        uint256 count = 0;
        for (uint256 i = 0; i < hashed.length; i++) {
            bool approved = IRegistryDelegatesV3(r.registry).approvedV5(authority, hashed[i], delegate);
            record = string.concat(record, describeScope(scopes[i], approved, approve));
            if (approved != approve) {
                calls[count] = LibRegistryDelegates.approveCalldata(hashed[i], delegate, approve);
                count++;
            }
        }
        if (unscoped) {
            bool approved = IRegistryDelegatesV3(r.registry).approvedUnscopedV5(authority, delegate);
            record = string.concat(record, describeScope("(unscoped)", approved, approve));
            if (approved != approve) {
                calls[count] = LibRegistryDelegates.approveUnscopedCalldata(delegate, approve);
                count++;
            }
        }
        bytes memory data = transactionCalldata(calls, count);
        if (count > 0) {
            record = string.concat(record, "\n  Calldata: ", vm.toString(data));
        }
        console2.log(record);
        if (count > 0) {
            vm.startBroadcast(authority);
            // The registry's calls return nothing that is read.
            // slither-disable-next-line unused-return
            Address.functionCall(r.registry, data);
            vm.stopBroadcast();
        }
        return (count > 0, record);
    }

    /// The calldata of one network's transaction over the first `count` of
    /// `calls`: a lone call as itself, which the device decodes; two or more as
    /// one `multicall`.
    /// @param calls The calls, the first `count` of them in use.
    /// @param count How many are in use.
    /// @return The calldata, empty when `count` is zero.
    function transactionCalldata(bytes[] memory calls, uint256 count) internal pure returns (bytes memory) {
        if (count == 0) {
            return "";
        }
        if (count == 1) {
            return calls[0];
        }
        bytes[] memory batch = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            batch[i] = calls[i];
        }
        return abi.encodeCall(Multicall.multicall, (batch));
    }

    /// Every input refusal of `approveOnNetworks`, in order — the sender, the
    /// delegate, the scopes, then the networks.
    /// @param selected The networks to act on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs.
    /// @param authority The account to approve under.
    /// @param scopes The scopes as a consumer writes them.
    /// @param unscoped Whether the run also sets the unscoped approval.
    /// @param delegate The delegate.
    /// @return The hashed scopes.
    /// @return The selected networks' catalogue entries.
    function checkInputs(
        string[] memory selected,
        string[] memory declared,
        address sender,
        address authority,
        string[] memory scopes,
        bool unscoped,
        address delegate
    ) internal pure returns (bytes32[] memory, SupportedNetwork[] memory) {
        if (sender != authority) {
            revert SenderNotAuthority(sender, authority);
        }
        if (delegate == address(0)) {
            revert IRegistryDelegatesV3.ZeroDelegate();
        }
        bytes32[] memory hashed = hashScopes(scopes, unscoped);
        SupportedNetwork[] memory networks = LibConfigRegistryRegister.selectNetworks(selected, declared);
        return (hashed, networks);
    }

    /// Sets the approval of `delegate` for every scope under `authority` to
    /// `approve` on every selected network, signed by `sender`, one
    /// transaction per network.
    ///
    /// Every input refusal comes before the first fork, and every network is
    /// forked before any is selected, as `LibRainDeploy.createForks` requires.
    /// @param r The registry.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param selected The networks to act on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs: the authority.
    /// @param authority The account to approve under.
    /// @param scopes The scopes as a consumer writes them.
    /// @param unscoped Whether the run also sets the unscoped approval.
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
        string[] memory scopes,
        bool unscoped,
        address delegate,
        bool approve
    ) internal returns (uint256[] memory, string memory) {
        // slither-disable-next-line unused-return
        checkInputs(selected, declared, sender, authority, scopes, unscoped, delegate);
        string memory record = describeInputs(r, vm, scopes, unscoped, authority, delegate, approve);
        console2.log(record);

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, selected);
        approveOnForks(r, vm, selected, declared, forkIds, sender, authority, scopes, unscoped, delegate, approve);
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
    /// @param scopes The scopes as a consumer writes them.
    /// @param unscoped Whether the run also sets the unscoped approval.
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
        string[] memory scopes,
        bool unscoped,
        address delegate,
        bool approve
    ) internal {
        (bytes32[] memory hashed, SupportedNetwork[] memory networks) =
            checkInputs(selected, declared, sender, authority, scopes, unscoped, delegate);
        if (forkIds.length != networks.length) {
            revert LibRainDeploy.ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            // slither-disable-next-line unused-return
            approveOnSelectedChain(r, vm, networks[i], authority, scopes, hashed, unscoped, delegate, approve);
        }
    }

    /// Reverts unless the selected chain is the network's and its registry
    /// holds the approval of `delegate` for every scope under `authority` in
    /// the state `approve`.
    /// @param r The registry.
    /// @param vm The Vm the chain id is read through.
    /// @param network The catalogue entry of the selected chain.
    /// @param authority The account to read under.
    /// @param hashed The hashed scopes.
    /// @param unscoped Whether the unscoped approval is checked too.
    /// @param delegate The delegate.
    /// @param approve Whether it must be approved.
    function checkApprovalOnSelectedChain(
        RegistryDelegation memory r,
        Vm vm,
        SupportedNetwork memory network,
        address authority,
        bytes32[] memory hashed,
        bool unscoped,
        address delegate,
        bool approve
    ) internal view {
        checkChain(r, vm, network);
        for (uint256 i = 0; i < hashed.length; i++) {
            if (IRegistryDelegatesV3(r.registry).approvedV5(authority, hashed[i], delegate) != approve) {
                revert UnexpectedApproval(network.name, authority, hashed[i], delegate, approve);
            }
        }
        if (unscoped && IRegistryDelegatesV3(r.registry).approvedUnscopedV5(authority, delegate) != approve) {
            revert UnexpectedUnscopedApproval(network.name, authority, delegate, approve);
        }
    }

    /// Reverts unless every given fork's registry holds every approval in the
    /// state `approve`, logging each network checked.
    /// @param r The registry.
    /// @param vm The Vm instance to select forks with.
    /// @param selected The networks the forks are of.
    /// @param declared The networks the declaration supports.
    /// @param forkIds The fork of each selected network, positionally paired.
    /// @param authority The account to read under.
    /// @param scopes The scopes as a consumer writes them.
    /// @param unscoped Whether the run also sets the unscoped approval.
    /// @param delegate The delegate.
    /// @param approve Whether it must be approved.
    function checkApprovalOnForks(
        RegistryDelegation memory r,
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        address authority,
        string[] memory scopes,
        bool unscoped,
        address delegate,
        bool approve
    ) internal {
        bytes32[] memory hashed = hashScopes(scopes, unscoped);
        SupportedNetwork[] memory networks = LibConfigRegistryRegister.selectNetworks(selected, declared);
        if (forkIds.length != networks.length) {
            revert LibRainDeploy.ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            checkApprovalOnSelectedChain(r, vm, networks[i], authority, hashed, unscoped, delegate, approve);
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
    /// @param scopes The scopes as a consumer writes them.
    /// @param unscoped Whether the run also sets the unscoped approval.
    /// @param delegate The delegate.
    /// @param approve Whether it must be approved.
    function checkApprovalOnNetworks(
        RegistryDelegation memory r,
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address authority,
        string[] memory scopes,
        bool unscoped,
        address delegate,
        bool approve
    ) internal {
        // Refused before anything is forked; the returns are not needed here.
        // slither-disable-next-line unused-return
        hashScopes(scopes, unscoped);
        // slither-disable-next-line unused-return
        LibConfigRegistryRegister.selectNetworks(selected, declared);
        checkApprovalOnForks(
            r,
            vm,
            selected,
            declared,
            LibRainDeploy.createForks(vm, selected),
            authority,
            scopes,
            unscoped,
            delegate,
            approve
        );
    }
}
