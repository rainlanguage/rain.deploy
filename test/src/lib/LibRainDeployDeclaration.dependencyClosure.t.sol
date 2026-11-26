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
import {MockCreate2DeploySuites} from "../../abstract/MockCreate2DeploySuites.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";
import {LibMockCreate2Mechanism} from "../../lib/LibMockCreate2Mechanism.sol";
import {LibMockNetworkRecord, MockNetworkDeploy} from "../../lib/LibMockNetworkRecord.sol";

contract LibRainDeployDeclarationDependencyClosureTest is MockCreate2DeploySuites, Test {
    address constant SUBJECT = address(0x5);
    address constant A = address(0xa);
    address constant B = address(0xb);
    address constant EXTERNAL = address(0xe);
    address constant UNKNOWN = address(0xf);

    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
        d.externalDeployments = new ExternalDeployment[](1);
        d.externalDeployments[0] = ExternalDeployment({deployedAddress: EXTERNAL, codeHash: keccak256(hex"ee")});
        return d;
    }

    function declarationOf(DeploySuite[] memory released, DeploySuite[] memory candidates)
        internal
        pure
        returns (DeployDeclaration memory)
    {
        DeployDeclaration memory d = declaration();
        d.released = released;
        d.candidates = new DeployCandidate[](candidates.length);
        for (uint256 i = 0; i < candidates.length; i++) {
            d.candidates[i] = DeployCandidate({snapshot: candidates[i], unanchorableReason: ""});
        }
        return d;
    }

    function closureOf(DeploySuite[] memory released, DeploySuite[] memory candidates, DeploySuite memory suite)
        public
        view
        returns (DeployDependency[] memory)
    {
        DeployDeclaration memory d = declarationOf(released, candidates);
        return
            LibRainDeployDeclaration.dependencyClosure(d, suite, LibRainDeployDeclaration.recordedAddresses(d, suite));
    }

    function deployLocallyOf(DeploySuite[] memory candidates, DeploySuite memory suite) external {
        LibMockCreate2Mechanism.deployLocally(declarationOf(new DeploySuite[](0), candidates), vm, suite);
    }

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

    function deps(DeployDependency memory a, DeployDependency memory b, DeployDependency memory c)
        internal
        pure
        returns (DeployDependency[] memory)
    {
        DeployDependency[] memory list = new DeployDependency[](3);
        list[0] = a;
        list[1] = b;
        list[2] = c;
        return list;
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

    function suiteAt(string memory key, address at, DeployDependency[] memory dependencies)
        internal
        pure
        returns (DeploySuite memory)
    {
        DeploySuite memory suite = LibBeaconTest.zoltuSuite(key, "", "", "");
        suite.storedDeployedAddress = at;
        suite.dependencies = dependencies;
        suite.networks = new string[](1);
        suite.networks[0] = LibRainDeploy.ARBITRUM_ONE;
        return suite;
    }

    function leafAt(string memory key, address at) internal pure returns (DeploySuite memory) {
        return suiteAt(key, at, new DeployDependency[](0));
    }

    function releaseDependingOn(DeployDependency[] memory dependencies) internal view returns (DeploySuite memory) {
        DeploySuite memory release = mockRelease();
        release.dependencies = dependencies;
        return release;
    }

    function uncatalogued() internal pure returns (DeploySuite memory) {
        DeploySuite memory suite = leafAt("uncatalogued", A);
        suite.networks[0] = "not-a-network";
        return suite;
    }

    function copy(DeploySuite memory suite) internal pure returns (DeploySuite memory) {
        return abi.decode(abi.encode(suite), (DeploySuite));
    }

    function assertClosure(DeployDependency[] memory actual, DeployDependency[] memory expected) internal pure {
        assertEq(abi.encode(actual), abi.encode(expected));
    }

    function checkRefused(
        bytes memory err,
        DeploySuite[] memory released,
        DeploySuite[] memory candidates,
        DeploySuite memory suite
    ) internal {
        vm.expectRevert(err);
        this.closureOf(released, candidates, suite);
    }

    function testClosureAppendsTransitiveDependenciesThroughEveryHopEndingAtAnExternal() external view {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa")));
        DeploySuite memory a = suiteAt("a", A, deps(dep(B, hex"bb")));
        DeploySuite memory b = suiteAt("b", B, deps(dep(EXTERNAL, hex"ee")));

        assertClosure(
            closureOf(suites(a, b), suites(subject), subject),
            deps(dep(A, hex"aa"), dep(B, hex"bb"), dep(EXTERNAL, hex"ee"))
        );
    }

    function testClosureTakesTheReleasedThenTheCandidateAtOneAddress() external view {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa")));
        DeploySuite memory released = suiteAt("a@0_0_1", A, deps(dep(B, hex"bb")));
        DeploySuite memory candidate = suiteAt("a", A, deps(dep(EXTERNAL, hex"ee")));

        assertClosure(
            closureOf(suites(released, leafAt("b", B)), suites(subject, candidate), subject),
            deps(dep(A, hex"aa"), dep(B, hex"bb"), dep(EXTERNAL, hex"ee"))
        );
    }

    function testClosureKeepsTheFirstEntryAtEachAddressInDeclaredOrder() external view {
        DeploySuite memory subject =
            suiteAt("subject", SUBJECT, deps(dep(A, hex"a1"), dep(B, hex"b1"), dep(A, hex"a2")));
        DeploySuite memory a = suiteAt("a", A, deps(dep(B, hex"b2")));

        assertClosure(
            closureOf(suites(a, leafAt("b", B)), suites(subject), subject), deps(dep(A, hex"a1"), dep(B, hex"b1"))
        );
    }

    function testClosureReachesAPerNetworkSuiteThroughTheAddressItRecordsOnEachNetwork() external view {
        address first = mockNetwork(42161).deployedAddress;
        address later = mockNetwork(137).deployedAddress;
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(first, hex"70"), dep(later, hex"71")));

        assertClosure(
            closureOf(suites(releaseDependingOn(deps(dep(B, hex"bb"))), leafAt("b", B)), suites(subject), subject),
            deps(dep(first, hex"70"), dep(later, hex"71"), dep(B, hex"bb"))
        );
    }

    function testClosureReachesASuiteRecordingZeroThroughAZeroDependency() external view {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(address(0), hex"00")));
        DeploySuite memory zero = suiteAt("zero", address(0), deps(dep(B, hex"bb")));

        assertClosure(
            closureOf(suites(zero, leafAt("b", B)), suites(subject), subject),
            deps(dep(address(0), hex"00"), dep(B, hex"bb"))
        );
    }

    function testClosureRefusesAnUnknownDependencyNamingItsDeclarer() external {
        DeploySuite memory direct = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa"), dep(UNKNOWN, hex"ff")));
        checkRefused(
            abi.encodeWithSelector(UnknownDependency.selector, "subject", UNKNOWN),
            suites(leafAt("a", A)),
            suites(direct),
            direct
        );

        DeploySuite memory transitive = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa")));
        checkRefused(
            abi.encodeWithSelector(UnknownDependency.selector, "a", UNKNOWN),
            suites(suiteAt("a", A, deps(dep(UNKNOWN, hex"ff")))),
            suites(transitive),
            transitive
        );

        DeploySuite memory zero = suiteAt("subject", SUBJECT, deps(dep(address(0), hex"00")));
        checkRefused(
            abi.encodeWithSelector(UnknownDependency.selector, "subject", address(0)),
            new DeploySuite[](0),
            suites(zero),
            zero
        );
    }

    function testClosureRefusesADependencyOnASuiteWithoutNetworks() external {
        DeploySuite memory subject = suiteAt("subject", SUBJECT, deps(dep(A, hex"aa")));
        DeploySuite memory a = leafAt("a", A);
        a.networks = new string[](0);

        checkRefused(
            abi.encodeWithSelector(UnknownDependency.selector, "subject", A), suites(a), suites(subject), subject
        );
    }

    function testClosureRefusesADependencyAtAnAddressTheSuiteOccupies() external {
        DeploySuite memory self = suiteAt("subject", SUBJECT, deps(dep(SUBJECT, hex"55")));
        checkRefused(
            abi.encodeWithSelector(DependencyCycle.selector, "subject"),
            new DeploySuite[](0),
            new DeploySuite[](0),
            self
        );

        DeploySuite memory a = suiteAt("a", A, deps(dep(B, hex"bb")));
        checkRefused(
            abi.encodeWithSelector(DependencyCycle.selector, "a"),
            suites(suiteAt("b", B, deps(dep(A, hex"aa")))),
            suites(a),
            a
        );

        DeploySuite memory perNetwork = releaseDependingOn(deps(dep(A, hex"aa")));
        checkRefused(
            abi.encodeWithSelector(DependencyCycle.selector, perNetwork.suite),
            suites(perNetwork, suiteAt("a", A, deps(dep(mockNetwork(137).deployedAddress, hex"71")))),
            new DeploySuite[](0),
            perNetwork
        );

        DeploySuite memory zero = suiteAt("zero", address(0), deps(dep(address(0), hex"00")));
        checkRefused(abi.encodeWithSelector(DependencyCycle.selector, "zero"), new DeploySuite[](0), suites(zero), zero);
    }

    function testSuiteWithoutDependenciesDerivesNoOtherSuite() external {
        DeploySuite memory subject = mockSingleSuite("subject");
        subject.networks = new string[](1);
        subject.networks[0] = LibRainDeploy.ARBITRUM_ONE;

        assertEq(closureOf(suites(uncatalogued()), suites(subject), subject).length, 0);
        this.deployLocallyOf(suites(uncatalogued(), subject), subject);
        assertEq(subject.storedDeployedAddress.code, subject.storedRuntimeCode);

        subject.dependencies = deps(dep(EXTERNAL, hex"ee"));
        checkRefused(
            abi.encodeWithSelector(LibRainDeploy.NetworkNotInCatalogue.selector, "not-a-network"),
            suites(uncatalogued()),
            suites(subject),
            subject
        );
    }

    function testClosureRefusesACycleThroughAnAddressItsCandidateAddsANetworkAt() external {
        DeploySuite memory frozen = releaseDependingOn(deps(dep(A, hex"aa")));
        DeploySuite memory a = suiteAt("a", A, deps(dep(mockNetwork(8453).deployedAddress, hex"72")));
        DeployDeclaration memory d = declarationOf(suites(frozen, a), suites(mockCandidate()));
        DeploySuite memory broadcast = copy(frozen);
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 8453;
        addCandidateNetworks(d, broadcast, chainIds);

        checkRefused(
            abi.encodeWithSelector(DependencyCycle.selector, frozen.suite),
            d.released,
            suites(mockCandidate()),
            broadcast
        );
    }

    function testClosureRefusesACycleThroughAnAddressItsRecordsAddANetworkAt() external {
        string memory root = "test/generated-snapshot/closure-recorded-cycle";
        sMockRecordRoot = root;
        DeploySuite memory frozen = releaseDependingOn(deps(dep(A, hex"aa")));
        MockNetworkDeploy[] memory recorded = new MockNetworkDeploy[](1);
        recorded[0] = mockNetwork(8453);
        LibMockNetworkRecord.write(vm, root, frozen.suite, recorded);
        DeploySuite memory a = suiteAt("a", A, deps(dep(recorded[0].deployedAddress, hex"72")));
        DeploySuite memory broadcast = copy(frozen);
        addRecordedNetworks(declaration(), broadcast);

        checkRefused(
            abi.encodeWithSelector(DependencyCycle.selector, frozen.suite), suites(frozen), suites(a), broadcast
        );
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);
    }

    function testLocalPerNetworkDeployOccupiesNoAddressOnANetworkItRecordsNothingOn() external {
        MockNetworkDeploy[] memory recorded = new MockNetworkDeploy[](1);
        recorded[0] = mockNetwork(42161);
        DeploySuite memory declared = mockSuite("p", recorded);
        declared.dependencies = deps(dep(address(0), hex"00"));
        DeploySuite memory local = copy(declared);
        local.networks = mockRelease().networks;

        vm.expectRevert(abi.encodeWithSelector(UnknownDependency.selector, "p", address(0)));
        this.deployLocallyOf(suites(declared), local);
    }
}
