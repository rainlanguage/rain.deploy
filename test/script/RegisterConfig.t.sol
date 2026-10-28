// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV5} from "../../src/interface/IConfigRegistryV5.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibConfigRegistryDeploy} from "../../src/lib/LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister} from "../../src/lib/LibConfigRegistryRegister.sol";
import {LibConfigRegistryFork} from "../lib/LibConfigRegistryFork.sol";
import {LibConfigRegistryRead} from "../lib/LibConfigRegistryRead.sol";
import {LibRegistryAuthority} from "../../src/lib/LibRegistryAuthority.sol";
import {LocalRegisterConfig} from "../concrete/LocalRegisterConfig.sol";
import {VALUE_TYPE, VALUE_TYPE_HASH} from "../lib/ConfigTestBinding.sol";

/// @title RegisterConfigTest
/// The script's wiring: which variables it reads, that the signer is the
/// script's `msg.sender`, that both entries default to every supported
/// network, and that it forks with the cheatcodes. Every network forks as the
/// local EVM, so nothing here needs an RPC. `LibConfigRegistryRegister`'s own
/// tests cover what it does with them on live forks.
///
/// ONE test function, because it writes process-wide environment variables and
/// forge runs test functions concurrently. Nothing else in the suite reads or
/// writes these names, and the unset-networks cases run before the variable is
/// first set, since a set variable cannot be unset.
contract RegisterConfigTest is Test {
    struct Pair {
        address account;
        uint256 amount;
    }

    struct PairWithHashes {
        Pair pair;
        bytes32[] hashes;
    }

    struct Flag {
        address account;
        bool on;
    }

    struct Entry {
        uint256 id;
        Flag[] flags;
    }

    function testWiring() external {
        // The no-op broadcast leaves the script signing, so deployed at the
        // root authority the script signs as it.
        address authority = LibRegistryAuthority.ROOT_AUTHORITY;
        deployCodeTo("LocalRegisterConfig.sol:LocalRegisterConfig", authority);
        LocalRegisterConfig script = LocalRegisterConfig(authority);
        assertEq(address(script.baseForkVm()), address(vm));
        string memory name = string.concat("rain.deploy.register-test.", vm.toString(vm.randomUint()));

        vm.setEnv("CONFIG_REGISTRY_VALUE_TYPE", VALUE_TYPE);
        vm.setEnv("CONFIG_REGISTRY_NAME", "Not.Canonical");
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.run();

        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        vm.setEnv("CONFIG_REGISTRY_VALUE", "0x");
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValue.selector, keccak256(bytes(name))));
        script.run();

        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));

        // The confirmed check forks every declared network, and the first
        // fails first, with no registry there yet.
        vm.expectRevert(LibConfigRegistryFork.unboundResolveRevert(authority, keccak256(bytes(name))));
        script.verify();

        runAsAuthorityOnEveryNetwork(script, name);
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));

        // Networks unset: the default is every declared network, and the
        // first refuses the sender — this test contract, as the script's
        // `msg.sender` — which the authority has not approved there.
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.SenderNotApproved.selector,
                LibRainDeploy.supportedNetworks()[0],
                address(this),
                authority,
                keccak256(bytes(name))
            )
        );
        script.run();

        vm.setEnv("CONFIG_REGISTRY_NETWORKS", "base,nowhere");
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        script.run();
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        script.verify();

        vm.setEnv("CONFIG_REGISTRY_NAME", "Not.Canonical");
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.verify();

        // With the name bound, the confirmed check passes on exactly the value
        // given and refuses any other.
        string memory network = LibRainDeploy.supportedNetworks()[0];
        bytes memory value = abi.encode(address(1));
        vm.prank(authority);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV5(authority, keccak256(bytes(name)), VALUE_TYPE, value, "");
        vm.setEnv("CONFIG_REGISTRY_NETWORKS", network);
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        script.verify();

        bytes memory other = abi.encode(address(2));
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(other));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.UnexpectedBinding.selector,
                network,
                authority,
                keccak256(bytes(name)),
                other,
                value
            )
        );
        script.verify();

        // Run as the authority on a fresh name binds it on exactly the
        // selected network.
        string memory freshName = string.concat(name, "-run");
        bytes memory freshValue = abi.encode(address(3));
        vm.setEnv("CONFIG_REGISTRY_NAME", freshName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(freshValue));
        uint256[] memory forkIds = script.runAsItself();
        assertEq(forkIds.length, 1);
        assertEq(forkIds[0], LibRainDeploy.declaredNetworkConfigs(LibRainDeploy.supportedNetworks())[0].chainId);
        assertEq(block.chainid, forkIds[0]);
        (bytes memory bound, uint256 registeredAt, bytes32 boundTypeHash) = IConfigRegistryV5(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
            ).getV5(authority, keccak256(bytes(freshName)));
        assertEq(bound, freshValue);
        assertEq(registeredAt, vm.getBlockTimestamp());
        assertEq(boundTypeHash, VALUE_TYPE_HASH);

        assertRunSkips(script, authority, keccak256(bytes(freshName)), freshValue, registeredAt);

        // Run as the authority on a name already bound to another value
        // rebinds it.
        string memory rotateName = string.concat(name, "-rotate");
        bytes memory rotateValue = abi.encode(address(4));
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(authority);
        IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV5(authority, keccak256(bytes(rotateName)), VALUE_TYPE, freshValue, "");
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.setEnv("CONFIG_REGISTRY_NAME", rotateName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(rotateValue));
        forkIds = script.runAsItself();
        assertEq(forkIds.length, 1);
        (bound, registeredAt, boundTypeHash) = IConfigRegistryV5(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
            ).getV5(authority, keccak256(bytes(rotateName)));
        assertEq(bound, rotateValue);
        assertEq(registeredAt, block.timestamp);
        assertEq(boundTypeHash, VALUE_TYPE_HASH);

        runAsValueTypes(script, name);
        runAsDelegate(name);
        runWithMeta(script, name);
    }

    /// `CONFIG_REGISTRY_VALUE_TYPE` is the type the bind records, scalar or
    /// structured.
    /// @param script The script.
    /// @param name The test's base name.
    function runAsValueTypes(LocalRegisterConfig script, string memory name) internal {
        bytes memory bound = bindAs(script, string.concat(name, "-uint256"), "uint256", abi.encode(uint256(42)));
        assertEq(abi.decode(bound, (uint256)), 42);

        Pair memory pair = Pair(address(0xA), 7);
        bound = bindAs(script, string.concat(name, "-tuple"), "(address,uint256)", abi.encode(pair));
        Pair memory decodedPair = abi.decode(bound, (Pair));
        assertEq(decodedPair.account, pair.account);
        assertEq(decodedPair.amount, pair.amount);

        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = keccak256("a");
        hashes[1] = keccak256("b");
        PairWithHashes memory nested = PairWithHashes(pair, hashes);
        bound = bindAs(script, string.concat(name, "-nested"), "((address,uint256),bytes32[])", abi.encode(nested));
        PairWithHashes memory decodedNested = abi.decode(bound, (PairWithHashes));
        assertEq(decodedNested.pair.account, pair.account);
        assertEq(decodedNested.pair.amount, pair.amount);
        assertEq(decodedNested.hashes, hashes);

        Entry[] memory entries = new Entry[](2);
        entries[0].id = 1;
        entries[0].flags = new Flag[](2);
        entries[0].flags[0] = Flag(address(0xB), true);
        entries[0].flags[1] = Flag(address(0xC), false);
        entries[1].id = 2;
        entries[1].flags = new Flag[](1);
        entries[1].flags[0] = Flag(address(0xD), true);
        bound = bindAs(script, string.concat(name, "-entries"), "(uint256,(address,bool)[])[]", abi.encode(entries));
        Entry[] memory decodedEntries = abi.decode(bound, (Entry[]));
        assertEq(decodedEntries.length, entries.length);
        for (uint256 i = 0; i < entries.length; i++) {
            assertEq(decodedEntries[i].id, entries[i].id);
            assertEq(decodedEntries[i].flags.length, entries[i].flags.length);
            for (uint256 j = 0; j < entries[i].flags.length; j++) {
                assertEq(decodedEntries[i].flags[j].account, entries[i].flags[j].account);
                assertEq(decodedEntries[i].flags[j].on, entries[i].flags[j].on);
            }
        }

        vm.setEnv("CONFIG_REGISTRY_VALUE_TYPE", VALUE_TYPE);
    }

    /// Runs the script binding `name` to `value` as `valueType` and checks the
    /// type hash and the `Register` type string.
    /// @return The bound value.
    function bindAs(LocalRegisterConfig script, string memory name, string memory valueType, bytes memory value)
        internal
        returns (bytes memory)
    {
        address registry = LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS;
        vm.setEnv("CONFIG_REGISTRY_VALUE_TYPE", valueType);
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(value));
        vm.recordLogs();
        script.runAsItself();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 registerTopic = keccak256("Register(address,address,bytes32,string,bytes)");
        uint256 registers = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == registry && entries[i].topics[0] == registerTopic) {
                registers++;
                assertEq(
                    entries[i].data,
                    abi.encode(address(script), address(script), keccak256(bytes(name)), valueType, value)
                );
            }
        }
        assertEq(registers, 1);
        (bytes memory bound,, bytes32 boundTypeHash) =
            IConfigRegistryV5(registry).getV5(address(script), keccak256(bytes(name)));
        assertEq(boundTypeHash, keccak256(bytes(valueType)));
        assertEq(bound, value);
        return bound;
    }

    /// `CONFIG_REGISTRY_META` is sent with the bind: unset, none is emitted;
    /// set, it is emitted as `MetaV1_2` about the root authority's name.
    /// @param script The script.
    /// @param name The test's base name.
    function runWithMeta(LocalRegisterConfig script, string memory name) internal {
        address registry = LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS;
        bytes32 metaTopic = keccak256("MetaV1_2(address,bytes32,bytes)");
        string memory plainName = string.concat(name, "-plain");
        vm.setEnv("CONFIG_REGISTRY_NAME", plainName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(abi.encode(address(7))));
        vm.recordLogs();
        script.runAsItself();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 registers = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].emitter != registry || entries[i].topics[0] != metaTopic);
            if (entries[i].emitter == registry) registers++;
        }
        assertEq(registers, 1);

        string memory metaName = string.concat(name, "-meta");
        bytes memory meta = hex"ff0a89c674ee7874";
        vm.setEnv("CONFIG_REGISTRY_NAME", metaName);
        vm.setEnv("CONFIG_REGISTRY_META", vm.toString(meta));
        vm.recordLogs();
        script.runAsItself();
        entries = vm.getRecordedLogs();
        uint256 metas = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == registry && entries[i].topics[0] == metaTopic) {
                metas++;
                assertEq(
                    entries[i].data,
                    abi.encode(
                        address(script), keccak256(abi.encode(address(script), keccak256(bytes(metaName)))), meta
                    )
                );
            }
        }
        assertEq(metas, 1);
    }

    /// Runs as a delegate: refused until the root authority approves the
    /// script for the name, then it binds under the root authority and not
    /// under itself, and the confirmed check passes.
    /// @param name The test's base name.
    function runAsDelegate(string memory name) internal {
        LocalRegisterConfig delegate = new LocalRegisterConfig();
        address authority = LibRegistryAuthority.ROOT_AUTHORITY;
        IConfigRegistryV5 registry = IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        string memory delegatedName = string.concat(name, "-delegated");
        bytes32 hashed = keccak256(bytes(delegatedName));
        bytes memory delegatedValue = abi.encode(address(6));
        vm.setEnv("CONFIG_REGISTRY_NAME", delegatedName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(delegatedValue));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.SenderNotApproved.selector,
                LibRainDeploy.supportedNetworks()[0],
                address(delegate),
                authority,
                hashed
            )
        );
        delegate.runAsItself();
        vm.prank(authority);
        registry.approveV5(hashed, address(delegate));
        delegate.runAsItself();
        assertEq(LibConfigRegistryRead.getValue(registry, authority, hashed), delegatedValue);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.NameNotRegistered.selector, address(delegate), hashed));
        registry.getV5(address(delegate), hashed);
        delegate.verify();
    }

    /// Deploys the registry, then runs as the authority with networks unset,
    /// which forks every supported network in declaration order: the first
    /// binds and the rest, the same local EVM, skip. The confirmed check then
    /// passes on every one.
    /// @param script The script.
    /// @param name The test's base name.
    function runAsAuthorityOnEveryNetwork(LocalRegisterConfig script, string memory name) internal {
        LibConfigRegistryFork.ensureDeployed(vm);
        address authority = address(script);
        bytes32 allName = keccak256(bytes(string.concat(name, "-all")));
        bytes memory allValue = abi.encode(address(5));
        vm.setEnv("CONFIG_REGISTRY_NAME", string.concat(name, "-all"));
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(allValue));

        string[] memory supported = LibRainDeploy.supportedNetworks();
        uint256[] memory forkIds = script.runAsItself();
        assertEq(forkIds.length, supported.length);
        Vm forkVm = Vm(address(script.iLocalForkVm()));
        for (uint256 i = 0; i < forkIds.length; i++) {
            assertEq(forkIds[i], LibRainDeploy.declaredNetworkConfigs(supported)[i].chainId);
            forkVm.selectFork(forkIds[i]);
            assertEq(vm.getChainId(), forkIds[i]);
            assertEq(
                LibConfigRegistryRead.getValue(
                    IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS), authority, allName
                ),
                allValue
            );
        }
        script.verify();
    }

    /// Runs again as the authority with `name` bound to `value` already, which
    /// skips it: no `Register`, and the binding and its moment are unchanged.
    /// @param script The script.
    /// @param authority The authority it is bound under.
    /// @param name The bound name, hashed.
    /// @param value The value it is bound to.
    /// @param registeredAt The moment it was bound at.
    function assertRunSkips(
        LocalRegisterConfig script,
        address authority,
        bytes32 name,
        bytes memory value,
        uint256 registeredAt
    ) internal {
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.recordLogs();
        uint256[] memory forkIds = script.runAsItself();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].emitter != LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        }
        assertEq(forkIds.length, 1);
        IConfigRegistryV5 registry = IConfigRegistryV5(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(LibConfigRegistryRead.getValue(registry, authority, name), value);
        assertEq(LibConfigRegistryRead.getMoment(registry, authority, name), registeredAt);
    }
}
