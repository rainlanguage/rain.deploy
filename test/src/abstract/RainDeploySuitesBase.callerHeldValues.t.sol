// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployCandidate, DeployDeclaration, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibMockNetworkRecord, MockNetworkDeploy} from "../../lib/LibMockNetworkRecord.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {LibMockCreate2Mechanism} from "../../lib/LibMockCreate2Mechanism.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";
import {MockCreate2DeploySuites} from "../../abstract/MockCreate2DeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title RainDeploySuitesBaseCallerHeldValuesTest
/// @notice Internal calls share memory, so a caller holding a value before a call sees exactly the documented effect:
/// a mutator changes its first argument in place and nothing else; a function returning a struct hands back one the
/// caller can change without changing the declaration.
contract RainDeploySuitesBaseCallerHeldValuesTest is Test, MockCreate2DeploySuites {
    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibMockCreate2Mechanism.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        addMockCreate2(d);
        DeploySuite[] memory released = new DeploySuite[](1);
        released[0] = zoltuRelease();
        LibRainDeployDeclaration.addReleased(d, released);
        return d;
    }

    function zoltuRelease() internal pure returns (DeploySuite memory) {
        DeploySuite memory suite = LibBeaconTest.zoltuSuite(
            "mock-deployable@0_0_1",
            type(MockDeployable).creationCode,
            type(MockDeployable).runtimeCode,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
        suite.networks = new string[](1);
        suite.networks[0] = LibRainDeploy.ARBITRUM_ONE;
        return suite;
    }

    function declarationHash(DeployDeclaration memory d) internal pure returns (bytes32) {
        return keccak256(abi.encode(d.released, d.candidates, d.networks));
    }

    function chainIds(uint256 chainId) internal pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = chainId;
        return ids;
    }

    function testAddUnrecordedNetworksWidensTheCallersMockSuiteAndNothingElse() external view {
        DeployDeclaration memory d = declaration();
        DeploySuite memory suite = mockRelease();
        DeploySuite memory candidate = mockCandidate();
        uint256[] memory ids = chainIds(8453);
        bytes32 candidateBefore = keccak256(abi.encode(candidate));
        bytes32 idsBefore = keccak256(abi.encode(ids));
        bytes32 declarationBefore = declarationHash(d);

        addUnrecordedNetworks(d, suite, candidate, ids);

        assertEq(suite.networks.length, 3);
        assertEq(suite.networks[2], LibRainDeploy.BASE);
        assertEq(LibMockCreate2Mechanism.decode(suite).networks.length, 3);
        assertEq(keccak256(abi.encode(candidate)), candidateBefore);
        assertEq(keccak256(abi.encode(ids)), idsBefore);
        assertEq(declarationHash(d), declarationBefore);
    }

    function testAddUnrecordedNetworksLeavesEveryZoltuValueUnchanged() external view {
        DeployDeclaration memory d = declaration();
        DeploySuite memory suite = zoltuRelease();
        DeploySuite memory candidate = zoltuRelease();
        candidate.networks = LibRainDeploy.supportedNetworks();
        uint256[] memory ids = chainIds(8453);
        bytes32 suiteBefore = keccak256(abi.encode(suite));
        bytes32 candidateBefore = keccak256(abi.encode(candidate));
        bytes32 declarationBefore = declarationHash(d);

        addUnrecordedNetworks(d, suite, candidate, ids);

        assertEq(keccak256(abi.encode(suite)), suiteBefore);
        assertEq(keccak256(abi.encode(candidate)), candidateBefore);
        assertEq(declarationHash(d), declarationBefore);
    }

    function testAddRecordedNetworksWidensTheCallersMockSuiteAndNotTheDeclaration() external {
        string memory root = "test/generated-snapshot/mock-create2-caller-held";
        //forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.removeDir(root, true) {} catch {}
        sMockRecordRoot = root;
        DeployDeclaration memory d = declaration();
        DeploySuite memory suite = mockRelease();
        MockNetworkDeploy[] memory recorded = new MockNetworkDeploy[](1);
        recorded[0] = mockNetwork(56);
        LibMockNetworkRecord.write(vm, root, suite.suite, recorded);
        bytes32 declarationBefore = declarationHash(d);

        addRecordedNetworks(d, suite);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);

        assertEq(suite.networks.length, 3);
        assertEq(suite.networks[2], LibRainDeploy.BSC);
        assertEq(LibMockCreate2Mechanism.decode(suite).networks.length, 3);
        assertEq(declarationHash(d), declarationBefore);
        assertEq(d.released[0].networks.length, 2);
    }

    function testAddRecordedNetworksLeavesEveryZoltuValueUnchanged() external view {
        DeployDeclaration memory d = declaration();
        DeploySuite memory suite = zoltuRelease();
        bytes32 suiteBefore = keccak256(abi.encode(suite));
        bytes32 declarationBefore = declarationHash(d);

        addRecordedNetworks(d, suite);

        assertEq(keccak256(abi.encode(suite)), suiteBefore);
        assertEq(declarationHash(d), declarationBefore);
    }

    function testAddCandidateNetworksWidensTheCallersMockSuiteAndNotTheDeclaredCandidate() external view {
        DeployDeclaration memory d = declaration();
        DeploySuite memory suite = mockRelease();
        uint256[] memory ids = chainIds(8453);
        bytes32 idsBefore = keccak256(abi.encode(ids));
        bytes32 declarationBefore = declarationHash(d);

        addCandidateNetworks(d, suite, ids);

        assertEq(suite.networks.length, 3);
        assertEq(suite.networks[2], LibRainDeploy.BASE);
        assertEq(keccak256(abi.encode(ids)), idsBefore);
        assertEq(declarationHash(d), declarationBefore);
    }

    function testAddCandidateNetworksLeavesEveryZoltuValueUnchanged() external view {
        DeployDeclaration memory d = declaration();
        DeploySuite memory suite = zoltuRelease();
        bytes32 suiteBefore = keccak256(abi.encode(suite));
        bytes32 declarationBefore = declarationHash(d);

        addCandidateNetworks(d, suite, chainIds(8453));

        assertEq(keccak256(abi.encode(suite)), suiteBefore);
        assertEq(declarationHash(d), declarationBefore);
    }

    function testCandidateOfReturnsACandidateTheCallerCanChangeWithoutChangingTheDeclaration() external view {
        DeployDeclaration memory d = declaration();
        bytes32 declarationBefore = declarationHash(d);
        (DeploySuite memory candidate, bool found) = candidateOf(d, "mock-create-two@0_0_1");
        assertTrue(found);

        candidate.networks[0] = LibRainDeploy.BASE;
        candidate.suite = "changed";

        assertEq(declarationHash(d), declarationBefore);
    }

    function testCheckedCandidateSuitesReturnsCandidatesTheCallerCanChangeWithoutChangingTheDeclaration()
        external
        view
    {
        DeployDeclaration memory d = declaration();
        bytes32 declarationBefore = declarationHash(d);
        DeployCandidate[] memory candidates = checkedCandidateSuites(d);
        assertEq(keccak256(abi.encode(candidates)), keccak256(abi.encode(d.candidates)));

        candidates[0].snapshot.networks[0] = LibRainDeploy.BASE;
        candidates[0].snapshot.suite = "changed";
        candidates[0].unanchorableReason = "changed";
        candidates[0] = candidates[candidates.length - 1];

        assertEq(declarationHash(d), declarationBefore);
    }

    function testAddReleasedLeavesTheCallersSuitesUnfilledAndUnshared() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = zoltuRelease();
        suites[0].networks = new string[](0);
        suites[1] = zoltuRelease();
        string[] memory explicitNetworks = suites[1].networks;
        string memory explicitFirst = explicitNetworks[0];
        DeploySuite[] memory heldReleased = d.released;

        LibRainDeployDeclaration.addReleased(d, suites);

        assertEq(suites[0].networks.length, 0);
        assertEq(d.released[0].networks, d.networks);
        d.networks[0] = "changed";
        assertEq(d.released[0].networks[0], LibRainDeploy.supportedNetworks()[0]);
        assertEq(suites[1].networks, explicitNetworks);
        explicitNetworks[0] = "changed";
        assertEq(d.released[1].networks[0], explicitFirst);
        assertEq(heldReleased.length, 0);
        assertEq(d.released.length, 2);
    }

    function testAddCandidatesLeavesTheCallersSnapshotsUnfilledAndUnshared() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({snapshot: zoltuRelease(), unanchorableReason: ""});
        candidates[0].snapshot.networks = new string[](0);
        candidates[1] = DeployCandidate({snapshot: zoltuRelease(), unanchorableReason: ""});
        string[] memory explicitNetworks = candidates[1].snapshot.networks;
        string memory explicitFirst = explicitNetworks[0];
        DeployCandidate[] memory heldCandidates = d.candidates;

        LibRainDeployDeclaration.addCandidates(d, candidates);

        assertEq(candidates[0].snapshot.networks.length, 0);
        assertEq(d.candidates[0].snapshot.networks, d.networks);
        d.networks[0] = "changed";
        assertEq(d.candidates[0].snapshot.networks[0], LibRainDeploy.supportedNetworks()[0]);
        assertEq(candidates[1].snapshot.networks, explicitNetworks);
        explicitNetworks[0] = "changed";
        assertEq(d.candidates[1].snapshot.networks[0], explicitFirst);
        assertEq(heldCandidates.length, 0);
        assertEq(d.candidates.length, 2);
    }
}
