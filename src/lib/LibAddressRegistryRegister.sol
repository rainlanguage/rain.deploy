// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";

import {ADDRESS_REGISTRY_ROOT} from "../concrete/AddressRegistry.sol";
import {IAddressRegistryV1} from "../interface/IAddressRegistryV1.sol";
import {LibAddressRegistry} from "./LibAddressRegistry.sol";
import {LibAddressRegistryDeploy} from "./LibAddressRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "./LibRainDeploy.sol";

/// @title LibAddressRegistryRegister
/// @notice Root's side of `AddressRegistry`: binds one name to one account on
/// every network it is given, from `ADDRESS_REGISTRY_ROOT`, and reads the
/// binding back. `script/RegisterAddress.sol` is the entry point and says how
/// it is run; everything with behaviour is here.
///
/// ## The name
///
/// Taken as the string a consumer hashes, never as a `bytes32`. Every consumer
/// derives its name as `keccak256("<org>.<name>")` — st0x's token-owner Safe
/// is `keccak256("st0x.token-owner-safe")` — and the registry cannot tell one
/// derivation from another, so a binding under any other encoding of the same
/// words is a binding no consumer ever resolves. Hashing here leaves no other
/// encoding to type.
///
/// The string is held to the alphabet those names are written in: lowercase
/// letters, digits, and `.` or `-` between non-empty runs of them, starting
/// with a letter. Everything outside it is a near miss of a real name rather
/// than a name of its own — a capital, a trailing space or newline from a
/// paste, an already-hashed `0x…` that would be hashed a second time — and each
/// hashes to a name nobody resolves, while the bind succeeds.
///
/// ## The guards
///
/// Everything a signature commits to is checked on the chain it will land on
/// before anything is broadcast, and a script that reverts signs nothing: forge
/// signs what a script recorded only once the script has returned. Per network,
/// the chain id is the one the catalogue states for the alias, and the
/// registry at the pinned address holds the pinned code hash — the check
/// `LibAddressRegistry.resolve` makes before every read, so the binding written
/// is in the registry consumers read. The inputs are checked once, before any
/// fork: the name is canonical, the account is not zero, the networks are a
/// non-empty, duplicate-free subset of the declared ones, and the sender is
/// root.
///
/// ## Simulation and confirmation
///
/// The same split as `LibRainDeploy.checkResolvedAddressesOnForks` and
/// `checkResolvedAddressesOnNetworks`. `registerOnNetworks` returns the forks
/// it simulated on, and `checkRegisteredOnForks` reads those; nothing is mined
/// while the script that registers is running, so the binding exists there and
/// nowhere else. `checkRegisteredOnNetworks` forks every network fresh, as a
/// run of its own once the transactions have been mined, and is the check that
/// the binding is on chain.
library LibAddressRegistryRegister {
    /// Thrown when a name is outside the alphabet consumers write names in.
    /// @param name The name as given.
    error NonCanonicalName(string name);

    /// Thrown when the account that would sign is not `ADDRESS_REGISTRY_ROOT`.
    /// The registry would refuse it with `NotRoot`; this says so before a
    /// device is asked to sign something that can only revert.
    /// @param sender The account that would sign.
    /// @param root The only account the registry accepts.
    error SenderNotRoot(address sender, address root);

    /// Thrown when a selected network is not one the declaration supports.
    /// @param network The selected name.
    error NetworkNotDeclared(string network);

    /// Thrown when a network is selected twice. Each selection is its own fork,
    /// and a second fork of a chain does not see the first one's bind, so it
    /// would record a second transaction to the same chain.
    /// @param network The repeated name.
    error DuplicateNetwork(string network);

    /// Thrown when the chain an alias forks is not the chain the catalogue
    /// states for it. A signature carries its chain id, so this is a bind sent
    /// to a chain nobody named.
    /// @param network The alias.
    /// @param expected The chain id the catalogue states.
    /// @param actual The chain id the fork reports.
    error UnexpectedChainId(string network, uint256 expected, uint256 actual);

    /// Thrown when a network's registry binds the name to an account other than
    /// the one expected.
    /// @param network The network read.
    /// @param name The hashed name.
    /// @param expected The account it should be bound to.
    /// @param actual The account it is bound to.
    error UnexpectedBinding(string network, bytes32 name, address expected, address actual);

    /// The `bytes32` a consumer resolves for `name`, refusing a non-canonical
    /// name.
    /// @param name The name as a consumer writes it.
    /// @return The name as the registry keys it.
    function nameHash(string memory name) internal pure returns (bytes32) {
        checkName(name);
        return keccak256(bytes(name));
    }

    /// Reverts `NonCanonicalName` unless `name` is lowercase letters, digits,
    /// and single `.` or `-` separators between them, starting with a letter
    /// and not ending with a separator.
    /// @param name The name as given.
    function checkName(string memory name) internal pure {
        bytes memory raw = bytes(name);
        if (raw.length == 0) {
            revert NonCanonicalName(name);
        }
        bool afterSeparator = false;
        for (uint256 i = 0; i < raw.length; i++) {
            bytes1 c = raw[i];
            bool letter = c >= "a" && c <= "z";
            if (i == 0 && !letter) {
                revert NonCanonicalName(name);
            }
            if (c == "." || c == "-") {
                if (afterSeparator) {
                    revert NonCanonicalName(name);
                }
                afterSeparator = true;
            } else if (letter || (c >= "0" && c <= "9")) {
                afterSeparator = false;
            } else {
                revert NonCanonicalName(name);
            }
        }
        if (afterSeparator) {
            revert NonCanonicalName(name);
        }
    }

    /// The catalogue entries for the selected networks, in selection order,
    /// refusing an empty selection, a network the declaration does not support
    /// and a repeated one.
    /// @param selected The networks to act on.
    /// @param declared The networks the declaration supports.
    /// @return The catalogue entry of each selected network.
    function selectNetworks(string[] memory selected, string[] memory declared)
        internal
        pure
        returns (SupportedNetwork[] memory)
    {
        if (selected.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }
        for (uint256 i = 0; i < selected.length; i++) {
            bytes32 network = keccak256(bytes(selected[i]));
            bool found = false;
            for (uint256 j = 0; j < declared.length; j++) {
                if (network == keccak256(bytes(declared[j]))) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                revert NetworkNotDeclared(selected[i]);
            }
            for (uint256 j = 0; j < i; j++) {
                if (network == keccak256(bytes(selected[j]))) {
                    revert DuplicateNetwork(selected[i]);
                }
            }
        }
        return LibRainDeploy.declaredNetworkConfigs(selected);
    }

    /// Reverts `SenderNotRoot` unless `sender` is `ADDRESS_REGISTRY_ROOT`.
    /// @param sender The account that would sign.
    function checkSender(address sender) internal pure {
        if (sender != ADDRESS_REGISTRY_ROOT) {
            revert SenderNotRoot(sender, ADDRESS_REGISTRY_ROOT);
        }
    }

    /// Reverts unless the selected chain is the network's and its registry is
    /// the pinned one.
    /// @param network The catalogue entry of the selected chain.
    function checkChain(SupportedNetwork memory network) internal view {
        if (block.chainid != network.chainId) {
            revert UnexpectedChainId(network.name, network.chainId, block.chainid);
        }
        LibAddressRegistry.checkCodeHash();
    }

    /// The selected chain's current binding of `name`, the zero address and
    /// moment when it is unbound. Only the registry's own `NameNotRegistered`
    /// for this name reads as unbound; any other revert is re-raised.
    /// @param name The hashed name.
    /// @return The bound account, or zero.
    /// @return The moment it was bound, or zero.
    function currentBinding(bytes32 name) internal view returns (address, uint256) {
        try IAddressRegistryV1(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS).get(name) returns (
            address account, uint256 registeredAt
        ) {
            return (account, registeredAt);
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    == keccak256(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, name))
            ) {
                return (address(0), 0);
            }
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }

    /// Binds `name` to `account` on the selected chain from `sender`, unless it
    /// is bound to `account` already. Logs the current binding and what is
    /// about to happen to it.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The catalogue entry of the selected chain.
    /// @param sender The account that signs.
    /// @param name The hashed name.
    /// @param account The account to bind it to.
    /// @return Whether a bind was broadcast.
    function registerOnSelectedChain(
        Vm vm,
        SupportedNetwork memory network,
        address sender,
        bytes32 name,
        address account
    ) internal returns (bool) {
        checkChain(network);
        (address bound, uint256 registeredAt) = currentBinding(name);

        console2.log("Network:", network.name);
        console2.log("  chain id:", block.chainid);
        if (bound == address(0)) {
            console2.log("  current: unbound");
        } else {
            console2.log(
                string.concat("  current: ", vm.toString(bound), " (bound at ", vm.toString(registeredAt), ")")
            );
        }
        if (bound == account) {
            console2.log("  SKIP: already bound to", account);
            return false;
        }
        console2.log(string.concat("  ", bound == address(0) ? "BIND" : "REBIND", ": -> ", vm.toString(account)));

        vm.startBroadcast(sender);
        IAddressRegistryV1(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS).register(name, account);
        vm.stopBroadcast();
        return true;
    }

    /// Binds `name` to `account` on every selected network from `sender`.
    ///
    /// Every input refusal comes before the first fork — the name, the account,
    /// the networks, then the sender — and every network is forked before any
    /// is selected, as `LibRainDeploy.createForks` requires.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param selected The networks to bind on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs. MUST be `ADDRESS_REGISTRY_ROOT`.
    /// @param name The name as a consumer writes it.
    /// @param account The account to bind it to.
    /// @return forkIds The fork each selected network was simulated on, for
    /// `checkRegisteredOnForks`.
    function registerOnNetworks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address sender,
        string memory name,
        address account
    ) internal returns (uint256[] memory forkIds) {
        bytes32 hashed = nameHash(name);
        if (account == address(0)) {
            revert IAddressRegistryV1.ZeroAccount(hashed);
        }
        SupportedNetwork[] memory networks = selectNetworks(selected, declared);
        checkSender(sender);

        console2.log("Name:", name);
        console2.log("Name hash (keccak256 of the name):", vm.toString(hashed));
        console2.log("Account:", account);
        console2.log("Sender (root):", sender);
        console2.log("Registry:", LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS);
        console2.log("Calldata:", vm.toString(abi.encodeCall(IAddressRegistryV1.register, (hashed, account))));

        forkIds = LibRainDeploy.createForks(vm, selected);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            registerOnSelectedChain(vm, networks[i], sender, hashed, account);
        }
    }

    /// Reverts unless every given fork's registry binds `name` to `account`,
    /// read through `LibAddressRegistry.resolve` exactly as a consumer reads
    /// it.
    /// @param vm The Vm instance to select forks with.
    /// @param selected The networks the forks are of.
    /// @param declared The networks the declaration supports.
    /// @param forkIds The fork of each selected network, positionally paired.
    /// @param name The name as a consumer writes it.
    /// @param account The account it must be bound to.
    function checkRegisteredOnForks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        string memory name,
        address account
    ) internal {
        bytes32 hashed = nameHash(name);
        SupportedNetwork[] memory networks = selectNetworks(selected, declared);
        if (forkIds.length != networks.length) {
            revert LibRainDeploy.ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            checkChain(networks[i]);
            (address actual,) = LibAddressRegistry.resolve(hashed);
            if (actual != account) {
                revert UnexpectedBinding(networks[i].name, hashed, account, actual);
            }
            console2.log("Bound on", networks[i].name);
        }
    }

    /// `checkRegisteredOnForks` on a fresh fork of every selected network: the
    /// confirmed check, run on its own once the binds have been mined.
    /// @param vm The Vm instance to fork with.
    /// @param selected The networks to check.
    /// @param declared The networks the declaration supports.
    /// @param name The name as a consumer writes it.
    /// @param account The account it must be bound to.
    function checkRegisteredOnNetworks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        string memory name,
        address account
    ) internal {
        // Refused before anything is forked.
        nameHash(name);
        selectNetworks(selected, declared);
        checkRegisteredOnForks(vm, selected, declared, LibRainDeploy.createForks(vm, selected), name, account);
    }
}
