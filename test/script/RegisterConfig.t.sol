// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {CONFIG_REGISTRY_ROOT} from "../../src/concrete/ConfigRegistry.sol";
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
    function testWiring() external {
        RegisterConfig script = new RegisterConfig();
        string memory name = string.concat("rain.deploy.register-test.", vm.toString(vm.randomUint()));

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
            abi.encodeWithSelector(
                LibConfigRegistryRegister.SenderNotRoot.selector, address(this), CONFIG_REGISTRY_ROOT
            )
        );
        script.run();

        // The confirmed check forks every declared network fresh, where the
        // fresh name is bound nowhere. The first network fails first, so its
        // fork says which refusal that is.
        vm.makePersistent(address(script));
        vm.createSelectFork(LibRainDeploy.supportedNetworks()[0]);
        vm.expectRevert(LibConfigRegistryFork.unboundResolveRevert(keccak256(bytes(name))));
        script.verify();

        runAsRootOnEveryNetwork(script, name);
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
        vm.prank(CONFIG_REGISTRY_ROOT);
        IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV1(keccak256(bytes(name)), value);
        vm.makePersistent(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        vm.setEnv("CONFIG_REGISTRY_NETWORKS", network);
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        script.verify();

        bytes memory other = abi.encode(address(2));
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(other));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.UnexpectedBinding.selector, network, keccak256(bytes(name)), other, value
            )
        );
        script.verify();

        // Run as root on a fresh name binds it on exactly the selected network.
        string memory freshName = string.concat(name, "-run");
        bytes memory freshValue = abi.encode(address(3));
        vm.setEnv("CONFIG_REGISTRY_NAME", freshName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(freshValue));
        uint256[] memory forkIds = RegisterConfigRunCaller(CONFIG_REGISTRY_ROOT).callRun(script);
        assertEq(forkIds.length, 1);
        vm.selectFork(forkIds[0]);
        assertEq(block.chainid, LibRainDeploy.declaredNetworkConfigs(LibRainDeploy.supportedNetworks())[0].chainId);
        (bytes memory bound, uint256 registeredAt) = IConfigRegistryV1(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
            ).getV1(keccak256(bytes(freshName)));
        assertEq(bound, freshValue);
        assertEq(registeredAt, block.timestamp);

        assertRunSkips(script, keccak256(bytes(freshName)), freshValue, registeredAt);

        // Run as root on a name already bound to another value rebinds it.
        string memory rotateName = string.concat(name, "-rotate");
        bytes memory rotateValue = abi.encode(address(4));
        vm.warp(block.timestamp - 1);
        vm.prank(CONFIG_REGISTRY_ROOT);
        IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV1(keccak256(bytes(rotateName)), freshValue);
        vm.setEnv("CONFIG_REGISTRY_NAME", rotateName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(rotateValue));
        forkIds = RegisterConfigRunCaller(CONFIG_REGISTRY_ROOT).callRun(script);
        assertEq(forkIds.length, 1);
        vm.selectFork(forkIds[0]);
        (bound, registeredAt) = IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .getV1(keccak256(bytes(rotateName)));
        assertEq(bound, rotateValue);
        assertEq(registeredAt, block.timestamp);
    }

    /// Runs as root with networks unset, which forks every supported network in
    /// declaration order; the persistent registry carries the first fork's bind
    /// to the rest, which skip. A prank cannot reach `run()`, since a
    /// prank and a broadcast cannot both be active, so root calls it through
    /// code etched there.
    /// @param script The script.
    /// @param name The test's base name.
    function runAsRootOnEveryNetwork(RegisterConfig script, string memory name) internal {
        LibConfigRegistryFork.ensureDeployed(vm);
        vm.makePersistent(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        vm.etch(CONFIG_REGISTRY_ROOT, address(new RegisterConfigRunCaller()).code);
        vm.makePersistent(CONFIG_REGISTRY_ROOT);
        bytes32 allName = keccak256(bytes(string.concat(name, "-all")));
        bytes memory allValue = abi.encode(address(5));
        vm.setEnv("CONFIG_REGISTRY_NAME", string.concat(name, "-all"));
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(allValue));

        string[] memory supported = LibRainDeploy.supportedNetworks();
        uint256[] memory forkIds = RegisterConfigRunCaller(CONFIG_REGISTRY_ROOT).callRun(script);
        assertEq(forkIds.length, supported.length);
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertEq(block.chainid, LibRainDeploy.declaredNetworkConfigs(supported)[i].chainId);
            assertEq(
                LibConfigRegistryRead.getValue(
                    IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS), allName
                ),
                allValue
            );
        }
    }

    /// Runs again as root with `name` bound to `value` already, which skips it:
    /// no `Register`, and the binding and its moment are unchanged.
    /// @param script The script.
    /// @param name The bound name, hashed.
    /// @param value The value it is bound to.
    /// @param registeredAt The moment it was bound at.
    function assertRunSkips(RegisterConfig script, bytes32 name, bytes memory value, uint256 registeredAt) internal {
        vm.recordLogs();
        uint256[] memory forkIds = RegisterConfigRunCaller(CONFIG_REGISTRY_ROOT).callRun(script);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].emitter != LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        }
        assertEq(forkIds.length, 1);
        vm.selectFork(forkIds[0]);
        IConfigRegistryV1 registry = IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(LibConfigRegistryRead.getValue(registry, name), value);
        assertEq(LibConfigRegistryRead.getMoment(registry, name), registeredAt);
    }
}
