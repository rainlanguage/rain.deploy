// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    CLONE_ARTIFACT_PATH,
    CloneNetwork,
    CloneNetworks,
    CloneTarget,
    LibRainDeployClone
} from "../../../src/lib/LibRainDeployClone.sol";
import {
    ExtendedNetworkUnfrozen,
    LibRainDeployMechanism,
    UnverifiableSource
} from "../../../src/lib/LibRainDeployMechanism.sol";
import {DeployMechanism, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    exampleCloneDependencies,
    exampleCloneFactory,
    exampleCloneImplementation
} from "../../abstract/ExampleCloneDeploys.sol";
import {ZoltuDeployOrAdopt} from "../../abstract/ZoltuDeployOrAdopt.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";

contract LibRainDeployMechanismBroadcastTest is ZoltuDeployOrAdopt {
    bytes32 constant TEST_SALT = 0x1122334455667788990011223344556677889900112233445566778899001122;

    bytes constant TEST_DATA = hex"deadbeefcafe0102030405060708090a0b0c0d0e0f";

    function localClone(address factory, address implementation) internal pure returns (CloneTarget memory) {
        return CloneTarget({factory: factory, implementation: implementation, data: TEST_DATA, salt: TEST_SALT});
    }

    function cloneSuite(
        CloneTarget memory clone,
        address recordedAddress,
        bytes32 codeHash,
        DeployDependency[] memory dependencies
    ) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "clone",
            creationCode: LibRainDeployClone.cloneCreationCode(clone.implementation),
            storedDeployedAddress: recordedAddress,
            storedBytecodeHash: codeHash,
            storedRuntimeCode: "",
            artifactPath: CLONE_ARTIFACT_PATH,
            dependencies: dependencies,
            mechanism: DeployMechanism.Clone,
            mechanismData: abi.encode(clone)
        });
    }

    function exampleCloneNetworks() internal pure returns (CloneNetworks memory) {
        CloneNetworks memory clones = CloneNetworks({
            factory: exampleCloneFactory(),
            implementation: exampleCloneImplementation(),
            salt: TEST_SALT,
            networks: new CloneNetwork[](2)
        });
        clones.networks[0] =
            CloneNetwork({chainId: 42161, data: abi.encode(uint256(42161)), deployedAddress: address(0)});
        clones.networks[1] = CloneNetwork({chainId: 137, data: abi.encode(uint256(137)), deployedAddress: address(0)});
        for (uint256 i = 0; i < clones.networks.length; i++) {
            clones.networks[i].deployedAddress =
                LibRainDeployClone.cloneDeployedAddress(LibRainDeployClone.cloneNetworkTarget(clones, i));
        }
        return clones;
    }

    function perNetworkSuite(CloneNetworks memory clones) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "clone-per-network",
            creationCode: LibRainDeployClone.cloneCreationCode(clones.implementation),
            storedDeployedAddress: address(0),
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: CLONE_ARTIFACT_PATH,
            dependencies: exampleCloneDependencies(),
            mechanism: DeployMechanism.ClonePerNetwork,
            mechanismData: abi.encode(clones)
        });
    }

    function zoltuSuite(address recordedAddress) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "zoltu",
            creationCode: type(MockCloneable).creationCode,
            storedDeployedAddress: recordedAddress,
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: "test/concrete/MockCloneable.sol:MockCloneable",
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
    }

    function externalDeployAndBroadcast(string[] memory networks, uint256 deployerPrivateKey, DeploySuite memory suite)
        external
        returns (address[] memory, uint256[] memory)
    {
        return LibRainDeployMechanism.deployAndBroadcast(vm, networks, deployerPrivateKey, suite, suite);
    }

    /// External wrapper for `LibRainDeployMechanism.deployAndBroadcast` on a given fork Vm, as key 1.
    /// @param forkVm The Vm to fork and broadcast with.
    /// @param networks The networks to broadcast to.
    /// @param suite The suite to broadcast.
    /// @return Where the suite is on each network.
    function externalDeployAndBroadcastOn(Vm forkVm, string[] memory networks, DeploySuite memory suite)
        external
        returns (address[] memory)
    {
        (address[] memory deployed,) = LibRainDeployMechanism.deployAndBroadcast(forkVm, networks, 1, suite, suite);
        return deployed;
    }

    /// A clone broadcast formats no verify command, even under a compiled artifact's path.
    function testCloneBroadcastPrintsNoVerifyCommand() external {
        address factory = LibRainDeploy.etchAndDeployZoltu(vm, type(MockCloneFactory).creationCode);
        address implementation = LibRainDeploy.etchAndDeployZoltu(vm, type(MockCloneable).creationCode);
        CloneTarget memory clone = localClone(factory, implementation);
        address expected = LibRainDeployClone.cloneDeployedAddress(clone);
        DeploySuite memory suite = cloneSuite(
            clone, expected, LibRainDeployClone.cloneDeployedCodehash(implementation), exampleCloneDependencies()
        );
        suite.artifactPath = "test/concrete/MockCloneable.sol:MockCloneable";
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        LocalForkVm forkVm = new LocalForkVm();
        vm.expectCall(address(forkVm), abi.encodeWithSelector(LocalForkVm.toString.selector), 0);
        address[] memory deployed = this.externalDeployAndBroadcastOn(Vm(address(forkVm)), networks, suite);
        assertEq(deployed.length, 1);
        assertEq(deployed[0], expected);
        assertEq(deployed[0].code, LibRainDeployClone.cloneRuntimeCode(implementation));
    }

    /// A Zoltu broadcast under `CLONE_ARTIFACT_PATH` formats no verify command, and instead one notice naming the
    /// deployed address once, whose source needs verifying by hand on each network, emitted as `UnverifiableSource`
    /// with the caller, not the test contract, as its sender.
    function testZoltuBroadcastUnderTheCloneArtifactPathPrintsAManualVerificationNotice() external {
        LibRainDeploy.etchZoltuFactory(vm);
        DeploySuite memory suite = zoltuSuite(LibRainDeploy.zoltuAddress(type(MockCloneable).creationCode));
        suite.storedBytecodeHash = keccak256(type(MockCloneable).runtimeCode);
        suite.artifactPath = CLONE_ARTIFACT_PATH;
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;

        address caller = makeAddr("broadcast caller");
        LocalForkVm forkVm = new LocalForkVm();
        vm.expectCall(address(forkVm), abi.encodeWithSelector(LocalForkVm.toString.selector), 1);
        vm.expectCall(
            address(forkVm), abi.encodeWithSelector(LocalForkVm.toString.selector, suite.storedDeployedAddress), 1
        );
        vm.expectEmit(address(this));
        emit UnverifiableSource(caller, suite.storedDeployedAddress, networks);
        vm.prank(caller);
        address[] memory deployed = this.externalDeployAndBroadcastOn(Vm(address(forkVm)), networks, suite);
        assertEq(deployed.length, 2);
        assertEq(deployed[0], suite.storedDeployedAddress);
        assertEq(deployed[1], suite.storedDeployedAddress);
        assertEq(deployed[0].code, type(MockCloneable).runtimeCode);
    }

    /// A per-network clone broadcast formats no verify command and no notice, even under a compiled artifact's path.
    function testPerNetworkBroadcastUnderACompiledArtifactPrintsNoVerifyCommand() external {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MockCloneFactory).creationCode);
        address implementation = LibRainDeploy.etchAndDeployZoltu(vm, type(MockCloneable).creationCode);
        CloneNetworks memory clones = exampleCloneNetworks();
        DeploySuite memory suite = perNetworkSuite(clones);
        suite.storedBytecodeHash = LibRainDeployClone.cloneDeployedCodehash(implementation);
        suite.artifactPath = "test/concrete/MockCloneable.sol:MockCloneable";
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        LocalForkVm forkVm = new LocalForkVm();
        vm.expectCall(address(forkVm), abi.encodeWithSelector(LocalForkVm.toString.selector), 0);
        address[] memory deployed = this.externalDeployAndBroadcastOn(Vm(address(forkVm)), networks, suite);
        assertEq(deployed.length, 2);
        assertEq(deployed[0], clones.networks[0].deployedAddress);
        assertEq(deployed[1], clones.networks[1].deployedAddress);
    }

    /// A Zoltu broadcast under a compiled artifact path formats one verify command per network and emits no
    /// `UnverifiableSource`.
    function testZoltuBroadcastUnderACompiledArtifactPrintsVerifyCommands() external {
        LibRainDeploy.etchZoltuFactory(vm);
        DeploySuite memory suite = zoltuSuite(LibRainDeploy.zoltuAddress(type(MockCloneable).creationCode));
        suite.storedBytecodeHash = keccak256(type(MockCloneable).runtimeCode);
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        LocalForkVm forkVm = new LocalForkVm();
        vm.expectCall(
            address(forkVm), abi.encodeWithSelector(LocalForkVm.toString.selector, suite.storedDeployedAddress), 2
        );
        vm.recordLogs();
        this.externalDeployAndBroadcastOn(Vm(address(forkVm)), networks, suite);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics.length == 0 || logs[i].topics[0] != UnverifiableSource.selector);
        }
    }

    function anyForkExists() internal returns (bool) {
        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        return forked;
    }

    function walletsHold(address account) internal view returns (bool) {
        address[] memory wallets = vm.getWallets();
        for (uint256 i = 0; i < wallets.length; i++) {
            if (wallets[i] == account) {
                return true;
            }
        }
        return false;
    }

    function arbitrumAndPolygon() internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        return networks;
    }

    /// Key zero has no wallet, so `NoNetworks` proves the list is refused before the key, and a
    /// stale recorded address proves it is refused before the address check.
    function testNoNetworksRevertsBeforeTheKeyAndTheAddress() external {
        CloneTarget memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        address stale = address(uint160(LibRainDeployClone.cloneDeployedAddress(clone)) + 1);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalDeployAndBroadcast(
            new string[](0), 0, cloneSuite(clone, stale, bytes32(0), exampleCloneDependencies())
        );

        CloneNetworks memory clones = exampleCloneNetworks();
        clones.networks[0].deployedAddress = address(1);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalDeployAndBroadcast(new string[](0), 0, perNetworkSuite(clones));

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalDeployAndBroadcast(new string[](0), 0, zoltuSuite(address(1)));
    }

    /// External wrapper for `LibRainDeployMechanism.deployAndBroadcast` against a separate frozen suite, as key 1.
    /// @param networks The networks to broadcast to.
    /// @param frozen The suite with its extended networks.
    /// @param suite The suite to broadcast.
    function externalDeployAndBroadcastFrozen(
        string[] memory networks,
        DeploySuite memory frozen,
        DeploySuite memory suite
    ) external {
        LibRainDeployMechanism.deployAndBroadcast(vm, networks, 1, frozen, suite);
    }

    /// The library entry point refuses a per-network suite on a network its frozen suite neither records nor
    /// declares, before any fork.
    function testDeployAndBroadcastRefusesAnUnfrozenNetworkBeforeForking() external {
        CloneNetworks memory clones = exampleCloneNetworks();
        DeploySuite memory onNetworks = perNetworkSuite(clones);
        CloneNetworks memory recorded = exampleCloneNetworks();
        recorded.networks = new CloneNetwork[](1);
        recorded.networks[0] = clones.networks[0];

        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector,
                onNetworks.suite,
                LibRainDeploy.POLYGON,
                clones.networks[1].deployedAddress
            )
        );
        this.externalDeployAndBroadcastFrozen(arbitrumAndPolygon(), perNetworkSuite(recorded), onNetworks);
        assertFalse(anyForkExists());
    }

    function testZoltuStaleRecordedAddressRevertsBeforeForking() external {
        address derived = LibRainDeploy.zoltuAddress(type(MockCloneable).creationCode);
        address stale = address(uint160(derived) + 1);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, stale, derived));
        this.externalDeployAndBroadcast(arbitrumAndPolygon(), 1, zoltuSuite(stale));
        assertFalse(anyForkExists());
    }

    function testCloneStaleRecordedAddressRevertsBeforeForking() external {
        CloneTarget memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        address derived = LibRainDeployClone.cloneDeployedAddress(clone);
        address stale = address(uint160(derived) + 1);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, stale, derived));
        this.externalDeployAndBroadcast(
            arbitrumAndPolygon(), 1, cloneSuite(clone, stale, bytes32(0), exampleCloneDependencies())
        );
        assertFalse(anyForkExists());
    }

    /// The SECOND network is staled, so a check of only the first passes it.
    function testPerNetworkStaleRecordedAddressRevertsBeforeForking() external {
        CloneNetworks memory clones = exampleCloneNetworks();
        address derived = clones.networks[1].deployedAddress;
        address stale = address(uint160(derived) + 1);
        clones.networks[1].deployedAddress = stale;

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, stale, derived));
        this.externalDeployAndBroadcast(arbitrumAndPolygon(), 1, perNetworkSuite(clones));
        assertFalse(anyForkExists());
    }

    function testPerNetworkUndeclaredNetworkRevertsBeforeForking() external {
        string[] memory networks = new string[](3);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        networks[2] = LibRainDeploy.BASE;

        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.CloneNetworkUndeclared.selector, 8453));
        this.externalDeployAndBroadcast(networks, 1, perNetworkSuite(exampleCloneNetworks()));
        assertFalse(anyForkExists());
    }

    function testPerNetworkDuplicateChainIdRevertsBeforeForking() external {
        CloneNetworks memory clones = exampleCloneNetworks();
        clones.networks[1].chainId = 42161;
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.DuplicateCloneNetwork.selector, 42161));
        this.externalDeployAndBroadcast(networks, 1, perNetworkSuite(clones));
        assertFalse(anyForkExists());
    }

    function testCloneUndeclaredFactoryReverts() external {
        CloneTarget memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        DeployDependency[] memory dependencies = new DeployDependency[](1);
        dependencies[0] = exampleCloneDependencies()[1];

        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, clone.factory));
        this.externalDeployAndBroadcast(
            arbitrumAndPolygon(),
            1,
            cloneSuite(clone, LibRainDeployClone.cloneDeployedAddress(clone), bytes32(0), dependencies)
        );
    }

    function testCloneUndeclaredImplementationReverts() external {
        CloneTarget memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        DeployDependency[] memory dependencies = new DeployDependency[](1);
        dependencies[0] = exampleCloneDependencies()[0];

        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, clone.implementation)
        );
        this.externalDeployAndBroadcast(
            arbitrumAndPolygon(),
            1,
            cloneSuite(clone, LibRainDeployClone.cloneDeployedAddress(clone), bytes32(0), dependencies)
        );
    }

    function testCloneUndeclaredDependencyRefusedBeforeTheAddress() external {
        CloneTarget memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        address stale = address(uint160(LibRainDeployClone.cloneDeployedAddress(clone)) + 1);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, clone.factory));
        this.externalDeployAndBroadcast(
            arbitrumAndPolygon(), 1, cloneSuite(clone, stale, bytes32(0), new DeployDependency[](0))
        );
    }

    function testCloneChangedFactoryReverts() external {
        vm.makePersistent(address(this));
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);

        address factory = zoltuDeployOrAdopt(type(MockCloneFactory).creationCode, type(MockCloneFactory).runtimeCode);
        vm.makePersistent(factory);
        address implementation = zoltuDeployOrAdopt(type(MockCloneable).creationCode, type(MockCloneable).runtimeCode);
        vm.makePersistent(implementation);

        CloneTarget memory clone = localClone(factory, implementation);
        DeployDependency[] memory dependencies = exampleCloneDependencies();
        dependencies[0].runtimeCode = type(MockCloneable).runtimeCode;

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.ARBITRUM_ONE,
                factory,
                keccak256(type(MockCloneable).runtimeCode),
                factory.codehash
            )
        );
        this.externalDeployAndBroadcast(
            networks,
            1,
            cloneSuite(
                clone,
                LibRainDeployClone.cloneDeployedAddress(clone),
                LibRainDeployClone.cloneDeployedCodehash(implementation),
                dependencies
            )
        );
    }

    function testCloneDeploysThenSkipsOnRerun() external {
        vm.makePersistent(address(this));
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);

        address factory = zoltuDeployOrAdopt(type(MockCloneFactory).creationCode, type(MockCloneFactory).runtimeCode);
        assertEq(factory, exampleCloneFactory());
        vm.makePersistent(factory);
        address implementation = zoltuDeployOrAdopt(type(MockCloneable).creationCode, type(MockCloneable).runtimeCode);
        assertEq(implementation, exampleCloneImplementation());
        vm.makePersistent(implementation);

        CloneTarget memory clone = localClone(factory, implementation);
        address expected = LibRainDeployClone.cloneDeployedAddress(clone);
        bytes32 expectedCodeHash = LibRainDeployClone.cloneDeployedCodehash(implementation);
        DeploySuite memory suite = cloneSuite(clone, expected, expectedCodeHash, exampleCloneDependencies());

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        assertEq(expected.code.length, 0);

        (address[] memory deployed,) = this.externalDeployAndBroadcast(networks, 1, suite);
        assertEq(deployed[0], expected);
        assertEq(deployed[0].codehash, expectedCodeHash);
        assertEq(deployed[0].code, LibRainDeployClone.cloneRuntimeCode(implementation));

        vm.makePersistent(deployed[0]);
        (address[] memory again,) = this.externalDeployAndBroadcast(networks, 1, suite);
        assertEq(again[0], expected);
        assertEq(again[0].codehash, expectedCodeHash);
    }

    function testCloneReachesEveryNetworkAsTheRememberedKey() external {
        vm.makePersistent(address(this));
        string[] memory networks = arbitrumAndPolygon();

        CloneTarget memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        address expected = LibRainDeployClone.cloneDeployedAddress(clone);
        bytes32 expectedCodeHash = LibRainDeployClone.cloneDeployedCodehash(exampleCloneImplementation());

        address deployer = vm.addr(1);
        assertFalse(walletsHold(deployer));

        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            address factory =
                zoltuDeployOrAdopt(type(MockCloneFactory).creationCode, type(MockCloneFactory).runtimeCode);
            assertEq(factory, exampleCloneFactory());
            address implementation =
                zoltuDeployOrAdopt(type(MockCloneable).creationCode, type(MockCloneable).runtimeCode);
            assertEq(implementation, exampleCloneImplementation());
            vm.makePersistent(factory);
            vm.makePersistent(implementation);
            assertEq(expected.code.length, 0, networks[i]);
        }

        (address[] memory deployed, uint256[] memory forkIds) = this.externalDeployAndBroadcast(
            networks, 1, cloneSuite(clone, expected, expectedCodeHash, exampleCloneDependencies())
        );
        assertEq(deployed.length, networks.length);
        assertEq(forkIds.length, networks.length);
        assertTrue(walletsHold(deployer));

        for (uint256 i = 0; i < forkIds.length; i++) {
            assertEq(deployed[i], expected);
            vm.selectFork(forkIds[i]);
            assertEq(expected.codehash, expectedCodeHash, networks[i]);
        }
    }
}
