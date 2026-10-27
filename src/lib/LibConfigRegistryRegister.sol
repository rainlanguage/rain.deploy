// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";

import {IConfigRegistryV4} from "../interface/IConfigRegistryV4.sol";
import {LibConfigRegistry} from "./LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "./LibConfigRegistryDeploy.sol";
import {LibRainDeploy, SupportedNetwork} from "./LibRainDeploy.sol";

/// @title LibConfigRegistryRegister
/// @notice An authority's side of `ConfigRegistry`: binds one name to one
/// typed, ABI-encoded value under that authority on every network it is given, signed
/// by the authority or a delegate it approved, and reads the binding back.
/// `script/RegisterConfig.sol` is the entry point and says how it is run;
/// everything with behaviour is here.
///
/// ## The value
///
/// Taken as the bytes the registry stores, already ABI-encoded, and compared
/// byte for byte. Nothing here decodes it, because nothing here knows the type
/// a consumer decodes it as; an address is `abi.encode(account)`, which is
/// `cast abi-encode "f(address)" <account>`.
///
/// ## The value type
///
/// Taken as the ABI type string of the value's encoding — `address` for
/// `abi.encode(account)` — which the registry hashes and stores beside the
/// value, and which a consumer's read refuses unless it is the type it decodes.
/// It is held to the alphabet canonical ABI types are written in: lowercase
/// letters, digits, `(`, `)`, `,`, `[` and `]`. A space, a capital or a pasted
/// newline is a type no consumer decodes as, so the read refuses the binding
/// while the bind succeeds.
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
/// is in the registry consumers read. `checkInputs` checks the inputs before
/// any fork: the name and the value type are canonical, the value is not empty and is a
/// whole number of 32-byte words, and the networks are a non-empty,
/// duplicate-free subset of the declared ones. An approval is per-chain state,
/// so `checkSender` is made per network once it is forked, before anything is
/// recorded: the sender is the authority or a delegate the authority approved
/// on that chain.
/// Forge is a second layer: `forge script --broadcast`, without `--unlocked`,
/// stops with `No associated wallet for addresses: [...]` before sending on any
/// chain when no key, Trezor or Ledger it was given is the sender
/// (`BundledState::broadcast` in foundry-rs/foundry
/// `crates/script/src/broadcast.rs`).
/// `registerOnNetworks` runs it and logs the inputs record before creating
/// the forks; `registerOnForks` runs it again for a caller with its own forks,
/// and logs no record.
///
/// ## Simulation and confirmation
///
/// The same split as `LibRainDeploy`'s `checkResolved*OnForks` and
/// `checkResolved*OnNetworks` pairs. `registerOnNetworks` returns the forks
/// it simulated on, and `checkRegisteredOnForks` reads those; nothing is mined
/// while the script that registers is running, so the binding exists there and
/// nowhere else. `checkRegisteredOnNetworks` forks every network fresh, as a
/// run of its own once the transactions have been mined, and is the check that
/// the binding is on chain.
library LibConfigRegistryRegister {
    /// Thrown when a name is outside the alphabet consumers write names in.
    /// @param name The name as given.
    error NonCanonicalName(string name);

    /// Thrown when a value type is empty or outside the alphabet canonical ABI
    /// types are written in.
    /// @param valueType The value type as given.
    error NonCanonicalValueType(string valueType);

    /// Thrown when a value is not a whole number of 32-byte words, which every
    /// `abi.encode` output is: a bare 20-byte address pasted in place of its
    /// ABI encoding, most likely. The registry binds any non-empty value; this
    /// refuses it before a device is asked to sign a value that is not the
    /// output of any `abi.encode`. This script binds ABI-encoded values only.
    ///
    /// It is the only check on what a value holds. Its type is agreed between
    /// the authority and the name's consumers, and any whole-word value can
    /// be correct for some name: a zero word is a threshold or delay of 0.
    /// Checking that the bytes encode what consumers decode is on whoever
    /// builds them, and `checkRegisteredOnNetworks` proves only that the chain
    /// holds those bytes.
    /// @param value The value as given.
    error NonCanonicalValue(bytes value);

    /// Thrown when the account that would sign is neither the authority the
    /// run binds under nor a delegate the authority approved on the network.
    /// The registry would refuse the bind with `NotApproved`; this refuses it
    /// before a device is asked to sign it: a wrong derivation path, or a
    /// delegate not yet approved on that chain, most likely.
    /// @param network The network the sender is not approved on.
    /// @param sender The account that would sign.
    /// @param authority The authority the run binds under.
    /// @param nameHash The hash of the name the run binds.
    error SenderNotApproved(string network, address sender, address authority, bytes32 nameHash);

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

    /// Thrown when a network's registry binds the name under the authority to
    /// a value other than the one expected.
    /// @param network The network read.
    /// @param authority The authority the name was read under.
    /// @param nameHash The hash of the name.
    /// @param expected The value it should be bound to.
    /// @param actual The value it is bound to.
    error UnexpectedBinding(string network, address authority, bytes32 nameHash, bytes expected, bytes actual);

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

    /// Reverts `NonCanonicalValueType` unless `valueType` is a non-empty run of
    /// the characters a canonical ABI type is written in: lowercase letters,
    /// digits, `(`, `)`, `,`, `[` and `]`.
    /// @param valueType The value type as given.
    function checkValueType(string memory valueType) internal pure {
        bytes memory raw = bytes(valueType);
        if (raw.length == 0) {
            revert NonCanonicalValueType(valueType);
        }
        for (uint256 i = 0; i < raw.length; i++) {
            bytes1 c = raw[i];
            if (!((c >= "a" && c <= "z") || (c >= "0" && c <= "9") || c == "(" || c == ")" || c == "," || c == "["
                        || c == "]")) {
                revert NonCanonicalValueType(valueType);
            }
        }
    }

    /// Reverts `SenderNotApproved` unless `sender` is `authority` or approved
    /// by it for `hashed` in the selected chain's registry.
    /// @param network The catalogue entry of the selected chain.
    /// @param sender The account that would sign.
    /// @param authority The authority the run binds under.
    /// @param hashed The hash of the name the run binds.
    function checkSender(SupportedNetwork memory network, address sender, address authority, bytes32 hashed)
        internal
        view
    {
        if (
            sender != authority
                && !IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
                    .approvedV3(authority, hashed, sender)
        ) {
            revert SenderNotApproved(network.name, sender, authority, hashed);
        }
    }

    /// Reverts unless the selected chain is the network's and its registry is
    /// the pinned one.
    /// @param vm The Vm the chain id is read through, so the read follows the
    /// selected fork.
    /// @param network The catalogue entry of the selected chain.
    function checkChain(Vm vm, SupportedNetwork memory network) internal view {
        uint256 chainId = vm.getChainId();
        if (chainId != network.chainId) {
            revert UnexpectedChainId(network.name, network.chainId, chainId);
        }
        LibConfigRegistry.checkCodeHash();
    }

    /// The selected chain's current binding of `hashed` under `authority`, an
    /// empty value, a moment of zero and a type hash of zero when it is
    /// unbound. Only the registry's own `NameNotRegistered` for this authority
    /// and name reads as unbound; any other revert is re-raised.
    /// @param authority The authority to read under.
    /// @param hashed The hash of the name.
    /// @return The bound value, or empty.
    /// @return The moment it was bound, or zero.
    /// @return The hash of the type it was bound as, or zero.
    function currentBinding(address authority, bytes32 hashed)
        internal
        view
        returns (bytes memory, uint256, bytes32)
    {
        try IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .getV4(authority, hashed) returns (
            bytes memory value, uint256 registeredAt, bytes32 valueTypeHash
        ) {
            return (value, registeredAt, valueTypeHash);
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    == keccak256(
                        abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, authority, hashed)
                    )
            ) {
                return ("", 0, bytes32(0));
            }
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }

    /// The calldata of the bind of `name` to `value` of type `valueType` under
    /// `authority`: what the device signs, and what `registerOnSelectedChain`
    /// sends.
    /// @param authority The authority to bind under.
    /// @param name The name as a consumer writes it.
    /// @param valueType The ABI type string of `value`'s encoding.
    /// @param value The ABI-encoded value to bind it to.
    /// @return The `registerV4` calldata.
    function registerCalldata(address authority, string memory name, string memory valueType, bytes memory value)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(IConfigRegistryV4.registerV4, (authority, name, valueType, value));
    }

    /// The record of a run's inputs, printed before any network: everything the
    /// sender's device is asked to sign, exactly as it will be signed.
    /// @param vm The Vm instance to format with.
    /// @param name The name as a consumer writes it.
    /// @param valueType The ABI type string of `value`'s encoding.
    /// @param value The ABI-encoded value to bind it to.
    /// @param sender The account that signs: the authority or a delegate it
    /// approved.
    /// @param authority The authority the name is bound under.
    /// @return The record, one field per line.
    function describeInputs(
        Vm vm,
        string memory name,
        string memory valueType,
        bytes memory value,
        address sender,
        address authority
    ) internal pure returns (string memory) {
        return string.concat(
            string.concat(
                "Name: ",
                name,
                "\nName hash (keccak256 of the name): ",
                vm.toString(nameHash(name)),
                "\nValue type: ",
                valueType,
                "\nValue type hash (keccak256 of the value type): ",
                vm.toString(keccak256(bytes(valueType))),
                "\nValue: ",
                vm.toString(value)
            ),
            "\nAuthority: ",
            vm.toString(authority),
            "\nSender: ",
            vm.toString(sender),
            "\nRegistry: ",
            vm.toString(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS),
            "\nCalldata: ",
            vm.toString(registerCalldata(authority, name, valueType, value))
        );
    }

    /// The record of one network: its chain id, the current binding, and what
    /// the run does to it — `SKIP` when it is bound to `value` as `valueType`
    /// already, `BIND` when it is unbound, `REBIND` otherwise.
    /// @param vm The Vm instance to format with.
    /// @param network The network's name.
    /// @param chainId The chain the network forked.
    /// @param bound The value the name is bound to, or empty.
    /// @param registeredAt The moment it was bound, or zero.
    /// @param boundValueTypeHash The hash of the type it was bound as, or zero.
    /// @param valueType The ABI type string to bind it as.
    /// @param value The value to bind it to.
    /// @return The record, one field per line.
    function describeNetwork(
        Vm vm,
        string memory network,
        uint256 chainId,
        bytes memory bound,
        uint256 registeredAt,
        bytes32 boundValueTypeHash,
        string memory valueType,
        bytes memory value
    ) internal pure returns (string memory) {
        string memory current = bound.length == 0
            ? "unbound"
            : string.concat(
                vm.toString(bound),
                " (type hash ",
                vm.toString(boundValueTypeHash),
                ", bound at ",
                vm.toString(registeredAt),
                ")"
            );
        string memory action;
        if (isBoundTo(bound, boundValueTypeHash, valueType, value)) {
            action = string.concat("SKIP: already bound to ", vm.toString(value), " as ", valueType);
        } else {
            action =
                string.concat(bound.length == 0 ? "BIND" : "REBIND", ": -> ", vm.toString(value), " as ", valueType);
        }
        return string.concat(
            "Network: ", network, "\n  chain id: ", vm.toString(chainId), "\n  current: ", current, "\n  ", action
        );
    }

    /// Whether a binding is `value` as `valueType`: the bytes and the type
    /// both, so a binding of the right bytes under another type is re-bound.
    /// @param bound The bound value, or empty.
    /// @param boundValueTypeHash The hash of the type it was bound as, or zero.
    /// @param valueType The ABI type string to bind it as.
    /// @param value The value to bind it to.
    /// @return True when nothing needs binding.
    function isBoundTo(bytes memory bound, bytes32 boundValueTypeHash, string memory valueType, bytes memory value)
        internal
        pure
        returns (bool)
    {
        return keccak256(bound) == keccak256(value) && boundValueTypeHash == keccak256(bytes(valueType));
    }

    /// Binds `name` to `value` of type `valueType` under `authority` on the
    /// selected chain, signed by `sender`, unless it is bound to `value` as
    /// `valueType` there already. Logs the current binding and what is about
    /// to happen to it.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The catalogue entry of the selected chain.
    /// @param sender The account that signs: `authority` or a delegate it
    /// approved on this chain.
    /// @param authority The authority to bind under.
    /// @param name The name as a consumer writes it, already checked.
    /// @param valueType The ABI type string of `value`'s encoding, already
    /// checked.
    /// @param value The ABI-encoded value to bind it to.
    /// @return Whether a bind was broadcast.
    /// @return The record logged.
    function registerOnSelectedChain(
        Vm vm,
        SupportedNetwork memory network,
        address sender,
        address authority,
        string memory name,
        string memory valueType,
        bytes memory value
    ) internal returns (bool, string memory) {
        bytes32 hashed = keccak256(bytes(name));
        checkChain(vm, network);
        checkSender(network, sender, authority, hashed);
        (bytes memory bound, uint256 registeredAt, bytes32 boundValueTypeHash) = currentBinding(authority, hashed);

        string memory record = describeNetwork(
            vm, network.name, network.chainId, bound, registeredAt, boundValueTypeHash, valueType, value
        );
        console2.log(record);
        bool binds = !isBoundTo(bound, boundValueTypeHash, valueType, value);
        if (binds) {
            vm.startBroadcast(sender);
            IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
                .registerV4(authority, name, valueType, value);
            vm.stopBroadcast();
        }
        return (binds, record);
    }

    /// Every input refusal of `registerOnNetworks`, in order — the name, the
    /// value type, the value, then the networks — and the inputs record it
    /// logs. The sender is checked per network, by `registerOnSelectedChain`.
    /// @param vm The Vm instance to format with.
    /// @param selected The networks to bind on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs.
    /// @param authority The authority to bind under.
    /// @param name The name as a consumer writes it.
    /// @param valueType The ABI type string of `value`'s encoding.
    /// @param value The ABI-encoded value to bind it to.
    /// @return The selected networks' catalogue entries.
    /// @return The `describeInputs` record of the inputs.
    function checkInputs(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address sender,
        address authority,
        string memory name,
        string memory valueType,
        bytes memory value
    ) internal pure returns (SupportedNetwork[] memory, string memory) {
        bytes32 hashed = nameHash(name);
        checkValueType(valueType);
        if (value.length == 0) {
            revert IConfigRegistryV4.EmptyValue(hashed);
        }
        if (value.length % 32 != 0) {
            revert NonCanonicalValue(value);
        }
        SupportedNetwork[] memory networks = selectNetworks(selected, declared);
        return (networks, describeInputs(vm, name, valueType, value, sender, authority));
    }

    /// Binds `name` to `value` of type `valueType` under `authority` on every
    /// selected network, signed by `sender`.
    ///
    /// Every input refusal comes before the first fork, and every network is
    /// forked before any is selected, as `LibRainDeploy.createForks` requires.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param selected The networks to bind on.
    /// @param declared The networks the declaration supports.
    /// @param sender The account that signs: `authority` or a delegate it
    /// approved on every selected network.
    /// @param authority The authority to bind under.
    /// @param name The name as a consumer writes it.
    /// @param valueType The ABI type string of `value`'s encoding.
    /// @param value The ABI-encoded value to bind it to.
    /// @return The fork each selected network was simulated on, for
    /// `checkRegisteredOnForks`.
    /// @return The `describeInputs` record logged.
    function registerOnNetworks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address sender,
        address authority,
        string memory name,
        string memory valueType,
        bytes memory value
    ) internal returns (uint256[] memory, string memory) {
        (, string memory record) = checkInputs(vm, selected, declared, sender, authority, name, valueType, value);
        console2.log(record);

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, selected);
        registerOnForks(vm, selected, declared, forkIds, sender, authority, name, valueType, value);
        return (forkIds, record);
    }

    /// Binds `name` to `value` of type `valueType` under `authority`, signed by
    /// `sender`, on every given fork, after the input refusals of
    /// `checkInputs`.
    /// @param vm The Vm instance to select forks and broadcast with.
    /// @param selected The networks the forks are of.
    /// @param declared The networks the declaration supports.
    /// @param forkIds The fork of each selected network, positionally paired.
    /// @param sender The account that signs: `authority` or a delegate it
    /// approved on every selected network.
    /// @param authority The authority to bind under.
    /// @param name The name as a consumer writes it.
    /// @param valueType The ABI type string of `value`'s encoding.
    /// @param value The ABI-encoded value to bind it to.
    function registerOnForks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        address sender,
        address authority,
        string memory name,
        string memory valueType,
        bytes memory value
    ) internal {
        (SupportedNetwork[] memory networks,) =
            checkInputs(vm, selected, declared, sender, authority, name, valueType, value);
        if (forkIds.length != networks.length) {
            revert LibRainDeploy.ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            registerOnSelectedChain(vm, networks[i], sender, authority, name, valueType, value);
        }
    }

    /// Reverts unless every given fork's registry binds `name` under
    /// `authority` to `value` as `valueType`, read through
    /// `LibConfigRegistry.resolve` exactly as a consumer reads it, logging the
    /// moment each was bound.
    /// @param vm The Vm instance to select forks with.
    /// @param selected The networks the forks are of.
    /// @param declared The networks the declaration supports.
    /// @param forkIds The fork of each selected network, positionally paired.
    /// @param authority The authority to read under.
    /// @param name The name as a consumer writes it.
    /// @param valueType The ABI type string it must be bound as.
    /// @param value The value it must be bound to.
    function checkRegisteredOnForks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        uint256[] memory forkIds,
        address authority,
        string memory name,
        string memory valueType,
        bytes memory value
    ) internal {
        bytes32 hashed = nameHash(name);
        checkValueType(valueType);
        SupportedNetwork[] memory networks = selectNetworks(selected, declared);
        if (forkIds.length != networks.length) {
            revert LibRainDeploy.ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            uint256 registeredAt =
                checkRegisteredOnSelectedChain(vm, networks[i], authority, hashed, keccak256(bytes(valueType)), value);
            console2.log(string.concat("Bound on ", networks[i].name, " at ", vm.toString(registeredAt)));
        }
    }

    /// Reverts unless the selected chain is the network's and its registry
    /// binds `hashed` under `authority` to `value` as `valueTypeHash`, read
    /// through `LibConfigRegistry.resolve` exactly as a consumer reads it.
    /// @param vm The Vm the chain id is read through.
    /// @param network The catalogue entry of the selected chain.
    /// @param authority The authority to read under.
    /// @param hashed The hash of the name.
    /// @param valueTypeHash The hash of the type it must be bound as.
    /// @param value The value it must be bound to.
    /// @return The moment it was bound.
    function checkRegisteredOnSelectedChain(
        Vm vm,
        SupportedNetwork memory network,
        address authority,
        bytes32 hashed,
        bytes32 valueTypeHash,
        bytes memory value
    ) internal view returns (uint256) {
        checkChain(vm, network);
        (bytes memory actual, uint256 registeredAt) = LibConfigRegistry.resolve(authority, hashed, valueTypeHash);
        if (keccak256(actual) != keccak256(value)) {
            revert UnexpectedBinding(network.name, authority, hashed, value, actual);
        }
        return registeredAt;
    }

    /// `checkRegisteredOnForks` on a fresh fork of every selected network: the
    /// confirmed check, run on its own once the binds have been mined.
    /// @param vm The Vm instance to fork with.
    /// @param selected The networks to check.
    /// @param declared The networks the declaration supports.
    /// @param authority The authority to read under.
    /// @param name The name as a consumer writes it.
    /// @param valueType The ABI type string it must be bound as.
    /// @param value The value it must be bound to.
    function checkRegisteredOnNetworks(
        Vm vm,
        string[] memory selected,
        string[] memory declared,
        address authority,
        string memory name,
        string memory valueType,
        bytes memory value
    ) internal {
        // Refused before anything is forked.
        nameHash(name);
        checkValueType(valueType);
        selectNetworks(selected, declared);
        checkRegisteredOnForks(
            vm, selected, declared, LibRainDeploy.createForks(vm, selected), authority, name, valueType, value
        );
    }
}
