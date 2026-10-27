// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibConfigRegistry} from "../../../src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "../../../src/lib/LibConfigRegistryDeploy.sol";
import {IConfigRegistryV4} from "../../../src/interface/IConfigRegistryV4.sol";
import {LibConfigRegistryFork} from "../../lib/LibConfigRegistryFork.sol";

/// @title LibConfigRegistryValueTypeTest
/// @notice `resolve` and `resolveSafe` return a binding only when it was made
/// as the type the caller expects, and otherwise revert `ValueTypeMismatch`.
contract LibConfigRegistryValueTypeTest is Test {
    address internal constant AUTHORITY = address(0xA11CE);

    function bind(bytes32 name, string memory valueType) internal returns (IConfigRegistryV4) {
        LibConfigRegistryFork.ensureDeployed(vm);
        IConfigRegistryV4 registry = IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, valueType, hex"01", "");
        return registry;
    }

    function externalResolve(bytes32 name, bytes32 valueTypeHash) external view returns (bytes memory, uint256) {
        return LibConfigRegistry.resolve(AUTHORITY, name, valueTypeHash);
    }

    function externalResolveSafe(bytes32 name, bytes32 valueTypeHash, uint256 minAge)
        external
        view
        returns (bytes memory)
    {
        return LibConfigRegistry.resolveSafe(AUTHORITY, name, valueTypeHash, minAge);
    }

    /// The matching type resolves.
    function testResolveMatchingType(bytes32 name, string memory valueType) external {
        vm.assume(bytes(valueType).length > 0);
        vm.warp(10);
        bind(name, valueType);
        (bytes memory value, uint256 registeredAt) = this.externalResolve(name, keccak256(bytes(valueType)));
        assertEq(value, hex"01");
        assertEq(registeredAt, 10);
        vm.warp(20);
        assertEq(this.externalResolveSafe(name, keccak256(bytes(valueType)), 5), hex"01");
    }

    /// Any other expected hash is refused, naming both.
    function testResolveMismatchedTypeReverts(bytes32 name, string memory valueType, bytes32 expected) external {
        vm.assume(bytes(valueType).length > 0);
        bytes32 actual = keccak256(bytes(valueType));
        vm.assume(expected != actual);
        vm.warp(10);
        bind(name, valueType);
        vm.warp(20);
        bytes memory err = abi.encodeWithSelector(
            LibConfigRegistry.ValueTypeMismatch.selector, AUTHORITY, name, expected, actual
        );
        vm.expectRevert(err);
        this.externalResolve(name, expected);
        vm.expectRevert(err);
        this.externalResolveSafe(name, expected, 5);
    }

    /// The type is checked before the age: a fresh binding of the wrong type
    /// is reported as the wrong type.
    function testResolveSafeTypeCheckedBeforeAge(bytes32 name) external {
        vm.warp(10);
        bind(name, "uint256");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                AUTHORITY,
                name,
                keccak256("address"),
                keccak256("uint256")
            )
        );
        this.externalResolveSafe(name, keccak256("address"), 100);
    }

    /// A rebind as another type moves what resolves.
    function testResolveFollowsRebindType(bytes32 name) external {
        vm.warp(10);
        IConfigRegistryV4 registry = bind(name, "address");
        vm.warp(20);
        vm.prank(AUTHORITY);
        registry.registerV4(AUTHORITY, name, "uint256", hex"01", "");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                AUTHORITY,
                name,
                keccak256("address"),
                keccak256("uint256")
            )
        );
        this.externalResolve(name, keccak256("address"));
        (bytes memory value,) = this.externalResolve(name, keccak256("uint256"));
        assertEq(value, hex"01");
    }
}
