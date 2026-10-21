// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {IMigrationRegistryV3} from "../../../src/interface/IMigrationRegistryV3.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryApprove} from "../../../src/lib/LibMigrationRegistryApprove.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRegistryDelegatesApprove, RegistryDelegation} from "../../../src/lib/LibRegistryDelegatesApprove.sol";

/// @title LibMigrationRegistryApproveTest
/// The migration registry's delegation surface: what it names, signs, reads
/// and writes, and the registry whose code hash it checks.
contract LibMigrationRegistryApproveTest is Test {
    /// External, so a revert inside it can be expected.
    function checkCodeHash() external view {
        LibMigrationRegistryApprove.delegation().checkCodeHash();
    }

    /// External, so the approval is made with this contract as the caller.
    /// @param namespace The hashed namespace.
    /// @param delegate The delegate.
    /// @param approve True to approve, false to revoke.
    function setApproval(bytes32 namespace, address delegate, bool approve) external {
        LibMigrationRegistryApprove.delegation().setApproval(namespace, delegate, approve);
    }

    /// The inputs record names a namespace and the migration registry.
    function testDescribeInputsNamesTheNamespace() external pure {
        address writer = address(0x0b30);
        address delegate = address(0x5AFE);
        bytes32 hashed = keccak256("st0x.deploy");
        assertEq(
            LibRegistryDelegatesApprove.describeInputs(
                LibMigrationRegistryApprove.delegation(), vm, "st0x.deploy", writer, delegate, true
            ),
            string.concat(
                "Namespace: st0x.deploy\nNamespace hash (keccak256 of the namespace): ",
                vm.toString(hashed),
                "\nAuthority (signer): ",
                vm.toString(writer),
                "\nDelegate: ",
                vm.toString(delegate),
                "\nTarget: approved\nRegistry: ",
                vm.toString(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS),
                "\nCalldata: ",
                vm.toString(abi.encodeCall(IMigrationRegistryV3.approveV3, (hashed, delegate)))
            )
        );
    }

    /// The signed calldata is `approveV3` to approve and `revokeV3` to revoke.
    function testApproveCalldataSelectsApproveOrRevoke(bytes32 namespace, address delegate) external pure {
        assertEq(
            LibMigrationRegistryApprove.approveCalldata(namespace, delegate, true),
            abi.encodeCall(IMigrationRegistryV3.approveV3, (namespace, delegate))
        );
        assertEq(
            LibMigrationRegistryApprove.approveCalldata(namespace, delegate, false),
            abi.encodeCall(IMigrationRegistryV3.revokeV3, (namespace, delegate))
        );
    }

    /// The code hash checked is the migration registry's: refused while the
    /// pinned address is empty, accepted once the registry is deployed there.
    function testCheckCodeHashIsTheMigrationRegistrys() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.checkCodeHash();
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        this.checkCodeHash();
    }

    /// The write approves and revokes under the caller, and the read answers
    /// for the writer, namespace and delegate it is asked about.
    function testSetApprovalAndApprovedRoundTrip(bytes32 namespace, address delegate) external {
        vm.assume(namespace != bytes32(0));
        vm.assume(delegate != address(0));
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        RegistryDelegation memory r = LibMigrationRegistryApprove.delegation();
        assertFalse(r.approved(address(this), namespace, delegate));
        this.setApproval(namespace, delegate, true);
        assertTrue(r.approved(address(this), namespace, delegate));
        assertFalse(r.approved(address(0xB0B), namespace, delegate));
        this.setApproval(namespace, delegate, false);
        assertFalse(r.approved(address(this), namespace, delegate));
    }
}
