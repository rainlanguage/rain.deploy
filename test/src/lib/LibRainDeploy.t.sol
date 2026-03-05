// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";

/// @title MockDeployable
/// Minimal contract used as a deployment target for Zoltu factory tests.
contract MockDeployable {
    /// @notice Placeholder value to ensure the contract has non-trivial code.
    uint256 public value = 42;
}

/// @title LibRainDeployTest
/// Tests for `LibRainDeploy`. External wrappers are used for library functions
/// that need `vm.expectRevert` at the correct call depth, and for functions
/// that require a storage mapping reference.
contract LibRainDeployTest is Test {
    mapping(string => mapping(address => bytes32)) internal sDepCodeHashes;

    /// `supportedNetworks` MUST return exactly 4 networks in the expected
    /// order matching the library constants.
    function testSupportedNetworks() external pure {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        assertEq(networks.length, 4);
        assertEq(networks[0], LibRainDeploy.ARBITRUM_ONE);
        assertEq(networks[1], LibRainDeploy.BASE);
        assertEq(networks[2], LibRainDeploy.FLARE);
        assertEq(networks[3], LibRainDeploy.POLYGON);
    }

    /// `ZOLTU_FACTORY_CODEHASH` MUST match the actual codehash of the Zoltu
    /// factory on a forked network.
    function testZoltuFactoryCodehash() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        assertEq(LibRainDeploy.ZOLTU_FACTORY.codehash, LibRainDeploy.ZOLTU_FACTORY_CODEHASH);
    }

    /// `ZOLTU_FACTORY_BYTECODE` MUST match the actual runtime bytecode of the
    /// Zoltu factory on a forked network.
    function testZoltuFactoryBytecode() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        assertEq(LibRainDeploy.ZOLTU_FACTORY.code, LibRainDeploy.ZOLTU_FACTORY_BYTECODE);
    }

    /// `etchZoltuFactory` MUST place the correct bytecode and codehash at the
    /// Zoltu factory address.
    function testEtchZoltuFactory() external {
        assertEq(LibRainDeploy.ZOLTU_FACTORY.code.length, 0);
        LibRainDeploy.etchZoltuFactory(vm);
        assertEq(LibRainDeploy.ZOLTU_FACTORY.code, LibRainDeploy.ZOLTU_FACTORY_BYTECODE);
        assertEq(LibRainDeploy.ZOLTU_FACTORY.codehash, LibRainDeploy.ZOLTU_FACTORY_CODEHASH);
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
            dependencies,
            sDepCodeHashes
        );
    }

    /// Empty networks array MUST revert with `NoNetworks`.
    function testNoNetworksReverts() external {
        string[] memory networks = new string[](0);
        address[] memory dependencies = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalDeployAndBroadcast(networks, 1, hex"", "", address(0), bytes32(0), dependencies);
    }

    /// External wrapper for `checkDependencies` so that `vm.expectRevert`
    /// works at the correct call depth.
    /// @param networks The list of network names to check.
    /// @param dependencies The dependency addresses to check.
    function externalCheckDependencies(string[] memory networks, address[] memory dependencies) external {
        LibRainDeploy.checkDependencies(vm, networks, dependencies, sDepCodeHashes);
    }

    /// External wrapper for `deployToNetworks` so that `vm.expectRevert`
    /// works at the correct call depth.
    /// @param networks The list of network names to deploy to.
    /// @param deployer The deployer address.
    /// @param creationCode The creation code to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The expected deterministic address.
    /// @param expectedCodeHash The expected code hash of the deployed contract.
    /// @param dependencies The dependency addresses to re-verify.
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
            vm,
            networks,
            deployer,
            creationCode,
            contractPath,
            expectedAddress,
            expectedCodeHash,
            dependencies,
            sDepCodeHashes
        );
    }

    /// External wrapper for `deployZoltu` so that it can be called on a fork.
    /// @param creationCode The creation code to deploy via the Zoltu factory.
    /// @return deployedAddress The address of the deployed contract.
    function externalDeployZoltu(bytes memory creationCode) external returns (address deployedAddress) {
        deployedAddress = LibRainDeploy.deployZoltu(creationCode);
    }

    /// `deployZoltu` MUST deploy a contract via the Zoltu factory and return
    /// the deterministic address predicted by the factory's nonce.
    function testDeployZoltu() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        address deployed = this.externalDeployZoltu(type(MockDeployable).creationCode);
        assertEq(deployed, 0xC24016f209562fc151e5Ab7F88694ED5775feb36);
    }

    /// `deployZoltu` MUST revert with `DeployFailed` when the Zoltu factory
    /// has no code.
    function testDeployZoltuRevertsNoFactory() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, hex"");
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, true, address(0)));
        this.externalDeployZoltu(type(MockDeployable).creationCode);
    }

    /// `deployToNetworks` MUST revert with `UnexpectedDeployedAddress` when the
    /// deployed address does not match the expected address.
    function testUnexpectedDeployedAddressReverts() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        address[] memory dependencies = new address[](0);
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedAddress.selector,
                address(0xdead),
                0xC24016f209562fc151e5Ab7F88694ED5775feb36
            )
        );
        this.externalDeployToNetworks(
            networks, address(this), type(MockDeployable).creationCode, "", address(0xdead), bytes32(0), dependencies
        );
    }

    /// `deployToNetworks` MUST revert with `UnexpectedDeployedCodeHash` when the
    /// deployed code hash does not match the expected code hash.
    function testUnexpectedDeployedCodeHashReverts() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        address[] memory dependencies = new address[](0);
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address expectedAddress = 0xC24016f209562fc151e5Ab7F88694ED5775feb36;
        bytes32 wrongCodeHash = bytes32(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedCodeHash.selector,
                wrongCodeHash,
                0xc1a263a0b50505687a5140c7964ec5c947329e7d03410306fee68cc3620c5483
            )
        );
        this.externalDeployToNetworks(
            networks, address(this), type(MockDeployable).creationCode, "", expectedAddress, wrongCodeHash, dependencies
        );
    }

    /// `deployAndBroadcast` MUST check dependencies, deploy
    /// via Zoltu, and return the correct address with the correct codehash.
    function testDeployAndBroadcastHappyPath() external {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);
        address deployed = this.externalDeployAndBroadcast(
            networks,
            1,
            type(MockDeployable).creationCode,
            "test/src/lib/LibRainDeploy.t.sol:MockDeployable",
            0xC24016f209562fc151e5Ab7F88694ED5775feb36,
            0xc1a263a0b50505687a5140c7964ec5c947329e7d03410306fee68cc3620c5483,
            dependencies
        );
        assertEq(deployed, 0xC24016f209562fc151e5Ab7F88694ED5775feb36);
    }

    /// `checkDependencies` MUST record the codehash of each dependency in the
    /// storage mapping after verifying it exists.
    function testCheckDependenciesRecordsCodehash() external {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](1);
        dependencies[0] = LibRainDeploy.ZOLTU_FACTORY;

        this.externalCheckDependencies(networks, dependencies);

        assertTrue(sDepCodeHashes[LibRainDeploy.ARBITRUM_ONE][LibRainDeploy.ZOLTU_FACTORY] != bytes32(0));
    }

    /// `checkDependencies` MUST revert with `MissingDependency` when a
    /// dependency has no code on the network.
    function testMissingDependencyReverts() external {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](1);
        dependencies[0] = address(0xdead);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, address(0xdead)
            )
        );
        this.externalCheckDependencies(networks, dependencies);
    }

    /// `deployToNetworks` MUST revert with `DependencyChanged` when a
    /// dependency's codehash differs from what was recorded during the check
    /// phase.
    function testDependencyChangedCodehashReverts() external {
        // Make the test contract persistent so storage survives fork switches.
        vm.makePersistent(address(this));

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](1);
        dependencies[0] = LibRainDeploy.ZOLTU_FACTORY;

        // Pre-populate with a wrong codehash to simulate a change between
        // the check and deploy phases.
        sDepCodeHashes[LibRainDeploy.ARBITRUM_ONE][LibRainDeploy.ZOLTU_FACTORY] = bytes32(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.ARBITRUM_ONE,
                LibRainDeploy.ZOLTU_FACTORY,
                bytes32(uint256(1)),
                LibRainDeploy.ZOLTU_FACTORY_CODEHASH
            )
        );
        this.externalDeployToNetworks(networks, address(this), hex"", "", address(0), bytes32(0), dependencies);
    }

    /// `deployToNetworks` MUST revert with `DependencyChanged` when a
    /// dependency has been destroyed (code.length == 0) since the check phase.
    function testDependencyChangedCodeLengthReverts() external {
        // Make the test contract persistent so storage survives fork switches.
        vm.makePersistent(address(this));

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](1);
        dependencies[0] = address(0xdead);

        // Pre-populate as if the dependency existed during the check phase.
        sDepCodeHashes[LibRainDeploy.ARBITRUM_ONE][address(0xdead)] = bytes32(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.ARBITRUM_ONE,
                address(0xdead),
                bytes32(uint256(1)),
                0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
            )
        );
        this.externalDeployToNetworks(networks, address(this), hex"", "", address(0), bytes32(0), dependencies);
    }
}
