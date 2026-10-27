// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV4} from "../../src/interface/IConfigRegistryV4.sol";
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
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.EmptyValue.selector, keccak256(bytes(name))));
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
        IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV4(authority, keccak256(bytes(name)), VALUE_TYPE, value, "");
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
        (bytes memory bound, uint256 registeredAt, bytes32 boundTypeHash) = IConfigRegistryV4(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
            ).getV4(authority, keccak256(bytes(freshName)));
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
        IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV4(authority, keccak256(bytes(rotateName)), VALUE_TYPE, freshValue, "");
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.setEnv("CONFIG_REGISTRY_NAME", rotateName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(rotateValue));
        forkIds = script.runAsItself();
        assertEq(forkIds.length, 1);
        (bound, registeredAt, boundTypeHash) = IConfigRegistryV4(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
            ).getV4(authority, keccak256(bytes(rotateName)));
        assertEq(bound, rotateValue);
        assertEq(registeredAt, block.timestamp);
        assertEq(boundTypeHash, VALUE_TYPE_HASH);

        runAsDelegate(name);
    }

    /// Runs as a delegate: refused until the root authority approves the
    /// script for the name, then it binds under the root authority and not
    /// under itself, and the confirmed check passes.
    /// @param name The test's base name.
    function runAsDelegate(string memory name) internal {
        LocalRegisterConfig delegate = new LocalRegisterConfig();
        address authority = LibRegistryAuthority.ROOT_AUTHORITY;
        IConfigRegistryV4 registry = IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
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
        registry.approveV4(hashed, address(delegate));
        delegate.runAsItself();
        assertEq(LibConfigRegistryRead.getValue(registry, authority, hashed), delegatedValue);
        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV4.NameNotRegistered.selector, address(delegate), hashed));
        registry.getV4(address(delegate), hashed);
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
                    IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS), authority, allName
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
        IConfigRegistryV4 registry = IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(LibConfigRegistryRead.getValue(registry, authority, name), value);
        assertEq(LibConfigRegistryRead.getMoment(registry, authority, name), registeredAt);
    }
}
