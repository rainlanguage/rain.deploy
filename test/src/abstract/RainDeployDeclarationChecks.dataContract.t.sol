// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDataContract, PREFIX_BYTES_LENGTH} from "rain-datacontract-0.2.1/src/lib/LibDataContract.sol";
import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    ExternalDeployment
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {UndeclaredDependency} from "../../../src/abstract/RainDeployDeclarationChecks.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ReachingDeploySuites} from "../../abstract/ReachingDeploySuites.sol";
import {LibMockCreate2Mechanism, MOCK_CREATE2_SALT, MockCreate2Mechanism} from "../../lib/LibMockCreate2Mechanism.sol";
import {MockNetworkDeploy} from "../../lib/LibMockNetworkRecord.sol";
import {
    MOCK_DEPLOYABLE_ADDRESS,
    MOCK_EXTERNAL_ADDRESS,
    MockReachingDeployable
} from "../../concrete/MockReachingDeployable.sol";

// An external deployment narrow enough for creation code shorter than a data contract prefix to embed.
address constant NARROW_EXTERNAL_ADDRESS = address(uint160(0xc0ffee5eed));

/// @title RainDeployDeclarationChecksDataContractTest
/// @notice The embedded-dependency check skips the payload of creation code that rebuilds exactly as
/// `LibDataContract.contractCreationCode` of it, and checks all other creation code and every suite's mechanism data.
contract RainDeployDeclarationChecksDataContractTest is ReachingDeploySuites {
    string constant SUITE = "mock-rows";

    function declaration() internal pure override returns (DeployDeclaration memory) {
        return declarationWith(suiteOf(LibDataContract.contractCreationCode(rows())), reachingExternalDeployments());
    }

    function declarationWith(DeploySuite memory suite, ExternalDeployment[] memory externals)
        internal
        pure
        returns (DeployDeclaration memory)
    {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({snapshot: leafSuite("mock-deployable"), unanchorableReason: ""});
        candidates[1] =
            DeployCandidate({snapshot: suite, unanchorableReason: "A data contract: no compiler produces its bytes."});
        LibRainDeployDeclaration.addCandidates(d, candidates);
        d.externalDeployments = externals;
        return d;
    }

    function externalCheckDependenciesAreTheEmbeddedDeployments(
        DeploySuite memory suite,
        ExternalDeployment[] memory externals
    ) external pure {
        checkDependenciesAreTheEmbeddedDeployments(declarationWith(suite, externals));
    }

    /// Rows keyed by a sibling's and an external deployment's address.
    function rows() internal pure returns (bytes memory) {
        return abi.encodePacked(MOCK_DEPLOYABLE_ADDRESS, uint256(1), MOCK_EXTERNAL_ADDRESS, uint256(2));
    }

    function suiteOf(bytes memory creationCode) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            networks: new string[](0),
            suite: SUITE,
            creationCode: creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(creationCode),
            storedBytecodeHash: keccak256(""),
            storedRuntimeCode: "",
            artifactPath: "test/concrete/MockRows.sol:MockRows",
            dependencies: new DeployDependency[](0),
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            describedByMeta: ""
        });
    }

    function checkIsCode(bytes memory creationCode) internal {
        assertTrue(containsAddress(creationCode, MOCK_DEPLOYABLE_ADDRESS));
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, SUITE, MOCK_DEPLOYABLE_ADDRESS));
        this.externalCheckDependenciesAreTheEmbeddedDeployments(suiteOf(creationCode), reachingExternalDeployments());
    }

    function testDataContractRowsAreNotDependencies() external pure {
        DeployDeclaration memory d = declaration();
        bytes memory creationCode = d.candidates[1].snapshot.creationCode;
        assertTrue(containsAddress(creationCode, MOCK_DEPLOYABLE_ADDRESS));
        assertTrue(containsAddress(creationCode, MOCK_EXTERNAL_ADDRESS));
        checkDependenciesAreTheEmbeddedDeployments(d);
    }

    function testLargestDataContractRowsAreNotDependencies() external pure {
        bytes memory data = new bytes(uint256(type(uint16).max) - 1);
        bytes memory held = rows();
        for (uint256 i = 0; i < held.length; i++) {
            data[i] = held[i];
        }
        bytes memory creationCode = LibDataContract.contractCreationCode(data);
        assertTrue(containsAddress(creationCode, MOCK_DEPLOYABLE_ADDRESS));
        checkDependenciesAreTheEmbeddedDeployments(
            declarationWith(suiteOf(creationCode), reachingExternalDeployments())
        );
    }

    function testCodeEmbeddingTheRowAddressesIsChecked() external {
        bytes memory creationCode = type(MockReachingDeployable).creationCode;
        assertTrue(containsAddress(creationCode, MOCK_EXTERNAL_ADDRESS));
        checkIsCode(creationCode);
    }

    function testDataContractWithAPrefixByteChangedIsCode(uint8 flip) external {
        vm.assume(flip != 0);
        for (uint256 i = 0; i < PREFIX_BYTES_LENGTH; i++) {
            if (i == 1 || i == 2) {
                continue;
            }
            bytes memory creationCode = LibDataContract.contractCreationCode(rows());
            creationCode[i] ^= bytes1(flip);
            checkIsCode(creationCode);
        }
    }

    function testDataContractWithAnotherLengthIsCode(uint16 length) external {
        vm.assume(length != rows().length + 1);
        bytes memory creationCode = LibDataContract.contractCreationCode(rows());
        creationCode[1] = bytes1(uint8(length >> 8));
        creationCode[2] = bytes1(uint8(length));
        checkIsCode(creationCode);
    }

    function testDataContractWithTrailingBytesIsCode(bytes memory trailing) external {
        vm.assume(trailing.length != 0);
        checkIsCode(bytes.concat(LibDataContract.contractCreationCode(rows()), trailing));
    }

    function testPayloadTooLargeForADataContractIsCode() external {
        bytes memory payload = new bytes(type(uint16).max);
        bytes memory held = rows();
        for (uint256 i = 0; i < held.length; i++) {
            payload[i] = held[i];
        }
        bytes memory prefix = LibDataContract.contractCreationCode("");
        checkIsCode(bytes.concat(prefix, payload));
    }

    function testCodeShorterThanADataContractPrefixIsCode() external {
        bytes memory creationCode = abi.encodePacked(hex"64", uint40(uint160(NARROW_EXTERNAL_ADDRESS)), hex"3f");
        assertLt(creationCode.length, PREFIX_BYTES_LENGTH);
        ExternalDeployment[] memory externals = new ExternalDeployment[](1);
        externals[0] = ExternalDeployment({deployedAddress: NARROW_EXTERNAL_ADDRESS, codeHash: keccak256(hex"00")});
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, SUITE, NARROW_EXTERNAL_ADDRESS));
        this.externalCheckDependenciesAreTheEmbeddedDeployments(suiteOf(creationCode), externals);
    }

    function testDataContractMechanismDataIsChecked() external {
        DeploySuite memory suite = suiteOf(LibDataContract.contractCreationCode(rows()));
        suite.mechanismData = LibMockCreate2Mechanism.encode(
            MockCreate2Mechanism({
                factory: MOCK_EXTERNAL_ADDRESS,
                salt: MOCK_CREATE2_SALT,
                perNetwork: false,
                networks: new MockNetworkDeploy[](0),
                root: ""
            })
        );
        vm.expectRevert(abi.encodeWithSelector(UndeclaredDependency.selector, SUITE, MOCK_EXTERNAL_ADDRESS));
        this.externalCheckDependenciesAreTheEmbeddedDeployments(suite, reachingExternalDeployments());
    }
}
