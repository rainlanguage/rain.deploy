// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";

import {CONFIG_REGISTRY_ROOT} from "../concrete/ConfigRegistry.sol";
import {IConfigRegistryV1} from "../interface/IConfigRegistryV1.sol";
import {LibConfigRegistry} from "./LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "./LibConfigRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "./LibRainDeploy.sol";

/// @title LibConfigRegistryRegister
/// @notice Root's side of `ConfigRegistry`: binds one name to one ABI-encoded
/// value on every network it is given, from `CONFIG_REGISTRY_ROOT`, and reads
/// the binding back. `script/RegisterConfig.sol` is the entry point and says
/// how it is run; everything with behaviour is here.
///
/// ## The value
///
/// Taken as the bytes the registry stores, already ABI-encoded, and compared
/// byte for byte. Nothing here decodes it, because nothing here knows the type
/// a consumer decodes it as; an address is `abi.encode(account)`, which is
/// `cast abi-encode "f(address)" <account>`.
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
/// with a letter, and qualified by its `<org>.`. Everything outside it is a
/// near miss of a real name rather than a name of its own — a capital, a
/// trailing space or newline from a paste, an already-hashed `0x…` that would
/// be hashed a second time, `token-owner-safe` with its `st0x.` dropped — and
/// each hashes to a name nobody resolves, while the bind succeeds.
///
/// ## The guards
///
/// Everything a signature commits to is checked on the chain it will land on
/// before anything is broadcast, and a script that reverts signs nothing: forge
/// signs what a script recorded only once the script has returned. Per network,
/// the chain id is the one the catalogue states for the alias, and the
/// registry at the pinned address holds the pinned code hash — the check
/// `LibConfigRegistry.resolve` makes before every read, so the binding written
/// is in the registry consumers read. The inputs are checked once, before any
/// fork: the name is canonical, the value is not empty, the networks are a
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
library LibConfigRegistryRegister {
    /// Thrown when a name is outside the alphabet consumers write names in.
    /// @param name The name as given.
    error NonCanonicalName(string name);

    /// Thrown when a value is not a whole number of 32-byte words, which every
    /// `abi.encode` output is: a bare 20-byte address pasted in place of its
    /// ABI encoding, most likely. The registry binds any non-empty value; this
    /// refuses it before a device is asked to sign one no consumer can decode.
    /// @param value The value as given.
    error NonCanonicalValue(bytes value);

    /// Thrown when the account that would sign is not `CONFIG_REGISTRY_ROOT`.
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

    /// Thrown when a network's registry binds the name to a value other than the
    /// one expected.
    /// @param network The network read.
    /// @param name The hashed name.
    /// @param expected The value it should be bound to.
    /// @param actual The value it is bound to.
    error UnexpectedBinding(string network, bytes32 name, bytes expected, bytes actual);

    /// The `bytes32` a consumer resolves for `name`, refusing a non-canonical
    /// name.
    /// @param name The name as a consumer writes it.
    /// @return The name as the registry keys it.
    function nameHash(string memory name) internal pure returns (bytes32) {
        checkName(name);
        return keccak256(bytes(name));
    }

    /// Reverts `NonCanonicalName` unless `name` is lowercase letters, digits,
    /// and single `.` or `-` separators between them, starting with a letter,
    /// not ending with a separator, and holding at least one `.`: the one after
    /// the `<org>` every consumer's name is qualified by.
    /// @param name The name as given.
    function checkName(string memory name) internal pure {
        bytes memory raw = bytes(name);
        if (raw.length == 0) {
            revert NonCanonicalName(name);
        }
        bool afterSeparator = false;
        bool qualified = false;
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
                if (c == ".") {
                    qualified = true;
                }
            } else if (letter || (c >= "0" && c <= "9")) {
                afterSeparator = false;
            } else {
                revert NonCanonicalName(name);
            }
        }
        if (afterSeparator || !qualified) {
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

    /// Reverts `SenderNotRoot` unless `sender` is `CONFIG_REGISTRY_ROOT`.
    /// @param sender The account that would sign.
    function checkSender(address sender) internal pure {
        if (sender != CONFIG_REGISTRY_ROOT) {
            revert SenderNotRoot(sender, CONFIG_REGISTRY_ROOT);
        }
    }

    /// Reverts unless the selected chain is the network's and its registry is
    /// the pinned one.
    /// @param network The catalogue entry of the selected chain.
    function checkChain(SupportedNetwork memory network) internal view {
        if (block.chainid != network.chainId) {
            revert UnexpectedChainId(network.name, network.chainId, block.chainid);
        }
        LibConfigRegistry.checkCodeHash();
    }

    /// The selected chain's current binding of `name`, an empty value and a
    /// moment of zero when it is unbound. Only the registry's own
    /// `NameNotRegistered` for this name reads as unbound; any other revert is
    /// re-raised.
    /// @param name The hashed name.
    /// @return The bound value, or empty.
    /// @return The moment it was bound, or zero.
    function currentBinding(bytes32 name) internal view returns (bytes memory, uint256) {
        try IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS).get(name) returns (
            bytes memory value, uint256 registeredAt
        ) {
            return (value, registeredAt);
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    == keccak256(abi.encodeWithSelector(IConfigRegistryV1.NameNotRegistered.selector, name))
            ) {
                return ("", 0);
            }
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }

    /// The calldata of the bind of `name` to `value`: what the device signs,
    /// and what `registerOnSelectedChain` sends.
    /// @param name The hashed name.
    /// @param value The ABI-encoded value to bind it to.
    /// @return The `register` calldata.
    function registerCalldata(bytes32 name, bytes memory value) internal pure returns (bytes memory) {
        return abi.encodeCall(IConfigRegistryV1.register, (name, value));
    }

    /// The record of a run's inputs, printed before any network: everything the
    /// device is asked to sign, exactly as it will be signed.
    /// @param vm The Vm instance to format with.
    /// @param name The name as a consumer writes it.
    /// @param value The ABI-encoded value to bind it to.
    /// @param sender The account that signs.
    /// @return The record, one field per line.
    function describeInputs(Vm vm, string memory name, bytes memory value, address sender)
        internal
        pure
        returns (string memory)
    {
        bytes32 hashed = nameHash(name);
        return string.concat(
            "Name: ",
            name,
            "\nName hash (keccak256 of the name): ",
            vm.toString(hashed),
            "\nValue: ",
            vm.toString(value),
            "\nSender (root): ",
            vm.toString(sender),
            "\nRegistry: ",
            vm.toString(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS),
            "\nCalldata: ",
            vm.toString(registerCalldata(hashed, value))
        );
    }

    /// The record of one network: its chain id, the current binding, and what
    /// the run does to it — `SKIP` when it is bound to `value` already, `BIND`
    /// when it is unbound, `REBIND` otherwise.
    /// @param vm The Vm instance to format with.
    /// @param network The network's name.
    /// @param chainId The chain the network forked.
    /// @param bound The value the name is bound to, or empty.
    /// @param registeredAt The moment it was bound, or zero.
    /// @param value The value to bind it to.
    /// @return The record, one field per line.
    function describeNetwork(
        Vm vm,
        string memory network,
        uint256 chainId,
        bytes memory bound,
        uint256 registeredAt,
        bytes memory value
    ) internal pure returns (string memory) {
        string memory current = bound.length == 0
            ? "unbound"
            : string.concat(vm.toString(bound), " (bound at ", vm.toString(registeredAt), ")");
        string memory action;
        if (keccak256(bound) == keccak256(value)) {
            action = string.concat("SKIP: already bound to ", vm.toString(value));
        } else {
            action = string.concat(bound.length == 0 ? "BIND" : "REBIND", ": -> ", vm.toString(value));
        }
        return string.concat(
            "Network: ", network, "\n  chain id: ", vm.toString(chainId), "\n  current: ", current, "\n  ", action
        );
    }

    /// Binds `name` to `value` on the selected chain from `sender`, unless it
    /// is bound to `value` already. Logs the current binding and what is about
    /// to happen to it.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The catalogue entry of the selected chain.
    /// @param sender The account that signs.
    /// @param name The hashed name.
    /// @param value The ABI-encoded value to bind it to.
    /// @return Whether a bind was broadcast.
    /// @return The record logged.
    function registerOnSelectedChain(
        Vm vm,
        SupportedNetwork memory network,
        address sender,
        bytes32 name,
        bytes memory value
    ) internal returns (bool, string memory) {
        checkChain(network);
        (bytes memory bound, uint256 registeredAt) = currentBinding(name);

        string memory record = describeNetwork(vm, network.name, block.chainid, bound, registeredAt, value);
        console2.log(record);
        bool binds = keccak256(bound) != keccak256(value);
        if (binds) {
            vm.startBroadcast(sender);
            IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS).register(name, value);
            vm.stopBroadcast();
        }
        return (binds, record);
    }

    /// Every input refusal of `registerOnNetworks`, in order — the name, the
    /// value, the networks, then the sender — and the inputs record it logs.
    /// @param vm The Vm instance to format with.
    /// @param selected The networks to bind on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs. MUST be `CONFIG_REGISTRY_ROOT`.
    /// @param name The name as a consumer writes it.
    /// @param value The ABI-encoded value to bind it to.
    /// @return The selected networks' catalogue entries.
    /// @return The `describeInputs` record of the inputs.
    function checkInputs(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address sender,
        string memory name,
        bytes memory value
    ) internal pure returns (SupportedNetwork[] memory, string memory) {
        bytes32 hashed = nameHash(name);
        if (value.length == 0) {
            revert IConfigRegistryV1.EmptyValue(hashed);
        }
        if (value.length % 32 != 0) {
            revert NonCanonicalValue(value);
        }
        SupportedNetwork[] memory networks = selectNetworks(selected, declared);
        checkSender(sender);
        return (networks, describeInputs(vm, name, value, sender));
    }

    /// Binds `name` to `value` on every selected network from `sender`.
    ///
    /// Every input refusal comes before the first fork, and every network is
    /// forked before any is selected, as `LibRainDeploy.createForks` requires.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param selected The networks to bind on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs. MUST be `CONFIG_REGISTRY_ROOT`.
    /// @param name The name as a consumer writes it.
    /// @param value The ABI-encoded value to bind it to.
    /// @return The fork each selected network was simulated on, for
    /// `checkRegisteredOnForks`.
    function registerOnNetworks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address sender,
        string memory name,
        bytes memory value
    ) internal returns (uint256[] memory) {
        (SupportedNetwork[] memory networks, string memory record) =
            checkInputs(vm, selected, declared, sender, name, value);
        console2.log(record);
        bytes32 hashed = nameHash(name);

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, selected);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            registerOnSelectedChain(vm, networks[i], sender, hashed, value);
        }
        return forkIds;
    }

    /// Reverts unless every given fork's registry binds `name` to `value`, read
    /// through `LibConfigRegistry.resolve` exactly as a consumer reads it,
    /// logging the moment each was bound.
    /// @param vm The Vm instance to select forks with.
    /// @param selected The networks the forks are of.
    /// @param declared The networks the declaration supports.
    /// @param forkIds The fork of each selected network, positionally paired.
    /// @param name The name as a consumer writes it.
    /// @param value The value it must be bound to.
    function checkRegisteredOnForks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        string memory name,
        bytes memory value
    ) internal {
        bytes32 hashed = nameHash(name);
        SupportedNetwork[] memory networks = selectNetworks(selected, declared);
        if (forkIds.length != networks.length) {
            revert LibRainDeploy.ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            checkChain(networks[i]);
            (bytes memory actual, uint256 registeredAt) = LibConfigRegistry.resolve(hashed);
            if (keccak256(actual) != keccak256(value)) {
                revert UnexpectedBinding(networks[i].name, hashed, value, actual);
            }
            console2.log(string.concat("Bound on ", networks[i].name, " at ", vm.toString(registeredAt)));
        }
    }

    /// `checkRegisteredOnForks` on a fresh fork of every selected network: the
    /// confirmed check, run on its own once the binds have been mined.
    /// @param vm The Vm instance to fork with.
    /// @param selected The networks to check.
    /// @param declared The networks the declaration supports.
    /// @param name The name as a consumer writes it.
    /// @param value The value it must be bound to.
    function checkRegisteredOnNetworks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        string memory name,
        bytes memory value
    ) internal {
        // Refused before anything is forked.
        nameHash(name);
        selectNetworks(selected, declared);
        checkRegisteredOnForks(vm, selected, declared, LibRainDeploy.createForks(vm, selected), name, value);
    }
}
