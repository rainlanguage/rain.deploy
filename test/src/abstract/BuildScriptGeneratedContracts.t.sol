// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    DeclaredCandidateNotGenerated,
    DuplicateConstantPrefix,
    DuplicateGeneratedContractName,
    GeneratedCandidateNotDeclared,
    GeneratedContract,
    GeneratedContractNameNotArtifact,
    GeneratedContractNotDeclared,
    RetiredContract
} from "../../../src/abstract/BuildScript.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeployMechanism,
    DeploySuite,
    DuplicateDeploySuite
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {GeneratedContractsBuildScriptHarness} from "../../concrete/GeneratedContractsBuildScriptHarness.sol";

contract BuildScriptGeneratedContractsTest is Test {
    string constant ROOT = "test/generated-buildscript-generated-contracts";

    function suite(string memory key, string memory artifactPath) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: key,
            creationCode: "",
            storedDeployedAddress: address(0),
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: artifactPath,
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
    }

    function anchored(string memory key, string memory name) internal pure returns (DeployCandidate memory) {
        return
            DeployCandidate({snapshot: suite(key, string.concat("src/", name, ".sol:", name)), unanchorableReason: ""});
    }

    function unanchorable(string memory key) internal pure returns (DeployCandidate memory) {
        return DeployCandidate({snapshot: suite(key, "src/Shared.sol:Shared"), unanchorableReason: "shared artifact"});
    }

    function generated(string memory name, string memory prefix, DeployCandidate memory candidate)
        internal
        pure
        returns (GeneratedContract memory)
    {
        return GeneratedContract({contractName: name, constantPrefix: prefix, candidate: candidate});
    }

    function retired(string memory name) internal pure returns (RetiredContract memory) {
        return RetiredContract({contractName: name, template: suite(string.concat("retired-", name), "src/R.sol:R")});
    }

    function one(DeployCandidate memory a) internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory list = new DeployCandidate[](1);
        list[0] = a;
        return list;
    }

    function two(DeployCandidate memory a, DeployCandidate memory b) internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory list = new DeployCandidate[](2);
        list[0] = a;
        list[1] = b;
        return list;
    }

    function one(GeneratedContract memory a) internal pure returns (GeneratedContract[] memory) {
        GeneratedContract[] memory list = new GeneratedContract[](1);
        list[0] = a;
        return list;
    }

    function two(GeneratedContract memory a, GeneratedContract memory b)
        internal
        pure
        returns (GeneratedContract[] memory)
    {
        GeneratedContract[] memory list = new GeneratedContract[](2);
        list[0] = a;
        list[1] = b;
        return list;
    }

    function noRetired() internal pure returns (RetiredContract[] memory) {
        return new RetiredContract[](0);
    }

    function harnessDeclaring(
        DeployCandidate[] memory candidates,
        GeneratedContract[] memory generatedList,
        RetiredContract[] memory retiredList
    ) internal returns (GeneratedContractsBuildScriptHarness) {
        GeneratedContractsBuildScriptHarness harness = new GeneratedContractsBuildScriptHarness(ROOT, ROOT);
        harness.declare(abi.encode(candidates), abi.encode(generatedList), abi.encode(retiredList));
        return harness;
    }

    function testRefusesAGeneratedContractWhoseKeyNoCandidateDeclares() external {
        GeneratedContractsBuildScriptHarness harness = harnessDeclaring(
            one(anchored("a", "A")),
            two(generated("A", "", anchored("a", "A")), generated("B", "", anchored("b", "B"))),
            noRetired()
        );
        vm.expectRevert(abi.encodeWithSelector(GeneratedContractNotDeclared.selector, "B", "b"));
        harness.externalCheckedGeneratedContracts();
    }

    function testRefusesADeclaredCandidateNothingGenerates() external {
        GeneratedContractsBuildScriptHarness harness = harnessDeclaring(
            two(anchored("a", "A"), anchored("b", "B")), one(generated("A", "", anchored("a", "A"))), noRetired()
        );
        vm.expectRevert(abi.encodeWithSelector(DeclaredCandidateNotGenerated.selector, "b"));
        harness.externalCheckedGeneratedContracts();
    }

    function testRefusesAGeneratedCandidateOtherThanTheOneDeclaredUnderItsKey() external {
        DeployCandidate memory declared = anchored("a", "A");
        DeployCandidate memory other = anchored("a", "A");
        other.snapshot.creationCode = hex"00";
        GeneratedContractsBuildScriptHarness harness =
            harnessDeclaring(one(declared), one(generated("A", "", other)), noRetired());
        vm.expectRevert(abi.encodeWithSelector(GeneratedCandidateNotDeclared.selector, "a"));
        harness.externalCheckedGeneratedContracts();
    }

    function testRefusesAnAnchoredCandidateGeneratedUnderAnotherContractsName() external {
        GeneratedContractsBuildScriptHarness harness =
            harnessDeclaring(one(anchored("a", "A")), one(generated("Other", "", anchored("a", "A"))), noRetired());
        vm.expectRevert(abi.encodeWithSelector(GeneratedContractNameNotArtifact.selector, "Other", "src/A.sol:A"));
        harness.externalCheckedGeneratedContracts();
    }

    function testAnUnanchorableCandidateMayBeGeneratedUnderAnyName() external {
        GeneratedContractsBuildScriptHarness harness =
            harnessDeclaring(one(unanchorable("a")), one(generated("Anything", "", unanchorable("a"))), noRetired());
        GeneratedContract[] memory checked =
            abi.decode(harness.externalCheckedGeneratedContracts(), (GeneratedContract[]));
        assertEq(checked.length, 1);
        assertEq(checked[0].contractName, "Anything");
    }

    function testRefusesTwoGeneratedContractsUnderOneKey() external {
        GeneratedContractsBuildScriptHarness harness = harnessDeclaring(
            one(unanchorable("a")),
            two(generated("A", "", unanchorable("a")), generated("B", "", unanchorable("a"))),
            noRetired()
        );
        vm.expectRevert(abi.encodeWithSelector(DuplicateDeploySuite.selector, "a"));
        harness.externalCheckedGeneratedContracts();
    }

    function testRefusesTwoGeneratedContractsUnderOneName() external {
        GeneratedContractsBuildScriptHarness harness = harnessDeclaring(
            two(unanchorable("a"), unanchorable("b")),
            two(generated("X", "", unanchorable("a")), generated("X", "", unanchorable("b"))),
            noRetired()
        );
        vm.expectRevert(abi.encodeWithSelector(DuplicateGeneratedContractName.selector, "X"));
        harness.externalCheckedGeneratedContracts();
    }

    function testRefusesARetiredContractUnderAGeneratedContractsName() external {
        RetiredContract[] memory retiredList = new RetiredContract[](1);
        retiredList[0] = retired("A");
        GeneratedContractsBuildScriptHarness harness =
            harnessDeclaring(one(anchored("a", "A")), one(generated("A", "", anchored("a", "A"))), retiredList);
        vm.expectRevert(abi.encodeWithSelector(DuplicateGeneratedContractName.selector, "A"));
        harness.externalCheckedGeneratedContracts();
    }

    function testRefusesTwoRetiredContractsUnderOneName() external {
        RetiredContract[] memory retiredList = new RetiredContract[](2);
        retiredList[0] = retired("R");
        retiredList[1] = retired("R");
        GeneratedContractsBuildScriptHarness harness =
            harnessDeclaring(one(anchored("a", "A")), one(generated("A", "", anchored("a", "A"))), retiredList);
        vm.expectRevert(abi.encodeWithSelector(DuplicateGeneratedContractName.selector, "R"));
        harness.externalCheckedGeneratedContracts();
    }

    function testRefusesTwoAliasLibsUnderOnePrefix() external {
        GeneratedContractsBuildScriptHarness harness = harnessDeclaring(
            two(anchored("a", "A"), anchored("b", "B")),
            two(generated("A", "P", anchored("a", "A")), generated("B", "P", anchored("b", "B"))),
            noRetired()
        );
        vm.expectRevert(abi.encodeWithSelector(DuplicateConstantPrefix.selector, "P"));
        harness.externalCheckedGeneratedContracts();
    }

    function testSeveralContractsMayHaveNoAliasLib() external {
        GeneratedContractsBuildScriptHarness harness = harnessDeclaring(
            two(anchored("a", "A"), anchored("b", "B")),
            two(generated("A", "", anchored("a", "A")), generated("B", "", anchored("b", "B"))),
            noRetired()
        );
        assertEq(abi.decode(harness.externalCheckedGeneratedContracts(), (GeneratedContract[])).length, 2);
    }

    function testRunRefusesABadDeclaration() external {
        GeneratedContractsBuildScriptHarness harness = harnessDeclaring(
            two(anchored("a", "A"), anchored("b", "B")), one(generated("A", "", anchored("a", "A"))), noRetired()
        );
        vm.expectRevert(abi.encodeWithSelector(DeclaredCandidateNotGenerated.selector, "b"));
        harness.run();
    }

    function testCutReleaseRefusesABadDeclaration() external {
        GeneratedContractsBuildScriptHarness harness = harnessDeclaring(
            two(anchored("a", "A"), anchored("b", "B")), one(generated("A", "", anchored("a", "A"))), noRetired()
        );
        vm.expectRevert(abi.encodeWithSelector(DeclaredCandidateNotGenerated.selector, "b"));
        harness.cutRelease();
    }

    function testSnapshotContractNamesAreTheGeneratedNamesInOrder() external {
        GeneratedContractsBuildScriptHarness harness = harnessDeclaring(
            two(anchored("b", "B"), anchored("a", "A")),
            two(generated("A", "", anchored("a", "A")), generated("B", "", anchored("b", "B"))),
            noRetired()
        );
        string[] memory names = harness.externalSnapshotContractNames();
        assertEq(names.length, 2);
        assertEq(names[0], "A");
        assertEq(names[1], "B");
    }

    /// The alias lib is written for a prefixed contract only, and the
    /// aggregate lists the retired contracts before the generated ones.
    function testRegenerateLibsWritesAliasLibsForPrefixesAndAggregatesRetiredFirst() external {
        string memory dir = "fixture-lib/buildscript-generated-contracts-libs";
        if (vm.exists(dir)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(dir, true);
        }
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(dir, true);
        RetiredContract[] memory retiredList = new RetiredContract[](1);
        retiredList[0] = retired("R");
        GeneratedContractsBuildScriptHarness harness = new GeneratedContractsBuildScriptHarness(ROOT, dir);
        harness.declare(
            abi.encode(two(anchored("a", "A"), anchored("b", "B"))),
            abi.encode(two(generated("A", "A_PREFIX", anchored("a", "A")), generated("B", "", anchored("b", "B")))),
            abi.encode(retiredList)
        );
        harness.externalRegenerateLibs();

        bool aliasA = vm.exists(LibRainDeploySnapshot.pathForLib(dir, "LibADeploy"));
        bool aliasB = vm.exists(LibRainDeploySnapshot.pathForLib(dir, "LibBDeploy"));
        bool releasedR = vm.exists(LibRainDeploySnapshot.pathForLib(dir, "LibRReleased"));
        string memory aggregate =
            vm.readFile(LibRainDeploySnapshot.pathForLib(dir, LibRainDeploySnapshot.RELEASED_SUITES_LIBRARY));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(dir, true);

        assertTrue(aliasA);
        assertFalse(aliasB);
        assertTrue(releasedR);
        assertTrue(vm.contains(aggregate, "new DeploySuite[][](3)"));
        assertTrue(vm.contains(aggregate, "released[0] = LibRReleased.releasedSuites();"));
        assertTrue(vm.contains(aggregate, "released[1] = LibAReleased.releasedSuites();"));
        assertTrue(vm.contains(aggregate, "released[2] = LibBReleased.releasedSuites();"));
    }
}
