// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration, DeployDependency, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {IDescribedByMetaV1} from "rain-metadata-0.1.43/src/interface/IDescribedByMetaV1.sol";
import {RainDeployVerifySnapshotBase} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {DescribedByMetaMismatch, MetaBoardUndeclared} from "../../../src/lib/LibRainDeployDescribedByMeta.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
import {
    LibMockCreate2Mechanism,
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_SALT,
    MockCreate2Mechanism
} from "../../lib/LibMockCreate2Mechanism.sol";
import {MockNetworkDeploy} from "../../lib/LibMockNetworkRecord.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDescribedByMeta} from "../../concrete/MockDescribedByMeta.sol";

contract RainDeployVerifySnapshotBaseDescribedByMetaTest is ExampleDeploySuites, RainDeployVerifySnapshotBase {
    address constant META_BOARD = address(0x4d455441);

    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        addExample(d);
        return d;
    }

    function externalCheckInternallyConsistent(address metaBoard, DeploySuite memory suite) external {
        DeployDeclaration memory d = declaration();
        d.metaBoard = metaBoard;
        checkInternallyConsistent(d, suite);
    }

    function externalCheckDescribedByMeta(DeploySuite memory suite) external {
        DeployDeclaration memory d = declaration();
        LibMockCreate2Mechanism.extend(d);
        d.metaBoard = META_BOARD;
        checkDescribedByMeta(d, suite);
    }

    function zoltuSuite(bytes memory creationCode, bytes memory runtimeCode, bytes memory meta)
        internal
        pure
        returns (DeploySuite memory)
    {
        return DeploySuite({
            networks: LibRainDeploy.supportedNetworks(),
            suite: "described@0_0_1",
            creationCode: creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(creationCode),
            storedBytecodeHash: keccak256(runtimeCode),
            storedRuntimeCode: runtimeCode,
            artifactPath: "test/concrete/MockDescribedByMeta.sol:MockDescribedByMeta",
            dependencies: new DeployDependency[](0),
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            describedByMeta: meta
        });
    }

    function describedSuite(bytes32 answer, bytes memory meta) internal pure returns (DeploySuite memory) {
        return zoltuSuite(
            abi.encodePacked(type(MockDescribedByMeta).creationCode, abi.encode(answer)),
            type(MockDescribedByMeta).runtimeCode,
            meta
        );
    }

    function describedNetwork(bytes memory creationCode, uint256 chainId)
        internal
        pure
        returns (MockNetworkDeploy memory)
    {
        return LibMockCreate2Mechanism.network(
            MOCK_CREATE2_FACTORY, MOCK_CREATE2_SALT, creationCode, chainId, abi.encode(chainId)
        );
    }

    function perNetworkDescribedSuite(bytes memory creationCode, bytes memory meta, MockNetworkDeploy[] memory recorded)
        internal
        pure
        returns (DeploySuite memory)
    {
        DeploySuite memory suite = zoltuSuite(creationCode, type(MockDescribedByMeta).runtimeCode, meta);
        string[] memory networks = new string[](2);
        networks[0] = LibMockCreate2Mechanism.networkName(42161);
        networks[1] = LibMockCreate2Mechanism.networkName(137);
        suite.networks = networks;
        suite.storedDeployedAddress = address(0);
        suite.mechanismData = LibMockCreate2Mechanism.encode(
            MockCreate2Mechanism({
                factory: MOCK_CREATE2_FACTORY, salt: MOCK_CREATE2_SALT, perNetwork: true, networks: recorded, root: ""
            })
        );
        return suite;
    }

    function testAConsistentDescribedSuitePassesAndLeavesNoCode(bytes memory meta) external {
        vm.assume(meta.length != 0);
        DeploySuite memory suite = describedSuite(keccak256(meta), meta);
        this.externalCheckInternallyConsistent(META_BOARD, suite);
        assertEq(suite.storedDeployedAddress.code.length, 0);
    }

    function testADescribedSuiteRefusesAnUndeclaredMetaBoard(bytes memory meta) external {
        vm.assume(meta.length != 0);
        DeploySuite memory suite = describedSuite(keccak256(meta), meta);
        vm.expectRevert(abi.encodeWithSelector(MetaBoardUndeclared.selector, suite.suite));
        this.externalCheckInternallyConsistent(address(0), suite);
    }

    function testADeploymentAnsweringAnotherHashIsAMismatch(bytes memory meta, bytes32 answer) external {
        vm.assume(meta.length != 0);
        vm.assume(answer != keccak256(meta));
        DeploySuite memory suite = describedSuite(answer, meta);
        vm.expectRevert(
            abi.encodeWithSelector(
                DescribedByMetaMismatch.selector,
                suite.suite,
                suite.storedDeployedAddress,
                true,
                answer,
                keccak256(meta)
            )
        );
        this.externalCheckInternallyConsistent(META_BOARD, suite);
    }

    function testADeploymentAnsweringNothingIsAMismatch(bytes memory meta) external {
        vm.assume(meta.length != 0);
        DeploySuite memory suite = zoltuSuite(type(MockDeployable).creationCode, type(MockDeployable).runtimeCode, meta);
        vm.expectRevert(
            abi.encodeWithSelector(
                DescribedByMetaMismatch.selector,
                suite.suite,
                suite.storedDeployedAddress,
                false,
                bytes32(0),
                keccak256(meta)
            )
        );
        this.externalCheckInternallyConsistent(META_BOARD, suite);
    }

    function testANetworkDeployingNothingLocallyIsNotCheckedAndTheNextIs(bytes memory meta) external {
        vm.assume(meta.length != 0);
        bytes memory creationCode = abi.encodePacked(type(MockDescribedByMeta).creationCode, abi.encode(keccak256(meta)));
        MockNetworkDeploy[] memory recorded = new MockNetworkDeploy[](1);
        recorded[0] = describedNetwork(creationCode, 137);
        vm.expectCall(recorded[0].deployedAddress, abi.encodeCall(IDescribedByMetaV1.describedByMetaV1, ()), 1);
        this.externalCheckDescribedByMeta(perNetworkDescribedSuite(creationCode, meta, recorded));
    }

    function testALaterLocalDeploymentAnsweringAnotherHashIsAMismatch(bytes memory meta, bytes32 answer) external {
        vm.assume(meta.length != 0);
        vm.assume(answer != keccak256(meta));
        bytes memory creationCode = abi.encodePacked(type(MockDescribedByMeta).creationCode, abi.encode(keccak256(meta)));
        MockNetworkDeploy[] memory recorded = new MockNetworkDeploy[](2);
        recorded[0] = describedNetwork(creationCode, 42161);
        recorded[1] = describedNetwork(creationCode, 137);
        DeploySuite memory suite = perNetworkDescribedSuite(creationCode, meta, recorded);
        address later = recorded[1].deployedAddress;
        vm.mockCall(later, abi.encodeCall(IDescribedByMetaV1.describedByMetaV1, ()), abi.encode(answer));
        vm.expectRevert(
            abi.encodeWithSelector(DescribedByMetaMismatch.selector, suite.suite, later, true, answer, keccak256(meta))
        );
        this.externalCheckDescribedByMeta(suite);
    }

    function testASuiteCarryingNoMetaNeedsNoMetaBoardNorAnAnswer() external {
        this.externalCheckInternallyConsistent(
            address(0), zoltuSuite(type(MockDeployable).creationCode, type(MockDeployable).runtimeCode, "")
        );
    }
}
