// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";

import {IConfigRegistryV2} from "../interface/IConfigRegistryV2.sol";
import {IRegistryDelegatesV1} from "../interface/IRegistryDelegatesV1.sol";
import {LibConfigRegistryDeploy} from "./LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister} from "./LibConfigRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "./LibRainDeploy.sol";

/// @title LibConfigRegistryApprove
/// @notice An authority's delegation side of `ConfigRegistry`: approves one
/// delegate for one name under the authority on every network it is given, or
/// revokes it, signed by the authority itself, and reads the approval back.
/// `script/ApproveConfigDelegate.sol` is the entry point and says how it is
/// run; everything with behaviour is here.
///
/// The name and the networks are taken and refused exactly as
/// `LibConfigRegistryRegister` takes them, through its `nameHash`,
/// `selectNetworks` and `checkChain`, so an approval lands on the name a
/// `RegisterConfig` run binds and a consumer resolves.
///
/// ## The guards
///
/// `approveV2` and `revokeV2` act under their caller, so the sender is the
/// authority: a delegate cannot approve another, and a sender that is not the
/// authority approves under itself, which no consumer reads. `checkInputs`
/// refuses that, a zero delegate, a non-canonical name and a bad network
/// selection before any fork. Per network, once it is forked and before
/// anything is recorded, the chain id is the catalogue's and the registry
/// holds the pinned code hash. A script that reverts signs nothing.
///
/// ## Simulation and confirmation
///
/// The `LibConfigRegistryRegister` split: `approveOnNetworks` returns the
/// forks it simulated on, `checkApprovalOnForks` reads those, and
/// `checkApprovalOnNetworks` forks every network fresh, as a run of its own
/// once the transactions have been mined.
library LibConfigRegistryApprove {
    /// Thrown when the account that would sign is not the authority.
    /// `approveV2` and `revokeV2` act under their caller, so this would set an
    /// approval under the sender, which no consumer of the authority reads: a
    /// wrong derivation path, most likely.
    /// @param sender The account that would sign.
    /// @param authority The authority the run approves under.
    error SenderNotAuthority(address sender, address authority);

    /// Thrown when a network's registry does not hold the expected approval.
    /// @param network The network read.
    /// @param authority The authority the approval was read under.
    /// @param name The hashed name.
    /// @param delegate The delegate asked about.
    /// @param expected Whether it should be approved.
    error UnexpectedApproval(string network, address authority, bytes32 name, address delegate, bool expected);

    /// The calldata of the approval or revocation: what the device signs.
    /// @param name The hashed name.
    /// @param delegate The delegate.
    /// @param approve True for `approveV2`, false for `revokeV2`.
    /// @return The calldata.
    function approveCalldata(bytes32 name, address delegate, bool approve) internal pure returns (bytes memory) {
        return approve
            ? abi.encodeCall(IConfigRegistryV2.approveV2, (name, delegate))
            : abi.encodeCall(IConfigRegistryV2.revokeV2, (name, delegate));
    }

    /// The record of a run's inputs, printed before any network: everything
    /// the authority's device is asked to sign, exactly as it will be signed.
    /// @param vm The Vm instance to format with.
    /// @param name The name as a consumer writes it.
    /// @param authority The authority that signs.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    /// @return The record, one field per line.
    function describeInputs(Vm vm, string memory name, address authority, address delegate, bool approve)
        internal
        pure
        returns (string memory)
    {
        bytes32 hashed = LibConfigRegistryRegister.nameHash(name);
        return string.concat(
            "Name: ",
            name,
            "\nName hash (keccak256 of the name): ",
            vm.toString(hashed),
            "\nAuthority (signer): ",
            vm.toString(authority),
            "\nDelegate: ",
            vm.toString(delegate),
            "\nTarget: ",
            approve ? "approved" : "revoked",
            "\nRegistry: ",
            vm.toString(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS),
            "\nCalldata: ",
            vm.toString(approveCalldata(hashed, delegate, approve))
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

    /// Sets the approval of `delegate` for `name` under `authority` on the
    /// selected chain to `approve`, signed by `authority`, unless it is in that
    /// state there already. Logs the current approval and what is about to
    /// happen to it.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The catalogue entry of the selected chain.
    /// @param authority The authority that signs.
    /// @param name The hashed name.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    /// @return Whether a transaction was broadcast.
    /// @return The record logged.
    function approveOnSelectedChain(
        Vm vm,
        SupportedNetwork memory network,
        address authority,
        bytes32 name,
        address delegate,
        bool approve
    ) internal returns (bool, string memory) {
        LibConfigRegistryRegister.checkChain(vm, network);
        IConfigRegistryV2 registry = IConfigRegistryV2(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        bool approved = registry.approvedV2(authority, name, delegate);

        string memory record =
            describeNetwork(vm, network.name, network.chainId, delegate.code.length, approved, approve);
        console2.log(record);
        bool sends = approved != approve;
        if (sends) {
            vm.startBroadcast(authority);
            if (approve) {
                registry.approveV2(name, delegate);
            } else {
                registry.revokeV2(name, delegate);
            }
            vm.stopBroadcast();
        }
        return (sends, record);
    }

    /// Every input refusal of `approveOnNetworks`, in order — the sender, the
    /// delegate, the name, then the networks — and the inputs record it logs.
    /// @param vm The Vm instance to format with.
    /// @param selected The networks to act on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs.
    /// @param authority The authority to approve under.
    /// @param name The name as a consumer writes it.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    /// @return The hashed name.
    /// @return The selected networks' catalogue entries.
    /// @return The `describeInputs` record of the inputs.
    function checkInputs(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address sender,
        address authority,
        string memory name,
        address delegate,
        bool approve
    ) internal pure returns (bytes32, SupportedNetwork[] memory, string memory) {
        if (sender != authority) {
            revert SenderNotAuthority(sender, authority);
        }
        if (delegate == address(0)) {
            revert IRegistryDelegatesV1.ZeroDelegate();
        }
        bytes32 hashed = LibConfigRegistryRegister.nameHash(name);
        SupportedNetwork[] memory networks = LibConfigRegistryRegister.selectNetworks(selected, declared);
        return (hashed, networks, describeInputs(vm, name, authority, delegate, approve));
    }

    /// Sets the approval of `delegate` for `name` under `authority` to
    /// `approve` on every selected network, signed by `sender`.
    ///
    /// Every input refusal comes before the first fork, and every network is
    /// forked before any is selected, as `LibRainDeploy.createForks` requires.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param selected The networks to act on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs: the authority.
    /// @param authority The authority to approve under.
    /// @param name The name as a consumer writes it.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    /// @return The fork each selected network was simulated on, for
    /// `checkApprovalOnForks`.
    /// @return The `describeInputs` record logged.
    function approveOnNetworks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address sender,
        address authority,
        string memory name,
        address delegate,
        bool approve
    ) internal returns (uint256[] memory, string memory) {
        (,, string memory record) = checkInputs(vm, selected, declared, sender, authority, name, delegate, approve);
        console2.log(record);

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, selected);
        approveOnForks(vm, selected, declared, forkIds, sender, authority, name, delegate, approve);
        return (forkIds, record);
    }

    /// `approveOnNetworks` on forks the caller made, after the input refusals
    /// of `checkInputs`.
    /// @param vm The Vm instance to select forks and broadcast with.
    /// @param selected The networks the forks are of.
    /// @param declared The networks the declaration supports.
    /// @param forkIds The fork of each selected network, positionally paired.
    /// @param sender The account that signs: the authority.
    /// @param authority The authority to approve under.
    /// @param name The name as a consumer writes it.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    function approveOnForks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        address sender,
        address authority,
        string memory name,
        address delegate,
        bool approve
    ) internal {
        (bytes32 hashed, SupportedNetwork[] memory networks,) =
            checkInputs(vm, selected, declared, sender, authority, name, delegate, approve);
        if (forkIds.length != networks.length) {
            revert LibRainDeploy.ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            approveOnSelectedChain(vm, networks[i], authority, hashed, delegate, approve);
        }
    }

    /// Reverts unless the selected chain is the network's and its registry
    /// holds the approval of `delegate` for `name` under `authority` in the
    /// state `approve`.
    /// @param vm The Vm the chain id is read through.
    /// @param network The catalogue entry of the selected chain.
    /// @param authority The authority to read under.
    /// @param name The hashed name.
    /// @param delegate The delegate.
    /// @param approve Whether it must be approved.
    function checkApprovalOnSelectedChain(
        Vm vm,
        SupportedNetwork memory network,
        address authority,
        bytes32 name,
        address delegate,
        bool approve
    ) internal view {
        LibConfigRegistryRegister.checkChain(vm, network);
        if (
            IConfigRegistryV2(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
                    .approvedV2(authority, name, delegate) != approve
        ) {
            revert UnexpectedApproval(network.name, authority, name, delegate, approve);
        }
    }

    /// Reverts unless every given fork's registry holds the approval in the
    /// state `approve`, logging each network checked.
    /// @param vm The Vm instance to select forks with.
    /// @param selected The networks the forks are of.
    /// @param declared The networks the declaration supports.
    /// @param forkIds The fork of each selected network, positionally paired.
    /// @param authority The authority to read under.
    /// @param name The name as a consumer writes it.
    /// @param delegate The delegate.
    /// @param approve Whether it must be approved.
    function checkApprovalOnForks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        address authority,
        string memory name,
        address delegate,
        bool approve
    ) internal {
        bytes32 hashed = LibConfigRegistryRegister.nameHash(name);
        SupportedNetwork[] memory networks = LibConfigRegistryRegister.selectNetworks(selected, declared);
        if (forkIds.length != networks.length) {
            revert LibRainDeploy.ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            checkApprovalOnSelectedChain(vm, networks[i], authority, hashed, delegate, approve);
            console2.log(string.concat(approve ? "Approved on " : "Not approved on ", networks[i].name));
        }
    }

    /// `checkApprovalOnForks` on a fresh fork of every selected network: the
    /// confirmed check, run on its own once the transactions have been mined.
    /// @param vm The Vm instance to fork with.
    /// @param selected The networks to check.
    /// @param declared The networks the declaration supports.
    /// @param authority The authority to read under.
    /// @param name The name as a consumer writes it.
    /// @param delegate The delegate.
    /// @param approve Whether it must be approved.
    function checkApprovalOnNetworks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address authority,
        string memory name,
        address delegate,
        bool approve
    ) internal {
        // Refused before anything is forked; the returns are not needed here.
        // slither-disable-next-line unused-return
        LibConfigRegistryRegister.nameHash(name);
        // slither-disable-next-line unused-return
        LibConfigRegistryRegister.selectNetworks(selected, declared);
        checkApprovalOnForks(
            vm, selected, declared, LibRainDeploy.createForks(vm, selected), authority, name, delegate, approve
        );
    }
}
