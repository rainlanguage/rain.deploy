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
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {
    LibMockCreate2Mechanism,
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_SALT,
    MockCreate2Mechanism
} from "../../lib/LibMockCreate2Mechanism.sol";
import {MockNetworkDeploy} from "../../lib/LibMockNetworkRecord.sol";

contract LibRainDeployDeclarationDependencyClosureTest is Test {
    address constant SUBJECT = address(0x5);
    address constant A = address(0xa);
    address constant B = address(0xb);
    address constant C = address(0xc);
    address constant EXTERNAL = address(0xe);
    address constant UNKNOWN = address(0xf);
    address constant PER_NETWORK_FIRST = address(0x70);
    address constant PER_NETWORK_LATER = address(0x71);

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
            networks: twoNetworks(),
            describedByMeta: ""
        });
    }

    function chainIdAt(uint256 index) internal pure returns (uint256) {
        return LibRainDeploy.supportedNetworkConfigs()[index].chainId;
    }

    function twoNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibMockCreate2Mechanism.networkName(chainIdAt(0));
        networks[1] = LibMockCreate2Mechanism.networkName(chainIdAt(1));
        return networks;
    }

    /// A per-network suite whose stored address is the zero sentinel and whose mechanism records `first` on its first
    /// network and `later` on its second.
    function perNetworkSuiteAt(string memory key, address first, address later, DeployDependency[] memory dependencies)
        internal
        pure
        returns (DeploySuite memory)
    {
        MockNetworkDeploy[] memory recorded = new MockNetworkDeploy[](2);
        recorded[0] = MockNetworkDeploy({chainId: chainIdAt(0), data: "", deployedAddress: first});
        recorded[1] = MockNetworkDeploy({chainId: chainIdAt(1), data: "", deployedAddress: later});
        return perNetworkSuiteOn(key, recorded, dependencies);
    }

    /// A per-network suite on exactly the networks its mechanism records.
    function perNetworkSuiteOn(
        string memory key,
        MockNetworkDeploy[] memory recorded,
        DeployDependency[] memory dependencies
    ) internal pure returns (DeploySuite memory) {
        DeploySuite memory suite = suiteAt(key, address(0), dependencies);
        suite.networks = LibMockCreate2Mechanism.networkNames(recorded);
        suite.mechanismData = LibMockCreate2Mechanism.encode(
            MockCreate2Mechanism({
                factory: MOCK_CREATE2_FACTORY, salt: MOCK_CREATE2_SALT, perNetwork: true, networks: recorded, root: ""
            })
        );
        return suite;
    }

    /// What a per-network suite with empty creation code derives on the network at `index` from `data`.
    function derivedNetwork(uint256 index, bytes memory data) internal pure returns (MockNetworkDeploy memory) {
        return LibMockCreate2Mechanism.network(MOCK_CREATE2_FACTORY, MOCK_CREATE2_SALT, "", chainIdAt(index), data);
    }

    function withoutNetworks(DeploySuite memory suite) internal pure returns (DeploySuite memory) {
        suite.networks = new string[](0);
        return suite;
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

    function declarationOf(
        DeploySuite[] memory released,
        DeploySuite[] memory candidates,
        ExternalDeployment[] memory externals
    ) internal pure returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
        d.released = released;
        d.candidates = new DeployCandidate[](candidates.length);
        for (uint256 i = 0; i < candidates.length; i++) {
            d.candidates[i] = DeployCandidate({snapshot: candidates[i], unanchorableReason: ""});
        }
        d.externalDeployments = externals;
        return d;
    }

    function closureOf(
        DeploySuite[] memory released,
        DeploySuite[] memory candidates,
        ExternalDeployment[] memory externals,
        DeploySuite memory suite
    ) public view returns (DeployDependency[] memory) {
        return LibRainDeployDeclaration.dependencyClosure(declarationOf(released, candidates, externals), suite);
    }

    /// The closure of `suite` once its candidate adds the networks among `chainIds` it records nothing on, as a
    /// broadcast takes it.
    function closureOnAddedNetworksOf(
        DeploySuite[] memory released,
        DeploySuite[] memory candidates,
        DeploySuite memory suite,
        DeploySuite memory candidate,
        uint256[] memory chainIds
    ) public view returns (DeployDependency[] memory) {
        DeployDeclaration memory d = declarationOf(released, candidates, new ExternalDeployment[](0));
        LibRainDeployDeclaration.addUnrecordedNetworks(d, suite, candidate, chainIds);
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
    function testClosureOfDirectDependenciesIsThoseDependencies() external view {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa"), dep(B, hex"bb")));
        DeploySuite memory a = suiteAt("a", A, new DeployDependency[](0));
        DeploySuite memory b = suiteAt("b", B, new DeployDependency[](0));

        assertClosure(
            closureOf(new DeploySuite[](0), suites(subject, a, b), new ExternalDeployment[](0), subject),
            deps(dep(A, hex"aa"), dep(B, hex"bb"))
        );
    }

    /// A dependency's own dependencies are appended, through every hop, each with its declarer's code.
    function testClosureAppendsTransitiveDependencies() external view {
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
    function testClosureTakesTheReleasedAndTheCandidateAtOneAddress() external view {
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
    function testClosureEndsAtAnExternalDeployment() external view {
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
    function testClosureKeepsTheFirstOfTwoDirectEntriesAtOneAddress() external view {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"a1"), dep(A, hex"a2")));
        DeploySuite memory a = suiteAt("a", A, new DeployDependency[](0));

        assertClosure(
            closureOf(new DeploySuite[](0), suites(subject, a), new ExternalDeployment[](0), subject),
            deps(dep(A, hex"a1"))
        );
    }

    /// An address the suite declares and a dependency declares again keeps the suite's entry.
    function testClosureKeepsTheSuitesEntryOverATransitiveOneAtTheSameAddress() external view {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa"), dep(B, hex"b1")));
        DeploySuite memory a = suiteAt("a", A, deps(dep(B, hex"b2")));
        DeploySuite memory b = suiteAt("b", B, new DeployDependency[](0));

        assertClosure(
            closureOf(suites(a, b), suites(subject), new ExternalDeployment[](0), subject),
            deps(dep(A, hex"aa"), dep(B, hex"b1"))
        );
    }

    function checkClosureThroughPerNetworkSibling(address recorded) internal view {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(recorded, hex"70")));
        DeploySuite memory p = perNetworkSuiteAt("p", PER_NETWORK_FIRST, PER_NETWORK_LATER, deps(dep(B, hex"bb")));
        DeploySuite memory b = suiteAt("b", B, new DeployDependency[](0));

        assertClosure(
            closureOf(suites(p, b), suites(subject), new ExternalDeployment[](0), subject),
            deps(dep(recorded, hex"70"), dep(B, hex"bb"))
        );
    }

    /// A dependency at the address a per-network suite records on its first network takes that suite's dependencies.
    function testClosureReachesAPerNetworkSiblingThroughItsFirstNetworksAddress() external view {
        checkClosureThroughPerNetworkSibling(PER_NETWORK_FIRST);
    }

    /// A dependency at the address a per-network suite records on a later network takes that suite's dependencies.
    function testClosureReachesAPerNetworkSiblingThroughALaterNetworksAddress() external view {
        checkClosureThroughPerNetworkSibling(PER_NETWORK_LATER);
    }

    /// A per-network suite whose closure reaches the address it records on a later network is a cycle.
    function testClosureRefusesACycleThroughAPerNetworkSuitesLaterAddress() external {
        DeploySuite memory p = perNetworkSuiteAt("p", PER_NETWORK_FIRST, PER_NETWORK_LATER, deps(dep(A, hex"aa")));
        DeploySuite memory a = suiteAt("a", A, deps(dep(PER_NETWORK_LATER, hex"71")));

        vm.expectRevert(abi.encodeWithSelector(DependencyCycle.selector, "p"));
        this.closureOf(suites(a), suites(p), new ExternalDeployment[](0), p);
    }

    /// A per-network suite declaring the address it records on its first network is a cycle.
    function testClosureRefusesAPerNetworkSuiteDependingOnItsFirstNetworksAddress() external {
        DeploySuite memory p =
            perNetworkSuiteAt("p", PER_NETWORK_FIRST, PER_NETWORK_LATER, deps(dep(PER_NETWORK_FIRST, hex"70")));

        vm.expectRevert(abi.encodeWithSelector(DependencyCycle.selector, "p"));
        this.closureOf(new DeploySuite[](0), suites(p), new ExternalDeployment[](0), p);
    }

    /// A suite with no networks records no address, so a dependency at its stored address is unknown.
    function testClosureRefusesADependencyOnASuiteWithoutNetworks() external {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa")));
        DeploySuite memory a = withoutNetworks(suiteAt("a", A, deps(dep(B, hex"bb"))));
        DeploySuite memory b = suiteAt("b", B, new DeployDependency[](0));

        vm.expectRevert(abi.encodeWithSelector(UnknownDependency.selector, "subject", A));
        this.closureOf(suites(a, b), suites(subject), new ExternalDeployment[](0), subject);
    }

    /// A suite with no networks records no address of its own, so its stored address is unknown, not a cycle.
    function testClosureOfASuiteWithoutNetworksTakesNoAddressAsItsOwn() external {
        DeploySuite memory subject = withoutNetworks(suiteAt("subject", SUBJECT, deps(dep(SUBJECT, hex"55"))));

        vm.expectRevert(abi.encodeWithSelector(UnknownDependency.selector, "subject", SUBJECT));
        this.closureOf(new DeploySuite[](0), suites(subject), new ExternalDeployment[](0), subject);
    }

    /// A zero dependency no suite records and no external deployment is at is unknown.
    function testClosureRefusesAZeroDependencyNothingRecords() external {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(address(0), hex"00")));

        vm.expectRevert(abi.encodeWithSelector(UnknownDependency.selector, "subject", address(0)));
        this.closureOf(new DeploySuite[](0), suites(subject), oneExternal(), subject);
    }

    /// A zero dependency resolves to a suite recording zero, taking its dependencies.
    function testClosureReachesASuiteRecordingZeroThroughAZeroDependency() external view {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(address(0), hex"00")));
        DeploySuite memory zero = suiteAt("zero", address(0), deps(dep(B, hex"bb")));
        DeploySuite memory b = suiteAt("b", B, new DeployDependency[](0));

        assertClosure(
            closureOf(suites(zero, b), suites(subject), new ExternalDeployment[](0), subject),
            deps(dep(address(0), hex"00"), dep(B, hex"bb"))
        );
    }

    /// A suite recording zero that declares a zero dependency is a cycle.
    function testClosureRefusesAZeroDependencyOfASuiteRecordingZero() external {
        DeploySuite memory zero = suiteAt("zero", address(0), deps(dep(address(0), hex"00")));

        vm.expectRevert(abi.encodeWithSelector(DependencyCycle.selector, "zero"));
        this.closureOf(new DeploySuite[](0), suites(zero), new ExternalDeployment[](0), zero);
    }

    /// An undeclared suite records no address of its own, so a dependency at its own address is unknown, not a cycle.
    function testClosureOfAnUndeclaredSuiteRefusesItsOwnAddressAsUnknown() external {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(SUBJECT, hex"55")));

        vm.expectRevert(abi.encodeWithSelector(UnknownDependency.selector, "subject", SUBJECT));
        this.closureOf(new DeploySuite[](0), new DeploySuite[](0), new ExternalDeployment[](0), subject);
    }

    /// A release broadcast to a network only its candidate records deploys at the address its own salt derives there,
    /// so a closure reaching that address is a cycle.
    function testClosureRefusesACycleThroughAnAddressItsCandidateAddsANetworkAt() external {
        MockNetworkDeploy memory first = derivedNetwork(0, hex"01");
        MockNetworkDeploy memory later = derivedNetwork(1, hex"02");
        MockNetworkDeploy[] memory frozenNetworks = new MockNetworkDeploy[](1);
        frozenNetworks[0] = first;
        MockNetworkDeploy[] memory candidateNetworks = new MockNetworkDeploy[](2);
        candidateNetworks[0] = first;
        candidateNetworks[1] = later;
        DeploySuite memory frozen = perNetworkSuiteOn("p@0_0_1", frozenNetworks, deps(dep(A, hex"aa")));
        DeploySuite memory candidate = perNetworkSuiteOn("p", candidateNetworks, new DeployDependency[](0));
        DeploySuite memory a = suiteAt("a", A, deps(dep(later.deployedAddress, hex"71")));
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = chainIdAt(1);

        DeploySuite memory broadcast = abi.decode(abi.encode(frozen), (DeploySuite));
        DeployDeclaration memory d = declarationOf(suites(frozen, a), suites(candidate), new ExternalDeployment[](0));
        LibRainDeployDeclaration.addUnrecordedNetworks(d, broadcast, candidate, chainIds);
        address[] memory own = LibRainDeployDeclaration.recordedAddresses(d, broadcast);
        assertEq(own.length, 2, "networks");
        assertEq(own[1], later.deployedAddress, "added address");

        vm.expectRevert(abi.encodeWithSelector(DependencyCycle.selector, "p@0_0_1"));
        this.closureOnAddedNetworksOf(suites(frozen, a), suites(candidate), frozen, candidate, chainIds);
    }
}
