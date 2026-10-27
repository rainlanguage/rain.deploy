// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    IMigrationRegistryV4,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "../../../src/interface/IMigrationRegistryV4.sol";
import {IRegistryDelegatesV1} from "../../../src/interface/IRegistryDelegatesV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {MockMigrationApplier} from "../../concrete/MockMigrationApplier.sol";
import {LibAccountCode} from "../../lib/LibAccountCode.sol";

/// @title LibMigrationRegistryDelegateTest
/// @notice The delegation builders and read: each targets the pinned
/// registry, encodes exactly the call it names, lands as that call when sent,
/// and refuses a chain without the registry by its code hash.
contract LibMigrationRegistryDelegateTest is Test {
    address internal constant WRITER = address(0x1111);
    address internal constant DELEGATE = address(0x2222);
    string internal constant NAMESPACE_NAME = "namespace";
    string internal constant MIGRATION_NAME = "migration";
    string internal constant SECOND_NAME = "second";
    bytes32 internal constant NAMESPACE = keccak256(bytes(NAMESPACE_NAME));
    bytes32 internal constant MIGRATION = keccak256(bytes(MIGRATION_NAME));
    bytes32 internal constant SECOND = keccak256(bytes(SECOND_NAME));

    function deployRegistry() internal {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
    }

    function send(address sender, address to, bytes memory data) internal {
        vm.prank(sender);
        (bool success,) = to.call(data);
        assertTrue(success);
    }

    function expectCodeHash(bytes32 actualCodeHash) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                actualCodeHash
            )
        );
    }

    function expectDelegationWrappersRefuse(bytes32 actualCodeHash) internal {
        expectCodeHash(actualCodeHash);
        this.externalApproveCall();
        expectCodeHash(actualCodeHash);
        this.externalRevokeCall();
        expectCodeHash(actualCodeHash);
        this.externalApproved();
        expectCodeHash(actualCodeHash);
        this.externalAppliedBy();
    }

    function externalApproveCall() external view returns (address, bytes memory) {
        return LibMigrationRegistry.approveV3Call(NAMESPACE, DELEGATE);
    }

    function externalRevokeCall() external view returns (address, bytes memory) {
        return LibMigrationRegistry.revokeV3Call(NAMESPACE, DELEGATE);
    }

    function externalApproved() external view returns (bool) {
        return LibMigrationRegistry.approvedV3(WRITER, NAMESPACE, DELEGATE);
    }

    function externalAppliedBy() external view returns (address) {
        return LibMigrationRegistry.appliedByV4(WRITER, NAMESPACE, MIGRATION);
    }

    /// Approve then revoke, built and sent by the writer, are what `approvedV3`
    /// answers.
    function testApproveAndRevokeCallsLand() external {
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveV3Call(NAMESPACE, DELEGATE);
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(data, abi.encodeCall(IRegistryDelegatesV1.approveV3, (NAMESPACE, DELEGATE)));
        send(WRITER, to, data);
        assertTrue(LibMigrationRegistry.approvedV3(WRITER, NAMESPACE, DELEGATE));

        (to, data) = LibMigrationRegistry.revokeV3Call(NAMESPACE, DELEGATE);
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(data, abi.encodeCall(IRegistryDelegatesV1.revokeV3, (NAMESPACE, DELEGATE)));
        send(WRITER, to, data);
        assertFalse(LibMigrationRegistry.approvedV3(WRITER, NAMESPACE, DELEGATE));
    }

    /// A delegated write, built and sent by an approved delegate, lands in the
    /// writer's line.
    function testApplyMigrationCallDelegatedLands() external {
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveV3Call(NAMESPACE, DELEGATE);
        send(WRITER, to, data);
        (to, data) = LibMigrationRegistry.applyMigrationV4Call(
            WRITER, NAMESPACE_NAME, MIGRATION_NAME, LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS)
        );
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV4.applyMigrationV4,
                (
                    WRITER,
                    NAMESPACE_NAME,
                    MIGRATION_NAME,
                    LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS)
                )
            )
        );
        send(DELEGATE, to, data);
        assertEq(LibMigrationRegistry.appliedV4(WRITER, NAMESPACE, MIGRATION), block.timestamp);
    }

    /// A delegated history write carries its moment into the writer's line.
    function testApplyMigrationHistoryCallDelegatedLands(uint256 appliedAt) external {
        vm.warp(1_000_000);
        appliedAt = bound(appliedAt, 1, block.timestamp);
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveV3Call(NAMESPACE, DELEGATE);
        send(WRITER, to, data);
        (to, data) = LibMigrationRegistry.applyMigrationHistoryV4Call(
            WRITER,
            NAMESPACE_NAME,
            MIGRATION_NAME,
            appliedAt,
            LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS)
        );
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV4.applyMigrationHistoryV4,
                (
                    WRITER,
                    NAMESPACE_NAME,
                    MIGRATION_NAME,
                    appliedAt,
                    LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS)
                )
            )
        );
        send(DELEGATE, to, data);
        assertEq(LibMigrationRegistry.appliedV4(WRITER, NAMESPACE, MIGRATION), appliedAt);
    }

    /// The direct writes, made from a contract the writer approved, land in
    /// the writer's line and not the contract's.
    function testDirectWritesLandUnderTheNamedWriter() external {
        vm.warp(1_000_000);
        deployRegistry();
        vm.prank(WRITER);
        LibMigrationRegistry.approveV3(NAMESPACE, address(this));

        LibMigrationRegistry.applyMigrationV4(
            WRITER, NAMESPACE_NAME, MIGRATION_NAME, LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS)
        );
        assertEq(LibMigrationRegistry.appliedV4(WRITER, NAMESPACE, MIGRATION), block.timestamp);

        LibMigrationRegistry.applyMigrationHistoryV4(
            WRITER,
            NAMESPACE_NAME,
            SECOND_NAME,
            block.timestamp,
            LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION)
        );
        assertEq(LibMigrationRegistry.appliedV4(WRITER, NAMESPACE, SECOND), block.timestamp);
        assertEq(LibMigrationRegistry.headV4(WRITER, NAMESPACE), SECOND);
        assertEq(LibMigrationRegistry.headV4(address(this), NAMESPACE), MIGRATION_HEAD_GENESIS);
    }

    /// The approval builders and the read refuse a chain with no registry.
    function testNoRegistryIsRefused() external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);
        expectCodeHash(bytes32(0));
        this.externalApproveCall();
        expectCodeHash(bytes32(0));
        this.externalRevokeCall();
        expectCodeHash(bytes32(0));
        this.externalApproved();
    }

    /// The direct approve and revoke, made from a contract, approve and revoke
    /// for that contract's line.
    function testDirectApproveAndRevokeLand() external {
        deployRegistry();
        MockMigrationApplier applier = new MockMigrationApplier();
        applier.approveV3(NAMESPACE, DELEGATE);
        assertTrue(LibMigrationRegistry.approvedV3(address(applier), NAMESPACE, DELEGATE));
        assertFalse(LibMigrationRegistry.approvedV3(address(this), NAMESPACE, DELEGATE));
        applier.revokeV3(NAMESPACE, DELEGATE);
        assertFalse(LibMigrationRegistry.approvedV3(address(applier), NAMESPACE, DELEGATE));
    }

    /// The direct approve and revoke refuse an address with no registry.
    function testDirectApproveAndRevokeNoRegistryIsRefused() external {
        MockMigrationApplier applier = new MockMigrationApplier();
        expectCodeHash(bytes32(0));
        applier.approveV3(NAMESPACE, DELEGATE);
        expectCodeHash(bytes32(0));
        applier.revokeV3(NAMESPACE, DELEGATE);
    }

    /// The direct approve and revoke refuse other code at the registry
    /// address, naming its hash.
    function testDirectApproveAndRevokeWrongCodeIsRefused(bytes memory code) external {
        vm.assume(code.length > 0 && code[0] != 0xef);
        vm.assume(keccak256(code) != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);
        MockMigrationApplier applier = new MockMigrationApplier();
        expectCodeHash(keccak256(code));
        applier.approveV3(NAMESPACE, DELEGATE);
        expectCodeHash(keccak256(code));
        applier.revokeV3(NAMESPACE, DELEGATE);
    }

    /// `appliedByV4` reads the account that wrote the record.
    function testAppliedByReadsTheDelegate() external {
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveV3Call(NAMESPACE, DELEGATE);
        send(WRITER, to, data);
        (to, data) = LibMigrationRegistry.applyMigrationV4Call(
            WRITER, NAMESPACE_NAME, MIGRATION_NAME, LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS)
        );
        send(DELEGATE, to, data);
        assertEq(LibMigrationRegistry.appliedByV4(WRITER, NAMESPACE, MIGRATION), DELEGATE);
        assertEq(LibMigrationRegistry.appliedByV4(WRITER, NAMESPACE, SECOND), address(0));
    }

    /// `appliedByV4` refuses an address with no registry.
    function testAppliedByNoRegistryIsRefused() external {
        expectCodeHash(bytes32(0));
        this.externalAppliedBy();
    }

    /// Every delegation builder and read refuses other code at the registry
    /// address, naming its hash.
    function testDelegationWrappersWrongCodeIsRefused(bytes memory code) external {
        vm.assume(code.length > 0 && code[0] != 0xef);
        vm.assume(keccak256(code) != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);
        expectDelegationWrappersRefuse(keccak256(code));
    }

    /// Every delegation builder, read and direct approve and revoke refuses a
    /// registry address delegated to another account.
    function testDelegationWrappersDelegatedCodeIsRefused(address delegate) external {
        vm.assume(delegate != address(0));
        bytes memory designator = LibAccountCode.delegationDesignator(delegate);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);
        expectDelegationWrappersRefuse(keccak256(designator));
        MockMigrationApplier applier = new MockMigrationApplier();
        expectCodeHash(keccak256(designator));
        applier.approveV3(NAMESPACE, DELEGATE);
        expectCodeHash(keccak256(designator));
        applier.revokeV3(NAMESPACE, DELEGATE);
    }

    /// An approval is scoped to the namespace's hash: a delegate approved on
    /// `keccak256(bytes(namespace))` writes under the string `namespace`, and
    /// one approved on any other scope is refused `NotApproved` naming that
    /// hash.
    function testDelegateScopeBindsToTheNamespaceHash(string memory namespace, bytes32 otherScope) external {
        vm.assume(bytes(namespace).length != 0);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        vm.assume(otherScope != namespaceHash);
        vm.assume(otherScope != bytes32(0));
        deployRegistry();
        MockMigrationApplier wrongScope = new MockMigrationApplier();
        MockMigrationApplier rightScope = new MockMigrationApplier();

        vm.startPrank(WRITER);
        LibMigrationRegistry.approveV3(otherScope, address(wrongScope));
        LibMigrationRegistry.approveV3(namespaceHash, address(rightScope));
        vm.stopPrank();

        Prerequisite[] memory ontoGenesis = LibMigrationRegistry.onto(WRITER, namespaceHash, MIGRATION_HEAD_GENESIS);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRegistryDelegatesV1.NotApproved.selector, WRITER, namespaceHash, address(wrongScope)
            )
        );
        wrongScope.applyMigrationV4(WRITER, namespace, MIGRATION_NAME, ontoGenesis);

        rightScope.applyMigrationV4(WRITER, namespace, MIGRATION_NAME, ontoGenesis);
        assertEq(LibMigrationRegistry.appliedV4(WRITER, namespaceHash, MIGRATION), block.timestamp);
        assertEq(LibMigrationRegistry.appliedByV4(WRITER, namespaceHash, MIGRATION), address(rightScope));
    }
}
