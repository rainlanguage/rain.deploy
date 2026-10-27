// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV4} from "../../src/interface/IConfigRegistryV4.sol";
import {LibConfigRegistry} from "../../src/lib/LibConfigRegistry.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibConfigRegistryDeploy} from "../../src/lib/LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister} from "../../src/lib/LibConfigRegistryRegister.sol";
import {LibConfigRegistryFork} from "../lib/LibConfigRegistryFork.sol";
import {LibConfigRegistryRead} from "../lib/LibConfigRegistryRead.sol";
import {LocalRegisterConfig} from "../concrete/LocalRegisterConfig.sol";

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
        LocalRegisterConfig script = new LocalRegisterConfig();
        assertEq(address(script.baseForkVm()), address(vm));
        // The no-op broadcast leaves the script signing, so the script is the
        // authority a bind lands under.
        address authority = address(script);
        string memory name = string.concat("rain.deploy.register-test.", vm.toString(vm.randomUint()));

        // Authority not an address, set here so an exported one cannot leak
        // in: every other input is valid, so the run stops on reading it.
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", "not-an-address");
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        vm.setEnv("CONFIG_REGISTRY_VALUE_TYPE", "address");
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));
        assertEnvAddressRefused(script);
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", vm.toString(authority));

        vm.setEnv("CONFIG_REGISTRY_NAME", "Not.Canonical");
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.run();

        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        vm.setEnv("CONFIG_REGISTRY_VALUE_TYPE", "Address");
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalValueType.selector, "Address"));
        script.run();
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalValueType.selector, "Address"));
        script.verify();
        vm.setEnv("CONFIG_REGISTRY_VALUE_TYPE", "address");

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
            .registerV4(authority, name, "address", value);
        vm.setEnv("CONFIG_REGISTRY_NETWORKS", network);
        vm.setEnv("CONFIG_REGISTRY_NAME", name);
        script.verify();

        // The binding is under the authority the variable names; under any
        // other the name is unbound.
        address otherAuthority = address(0xB0B);
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", vm.toString(otherAuthority));
        vm.expectRevert(LibConfigRegistryFork.unboundResolveRevert(otherAuthority, keccak256(bytes(name))));
        script.verify();
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", vm.toString(authority));

        // Bound as `address`, the name is refused as any other type.
        vm.setEnv("CONFIG_REGISTRY_VALUE_TYPE", "uint256");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedValueType.selector,
                authority,
                keccak256(bytes(name)),
                keccak256("uint256"),
                keccak256("address")
            )
        );
        script.verify();
        vm.setEnv("CONFIG_REGISTRY_VALUE_TYPE", "address");

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
        (bytes memory bound, uint256 registeredAt,) = IConfigRegistryV4(
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS
            ).getV4(authority, keccak256(bytes(freshName)));
        assertEq(bound, freshValue);
        assertEq(registeredAt, vm.getBlockTimestamp());

        assertRunSkips(script, authority, keccak256(bytes(freshName)), freshValue, registeredAt);

        // Run as the authority on a name already bound to another value
        // rebinds it.
        string memory rotateName = string.concat(name, "-rotate");
        bytes memory rotateValue = abi.encode(address(4));
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(authority);
        IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .registerV4(authority, rotateName, "address", freshValue);
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.setEnv("CONFIG_REGISTRY_NAME", rotateName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(rotateValue));
        forkIds = script.runAsItself();
        assertEq(forkIds.length, 1);
        (bound, registeredAt,) = IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .getV4(authority, keccak256(bytes(rotateName)));
        assertEq(bound, rotateValue);
        assertEq(registeredAt, block.timestamp);

        runAsDelegate(script, name);
    }

    /// Runs as a delegate: another authority approves the script, which then
    /// binds under that authority and not under itself, and the confirmed
    /// check under that authority passes.
    /// @param script The script.
    /// @param name The test's base name.
    function runAsDelegate(LocalRegisterConfig script, string memory name) internal {
        address delegator = address(0xD0D0);
        string memory delegatedName = string.concat(name, "-delegated");
        bytes memory delegatedValue = abi.encode(address(6));
        vm.prank(delegator);
        IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS)
            .approveV3(keccak256(bytes(delegatedName)), address(script));
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", vm.toString(delegator));
        vm.setEnv("CONFIG_REGISTRY_NAME", delegatedName);
        vm.setEnv("CONFIG_REGISTRY_VALUE", vm.toString(delegatedValue));
        script.runAsItself();
        assertEq(
            LibConfigRegistryRead.getValue(
                IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS),
                delegator,
                keccak256(bytes(delegatedName))
            ),
            delegatedValue
        );
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", vm.toString(address(script)));
        vm.expectRevert(LibConfigRegistryFork.unboundResolveRevert(address(script), keccak256(bytes(delegatedName))));
        script.verify();
        vm.setEnv("CONFIG_REGISTRY_AUTHORITY", vm.toString(delegator));
        script.verify();
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

    /// `run()` stops on forge's own refusal to parse
    /// `CONFIG_REGISTRY_AUTHORITY`. Forge raises it as `CheatcodeError(string)`,
    /// and only the prefix naming the variable is pinned; the parser's wording
    /// after it is forge's.
    /// @param script The script.
    function assertEnvAddressRefused(LocalRegisterConfig script) internal {
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
