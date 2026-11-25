// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    DependencyCycle,
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    ExternalDeployment,
    UnknownDependency
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";

contract LibRainDeployDeclarationDependencyClosureTest is Test {
    address constant SUBJECT = address(0x5);
    address constant A = address(0xa);
    address constant B = address(0xb);
    address constant C = address(0xc);
    address constant EXTERNAL = address(0xe);
    address constant UNKNOWN = address(0xf);

    function dep(address at, bytes memory code) internal pure returns (DeployDependency memory) {
        return DeployDependency({deployedAddress: at, runtimeCode: code});
    }

    function deps(DeployDependency memory a) internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory list = new DeployDependency[](1);
        list[0] = a;
        return list;
    }

    function deps(DeployDependency memory a, DeployDependency memory b)
        internal
        pure
        returns (DeployDependency[] memory)
    {
        DeployDependency[] memory list = new DeployDependency[](2);
        list[0] = a;
        list[1] = b;
        return list;
    }

    function suiteAt(string memory key, address at, DeployDependency[] memory dependencies)
        internal
        pure
        returns (DeploySuite memory)
    {
        return DeploySuite({
            suite: key,
            creationCode: "",
            storedDeployedAddress: at,
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: dependencies,
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            networks: new string[](0),
            describedByMeta: ""
        });
    }

    function suites(DeploySuite memory a) internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory list = new DeploySuite[](1);
        list[0] = a;
        return list;
    }

    function suites(DeploySuite memory a, DeploySuite memory b) internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory list = new DeploySuite[](2);
        list[0] = a;
        list[1] = b;
        return list;
    }

    function suites(DeploySuite memory a, DeploySuite memory b, DeploySuite memory c)
        internal
        pure
        returns (DeploySuite[] memory)
    {
        DeploySuite[] memory list = new DeploySuite[](3);
        list[0] = a;
        list[1] = b;
        list[2] = c;
        return list;
    }

    function oneExternal() internal pure returns (ExternalDeployment[] memory) {
        ExternalDeployment[] memory externals = new ExternalDeployment[](1);
        externals[0] = ExternalDeployment({deployedAddress: EXTERNAL, codeHash: keccak256(hex"ee")});
        return externals;
    }

    function closureOf(
        DeploySuite[] memory released,
        DeploySuite[] memory candidates,
        ExternalDeployment[] memory externals,
        DeploySuite memory suite
    ) public view returns (DeployDependency[] memory) {
        DeployDeclaration memory d;
        d.released = released;
        d.candidates = new DeployCandidate[](candidates.length);
        for (uint256 i = 0; i < candidates.length; i++) {
            d.candidates[i] = DeployCandidate({snapshot: candidates[i], unanchorableReason: ""});
        }
        d.externalDeployments = externals;
        return LibRainDeployDeclaration.dependencyClosure(d, suite);
    }

    function assertClosure(DeployDependency[] memory actual, DeployDependency[] memory expected) internal pure {
        assertEq(actual.length, expected.length, "length");
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(actual[i].deployedAddress, expected[i].deployedAddress, "address");
            assertEq(actual[i].runtimeCode, expected[i].runtimeCode, "runtime code");
        }
    }

    /// Direct dependencies on suites declaring none are the closure, in declared order.
    function testClosureOfDirectDependenciesIsThoseDependencies() external pure {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa"), dep(B, hex"bb")));
        DeploySuite memory a = suiteAt("a", A, new DeployDependency[](0));
        DeploySuite memory b = suiteAt("b", B, new DeployDependency[](0));

        assertClosure(
            closureOf(new DeploySuite[](0), suites(subject, a, b), new ExternalDeployment[](0), subject),
            deps(dep(A, hex"aa"), dep(B, hex"bb"))
        );
    }

    /// A dependency's own dependencies are appended, through every hop, each with its declarer's code.
    function testClosureAppendsTransitiveDependencies() external pure {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa")));
        DeploySuite memory a = suiteAt("a", A, deps(dep(B, hex"bb")));
        DeploySuite memory b = suiteAt("b", B, deps(dep(C, hex"cc")));
        DeploySuite memory c = suiteAt("c", C, new DeployDependency[](0));

        DeployDependency[] memory expected = new DeployDependency[](3);
        expected[0] = dep(A, hex"aa");
        expected[1] = dep(B, hex"bb");
        expected[2] = dep(C, hex"cc");
        assertClosure(closureOf(suites(a, b, c), suites(subject), new ExternalDeployment[](0), subject), expected);
    }

    /// A released suite and a candidate at one address each contribute their dependencies, released first.
    function testClosureTakesTheReleasedAndTheCandidateAtOneAddress() external pure {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa")));
        DeploySuite memory released = suiteAt("a@0_0_1", A, deps(dep(B, hex"bb")));
        DeploySuite memory candidate = suiteAt("a", A, deps(dep(C, hex"cc")));
        DeploySuite memory b = suiteAt("b", B, new DeployDependency[](0));
        DeploySuite memory c = suiteAt("c", C, new DeployDependency[](0));

        DeployDependency[] memory expected = new DeployDependency[](3);
        expected[0] = dep(A, hex"aa");
        expected[1] = dep(B, hex"bb");
        expected[2] = dep(C, hex"cc");
        assertClosure(
            closureOf(suites(released, b, c), suites(subject, candidate), new ExternalDeployment[](0), subject),
            expected
        );
    }

    /// An external deployment, reached directly or through a suite, is in the closure and adds nothing past it.
    function testClosureEndsAtAnExternalDeployment() external pure {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(EXTERNAL, hex"e1"), dep(A, hex"aa")));
        DeploySuite memory a = suiteAt("a", A, deps(dep(EXTERNAL, hex"e2"), dep(B, hex"bb")));
        DeploySuite memory b = suiteAt("b", B, new DeployDependency[](0));

        DeployDependency[] memory expected = new DeployDependency[](3);
        expected[0] = dep(EXTERNAL, hex"e1");
        expected[1] = dep(A, hex"aa");
        expected[2] = dep(B, hex"bb");
        assertClosure(closureOf(suites(a, b), suites(subject), oneExternal(), subject), expected);
    }

    /// A direct dependency at neither a suite nor an external deployment is refused naming the suite.
    function testClosureRefusesAnUnknownDirectDependency() external {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa"), dep(UNKNOWN, hex"ff")));
        DeploySuite memory a = suiteAt("a", A, new DeployDependency[](0));

        vm.expectRevert(abi.encodeWithSelector(UnknownDependency.selector, "subject", UNKNOWN));
        this.closureOf(new DeploySuite[](0), suites(subject, a), oneExternal(), subject);
    }

    /// A transitive dependency at neither a suite nor an external deployment is refused naming its declarer.
    function testClosureRefusesAnUnknownTransitiveDependencyNamingItsDeclarer() external {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa")));
        DeploySuite memory a = suiteAt("a", A, deps(dep(UNKNOWN, hex"ff")));

        vm.expectRevert(abi.encodeWithSelector(UnknownDependency.selector, "a", UNKNOWN));
        this.closureOf(suites(a), suites(subject), oneExternal(), subject);
    }

    /// A closure reaching back to the suite's own address through another suite is a cycle.
    function testClosureRefusesATwoSuiteCycle() external {
        DeploySuite memory a = suiteAt("a", A, deps(dep(B, hex"bb")));
        DeploySuite memory b = suiteAt("b", B, deps(dep(A, hex"aa")));

        vm.expectRevert(abi.encodeWithSelector(DependencyCycle.selector, "a"));
        this.closureOf(new DeploySuite[](0), suites(a, b), new ExternalDeployment[](0), a);
    }

    /// A suite declaring its own address is a cycle.
    function testClosureRefusesASelfDependency() external {
        DeploySuite memory a = suiteAt("a", A, deps(dep(A, hex"aa")));

        vm.expectRevert(abi.encodeWithSelector(DependencyCycle.selector, "a"));
        this.closureOf(new DeploySuite[](0), suites(a), new ExternalDeployment[](0), a);
    }

    /// One address declared twice by the suite keeps its first entry's code.
    function testClosureKeepsTheFirstOfTwoDirectEntriesAtOneAddress() external pure {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"a1"), dep(A, hex"a2")));
        DeploySuite memory a = suiteAt("a", A, new DeployDependency[](0));

        assertClosure(
            closureOf(new DeploySuite[](0), suites(subject, a), new ExternalDeployment[](0), subject),
            deps(dep(A, hex"a1"))
        );
    }

    /// An address the suite declares and a dependency declares again keeps the suite's entry.
    function testClosureKeepsTheSuitesEntryOverATransitiveOneAtTheSameAddress() external pure {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa"), dep(B, hex"b1")));
        DeploySuite memory a = suiteAt("a", A, deps(dep(B, hex"b2")));
        DeploySuite memory b = suiteAt("b", B, new DeployDependency[](0));

        assertClosure(
            closureOf(suites(a, b), suites(subject), new ExternalDeployment[](0), subject),
            deps(dep(A, hex"aa"), dep(B, hex"b1"))
        );
    }
}
