// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockAddressRevertingFactory} from "./MockAddressRevertingFactory.sol";
import {MockDeployable} from "./MockDeployable.sol";
import {MockReverter} from "./MockReverter.sol";

/// @title LibRainDeployTest
/// Tests for `LibRainDeploy`. External wrappers are used for library functions
/// that need `vm.expectRevert` at the correct call depth, and for functions
/// that require a storage mapping reference.
contract LibRainDeployTest is Test {
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

    /// `isStartBlock` MUST return false when the target has no code at the
    /// given block.
    function testIsStartBlockNoCode() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertFalse(LibRainDeploy.isStartBlock(vm, address(0xdead), bytes32(uint256(1)), block.number));
    }

    /// `isStartBlock` MUST return false when the target has the expected
    /// code hash at both the given block and the block before it.
    function testIsStartBlockCodeAtBothBlocks() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        // The Zoltu factory exists at the current block and the block
        // before it, so this is not a start block.
        assertFalse(
            LibRainDeploy.isStartBlock(
                vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, block.number
            )
        );
    }

    /// `isStartBlock` MUST return true when the target has the expected code
    /// hash at the given block but not at the block before it. Uses the
    /// actual Zoltu factory deploy block found by `findDeployBlock`.
    function testIsStartBlockAtDeployBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 deployBlock =
            LibRainDeploy.findDeployBlock(vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, 0);
        assertTrue(
            LibRainDeploy.isStartBlock(
                vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, deployBlock
            )
        );
    }

    /// `isStartBlock` MUST restore the fork to its original block number.
    function testIsStartBlockRestoresFork() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 originalBlock = block.number;
        LibRainDeploy.isStartBlock(vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, 0);
        assertEq(block.number, originalBlock);
    }

    /// `findDeployBlock` MUST revert with `NotDeployed` when the target
    /// address has no code on the current fork.
    function testFindDeployBlockNotDeployedReverts() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NotDeployed.selector, address(0xdead)));
        this.externalFindDeployBlock(address(0xdead), bytes32(0), 0);
    }

    /// `findDeployBlock` MUST revert with `UnexpectedDeployedCodeHash` when
    /// the target's code hash does not match the expected value.
    function testFindDeployBlockWrongCodeHashReverts() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        bytes32 wrongHash = bytes32(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedCodeHash.selector, wrongHash, LibRainDeploy.ZOLTU_FACTORY_CODEHASH
            )
        );
        this.externalFindDeployBlock(LibRainDeploy.ZOLTU_FACTORY, wrongHash, 0);
    }

    /// `findDeployBlock` MUST revert with `DeployedBeforeStartBlock` when
    /// the target already has code at the start block.
    function testFindDeployBlockDeployedBeforeStartBlockReverts() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        // Use the current block as startBlock — the Zoltu factory already
        // exists here, so the function should revert.
        uint256 startBlock = block.number;
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DeployedBeforeStartBlock.selector, LibRainDeploy.ZOLTU_FACTORY, startBlock
            )
        );
        this.externalFindDeployBlock(LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, startBlock);
    }

    /// `findDeployBlock` MUST return a block that `isStartBlock` confirms,
    /// and the fork MUST be restored to the original block number.
    /// Uses Base because the public Base RPC has full archive access.
    function testFindDeployBlockZoltuFactory() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 originalBlock = block.number;

        uint256 deployBlock =
            LibRainDeploy.findDeployBlock(vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, 0);

        // Fork must be restored to the original block.
        assertEq(block.number, originalBlock);

        // The result must be a valid start block.
        assertTrue(
            LibRainDeploy.isStartBlock(
                vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, deployBlock
            )
        );
    }

    /// `supportedNetworks` MUST return exactly 5 networks in the expected
    /// order matching the library constants.
    function testSupportedNetworks() external pure {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        assertEq(networks.length, 5);
        assertEq(networks[0], LibRainDeploy.ARBITRUM_ONE);
        assertEq(networks[1], LibRainDeploy.BASE);
        assertEq(networks[2], LibRainDeploy.BASE_SEPOLIA);
        assertEq(networks[3], LibRainDeploy.FLARE);
        assertEq(networks[4], LibRainDeploy.POLYGON);
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
            dependencies
        );
    }

    /// Empty networks array MUST revert with `NoNetworks`.
    function testNoNetworksReverts() external {
        string[] memory networks = new string[](0);
        address[] memory dependencies = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalDeployAndBroadcast(networks, 1, hex"", "", address(0), bytes32(0), dependencies);
    }

    /// `deployToNetworks` MUST revert with `NoNetworks` when given an empty
    /// networks array.
    function testDeployToNetworksNoNetworksReverts() external {
        string[] memory networks = new string[](0);
        address[] memory dependencies = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalDeployToNetworks(networks, address(this), hex"", "", address(0), bytes32(0), dependencies);
    }

    /// `deployToNetworks` MUST deploy to every network in the list, forking each
    /// independently. Two networks that start without the target both end up with
    /// the deterministic contract, and the call returns its address.
    function testDeployToNetworksMultipleNetworks() external {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);

        address result = this.externalDeployToNetworks(
            networks,
            address(this),
            type(MockDeployable).creationCode,
            "test/src/lib/MockDeployable.sol:MockDeployable",
            0xC24016f209562fc151e5Ab7F88694ED5775feb36,
            0xc1a263a0b50505687a5140c7964ec5c947329e7d03410306fee68cc3620c5483,
            dependencies
        );
        assertEq(result, 0xC24016f209562fc151e5Ab7F88694ED5775feb36);
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

    /// `deployZoltu` MUST revert with `DeployFailed` when the creation code
    /// has a reverting constructor (success=false from factory call).
    function testDeployZoltuRevertsRevertingConstructor() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, false, address(0)));
        this.externalDeployZoltu(type(MockReverter).creationCode);
    }

    /// `deployZoltu` MUST report the zero address when the factory call fails,
    /// even when the factory reverts with data that reads as an address. The
    /// call output buffer holds revert data on the failure path, so anything
    /// read from it there is not an address the factory returned.
    function testDeployZoltuFailedCallReportsZeroAddress() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, address(new MockAddressRevertingFactory()).code);
        // The factory reverts with its own address, which has code, so the
        // reported address is only zero if the failure path never reads the
        // output buffer.
        assertGt(LibRainDeploy.ZOLTU_FACTORY.code.length, 0);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, false, address(0)));
        this.externalDeployZoltu(type(MockDeployable).creationCode);
    }

    /// `deployToNetworks` MUST revert with `UnexpectedDeployedAddress` when the
    /// deployed address does not match the expected address.
    function testUnexpectedDeployedAddressReverts() external {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);
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
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);
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
            "test/src/lib/MockDeployable.sol:MockDeployable",
            0xC24016f209562fc151e5Ab7F88694ED5775feb36,
            0xc1a263a0b50505687a5140c7964ec5c947329e7d03410306fee68cc3620c5483,
            dependencies
        );
        assertEq(deployed, 0xC24016f209562fc151e5Ab7F88694ED5775feb36);
    }

    /// `deployToNetworks` MUST skip deployment and return the expected address
    /// when code already exists there, provided the codehash matches.
    function testDeployToNetworksSkipsWhenAlreadyDeployed() external {
        vm.makePersistent(address(this));

        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        address deployed = this.externalDeployZoltu(type(MockDeployable).creationCode);
        assertEq(deployed, 0xC24016f209562fc151e5Ab7F88694ED5775feb36);
        vm.makePersistent(deployed);

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);

        address result = this.externalDeployToNetworks(
            networks,
            address(this),
            type(MockDeployable).creationCode,
            "test/src/lib/MockDeployable.sol:MockDeployable",
            0xC24016f209562fc151e5Ab7F88694ED5775feb36,
            0xc1a263a0b50505687a5140c7964ec5c947329e7d03410306fee68cc3620c5483,
            dependencies
        );
        assertEq(result, 0xC24016f209562fc151e5Ab7F88694ED5775feb36);
    }

    /// `deployToNetworks` MUST skip an already-deployed network WITHOUT checking
    /// its dependencies. A rerun on a network that no longer needs deployment is
    /// a clean no-op even when a dependency is now missing, because the
    /// dependency check only guards the deploy path.
    function testDeployToNetworksSkipsAlreadyDeployedWithMissingDependency() external {
        vm.makePersistent(address(this));

        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        address deployed = this.externalDeployZoltu(type(MockDeployable).creationCode);
        assertEq(deployed, 0xC24016f209562fc151e5Ab7F88694ED5775feb36);
        vm.makePersistent(deployed);

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        // A dependency with no code: it would revert MissingDependency on the
        // deploy path, but the target is already deployed so it is never checked.
        address[] memory dependencies = new address[](1);
        dependencies[0] = address(0xdead);

        address result = this.externalDeployToNetworks(
            networks,
            address(this),
            type(MockDeployable).creationCode,
            "test/src/lib/MockDeployable.sol:MockDeployable",
            0xC24016f209562fc151e5Ab7F88694ED5775feb36,
            0xc1a263a0b50505687a5140c7964ec5c947329e7d03410306fee68cc3620c5483,
            dependencies
        );
        assertEq(result, 0xC24016f209562fc151e5Ab7F88694ED5775feb36);
    }

    /// `deployToNetworks` MUST revert with `MissingDependency` when the Zoltu
    /// factory has no code on the network.
    function testDeployToNetworksMissingZoltuFactoryReverts() external {
        vm.makePersistent(address(this));
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        vm.makePersistent(LibRainDeploy.ZOLTU_FACTORY);
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, hex"");

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.ZOLTU_FACTORY
            )
        );
        this.externalDeployToNetworks(networks, address(this), hex"", "", address(0), bytes32(0), dependencies);
    }

    /// `deployToNetworks` MUST revert with `DependencyChanged` when the Zoltu
    /// factory exists but has a wrong codehash.
    function testDeployToNetworksZoltuFactoryCodehashChangedReverts() external {
        vm.makePersistent(address(this));
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        vm.makePersistent(LibRainDeploy.ZOLTU_FACTORY);
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, hex"00");

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.ARBITRUM_ONE,
                LibRainDeploy.ZOLTU_FACTORY,
                LibRainDeploy.ZOLTU_FACTORY_CODEHASH,
                keccak256(hex"00")
            )
        );
        this.externalDeployToNetworks(networks, address(this), hex"", "", address(0), bytes32(0), dependencies);
    }

    /// `deployToNetworks` MUST revert with `MissingDependency` when a dependency
    /// has no code on the network.
    function testDeployToNetworksMissingDependencyReverts() external {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](1);
        dependencies[0] = address(0xdead);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, address(0xdead)
            )
        );
        this.externalDeployToNetworks(networks, address(this), hex"", "", address(0), bytes32(0), dependencies);
    }
}
