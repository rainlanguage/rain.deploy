// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibRainDeployTestBase} from "../../abstract/LibRainDeployTestBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockResolvedOwner} from "../../concrete/MockResolvedOwner.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

/// @title LibRainDeployChainTest
/// The `LibRainDeploy` tests that genuinely read a chain, and so cannot run
/// without a reachable RPC endpoint for every network they name. Three kinds,
/// and nothing else belongs here:
///
/// 1. The fork-history search. `isStartBlock` and `findDeployBlock` roll a fork
///    backwards and read the target's code hash at each block, so their subject
///    IS a chain's history — there is nothing to etch.
/// 2. The Zoltu factory pins. `ZOLTU_FACTORY_CODEHASH` and
///    `ZOLTU_FACTORY_BYTECODE` are constants asserted against the factory as
///    actually deployed, and `testDeployZoltu` / `testZoltuAddressMatchesFactoryDeploy`
///    take the LIVE factory as the oracle for the derivation. Etching any of
///    them would leave the constants checking themselves.
/// 3. Everything that reaches `deployToNetworks`' or
///    `checkResolvedAddressesOnNetworks`' per-network loop, both of which call
///    `vm.createSelectFork` themselves. The loop is the thing under test, so it
///    cannot be avoided from here.
///
/// `Chain` in the name is what selects it: `forge test --no-match-contract
/// Chain` excludes this contract, so a red there is never an endpoint. Its
/// sibling `LibRainDeployTest` is the rest, and forks nothing.
contract LibRainDeployChainTest is LibRainDeployTestBase {
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

    /// `deployZoltu` MUST deploy a contract via the Zoltu factory and return
    /// the deterministic address the factory derives with `CREATE2` over the
    /// creation code under a zero salt.
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
