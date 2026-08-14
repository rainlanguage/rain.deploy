// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {AddressRegistry, ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";
import {MockAddressRevertingFactory} from "../../concrete/MockAddressRevertingFactory.sol";
import {MockResolvedOwner} from "../../concrete/MockResolvedOwner.sol";
import {MockDirtyWordOwner} from "../../concrete/MockDirtyWordOwner.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {MockReverter} from "../../concrete/MockReverter.sol";

/// @title LibRainDeployTest
/// Tests for `LibRainDeploy`. External wrappers are used for library functions
/// that need `vm.expectRevert` at the correct call depth, and for functions
/// that require a storage mapping reference.
contract LibRainDeployTest is Test {
    /// Base allocates the OP Stack WETH9 predeploy in its genesis block, so
    /// this address has code at block 0.
    address constant BASE_GENESIS_PREDEPLOY = 0x4200000000000000000000000000000000000006;

    /// Code hash of the Base genesis WETH9 predeploy, fixed by the genesis
    /// allocation and therefore identical at block 0 and block 1.
    bytes32 constant BASE_GENESIS_PREDEPLOY_CODEHASH =
        0x8a3a1f6a9f9dce633117adee5b458245835a8645a8c8726a26382a4622508b1c;

    /// The block at which the Zoltu factory first has its code on Base.
    uint256 constant ZOLTU_BASE_DEPLOY_BLOCK = 1117029;

    /// Chain id of Base.
    uint256 constant BASE_CHAIN_ID = 8453;

    /// Chain id of Arbitrum One.
    uint256 constant ARBITRUM_ONE_CHAIN_ID = 42161;

    /// The address the Zoltu factory derives for empty creation code, i.e.
    /// CREATE2 over the factory address, a zero salt and the hash of empty
    /// creation code. An account is created there but it has no code.
    address constant ZOLTU_EMPTY_CREATION_CODE_ADDRESS = 0x5DC93B79FBDD6f26Ed9540597C78eD5893F9aC7A;

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
    /// factory on every supported network. Every name in `supportedNetworks`
    /// MUST also be a configured fork alias, otherwise it cannot be deployed
    /// to at all.
    function testZoltuFactoryCodehash() external {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            assertEq(LibRainDeploy.ZOLTU_FACTORY.codehash, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, networks[i]);
        }
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
    /// networks array, before any other input is checked.
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
            "test/concrete/MockDeployable.sol:MockDeployable",
            mockDeployableAddress(),
            mockDeployableCodeHash(),
            dependencies
        );
        assertEq(result, mockDeployableAddress());

        // The returned address is the same for every network, so it says
        // nothing about how many networks were visited. What does is the state
        // each fork was left in.
        //
        // `deployToNetworks` creates one fork per network, in list order, and
        // this test creates none of its own, so those forks are ids 0 and 1.
        // Selecting each in turn and asserting BOTH the chain it is on and
        // that the contract is deployed there is what pins "every network in
        // the list": a loop that stops early never creates the second fork, a
        // loop that starts late puts the wrong chain at id 0, and a loop that
        // forks `networks[0]` every iteration puts the same chain at both ids.
        vm.selectFork(0);
        assertEq(block.chainid, BASE_CHAIN_ID);
        assertEq(result.codehash, mockDeployableCodeHash());

        vm.selectFork(1);
        assertEq(block.chainid, ARBITRUM_ONE_CHAIN_ID);
        assertEq(result.codehash, mockDeployableCodeHash());
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

    /// `deployZoltu` MUST deploy a contract via the Zoltu factory and return
    /// the deterministic address predicted by the factory's nonce.
    function testDeployZoltu() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        address deployed = this.externalDeployZoltu(type(MockDeployable).creationCode);
        // Pinned literal, deliberately not `mockDeployableAddress()`. The live
        // factory on the fork is the oracle here, so an expected value taken
        // from the derivation would only check `zoltuAddress` against itself.
        // It is the address the factory returns for the creation code this
        // repo's compiler settings emit for `MockDeployable` — solc 0.8.25,
        // optimizer on at 100,000 runs, targeting cancun. Those settings are
        // now pinned exactly in `foundry.toml`, because this repo's deploy pins
        // depend on them; that is what makes a literal here stable at all, and
        // moving any of them moves this address.
        assertEq(deployed, 0x0c04367b381F8Ca252aD2516F1Eac2b9B2ca928F);
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

    /// `deployToNetworks` MUST revert with `UnexpectedDeployedAddress` when the
    /// creation code does not deploy to the expected address.
    function testUnexpectedDeployedAddressReverts() external {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedAddress.selector, address(0xdead), mockDeployableAddress()
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
        address expectedAddress = mockDeployableAddress();
        bytes32 wrongCodeHash = bytes32(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedCodeHash.selector, wrongCodeHash, mockDeployableCodeHash()
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
            "test/concrete/MockDeployable.sol:MockDeployable",
            mockDeployableAddress(),
            mockDeployableCodeHash(),
            dependencies
        );
        assertEq(deployed, mockDeployableAddress());
    }

    /// `deployToNetworks` MUST skip deployment and return the expected address
    /// when code already exists there, provided the codehash matches.
    function testDeployToNetworksSkipsWhenAlreadyDeployed() external {
        vm.makePersistent(address(this));

        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        address deployed = this.externalDeployZoltu(type(MockDeployable).creationCode);
        assertEq(deployed, mockDeployableAddress());
        vm.makePersistent(deployed);

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);

        address result = this.externalDeployToNetworks(
            networks,
            address(this),
            type(MockDeployable).creationCode,
            "test/concrete/MockDeployable.sol:MockDeployable",
            mockDeployableAddress(),
            mockDeployableCodeHash(),
            dependencies
        );
        assertEq(result, mockDeployableAddress());
    }

    /// `deployToNetworks` MUST skip an already-deployed network WITHOUT checking
    /// its dependencies. A rerun on a network that no longer needs deployment is
    /// a clean no-op even when a dependency is now missing, because the
    /// dependency check only guards the deploy path.
    function testDeployToNetworksSkipsAlreadyDeployedWithMissingDependency() external {
        vm.makePersistent(address(this));

        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        address deployed = this.externalDeployZoltu(type(MockDeployable).creationCode);
        assertEq(deployed, mockDeployableAddress());
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
            "test/concrete/MockDeployable.sol:MockDeployable",
            mockDeployableAddress(),
            mockDeployableCodeHash(),
            dependencies
        );
        assertEq(result, mockDeployableAddress());
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
        this.externalDeployToNetworks(
            networks,
            address(this),
            type(MockDeployable).creationCode,
            "",
            mockDeployableAddress(),
            bytes32(0),
            dependencies
        );
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
        this.externalDeployToNetworks(
            networks,
            address(this),
            type(MockDeployable).creationCode,
            "",
            mockDeployableAddress(),
            bytes32(0),
            dependencies
        );
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
        this.externalDeployToNetworks(
            networks,
            address(this),
            type(MockDeployable).creationCode,
            "",
            mockDeployableAddress(),
            bytes32(0),
            dependencies
        );
    }

    /// `zoltuAddress` MUST derive the address the Zoltu factory actually
    /// deploys the given creation code to, and creation code that differs MUST
    /// derive a different address.
    function testZoltuAddressMatchesFactoryDeploy() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        assertEq(
            LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            this.externalDeployZoltu(type(MockDeployable).creationCode)
        );
        assertEq(
            LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
            this.externalDeployZoltu(type(MockDeployableV2).creationCode)
        );
        assertNotEq(
            LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode)
        );
    }

    /// `deployToNetworks` MUST revert with `UnexpectedDeployedAddress` when the
    /// creation code does not deploy to `expectedAddress`, even when a contract
    /// with the expected code hash already sits at that address on every
    /// network and would otherwise be skipped as already deployed.
    function testDeployToNetworksStaleExpectedAddressReverts() external {
        vm.makePersistent(address(this));

        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        address deployed = this.externalDeployZoltu(type(MockDeployable).creationCode);
        assertEq(deployed, mockDeployableAddress());
        vm.makePersistent(deployed);

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedAddress.selector, mockDeployableAddress(), mockDeployableV2Address()
            )
        );
        // The new contract's creation code paired with the old contract's
        // address and code hash.
        this.externalDeployToNetworks(
            networks,
            address(this),
            type(MockDeployableV2).creationCode,
            "test/concrete/MockDeployableV2.sol:MockDeployableV2",
            mockDeployableAddress(),
            mockDeployableCodeHash(),
            dependencies
        );

        // The new contract was not deployed anywhere.
        assertEq(mockDeployableV2Address().code.length, 0);
    }

    /// `deployToNetworks` MUST check `expectedAddress` against the creation
    /// code before it forks anything, so the mismatch is reported without any
    /// network being reachable at all.
    function testDeployToNetworksStaleExpectedAddressRevertsBeforeForking() external {
        string[] memory networks = new string[](1);
        // Not a configured RPC alias, so forking it is itself an error.
        networks[0] = "unconfigured_network";
        address[] memory dependencies = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedAddress.selector, address(0xdead), mockDeployableAddress()
            )
        );
        this.externalDeployToNetworks(
            networks, address(this), type(MockDeployable).creationCode, "", address(0xdead), bytes32(0), dependencies
        );
    }

    /// `deployToNetworks` MUST revert with `UnexpectedDeployedAddress` when the
    /// factory reports an address other than the one derived from the creation
    /// code, so the chain is checked and not only the derivation.
    function testDeployToNetworksFactoryReportsOtherAddressReverts() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        // The factory reports the address of a contract that does have code,
        // but not the one the creation code derives.
        vm.mockCall(
            LibRainDeploy.ZOLTU_FACTORY,
            type(MockDeployable).creationCode,
            abi.encodePacked(bytes20(LibRainDeploy.ZOLTU_FACTORY))
        );

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedAddress.selector, mockDeployableAddress(), LibRainDeploy.ZOLTU_FACTORY
            )
        );
        this.externalDeployToNetworks(
            networks,
            address(this),
            type(MockDeployable).creationCode,
            "test/concrete/MockDeployable.sol:MockDeployable",
            mockDeployableAddress(),
            mockDeployableCodeHash(),
            dependencies
        );
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

    /// `checkResolvedAddresses` MUST pass when the deployed contract holds the
    /// address the deployment expects.
    function testCheckResolvedAddressesMatch(bytes32 name, address account) external {
        vm.assume(account != address(0));
        (, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);

        LibRainDeploy.checkResolvedAddresses("test_network", address(consumer), ownerReadCalls(), expected(account));
    }

    /// The check is against settled state, which is the entire point of running
    /// it after the deploy rather than before. Re-binding the name afterwards
    /// changes what the registry answers but cannot change what the deployed
    /// contract holds, so the check still passes against the address the
    /// deployment actually took.
    function testCheckResolvedAddressesUnaffectedByRebinding(bytes32 name, address account, address rebound) external {
        vm.assume(account != address(0));
        vm.assume(rebound != address(0));
        vm.assume(rebound != account);
        (IAddressRegistryV1 registry, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);

        vm.prank(ADDRESS_REGISTRY_ROOT);
        registry.register(name, rebound);
        assertEq(registry.get(name), rebound);

        assertEq(consumer.iOwner(), account);
        LibRainDeploy.checkResolvedAddresses("test_network", address(consumer), ownerReadCalls(), expected(account));

        // And the value the registry now answers with is NOT what this
        // deployment holds, so a check against it fails.
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                "test_network",
                address(consumer),
                uint256(0),
                rebound,
                account
            )
        );
        this.externalCheckResolvedAddresses("test_network", address(consumer), ownerReadCalls(), expected(rebound));
    }

    /// `checkResolvedAddresses` MUST revert with `UnexpectedResolvedAddress`
    /// when the deployed contract holds something else, naming the network and
    /// which read disagreed.
    function testCheckResolvedAddressesMismatchReverts(bytes32 name, address account, address wrong) external {
        vm.assume(account != address(0));
        vm.assume(wrong != account);
        (, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                "test_network",
                address(consumer),
                uint256(0),
                wrong,
                account
            )
        );
        this.externalCheckResolvedAddresses("test_network", address(consumer), ownerReadCalls(), expected(wrong));
    }

    /// `checkResolvedAddresses` MUST check every read, not only the first, so a
    /// later value that disagrees is still caught.
    function testCheckResolvedAddressesChecksEveryRead(bytes32 name, address account, address wrong) external {
        vm.assume(account != address(0));
        vm.assume(wrong != account);
        (, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);

        bytes[] memory readCalls = new bytes[](2);
        readCalls[0] = abi.encodeWithSignature("iOwner()");
        readCalls[1] = abi.encodeWithSignature("iOwner()");
        address[] memory expectedAddresses = new address[](2);
        expectedAddresses[0] = account;
        expectedAddresses[1] = wrong;

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                "test_network",
                address(consumer),
                uint256(1),
                wrong,
                account
            )
        );
        this.externalCheckResolvedAddresses("test_network", address(consumer), readCalls, expectedAddresses);
    }

    /// A read that cannot be answered is never a pass. An address with no code
    /// static-calls successfully and returns nothing, which would compare equal
    /// to nothing at all if the length were not checked.
    function testCheckResolvedAddressesUnreadableTargetReverts(address target, address account) external {
        vm.assume(target.code.length == 0);
        // The low address space is reserved for precompiles, which have no code
        // and yet DO answer — the identity precompile echoes its calldata back,
        // so a read of one returns data rather than nothing. They are not
        // instances of the case under test. Bounded by the reserved range rather
        // than by listing today's precompiles, so a chain or fork that adds one
        // does not reintroduce this.
        vm.assume(uint160(target) > 0xffff);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedAddressReadFailed.selector, "test_network", target, uint256(0), bytes("")
            )
        );
        this.externalCheckResolvedAddresses("test_network", target, ownerReadCalls(), expected(account));
    }

    /// A read that reverts is never a pass either.
    function testCheckResolvedAddressesRevertingReadReverts(bytes32 name, address account) external {
        vm.assume(account != address(0));
        (, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);

        bytes[] memory readCalls = new bytes[](1);
        readCalls[0] = abi.encodeWithSignature("thisFunctionDoesNotExist()");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedAddressReadFailed.selector,
                "test_network",
                address(consumer),
                uint256(0),
                bytes("")
            )
        );
        this.externalCheckResolvedAddresses("test_network", address(consumer), readCalls, expected(account));
    }

    /// A read that answers with one word whose upper 96 bits are dirty has not
    /// answered with an address, and MUST be reported as
    /// `ResolvedAddressReadFailed` — the error whose stated subject is a read
    /// that answers with something that is not a single address-sized word.
    ///
    /// The expected address here is the word's own low 160 bits, so the only
    /// thing wrong with the answer is the dirty bits. That rules out both ways
    /// of getting this wrong at once: truncating the word silently PASSES this
    /// check against an address the read never gave, and decoding it as an
    /// address reverts inside the decoder with no return data at all — a bare
    /// revert naming neither the network, the target, nor which read produced
    /// it, which is exactly what this error exists to avoid.
    function testCheckResolvedAddressesDirtyWordReverts(bytes32 word) external {
        // Only the words that are not an address. A clean one is an address and
        // decodes, which is `testCheckResolvedAddressesMatch`'s case.
        vm.assume(uint256(word) > type(uint160).max);
        MockDirtyWordOwner target = new MockDirtyWordOwner(word);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedAddressReadFailed.selector,
                "test_network",
                address(target),
                uint256(0),
                abi.encode(word)
            )
        );
        this.externalCheckResolvedAddresses(
            "test_network", address(target), ownerReadCalls(), expected(address(uint160(uint256(word))))
        );
    }

    /// `checkResolvedAddresses` MUST revert when the reads and expected
    /// addresses do not pair up, rather than checking the shorter of the two.
    function testCheckResolvedAddressesLengthMismatchReverts(uint8 readCallsLength, uint8 expectedLength) external {
        vm.assume(readCallsLength != expectedLength);

        bytes[] memory readCalls = new bytes[](readCallsLength);
        address[] memory expectedAddresses = new address[](expectedLength);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedAddressesLengthMismatch.selector,
                uint256(readCallsLength),
                uint256(expectedLength)
            )
        );
        this.externalCheckResolvedAddresses("test_network", address(this), readCalls, expectedAddresses);
    }

    /// `checkResolvedAddressesOnNetworks` MUST revert with `NoNetworks` when
    /// given none, so an empty target set can never be mistaken for every read
    /// checking out.
    function testCheckResolvedAddressesOnNetworksNoNetworksReverts(address account) external {
        string[] memory networks = new string[](0);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckResolvedAddressesOnNetworks(networks, address(this), ownerReadCalls(), expected(account));
    }

    /// `checkResolvedAddressesOnNetworks` MUST check the reads and expected
    /// addresses pair up before it forks anything, so a mispaired call is
    /// reported without any network being reachable at all.
    function testCheckResolvedAddressesOnNetworksLengthMismatchRevertsBeforeForking() external {
        string[] memory networks = new string[](1);
        // Not a configured RPC alias, so forking it is itself an error.
        networks[0] = "unconfigured_network";
        bytes[] memory readCalls = new bytes[](2);
        address[] memory expectedAddresses = new address[](1);

        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.ResolvedAddressesLengthMismatch.selector, uint256(2), uint256(1))
        );
        this.externalCheckResolvedAddressesOnNetworks(networks, address(this), readCalls, expectedAddresses);
    }

    /// `checkResolvedAddressesOnNetworks` MUST fork each network in turn and
    /// pass when the deployed contract holds the expected address on all of
    /// them. The deployment is made persistent so the same contract is present
    /// on every fork, which is the state a real multi-network deploy leaves
    /// behind.
    ///
    /// Two networks rather than `supportedNetworks()`. What is under test is
    /// that the loop visits every network it is given, which two prove as well
    /// as five; the roster itself is `testSupportedNetworks`'s job. These are
    /// the two networks the rest of this suite forks, so the test does not
    /// depend on the reliability of RPC endpoints nothing else here touches.
    function testCheckResolvedAddressesOnNetworksEachNetwork() external {
        bytes32 name = keccak256("testCheckResolvedAddressesOnNetworksEachNetwork");
        address account = address(0xf00);
        (, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);
        vm.makePersistent(address(consumer));

        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.BASE;

        LibRainDeploy.checkResolvedAddressesOnNetworks(
            vm, networks, address(consumer), ownerReadCalls(), expected(account)
        );
    }

    /// `checkResolvedAddressesOnNetworks` MUST fail on the network that
    /// disagrees, and MUST name it.
    function testCheckResolvedAddressesOnNetworksMismatchReverts() external {
        bytes32 name = keccak256("testCheckResolvedAddressesOnNetworksMismatchReverts");
        address account = address(0xf00);
        address wrong = address(0xba4);
        (, MockResolvedOwner consumer) = deployRegistryAndConsumer(name, account);
        vm.makePersistent(address(consumer));

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.BASE;

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                LibRainDeploy.BASE,
                address(consumer),
                uint256(0),
                wrong,
                account
            )
        );
        this.externalCheckResolvedAddressesOnNetworks(networks, address(consumer), ownerReadCalls(), expected(wrong));
    }

    /// `deployToNetworks` MUST deploy when every dependency has code on the
    /// network, i.e. a present dependency is not treated as missing.
    function testDeployToNetworksPresentDependencyDeploys() external {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](1);
        dependencies[0] = LibRainDeploy.ZOLTU_FACTORY;

        address result = this.externalDeployToNetworks(
            networks,
            address(this),
            type(MockDeployable).creationCode,
            "test/concrete/MockDeployable.sol:MockDeployable",
            mockDeployableAddress(),
            mockDeployableCodeHash(),
            dependencies
        );
        assertEq(result, mockDeployableAddress());
        assertEq(result.codehash, mockDeployableCodeHash());
    }

    /// `isStartBlock` MUST return true at block 0 for a target that already
    /// has the expected code hash in the genesis allocation. There is no block
    /// before genesis, so the code hash at the given block alone decides.
    function testIsStartBlockGenesisAllocationAtBlockZero() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertTrue(LibRainDeploy.isStartBlock(vm, BASE_GENESIS_PREDEPLOY, BASE_GENESIS_PREDEPLOY_CODEHASH, 0));
    }

    /// `isStartBlock` MUST return false at block 1 for a target from the
    /// genesis allocation, because block 0 already has the same code hash.
    function testIsStartBlockGenesisAllocationAtBlockOne() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertFalse(LibRainDeploy.isStartBlock(vm, BASE_GENESIS_PREDEPLOY, BASE_GENESIS_PREDEPLOY_CODEHASH, 1));
    }

    /// `isStartBlock` MUST return false for the block immediately after the
    /// deploy block. The block compared against is the immediately preceding
    /// one, which already has the expected code hash.
    function testIsStartBlockOneBlockAfterDeployBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertFalse(
            LibRainDeploy.isStartBlock(
                vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, ZOLTU_BASE_DEPLOY_BLOCK + 1
            )
        );
    }

    /// `findDeployBlock` MUST return the exact block at which the target first
    /// has the expected code hash, including when that is the block the fork is
    /// currently at.
    function testFindDeployBlockExactZoltuBaseDeployBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE, ZOLTU_BASE_DEPLOY_BLOCK);
        assertEq(
            LibRainDeploy.findDeployBlock(vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, 0),
            ZOLTU_BASE_DEPLOY_BLOCK
        );
    }

    /// `findDeployBlock` MUST leave the fork on its original block when it
    /// reverts because the target already has the expected code hash at the
    /// start block.
    function testFindDeployBlockRestoresForkOnDeployedBeforeStartBlockRevert() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 originalBlock = block.number;
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DeployedBeforeStartBlock.selector, LibRainDeploy.ZOLTU_FACTORY, ZOLTU_BASE_DEPLOY_BLOCK
            )
        );
        this.externalFindDeployBlock(
            LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, ZOLTU_BASE_DEPLOY_BLOCK
        );
        assertEq(block.number, originalBlock);
    }

    /// `deployZoltu` MUST revert when the factory call succeeds but leaves no
    /// code at the resulting address. Empty creation code creates an account
    /// with no runtime code, which is not a deployment.
    function testDeployZoltuRevertsEmptyCreationCode() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, true, ZOLTU_EMPTY_CREATION_CODE_ADDRESS)
        );
        this.externalDeployZoltu(hex"");
    }

    /// `deployZoltu` MUST NOT report a deployment when the factory call fails,
    /// even when the failed call leaves the address of a contract that does
    /// have code in the call output buffer.
    function testDeployZoltuRevertsWhenFactoryCallFailsWithAddressData() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, address(new MockAddressRevertingFactory()).code);
        assertGt(LibRainDeploy.ZOLTU_FACTORY.code.length, 0);

        vm.expectPartialRevert(LibRainDeploy.DeployFailed.selector);
        this.externalDeployZoltu(type(MockDeployable).creationCode);
    }

    /// `deployZoltu` MUST NOT report the zero address as a deployment, even
    /// when the zero address has code.
    function testDeployZoltuRevertsZeroAddressWithCode() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        // A call to an address with no code succeeds and returns nothing, so
        // the factory yields the zero address.
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, hex"");
        vm.etch(address(0), hex"00");
        assertGt(address(0).code.length, 0);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, true, address(0)));
        this.externalDeployZoltu(type(MockDeployable).creationCode);
    }

    /// `deployZoltu` MUST NOT forward the caller's value to the factory. The
    /// deployed mock has a non payable constructor, so forwarded value would
    /// fail the deployment outright.
    function testDeployZoltuDoesNotForwardValue() external {
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        vm.deal(address(this), 1 ether);
        address deployed = this.externalDeployZoltuPayable{value: 1}(type(MockDeployable).creationCode);
        assertEq(deployed, mockDeployableAddress());
        assertEq(deployed.balance, 0);
        assertEq(LibRainDeploy.ZOLTU_FACTORY.balance, 0);
    }

    /// `deployAndBroadcast` MUST broadcast as the address derived from the
    /// given private key.
    function testDeployAndBroadcastUsesDeployerFromPrivateKey() external {
        uint256 deployerPrivateKey = 0xA11CE;
        address deployer = vm.addr(deployerPrivateKey);

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        address[] memory dependencies = new address[](0);

        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);
        // Stated rather than assumed: the key is a test constant that has never
        // transacted on any supported network, so its nonce is zero on a fresh
        // fork. That is what makes the nonce read after the call — which lands
        // on the fork `deployToNetworks` made, not this one — comparable to
        // this baseline at all.
        uint64 nonceBefore = vm.getNonce(deployer);
        assertEq(nonceBefore, 0);

        this.externalDeployAndBroadcast(
            networks,
            deployerPrivateKey,
            type(MockDeployable).creationCode,
            "test/concrete/MockDeployable.sol:MockDeployable",
            mockDeployableAddress(),
            mockDeployableCodeHash(),
            dependencies
        );

        assertEq(vm.getNonce(deployer), nonceBefore + 1);
    }
}
