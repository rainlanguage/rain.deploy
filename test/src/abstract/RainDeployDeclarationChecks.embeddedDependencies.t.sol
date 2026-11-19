// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    ExternalDeployment
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    DependencyRuntimeCodeMismatch,
    UndeclaredDependency,
    UnreachedDependency,
    ZeroRecordedAddress
} from "../../../src/abstract/RainDeployDeclarationChecks.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {MOCK_EXTERNAL_RUNTIME_CODE, ReachingDeploySuites} from "../../abstract/ReachingDeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {
    LibMockCreate2Mechanism,
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_SALT,
    MockCreate2Mechanism
} from "../../lib/LibMockCreate2Mechanism.sol";
import {MockNetworkDeploy} from "../../lib/LibMockNetworkRecord.sol";
import {MOCK_DEPLOYABLE_ADDRESS, MOCK_EXTERNAL_ADDRESS} from "../../concrete/MockReachingDeployable.sol";

bytes constant STOP = hex"00";

address constant PER_NETWORK_ADDRESS = address(uint160(uint256(keccak256("rain.deploy.mock.per-network"))));

address constant LATER_NETWORK_ADDRESS = address(uint160(uint256(keccak256("rain.deploy.mock.per-network.later"))));

/// @title RainDeployDeclarationChecksEmbeddedDependenciesTest
/// @notice A suite embeds an address its reachable creation code pushes or its mechanism data holds, and declares
/// exactly the sibling and external deployments it embeds.
contract RainDeployDeclarationChecksEmbeddedDependenciesTest is ReachingDeploySuites {
    string constant SUITE = "mock-embedding";

    function declaration() internal pure override returns (DeployDeclaration memory) {
        return declarationWith(
            suiteOf(
                bytes.concat(pushAddress(MOCK_DEPLOYABLE_ADDRESS), pushAddress(MOCK_EXTERNAL_ADDRESS), STOP), both()
            )
        );
    }

    function declarationWith(DeploySuite memory suite) internal pure returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({snapshot: leafSuite("mock-deployable"), unanchorableReason: ""});
        candidates[1] = DeployCandidate({snapshot: suite, unanchorableReason: "Hand-assembled bytecode."});
        LibRainDeployDeclaration.addCandidates(d, candidates);
        d.externalDeployments = reachingExternalDeployments();
        return d;
    }

    function externalCheck(DeploySuite memory suite) external view {
        checkDependenciesAreTheEmbeddedDeployments(declarationWith(suite));
    }

    function externalCheckBeforeItsSibling(DeploySuite memory suite) external view {
        DeployDeclaration memory d = declarationWith(suite);
        (d.candidates[0], d.candidates[1]) = (d.candidates[1], d.candidates[0]);
        checkDependenciesAreTheEmbeddedDeployments(d);
    }

    function externalCheckAmong(DeploySuite memory suite, ExternalDeployment[] memory externals) external view {
        DeployDeclaration memory d = declarationWith(suite);
        d.externalDeployments = externals;
        checkDependenciesAreTheEmbeddedDeployments(d);
    }

    function suiteOf(bytes memory creationCode, DeployDependency[] memory dependencies)
        internal
        pure
        returns (DeploySuite memory)
    {
        return DeploySuite({
            networks: new string[](0),
            suite: SUITE,
            creationCode: creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(creationCode),
            storedBytecodeHash: keccak256(""),
            storedRuntimeCode: "",
            artifactPath: "test/concrete/MockEmbedding.sol:MockEmbedding",
            dependencies: dependencies,
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            describedByMeta: ""
        });
    }

    function siblingDependency() internal pure returns (DeployDependency memory) {
        return
            DeployDependency({deployedAddress: MOCK_DEPLOYABLE_ADDRESS, runtimeCode: type(MockDeployable).runtimeCode});
    }

    function externalDependency() internal pure returns (DeployDependency memory) {
        return DeployDependency({deployedAddress: MOCK_EXTERNAL_ADDRESS, runtimeCode: MOCK_EXTERNAL_RUNTIME_CODE});
    }

    function only(DeployDependency memory dependency) internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory deps = new DeployDependency[](1);
        deps[0] = dependency;
        return deps;
    }

    function both() internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory deps = new DeployDependency[](2);
        deps[0] = siblingDependency();
        deps[1] = externalDependency();
        return deps;
    }

    /// `PUSH<width>` of `value`'s low `width` bytes.
    function push(uint256 value, uint256 width) internal pure returns (bytes memory) {
        bytes memory code = new bytes(width + 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        code[0] = bytes1(uint8(0x5f + width));
        for (uint256 i = 0; i < width; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            code[width - i] = bytes1(uint8(value >> (8 * i)));
        }
        return code;
    }

    function pushAddress(address deployment) internal pure returns (bytes memory) {
        return push(uint160(deployment), 20);
    }

    /// The creation code `LibDataContract.contractCreationCode` builds of `data`.
    function dataContract(bytes memory data) internal pure returns (bytes memory) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return abi.encodePacked(hex"61", uint16(data.length + 1), hex"80600c6000396000f300", data);
    }

    function mechanismNaming(address factory) internal pure returns (bytes memory) {
        return LibMockCreate2Mechanism.encode(
            MockCreate2Mechanism({
                factory: factory,
                salt: MOCK_CREATE2_SALT,
                perNetwork: false,
                networks: new MockNetworkDeploy[](0),
                root: ""
            })
        );
    }

    function checkUndeclared(DeploySuite memory suite, address deployment) internal {
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, SUITE, deployment));
        this.externalCheck(suite);
    }

    function checkUnreached(DeploySuite memory suite, address dependency) internal {
        vm.expectRevert(abi.encodeWithSelector(UnreachedDependency.selector, SUITE, dependency));
        this.externalCheck(suite);
    }

    function testDeclaredPushedDeploymentsPass() external view {
        checkDependenciesAreTheEmbeddedDeployments(declaration());
    }

    function testReachablePushEmbedsAnUndeclaredSibling(uint256 width) external {
        width = bound(width, 20, 32);
        checkUndeclared(
            suiteOf(bytes.concat(push(uint160(MOCK_DEPLOYABLE_ADDRESS), width), STOP), only(externalDependency())),
            MOCK_DEPLOYABLE_ADDRESS
        );
    }

    function testReachablePushEmbedsAnUndeclaredExternalWithALeadingZeroByte(uint256 width) external {
        width = bound(width, 19, 32);
        checkUndeclared(
            suiteOf(bytes.concat(push(uint160(MOCK_EXTERNAL_ADDRESS), width), STOP), only(siblingDependency())),
            MOCK_EXTERNAL_ADDRESS
        );
    }

    function testSuiteMustDeclareAnExternalListedAfterAnother() external {
        ExternalDeployment[] memory externals = new ExternalDeployment[](2);
        externals[0] = ExternalDeployment({deployedAddress: address(0xdead), codeHash: keccak256("")});
        externals[1] = reachingExternalDeployments()[0];
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, SUITE, MOCK_EXTERNAL_ADDRESS));
        this.externalCheckAmong(
            suiteOf(bytes.concat(pushAddress(MOCK_EXTERNAL_ADDRESS), STOP), new DeployDependency[](0)), externals
        );
    }

    function testSuiteListedBeforeTheSiblingItEmbedsMustDeclareIt() external {
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, SUITE, MOCK_DEPLOYABLE_ADDRESS));
        this.externalCheckBeforeItsSibling(
            suiteOf(bytes.concat(pushAddress(MOCK_DEPLOYABLE_ADDRESS), STOP), new DeployDependency[](0))
        );
    }

    function testPushAfterAHaltAJumpCanPassEmbeds() external {
        bytes memory creationCode = bytes.concat(hex"6000600057005b", pushAddress(MOCK_DEPLOYABLE_ADDRESS), STOP);
        checkUndeclared(suiteOf(creationCode, new DeployDependency[](0)), MOCK_DEPLOYABLE_ADDRESS);
    }

    function testConstantHoldingTheAddressAmongOtherBytesIsNotEmbedded(uint256 above) external {
        above = bound(above, 1, type(uint96).max);
        uint256 value = uint160(MOCK_DEPLOYABLE_ADDRESS);
        checkNotEmbedded(value << 96);
        checkNotEmbedded((above << 160) | value);
    }

    function testConstantOneBitFromTheAddressIsNotEmbedded() external {
        uint256 value = uint160(MOCK_DEPLOYABLE_ADDRESS);
        for (uint256 bit = 0; bit < 160; bit++) {
            checkUnreached(
                suiteOf(bytes.concat(push(value ^ (2 ** bit), 20), STOP), only(siblingDependency())),
                MOCK_DEPLOYABLE_ADDRESS
            );
        }
    }

    function checkNotEmbedded(uint256 constantValue) internal {
        bytes memory creationCode = bytes.concat(push(constantValue, 32), STOP);
        assertTrue(containsAddress(creationCode, MOCK_DEPLOYABLE_ADDRESS));
        checkUnreached(suiteOf(creationCode, only(siblingDependency())), MOCK_DEPLOYABLE_ADDRESS);
    }

    function dataContractPushingBoth() internal pure returns (bytes memory) {
        bytes memory creationCode = dataContract(
            bytes.concat(hex"5b", pushAddress(MOCK_DEPLOYABLE_ADDRESS), hex"5b", pushAddress(MOCK_EXTERNAL_ADDRESS))
        );
        assertTrue(containsAddress(creationCode, MOCK_DEPLOYABLE_ADDRESS));
        assertTrue(containsAddress(creationCode, MOCK_EXTERNAL_ADDRESS));
        return creationCode;
    }

    function testDataContractDataNeedsNoDeclaration() external view {
        checkDependenciesAreTheEmbeddedDeployments(
            declarationWith(suiteOf(dataContractPushingBoth(), new DeployDependency[](0)))
        );
    }

    function testDataContractDataReachesNoDeclaredDependency() external {
        checkUnreached(suiteOf(dataContractPushingBoth(), only(siblingDependency())), MOCK_DEPLOYABLE_ADDRESS);
        checkUnreached(suiteOf(dataContractPushingBoth(), only(externalDependency())), MOCK_EXTERNAL_ADDRESS);
    }

    function mockCreate2DeclarationWith(DeploySuite memory suite) internal pure returns (DeployDeclaration memory) {
        DeployDeclaration memory d = declarationWith(suite);
        LibMockCreate2Mechanism.extend(d);
        return d;
    }

    function externalMockCreate2Check(DeploySuite memory suite) external view {
        checkDependenciesAreTheEmbeddedDeployments(mockCreate2DeclarationWith(suite));
    }

    function testMechanismDataEmbedsAnUndeclaredDeployment() external {
        DeploySuite memory suite = suiteOf(STOP, new DeployDependency[](0));
        suite.mechanismData = mechanismNaming(MOCK_EXTERNAL_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, SUITE, MOCK_EXTERNAL_ADDRESS));
        this.externalMockCreate2Check(suite);
    }

    function testMechanismDataReachesADeclaredDependency() external view {
        DeploySuite memory suite = suiteOf(STOP, only(externalDependency()));
        suite.mechanismData = mechanismNaming(MOCK_EXTERNAL_ADDRESS);
        checkDependenciesAreTheEmbeddedDeployments(mockCreate2DeclarationWith(suite));
    }

    function testDeclaredDependencyNothingEmbedsIsUnreached() external {
        checkUnreached(suiteOf(STOP, only(siblingDependency())), MOCK_DEPLOYABLE_ADDRESS);
        checkUnreached(suiteOf(STOP, only(externalDependency())), MOCK_EXTERNAL_ADDRESS);
        checkUnreached(suiteOf(bytes.concat(pushAddress(MOCK_DEPLOYABLE_ADDRESS), STOP), both()), MOCK_EXTERNAL_ADDRESS);
    }

    string constant PER_NETWORK = "mock-per-network";

    function perNetworkChainId(uint256 index) internal pure returns (uint256) {
        return LibRainDeploy.supportedNetworkConfigs()[index].chainId;
    }

    function recording(address recorded) internal pure returns (address[] memory) {
        address[] memory addresses = new address[](1);
        addresses[0] = recorded;
        return addresses;
    }

    function recording(address first, address later) internal pure returns (address[] memory) {
        address[] memory addresses = new address[](2);
        addresses[0] = first;
        addresses[1] = later;
        return addresses;
    }

    /// A per-network sibling whose stored address is the zero sentinel and whose mechanism records `recorded[i]` on
    /// the declaration's `i`th network.
    function perNetworkSuite(address[] memory recorded) internal pure returns (DeploySuite memory) {
        MockNetworkDeploy[] memory networks = new MockNetworkDeploy[](recorded.length);
        for (uint256 i = 0; i < recorded.length; i++) {
            networks[i] = MockNetworkDeploy({chainId: perNetworkChainId(i), data: "", deployedAddress: recorded[i]});
        }
        return DeploySuite({
            networks: new string[](0),
            suite: PER_NETWORK,
            creationCode: STOP,
            storedDeployedAddress: address(0),
            storedBytecodeHash: keccak256(""),
            storedRuntimeCode: "",
            artifactPath: "test/concrete/MockPerNetwork.sol:MockPerNetwork",
            dependencies: new DeployDependency[](0),
            mechanismData: LibMockCreate2Mechanism.encode(
                MockCreate2Mechanism({
                    factory: MOCK_CREATE2_FACTORY,
                    salt: MOCK_CREATE2_SALT,
                    perNetwork: true,
                    networks: networks,
                    root: ""
                })
            ),
            describedByMeta: ""
        });
    }

    function perNetworkDeclarationWith(DeploySuite memory suite, address[] memory recorded)
        internal
        pure
        returns (DeployDeclaration memory)
    {
        DeployDeclaration memory d = declarationWith(suite);
        LibMockCreate2Mechanism.extend(d);
        string[] memory networks = new string[](recorded.length);
        for (uint256 i = 0; i < recorded.length; i++) {
            networks[i] = LibMockCreate2Mechanism.networkName(perNetworkChainId(i));
        }
        LibRainDeployDeclaration.setNetworks(d, networks);
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] =
            DeployCandidate({snapshot: perNetworkSuite(recorded), unanchorableReason: "Hand-assembled bytecode."});
        LibRainDeployDeclaration.addCandidates(d, candidates);
        return d;
    }

    function externalPerNetworkCheck(DeploySuite memory suite, address[] memory recorded) external view {
        checkDependenciesAreTheEmbeddedDeployments(perNetworkDeclarationWith(suite, recorded));
    }

    function testPerNetworkSiblingWithAZeroPushPasses() external view {
        bytes memory creationCode =
            bytes.concat(push(0, 32), pushAddress(MOCK_DEPLOYABLE_ADDRESS), pushAddress(MOCK_EXTERNAL_ADDRESS), STOP);
        checkDependenciesAreTheEmbeddedDeployments(
            perNetworkDeclarationWith(suiteOf(creationCode, both()), recording(PER_NETWORK_ADDRESS))
        );
    }

    function testPerNetworkReleaseRecordingItsCandidatesAddressesPasses() external view {
        bytes memory creationCode =
            bytes.concat(pushAddress(MOCK_DEPLOYABLE_ADDRESS), pushAddress(MOCK_EXTERNAL_ADDRESS), STOP);
        DeployDeclaration memory d =
            perNetworkDeclarationWith(suiteOf(creationCode, both()), recording(PER_NETWORK_ADDRESS));
        DeploySuite[] memory released = new DeploySuite[](1);
        released[0] = perNetworkSuite(recording(PER_NETWORK_ADDRESS));
        released[0].suite = "mock-per-network@0_0_1";
        LibRainDeployDeclaration.addReleased(d, released);
        checkDependenciesAreTheEmbeddedDeployments(d);
    }

    function testPushOfAPerNetworkSiblingAddressMustBeDeclared() external {
        bytes memory creationCode = bytes.concat(
            pushAddress(PER_NETWORK_ADDRESS),
            pushAddress(MOCK_DEPLOYABLE_ADDRESS),
            pushAddress(MOCK_EXTERNAL_ADDRESS),
            STOP
        );
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, SUITE, PER_NETWORK_ADDRESS));
        this.externalPerNetworkCheck(suiteOf(creationCode, both()), recording(PER_NETWORK_ADDRESS));
    }

    function testPushOfAPerNetworkSiblingAddressOnALaterNetworkMustBeDeclared() external {
        bytes memory creationCode = bytes.concat(
            pushAddress(LATER_NETWORK_ADDRESS),
            pushAddress(MOCK_DEPLOYABLE_ADDRESS),
            pushAddress(MOCK_EXTERNAL_ADDRESS),
            STOP
        );
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, SUITE, LATER_NETWORK_ADDRESS));
        this.externalPerNetworkCheck(
            suiteOf(creationCode, both()), recording(PER_NETWORK_ADDRESS, LATER_NETWORK_ADDRESS)
        );
    }

    function externalCheckOver(DeploySuite memory suite, string[] memory networks) external view {
        DeployDeclaration memory d = declarationWith(suite);
        d.networks = networks;
        checkDependenciesAreTheEmbeddedDeployments(d);
    }

    function testDeclarationWithoutNetworksIsRefused() external {
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckOver(
            suiteOf(
                bytes.concat(pushAddress(MOCK_DEPLOYABLE_ADDRESS), pushAddress(MOCK_EXTERNAL_ADDRESS), STOP), both()
            ),
            new string[](0)
        );
    }

    function testDeclarationNamingAnUncataloguedNetworkIsRefused() external {
        string[] memory networks = new string[](1);
        networks[0] = "not-a-network";
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NetworkNotInCatalogue.selector, "not-a-network"));
        this.externalCheckOver(
            suiteOf(
                bytes.concat(pushAddress(MOCK_DEPLOYABLE_ADDRESS), pushAddress(MOCK_EXTERNAL_ADDRESS), STOP), both()
            ),
            networks
        );
    }

    function testZeroRecordedAddressIsRefused() external {
        bytes memory creationCode =
            bytes.concat(pushAddress(MOCK_DEPLOYABLE_ADDRESS), pushAddress(MOCK_EXTERNAL_ADDRESS), STOP);
        vm.expectRevert(abi.encodeWithSelector(ZeroRecordedAddress.selector, PER_NETWORK, perNetworkChainId(0)));
        this.externalPerNetworkCheck(suiteOf(creationCode, both()), recording(address(0)));
    }

    function testZeroRecordedAddressOnALaterNetworkIsRefused() external {
        bytes memory creationCode =
            bytes.concat(pushAddress(MOCK_DEPLOYABLE_ADDRESS), pushAddress(MOCK_EXTERNAL_ADDRESS), STOP);
        vm.expectRevert(abi.encodeWithSelector(ZeroRecordedAddress.selector, PER_NETWORK, perNetworkChainId(1)));
        this.externalPerNetworkCheck(suiteOf(creationCode, both()), recording(PER_NETWORK_ADDRESS, address(0)));
    }

    function dependingOn(address dependency, bytes memory runtimeCode) internal pure returns (DeploySuite memory) {
        return suiteOf(STOP, only(DeployDependency({deployedAddress: dependency, runtimeCode: runtimeCode})));
    }

    function externalPerNetworkRuntimeCodeCheck(DeploySuite memory suite, address[] memory recorded) external view {
        checkDependencyRuntimeCodeIsKnown(perNetworkDeclarationWith(suite, recorded));
    }

    function testPerNetworkSiblingDependencyWithItsRuntimeCodeIsKnown() external view {
        address[] memory recorded = recording(PER_NETWORK_ADDRESS);
        checkDependencyRuntimeCodeIsKnown(
            perNetworkDeclarationWith(
                dependingOn(PER_NETWORK_ADDRESS, perNetworkSuite(recorded).storedRuntimeCode), recorded
            )
        );
    }

    function testPerNetworkSiblingDependencyOnALaterNetworkWithItsRuntimeCodeIsKnown() external view {
        address[] memory recorded = recording(PER_NETWORK_ADDRESS, LATER_NETWORK_ADDRESS);
        checkDependencyRuntimeCodeIsKnown(
            perNetworkDeclarationWith(
                dependingOn(LATER_NETWORK_ADDRESS, perNetworkSuite(recorded).storedRuntimeCode), recorded
            )
        );
    }

    function checkPerNetworkRuntimeCodeMismatch(address dependency, address[] memory recorded) internal {
        bytes32 expected = perNetworkSuite(recorded).storedBytecodeHash;
        assertTrue(keccak256(STOP) != expected);
        vm.expectRevert(
            abi.encodeWithSelector(
                DependencyRuntimeCodeMismatch.selector, SUITE, dependency, keccak256(STOP), expected
            )
        );
        this.externalPerNetworkRuntimeCodeCheck(dependingOn(dependency, STOP), recorded);
    }

    function testPerNetworkSiblingDependencyWithOtherRuntimeCodeMismatches() external {
        checkPerNetworkRuntimeCodeMismatch(PER_NETWORK_ADDRESS, recording(PER_NETWORK_ADDRESS));
    }

    function testPerNetworkSiblingDependencyOnALaterNetworkWithOtherRuntimeCodeMismatches() external {
        checkPerNetworkRuntimeCodeMismatch(LATER_NETWORK_ADDRESS, recording(PER_NETWORK_ADDRESS, LATER_NETWORK_ADDRESS));
    }
}
