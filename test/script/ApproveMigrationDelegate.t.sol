// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IMigrationRegistryV3} from "../../src/interface/IMigrationRegistryV3.sol";
import {IRegistryDelegatesV1} from "../../src/interface/IRegistryDelegatesV1.sol";
import {MigrationRegistry} from "../../src/concrete/MigrationRegistry.sol";
import {LibMigrationRegistry} from "../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryApprove} from "../../src/lib/LibMigrationRegistryApprove.sol";
import {LibRegistryDelegatesApprove} from "../../src/lib/LibRegistryDelegatesApprove.sol";
import {LibMigrationRegistryDeploy} from "../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibConfigRegistryRegister} from "../../src/lib/LibConfigRegistryRegister.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LocalApproveMigrationDelegate} from "../concrete/LocalApproveMigrationDelegate.sol";

/// @title ApproveMigrationDelegateTest
/// The script's wiring: which variables it reads, that the signer is the
/// script's `msg.sender`, that both entries default to every supported network
/// and to approving, and that it forks with the cheatcodes. Every network forks
/// as the local EVM.
///
/// ONE test function, because it writes process-wide environment variables and
/// forge runs test functions concurrently. Nothing else in the suite reads or
/// writes these names, and the unset cases run before each variable is first
/// set, since a set variable cannot be unset.
contract ApproveMigrationDelegateTest is Test {
    function testWiring() external {
        LocalApproveMigrationDelegate script = new LocalApproveMigrationDelegate();
        assertEq(address(script.baseForkVm()), address(vm));
        // The no-op broadcast leaves the script signing, so the script is the
        // writer.
        address authority = address(script);
        address delegate = address(0x5AFE);
        string memory name = string.concat("rain.deploy.migration-approve-test.", vm.toString(vm.randomUint()));
        bytes32 hashed = keccak256(bytes(name));
        IMigrationRegistryV3 registry =
            IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);

        vm.setEnv("MIGRATION_DELEGATE_AUTHORITY", "not-an-address");
        vm.setEnv("MIGRATION_DELEGATE_SCOPE", name);
        vm.setEnv("MIGRATION_DELEGATE_ADDRESS", vm.toString(delegate));
        assertEnvAddressRefused(script, "MIGRATION_DELEGATE_AUTHORITY");
        vm.setEnv("MIGRATION_DELEGATE_AUTHORITY", vm.toString(authority));

        vm.setEnv("MIGRATION_DELEGATE_ADDRESS", "not-an-address");
        assertEnvAddressRefused(script, "MIGRATION_DELEGATE_ADDRESS");
        vm.setEnv("MIGRATION_DELEGATE_ADDRESS", vm.toString(address(0)));
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.ZeroDelegate.selector));
        script.runAsItself();
        vm.setEnv("MIGRATION_DELEGATE_ADDRESS", vm.toString(delegate));

        vm.setEnv("MIGRATION_DELEGATE_SCOPE", "Not.Canonical");
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.runAsItself();
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.verify();
        vm.setEnv("MIGRATION_DELEGATE_SCOPE", name);

        // The signer is the script's `msg.sender`: this test contract is not
        // the authority.
        vm.expectRevert(
            abi.encodeWithSelector(LibRegistryDelegatesApprove.SenderNotAuthority.selector, address(this), authority)
        );
        script.run();

        // Networks unset: every declared network, and the first has no
        // registry yet.
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRegistryDelegatesApprove.UnexpectedRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        script.runAsItself();
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);

        // Approved unset: the default approves, on every declared network:
        // the first sends and the rest, the same local EVM, skip.
        string[] memory supported = LibRainDeploy.supportedNetworks();
        uint256[] memory forkIds = script.runAsItself();
        assertEq(forkIds.length, supported.length);
        for (uint256 i = 0; i < forkIds.length; i++) {
            assertEq(forkIds[i], LibRainDeploy.declaredNetworkConfigs(supported)[i].chainId);
        }
        assertTrue(registry.approvedV3(authority, hashed, delegate));
        script.verify();

        // A run already in the target state sends nothing.
        vm.recordLogs();
        script.runAsItself();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].emitter != address(registry));
        }

        // The approval is under the authority the variable names.
        string memory network = supported[0];
        vm.setEnv("MIGRATION_DELEGATE_NETWORKS", string.concat(network, ",nowhere"));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        script.runAsItself();
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        script.verify();
        vm.setEnv("MIGRATION_DELEGATE_NETWORKS", network);
        address otherAuthority = address(0xB0B);
        vm.setEnv("MIGRATION_DELEGATE_AUTHORITY", vm.toString(otherAuthority));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRegistryDelegatesApprove.UnexpectedApproval.selector, network, otherAuthority, hashed, delegate, true
            )
        );
        script.verify();
        vm.setEnv("MIGRATION_DELEGATE_AUTHORITY", vm.toString(authority));

        // `false` revokes, on exactly the selected network.
        vm.setEnv("MIGRATION_DELEGATE_APPROVED", "false");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRegistryDelegatesApprove.UnexpectedApproval.selector, network, authority, hashed, delegate, false
            )
        );
        script.verify();
        forkIds = script.runAsItself();
        assertEq(forkIds.length, 1);
        assertEq(forkIds[0], LibRainDeploy.declaredNetworkConfigs(supported)[0].chainId);
        assertFalse(registry.approvedV3(authority, hashed, delegate));
        script.verify();

        // `true` approves again.
        vm.setEnv("MIGRATION_DELEGATE_APPROVED", "true");
        script.runAsItself();
        assertTrue(registry.approvedV3(authority, hashed, delegate));
        script.verify();
    }

    /// `run()` stops on forge's own refusal to parse `variable` as an address.
    /// Forge raises it as `CheatcodeError(string)`, and only the prefix naming
    /// the variable is pinned.
    /// @param script The script.
    /// @param variable The variable that does not parse.
    function assertEnvAddressRefused(LocalApproveMigrationDelegate script, string memory variable) internal {
        try script.runAsItself() {
            revert("run() did not revert");
        } catch (bytes memory reason) {
            bytes memory expectedSelector = abi.encodeWithSignature("CheatcodeError(string)");
            assertGe(reason.length, expectedSelector.length);
            for (uint256 i = 0; i < expectedSelector.length; i++) {
                assertEq(reason[i], expectedSelector[i]);
            }
            bytes memory payload = new bytes(reason.length - 4);
            for (uint256 i = 0; i < payload.length; i++) {
                payload[i] = reason[i + 4];
            }
            bytes memory message = bytes(abi.decode(payload, (string)));
            bytes memory prefix = bytes(string.concat("vm.envAddress: failed parsing $", variable));
            assertGe(message.length, prefix.length);
            for (uint256 i = 0; i < prefix.length; i++) {
                assertEq(message[i], prefix[i]);
            }
        }
    }
}
