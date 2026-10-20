// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV1} from "../../src/interface/IConfigRegistryV1.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibConfigRegistryDeploy} from "../../src/lib/LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister} from "../../src/lib/LibConfigRegistryRegister.sol";
import {RegisterConfig} from "../../script/RegisterConfig.sol";
import {LibConfigRegistryFork} from "../lib/LibConfigRegistryFork.sol";
import {LibConfigRegistryRead} from "../lib/LibConfigRegistryRead.sol";
import {RegisterConfigRunCaller} from "../concrete/RegisterConfigRunCaller.sol";

/// @title RegisterConfigTest
/// The script's wiring: which variables it reads, that the signer is the
/// script's `msg.sender`, and that both entries default to every supported
/// network. `LibConfigRegistryRegister`'s own tests cover what it does with
/// them.
///
/// ONE test function, because it writes process-wide environment variables and
/// forge runs test functions concurrently. Nothing else in the suite reads or
/// writes these names, and the unset-networks cases run before the variable is
/// first set, since a set variable cannot be unset.
contract RegisterConfigTest is Test {
    /// The authority `CONFIG_REGISTRY_AUTHORITY` names. Any account is one.
    address internal constant AUTHORITY = address(0xA11CE);

    function testWiring() external {
        RegisterConfig script = new RegisterConfig();
        string memory name = string.concat("rain.deploy.register-test.", vm.toString(vm.randomUint()));

        // Authority not an address, set here so an exported one cannot leak
        // in: every other input is valid, so the run stops on reading it.
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", "not-an-address");
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));
        assertEnvAddressRefused(script);
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", vm.toString(AUTHORITY));

        vm.setEnv("CONFIG_REGISTRY_NAME", "Not.Canonical");
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.run();

        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        vm.setEnv("CONFIG_REGISTRY_VALUE", "0x");
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV1.EmptyValue.selector, keccak256(bytes(name))));
        script.run();

        // Networks unset: the default is every declared network, which is a
        // valid selection, so the refusal reached is the sender — this test
        // contract, as the script's `msg.sender`.
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));
        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistryRegister.SenderNotAuthority.selector, address(this), AUTHORITY)
        );
        script.run();

        // The confirmed check forks every declared network fresh, where the
        // fresh name is bound nowhere. The first network fails first, so its
        // fork says which refusal that is.
        vm.makePersistent(address(script));
        vm.createSelectFork(LibRainDeploy.supportedNetworks()[0]);
        vm.expectRevert(LibConfigRegistryFork.unboundResolveRevert(AUTHORITY, keccak256(bytes(name))));
        script.verify();

        runAsAuthorityOnEveryNetwork(script, name);
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));

        vm.setEnv("CONFIG_REGISTRY_NETWORKS", "base,nowhere");
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        script.run();
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        script.verify();

        vm.setEnv("CONFIG_REGISTRY_NAME", "Not.Canonical");
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.verify();

        // With the name bound, the confirmed check passes on exactly the value
        // given and refuses any other. The registry is persistent so the fresh
        // fork `verify` creates carries the binding made here.
        string memory network = LibRainDeploy.supportedNetworks()[0];
        bytes memory value = abi.encode(address(1));
        LibConfigRegistryFork.ensureDeployed(vm);
        vm.prank(AUTHORITY);
        IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV1(keccak256(bytes(name)), value);
        vm.makePersistent(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        vm.setEnv("CONFIG_REGISTRY_NETWORKS", network);
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        script.verify();

        // The binding is under the authority the variable names; under any
        // other the name is unbound.
        address otherAuthority = address(0xB0B);
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", vm.toString(otherAuthority));
        vm.expectRevert(LibConfigRegistryFork.unboundResolveRevert(otherAuthority, keccak256(bytes(name))));
        script.verify();
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", vm.toString(AUTHORITY));

        bytes memory other = abi.encode(address(2));
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(other));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.UnexpectedBinding.selector,
                network,
                AUTHORITY,
                keccak256(bytes(name)),
                other,
                value
            )
        );
        script.verify();

        // Run as the authority on a fresh name binds it on exactly the selected network.
        string memory freshName = string.concat(name, "-run");
        bytes memory freshValue = abi.encode(address(3));
        vm.setEnv("CONFIG_REGISTRY_NAME", freshName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(freshValue));
        uint256[] memory forkIds = RegisterConfigRunCaller(AUTHORITY).callRun(script);
        assertEq(forkIds.length, 1);
        vm.selectFork(forkIds[0]);
        assertEq(block.chainid, LibRainDeploy.declaredNetworkConfigs(LibRainDeploy.supportedNetworks())[0].chainId);
        (bytes memory bound, uint256 registeredAt) = IConfigRegistryV1(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
            ).getV1(AUTHORITY, keccak256(bytes(freshName)));
        assertEq(bound, freshValue);
        assertEq(registeredAt, vm.getBlockTimestamp());

        assertRunSkips(script, keccak256(bytes(freshName)), freshValue, registeredAt);

        // Run as the authority on a name already bound to another value rebinds it.
        string memory rotateName = string.concat(name, "-rotate");
        bytes memory rotateValue = abi.encode(address(4));
        vm.warp(vm.getBlockTimestamp() - 1);
        vm.prank(AUTHORITY);
        IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV1(keccak256(bytes(rotateName)), freshValue);
        vm.setEnv("CONFIG_REGISTRY_NAME", rotateName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(rotateValue));
        forkIds = RegisterConfigRunCaller(AUTHORITY).callRun(script);
        assertEq(forkIds.length, 1);
        vm.selectFork(forkIds[0]);
        (bound, registeredAt) = IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .getV1(AUTHORITY, keccak256(bytes(rotateName)));
        assertEq(bound, rotateValue);
        assertEq(registeredAt, block.timestamp);

        assertSimulatesContractAuthority(script, string.concat(name, "-safe"));
    }

    /// `simulateContractAuthority()`, called by this test rather than the
    /// authority, binds under the authority on exactly the selected network
    /// and returns the inputs record, whose `Calldata:` line is exactly the
    /// bind's calldata; it refuses a non-canonical name and a bare 20-byte
    /// value as `run()` does.
    /// @param script The script.
    /// @param name A name bound nowhere.
    function assertSimulatesContractAuthority(RegisterConfig script, string memory name) internal {
        bytes memory value = abi.encode(address(6));
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(value));
        (uint256[] memory forkIds, string memory record) = script.simulateContractAuthority();
        assertEq(forkIds.length, 1);
        assertEq(record, LibConfigRegistryRegister.describeInputs(vm, name, value, AUTHORITY));
        assertTrue(
            vm.contains(
                record,
                string.concat(
                    "\nCalldata: ",
                    vm.toString(
                        LibConfigRegistryRegister.registerCalldata(LibConfigRegistryRegister.nameHash(name), value)
                    )
                )
            )
        );
        vm.selectFork(forkIds[0]);
        assertEq(block.chainid, LibRainDeploy.declaredNetworkConfigs(LibRainDeploy.supportedNetworks())[0].chainId);
        assertEq(
            LibConfigRegistryRead.getValue(
                IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS),
                AUTHORITY,
                keccak256(bytes(name))
            ),
            value
        );

        vm.setEnv("CONFIG_REGISTRY_NAME", "Not.Canonical");
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.simulateContractAuthority();

        bytes memory bare = abi.encodePacked(address(6));
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(bare));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalValue.selector, bare));
        script.simulateContractAuthority();
    }

    /// Runs as the authority with networks unset, which forks every supported network in
    /// declaration order; the persistent registry carries the first fork's bind
    /// to the rest, which skip. A prank cannot reach `run()`, since a
    /// prank and a broadcast cannot both be active, so the authority calls it through
    /// code etched there.
    /// @param script The script.
    /// @param name The test's base name.
    function runAsAuthorityOnEveryNetwork(RegisterConfig script, string memory name) internal {
        LibConfigRegistryFork.ensureDeployed(vm);
        vm.makePersistent(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        vm.etch(AUTHORITY, address(new RegisterConfigRunCaller()).code);
        vm.makePersistent(AUTHORITY);
        bytes32 allName = keccak256(bytes(string.concat(name, "-all")));
        bytes memory allValue = abi.encode(address(5));
        vm.setEnv("CONFIG_REGISTRY_NAME", string.concat(name, "-all"));
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(allValue));

        string[] memory supported = LibRainDeploy.supportedNetworks();
        uint256[] memory forkIds = RegisterConfigRunCaller(AUTHORITY).callRun(script);
        assertEq(forkIds.length, supported.length);
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertEq(vm.getChainId(), LibRainDeploy.declaredNetworkConfigs(supported)[i].chainId);
            assertEq(
                LibConfigRegistryRead.getValue(
                    IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS), AUTHORITY, allName
                ),
                allValue
            );
        }
    }

    /// `run()` stops on forge's own refusal to parse `CONFIG_REGISTRY_AUTHORITY`.
    /// Forge raises it as `CheatcodeError(string)`, and only the prefix naming
    /// the variable is pinned; the parser's wording
    /// after it is forge's.
    /// @param script The script.
    function assertEnvAddressRefused(RegisterConfig script) internal {
        try script.run() {
            revert("run() did not revert");
        } catch (bytes memory reason) {
            bytes memory expectedSelector = abi.encodeWithSignature("CheatcodeError(string)");
            assertGe(reason.length, expectedSelector.length);
            bytes memory selector = new bytes(expectedSelector.length);
            for (uint256 i = 0; i < selector.length; i++) {
                selector[i] = reason[i];
            }
            assertEq(selector, expectedSelector);
            bytes memory payload = new bytes(reason.length - 4);
            for (uint256 i = 0; i < payload.length; i++) {
                payload[i] = reason[i + 4];
            }
            bytes memory message = bytes(abi.decode(payload, (string)));
            bytes memory prefix = bytes("vm.envAddress: failed parsing $CONFIG_REGISTRY_AUTHORITY");
            assertGe(message.length, prefix.length);
            bytes memory head = new bytes(prefix.length);
            for (uint256 i = 0; i < head.length; i++) {
                head[i] = message[i];
            }
            assertEq(string(head), string(prefix));
        }
    }

    /// Runs again as the authority with `name` bound to `value` already, which skips it:
    /// no `Register`, and the binding and its moment are unchanged.
    /// @param script The script.
    /// @param name The bound name, hashed.
    /// @param value The value it is bound to.
    /// @param registeredAt The moment it was bound at.
    function assertRunSkips(RegisterConfig script, bytes32 name, bytes memory value, uint256 registeredAt) internal {
        vm.recordLogs();
        uint256[] memory forkIds = RegisterConfigRunCaller(AUTHORITY).callRun(script);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].emitter != LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        }
        assertEq(forkIds.length, 1);
        vm.selectFork(forkIds[0]);
        IConfigRegistryV1 registry = IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(LibConfigRegistryRead.getValue(registry, AUTHORITY, name), value);
        assertEq(LibConfigRegistryRead.getMoment(registry, AUTHORITY, name), registeredAt);
    }
}
