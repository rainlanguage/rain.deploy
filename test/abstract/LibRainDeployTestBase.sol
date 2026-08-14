// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {IAddressRegistryV1} from "../../src/interface/IAddressRegistryV1.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../src/concrete/AddressRegistry.sol";
import {MockResolvedOwner} from "../concrete/MockResolvedOwner.sol";
import {MockDeployable} from "../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../concrete/MockDeployableV2.sol";

/// @title LibRainDeployTestBase
/// The fixtures and external wrappers `LibRainDeploy`'s tests share, so that
/// splitting those tests by whether they need a chain does not duplicate any of
/// it. External wrappers are used for library functions that need
/// `vm.expectRevert` at the correct call depth.
///
/// The split itself is `LibRainDeployTest` (reads no chain state, forks nothing)
/// and `LibRainDeployChainTest` (forks, directly or through the library). It is
/// by contract because `--no-match-contract Chain` is what selects it.
abstract contract LibRainDeployTestBase is Test {
    /// The address the Zoltu factory deploys `MockDeployable` to. Derived from
    /// the mock's creation code by the same formula the factory applies, so it
    /// follows the compiler that builds the mock. `testDeployZoltu` pins the
    /// derivation against the live factory on a fork.
    /// @return The deterministic address for `MockDeployable`.
    function mockDeployableAddress() internal pure returns (address) {
        return LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode);
    }

    /// The code hash `MockDeployable` has once deployed, i.e. `keccak256` over
    /// the runtime code its creation code leaves behind. Derived from the mock
    /// rather than pinned, for the same reason as `mockDeployableAddress`.
    /// @return The deployed code hash for `MockDeployable`.
    function mockDeployableCodeHash() internal pure returns (bytes32) {
        return keccak256(type(MockDeployable).runtimeCode);
    }

    /// The address the Zoltu factory deploys `MockDeployableV2` to, derived the
    /// same way as `mockDeployableAddress`.
    /// @return The deterministic address for `MockDeployableV2`.
    function mockDeployableV2Address() internal pure returns (address) {
        return LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode);
    }

    /// External wrapper for `isStartBlock` so that it can be called
    /// externally in tests.
    /// @param target The contract address to check.
    /// @param expectedCodeHash The code hash to look for.
    /// @param blockNumber The block number to check.
    /// @return isStart True if the contract first appears at this block.
    function externalIsStartBlock(address target, bytes32 expectedCodeHash, uint256 blockNumber)
        external
        returns (bool isStart)
    {
        isStart = LibRainDeploy.isStartBlock(vm, target, expectedCodeHash, blockNumber);
    }

    /// External wrapper for `findDeployBlock` so that `vm.expectRevert`
    /// works at the correct call depth.
    /// @param target The contract address to search for.
    /// @param expectedCodeHash The expected code hash of the target.
    /// @param startBlock The earliest block to search from.
    /// @return deployBlock The first block number where `target` has code.
    function externalFindDeployBlock(address target, bytes32 expectedCodeHash, uint256 startBlock)
        external
        returns (uint256 deployBlock)
    {
        deployBlock = LibRainDeploy.findDeployBlock(vm, target, expectedCodeHash, startBlock);
    }

    /// External wrapper for `deployAndBroadcast` so that
    /// `vm.expectRevert` works at the correct call depth.
    /// @param networks The list of network names to deploy to.
    /// @param deployerPrivateKey The private key to use for broadcasting.
    /// @param creationCode The creation code to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The expected deterministic address.
    /// @param expectedCodeHash The expected code hash of the deployed contract.
    /// @param dependencies The dependency addresses to check.
    /// @return deployedAddress The deployed contract address.
    function externalDeployAndBroadcast(
        string[] memory networks,
        uint256 deployerPrivateKey,
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        address[] memory dependencies
    ) external returns (address deployedAddress) {
        deployedAddress = LibRainDeploy.deployAndBroadcast(
            vm,
            networks,
            deployerPrivateKey,
            creationCode,
            contractPath,
            expectedAddress,
            expectedCodeHash,
            dependencies
        );
    }

    /// External wrapper for `deployToNetworks` so that `vm.expectRevert`
    /// works at the correct call depth.
    /// @param networks The list of network names to deploy to.
    /// @param deployer The deployer address.
    /// @param creationCode The creation code to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The expected deterministic address.
    /// @param expectedCodeHash The expected code hash of the deployed contract.
    /// @param dependencies The addresses that must have code on each network.
    /// @return deployedAddress The deployed contract address.
    function externalDeployToNetworks(
        string[] memory networks,
        address deployer,
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        address[] memory dependencies
    ) external returns (address deployedAddress) {
        deployedAddress = LibRainDeploy.deployToNetworks(
            vm, networks, deployer, creationCode, contractPath, expectedAddress, expectedCodeHash, dependencies
        );
    }

    /// External wrapper for `deployZoltu` so that it can be called on a fork.
    /// @param creationCode The creation code to deploy via the Zoltu factory.
    /// @return deployedAddress The address of the deployed contract.
    function externalDeployZoltu(bytes memory creationCode) external returns (address deployedAddress) {
        deployedAddress = LibRainDeploy.deployZoltu(creationCode);
    }

    /// External wrapper for `deployZoltu` that carries value, so that what the
    /// library does with the caller's value is observable.
    /// @param creationCode The creation code to deploy via the Zoltu factory.
    /// @return deployedAddress The address of the deployed contract.
    function externalDeployZoltuPayable(bytes memory creationCode) external payable returns (address deployedAddress) {
        deployedAddress = LibRainDeploy.deployZoltu(creationCode);
    }

    /// Deploys `AddressRegistry` through the Zoltu factory (which lands it at
    /// its pinned address), binds `name` to `account` as root, then deploys a
    /// consumer that resolves `name` once in its constructor.
    /// @param name The name to bind and resolve.
    /// @param account The address to bind it to.
    /// @return registry The deployed registry.
    /// @return consumer The deployed consumer holding the resolved address.
    function deployRegistryAndConsumer(bytes32 name, address account)
        internal
        returns (IAddressRegistryV1 registry, MockResolvedOwner consumer)
    {
        LibRainDeploy.etchZoltuFactory(vm);
        registry = IAddressRegistryV1(LibRainDeploy.deployZoltu(type(AddressRegistry).creationCode));
        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, account);
        consumer = new MockResolvedOwner(name);
    }

    /// The calldata for reading `MockResolvedOwner`'s stored address.
    /// @return The single-element read call list.
    function ownerReadCalls() internal pure returns (bytes[] memory) {
        bytes[] memory readCalls = new bytes[](1);
        readCalls[0] = abi.encodeWithSignature("iOwner()");
        return readCalls;
    }

    /// A single-element expected address list.
    /// @param account The expected address.
    /// @return The list.
    function expected(address account) internal pure returns (address[] memory) {
        address[] memory expectedAddresses = new address[](1);
        expectedAddresses[0] = account;
        return expectedAddresses;
    }

    /// External wrapper for `checkResolvedAddresses` so that `vm.expectRevert`
    /// works at the correct call depth.
    /// @param network The network name, for the error only.
    /// @param target The deployed contract to read.
    /// @param readCalls The calldata for each read.
    /// @param expectedAddresses The address each read MUST answer with.
    function externalCheckResolvedAddresses(
        string memory network,
        address target,
        bytes[] memory readCalls,
        address[] memory expectedAddresses
    ) external view {
        LibRainDeploy.checkResolvedAddresses(network, target, readCalls, expectedAddresses);
    }

    /// External wrapper for `checkResolvedAddressesOnNetworks` so that
    /// `vm.expectRevert` works at the correct call depth.
    /// @param networks The list of network names to check.
    /// @param target The deployed contract to read on each network.
    /// @param readCalls The calldata for each read.
    /// @param expectedAddresses The address each read MUST answer with.
    function externalCheckResolvedAddressesOnNetworks(
        string[] memory networks,
        address target,
        bytes[] memory readCalls,
        address[] memory expectedAddresses
    ) external {
        LibRainDeploy.checkResolvedAddressesOnNetworks(vm, networks, target, readCalls, expectedAddresses);
    }
}
