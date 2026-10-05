// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {DeployDependency, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDependentDeployable} from "../../concrete/MockDependentDeployable.sol";
import {
    CREATION_CODE as ADDRESS_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../../src/generated/candidate/AddressRegistry.sol";

/// @title RainDeployVerifyBaseTest
/// @notice What the derivation RETURNS, read directly, which no other group
/// asks it for.
///
/// Every other contract that reaches `deriveDeployment` consumes it and asserts
/// about the consumption. The snapshot group compares the derivation against
/// the recorded fields and names the SUITE argument in its errors, never the
/// derivation's own key; the chain group is the only reader of
/// `DerivedDeploy.suite` and `DerivedDeploy.deployedAddress` as such, and every
/// one of its tests forks. So a derivation that returned the recorded fields
/// back, or an empty key, is invisible to a run with no RPC credentials — which
/// is the run the snapshot half exists to be.
///
/// The three fields are checked against oracles outside the derivation: the
/// generated pin for the address, the generated runtime code for the hash, and
/// the argument for the key.
///
/// It is also where the DEPENDENCY etch is asserted, for the same reason: the
/// etch exists so that a constructor which reads a dependency produces an
/// address and a code hash at all, and the snapshot group only ever sees those
/// two values compared against a record. A suite whose constructor needs a
/// dependency and whose declaration carries one derives here against
/// `MockDependentDeployable` — which CALLS what it is handed rather than
/// checking its `code.length` — so "the declared code was etched" and "anything
/// at all was etched" are different results.
contract RainDeployVerifyBaseTest is ExampleDeploySuites, RainDeployVerifyBase {
    /// The derivation MUST come from the creation code and the key, and from
    /// nothing else the suite records.
    ///
    /// The suite here records a deliberately wrong address, code hash and
    /// runtime code beside a real creation code, which is the shape of every
    /// snapshot the internal-consistency group exists to catch. A derivation
    /// that read any of those fields would agree with the snapshot by
    /// construction, and that group would be comparing a value against itself.
    function testDerivationReadsTheCreationCodeAndNotTheRecordedFields() external {
        DeploySuite memory suite = DeploySuite({
            suite: "a-declared-key",
            creationCode: ADDRESS_REGISTRY_CREATION_CODE,
            storedDeployedAddress: address(0xdead),
            storedBytecodeHash: bytes32(uint256(1)),
            storedRuntimeCode: hex"00",
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
            dependencies: new DeployDependency[](0)
        });

        DerivedDeploy memory derived = deriveDeployment(suite);

        assertEq(derived.suite, "a-declared-key");
        assertEq(derived.deployedAddress, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(derived.bytecodeHash, keccak256(ADDRESS_REGISTRY_RUNTIME_CODE));

        // The recorded fields really were something else, so agreeing with the
        // creation code is a different answer from echoing them back.
        assertNotEq(derived.deployedAddress, suite.storedDeployedAddress);
        assertNotEq(derived.bytecodeHash, suite.storedBytecodeHash);
        assertNotEq(derived.bytecodeHash, keccak256(suite.storedRuntimeCode));
    }

    /// EVERY suite MUST be derived, once each, into the position it was handed
    /// in.
    ///
    /// The chain matrix pairs nothing back up: it takes the array and reports
    /// on `derived[j]` alone, so a derivation that landed in the wrong slot
    /// checks one suite's address for another suite's code hash and names a
    /// third in the failure. A short array is worse — the suites that fell off
    /// the end are checked on no network at all, which is the exact absence
    /// this group is the only one that can see.
    function testDerivationsPairPositionallyWithTheSuites() external {
        DeploySuite[] memory suites = allSuites();
        assertEq(suites.length, 4);

        DerivedDeploy[] memory derived = deriveDeployments(suites);
        assertEq(derived.length, suites.length);

        for (uint256 i = 0; i < suites.length; i++) {
            assertEq(derived[i].suite, suites[i].suite);
            assertEq(derived[i].deployedAddress, suites[i].storedDeployedAddress);
            assertEq(derived[i].bytecodeHash, suites[i].storedBytecodeHash);
        }

        // Positional is a claim only while the positions differ. The first two
        // suites are different contracts at different addresses, and the last
        // is neither of them.
        assertNotEq(derived[0].deployedAddress, derived[1].deployedAddress);
        assertNotEq(derived[0].bytecodeHash, derived[1].bytecodeHash);
        assertNotEq(derived[3].suite, derived[0].suite);
    }

    /// Nothing to derive derives nothing, rather than a one-entry array of
    /// zeroes. The chain group returns early on a zero length and would fork
    /// every supported network for a subject at address zero otherwise.
    function testDerivingNoSuitesDerivesNothing() external {
        DerivedDeploy[] memory derived = deriveDeployments(new DeploySuite[](0));
        assertEq(derived.length, 0);
    }

    /// @dev An address no test puts anything at, for a declaration to name as a
    /// dependency. A second one beside it, because a one-entry list cannot tell
    /// a loop over a declaration apart from a read of its first entry.
    address constant FIRST_DEPENDENCY = address(0xdef1);

    /// @dev The second dependency address. See `FIRST_DEPENDENCY`.
    address constant SECOND_DEPENDENCY = address(0xdef2);

    /// The creation code of `MockDependentDeployable` over the addresses its
    /// constructor will read.
    ///
    /// The argument is appended to the creation code, which is the only way the
    /// Zoltu factory passes a constructor one — its calldata IS the creation
    /// code — and it means the subject's derived address depends on which
    /// addresses it needs, exactly as a beacon's does on its implementation.
    /// @param dependencies The addresses the constructor will read.
    /// @return The creation code.
    function dependentCreationCode(address[] memory dependencies) internal pure returns (bytes memory) {
        return abi.encodePacked(type(MockDependentDeployable).creationCode, abi.encode(dependencies));
    }

    /// A suite over `dependentCreationCode`, recording pins that are
    /// deliberately wrong.
    ///
    /// Wrong because nothing here reads them: a derivation is a function of the
    /// creation code and the declared dependencies, and
    /// `testDerivationReadsTheCreationCodeAndNotTheRecordedFields` is what
    /// holds it to that. Recording the right ones would let an etch of
    /// `storedRuntimeCode` at `storedDeployedAddress` pass every assertion
    /// below.
    /// @param creationCode The suite's creation code.
    /// @param dependencies The suite's declared dependencies.
    /// @return The suite.
    function dependentSuite(bytes memory creationCode, DeployDependency[] memory dependencies)
        internal
        pure
        returns (DeploySuite memory)
    {
        return DeploySuite({
            suite: "a-dependent-key",
            creationCode: creationCode,
            storedDeployedAddress: address(0xdead),
            storedBytecodeHash: bytes32(uint256(1)),
            storedRuntimeCode: hex"00",
            artifactPath: "test/concrete/MockDependentDeployable.sol:MockDependentDeployable",
            dependencies: dependencies
        });
    }

    /// A declaration putting `MockDeployable`'s runtime code at each of
    /// `addresses` — what a declarer writes by importing the dependency's own
    /// generated `RUNTIME_CODE` beside its `DEPLOYED_ADDRESS`.
    /// @param addresses The dependency addresses.
    /// @return The declaration.
    function mockDeployableDependencies(address[] memory addresses) internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory dependencies = new DeployDependency[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            dependencies[i] =
                DeployDependency({deployedAddress: addresses[i], runtimeCode: type(MockDeployable).runtimeCode});
        }
        return dependencies;
    }

    /// The two dependency addresses, in declaration order.
    /// @return addresses The addresses.
    function twoDependencies() internal pure returns (address[] memory addresses) {
        addresses = new address[](2);
        addresses[0] = FIRST_DEPENDENCY;
        addresses[1] = SECOND_DEPENDENCY;
    }

    /// External wrapper, so a derivation that cannot run its constructor is a
    /// failed CALL rather than a reverted test.
    /// @param suite The suite to derive.
    /// @return The derivation.
    function externalDeriveDeployment(DeploySuite memory suite) external returns (DerivedDeploy memory) {
        return deriveDeployment(suite);
    }

    /// A suite whose CONSTRUCTOR reads a dependency MUST derive, against the
    /// runtime code its own declaration carries.
    ///
    /// Derivation runs before anything forks, on an EVM where nothing is
    /// deployed, so a declared dependency is absent there by construction. Such
    /// a suite used to fail `DeployFailed(false, 0x0)` with its constructor's
    /// own revert buried, which left every pin it records checked by nothing —
    /// and that record is what the broadcast asserts against before it deploys.
    ///
    /// Both halves of the derivation are checked against oracles outside it:
    /// the pure address formula, and the mock's own runtime code. The code hash
    /// is the half that cannot be had without running the constructor, so it is
    /// the half that says the constructor ran.
    function testDerivationEtchesTheDeclaredDependencies() external {
        address[] memory addresses = new address[](1);
        addresses[0] = FIRST_DEPENDENCY;
        bytes memory creationCode = dependentCreationCode(addresses);

        DerivedDeploy memory derived =
            deriveDeployment(dependentSuite(creationCode, mockDeployableDependencies(addresses)));

        assertEq(derived.deployedAddress, LibRainDeploy.zoltuAddress(creationCode));
        assertEq(derived.bytecodeHash, keccak256(type(MockDependentDeployable).runtimeCode));

        // The etch is inside the snapshot the derivation reverts, so a
        // dependency is no more present afterwards than the local deploy is. A
        // dependency that leaked would be on every fork the chain group selects
        // afterwards, where the deployment under test is what is supposed to be
        // answering.
        assertEq(FIRST_DEPENDENCY.code.length, 0, "the dependency etch survived the derivation");
        assertEq(derived.deployedAddress.code.length, 0, "the local deploy survived the derivation");
    }

    /// The etch MUST be what makes the derivation above possible.
    ///
    /// The same creation code, needing the same dependency, with a declaration
    /// that carries none: the constructor cannot run and the derivation fails.
    /// Without this, "it derived" says nothing about the etch — it could as
    /// easily be a suite that never needed a dependency at all.
    function testDerivationOfAnUndeclaredDependencyCannotRunTheConstructor() external {
        address[] memory addresses = new address[](1);
        addresses[0] = FIRST_DEPENDENCY;

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, false, address(0)));
        this.externalDeriveDeployment(dependentSuite(dependentCreationCode(addresses), new DeployDependency[](0)));
    }

    /// EVERY declared dependency MUST be etched, not the first of them.
    ///
    /// A constructor reading two addresses derives only if both are there, so a
    /// loop that stopped after the first entry fails this. The suites this
    /// matters for are the ones with several — a set deployer constructing a
    /// beacon per implementation — where etching one of them is the defect that
    /// looks exactly like the fix.
    function testDerivationEtchesEveryDeclaredDependency() external {
        address[] memory addresses = twoDependencies();
        bytes memory creationCode = dependentCreationCode(addresses);

        DerivedDeploy memory derived =
            deriveDeployment(dependentSuite(creationCode, mockDeployableDependencies(addresses)));

        assertEq(derived.deployedAddress, LibRainDeploy.zoltuAddress(creationCode));
        assertEq(derived.bytecodeHash, keccak256(type(MockDependentDeployable).runtimeCode));

        assertEq(FIRST_DEPENDENCY.code.length, 0, "the first dependency etch survived the derivation");
        assertEq(SECOND_DEPENDENCY.code.length, 0, "the second dependency etch survived the derivation");
    }

    /// The second entry MUST be load-bearing in the test above.
    ///
    /// The same two-dependency constructor against a declaration carrying only
    /// the first: it fails, so a pass up there is a pass that needed the second
    /// entry. Otherwise a declaration whose tail is ignored and a declaration
    /// read whole are the same green.
    function testDerivationOfAPartlyDeclaredDependencyListFails() external {
        address[] memory declared = new address[](1);
        declared[0] = FIRST_DEPENDENCY;

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, false, address(0)));
        this.externalDeriveDeployment(
            dependentSuite(dependentCreationCode(twoDependencies()), mockDeployableDependencies(declared))
        );
    }

    /// The SUBJECT is deployed and never etched, whatever the declaration says
    /// about its address.
    ///
    /// A declaration naming the subject's own derived address is a declaration
    /// that would plant code where the deploy has to land. The derivation
    /// clears that address AFTER the declaration is etched, so the subject's
    /// code can only be what its creation code left behind.
    ///
    /// This is the one failure mode a blanket etch has and an etch of the
    /// dependencies does not: a subject that is etched rather than deployed
    /// hands back the runtime code the record already holds, so
    /// `checkInternallyConsistent` compares `storedBytecodeHash` against the
    /// record it came from and the suite is verified by nothing. The assertion
    /// is therefore against the mock's runtime code and AGAINST the code the
    /// declaration supplied, which are different values.
    function testDerivationDoesNotEtchTheSubject() external {
        address[] memory addresses = new address[](1);
        addresses[0] = FIRST_DEPENDENCY;
        bytes memory creationCode = dependentCreationCode(addresses);
        address subject = LibRainDeploy.zoltuAddress(creationCode);

        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] =
            DeployDependency({deployedAddress: FIRST_DEPENDENCY, runtimeCode: type(MockDeployable).runtimeCode});
        // The subject's own address, carrying code that is not the subject's.
        dependencies[1] = DeployDependency({deployedAddress: subject, runtimeCode: type(MockDeployable).runtimeCode});

        DerivedDeploy memory derived = deriveDeployment(dependentSuite(creationCode, dependencies));

        assertEq(derived.deployedAddress, subject);
        assertEq(derived.bytecodeHash, keccak256(type(MockDependentDeployable).runtimeCode));
        assertNotEq(derived.bytecodeHash, keccak256(type(MockDeployable).runtimeCode));
    }

    /// A declaration MUST NOT be able to replace the Zoltu factory bytecode the
    /// derivation deploys THROUGH.
    ///
    /// The factory is a legitimate dependency to declare — nothing deploys
    /// without it — so an address that matters to this function is an address a
    /// correct declaration may well name. The factory is etched AFTER the
    /// declaration, so whatever code a declaration pairs with that address, the
    /// derivation still runs through the real factory.
    function testDerivationDoesNotLetTheDeclarationReplaceTheZoltuFactory() external {
        address[] memory addresses = new address[](1);
        addresses[0] = FIRST_DEPENDENCY;
        bytes memory creationCode = dependentCreationCode(addresses);

        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] =
            DeployDependency({deployedAddress: FIRST_DEPENDENCY, runtimeCode: type(MockDeployable).runtimeCode});
        // The factory's address, carrying code that is not the factory's.
        dependencies[1] = DeployDependency({
            deployedAddress: LibRainDeploy.ZOLTU_FACTORY, runtimeCode: type(MockDeployable).runtimeCode
        });

        DerivedDeploy memory derived = deriveDeployment(dependentSuite(creationCode, dependencies));

        assertEq(derived.deployedAddress, LibRainDeploy.zoltuAddress(creationCode));
        assertEq(derived.bytecodeHash, keccak256(type(MockDependentDeployable).runtimeCode));
    }

    /// A dependency declared with NO code is etched as no code, so a suite that
    /// needs it still fails rather than deriving against an address that merely
    /// exists.
    ///
    /// The field carries code because an address alone cannot say what belongs
    /// at one. An implementation that treated a declaration as "mark these
    /// present" — a single non-zero byte, say — would derive this suite and
    /// report a success for a constructor that never read anything, and every
    /// pin it recorded would be checked against that.
    function testDerivationEtchesTheDeclaredCodeAndNotAPresenceMarker() external {
        address[] memory addresses = new address[](1);
        addresses[0] = FIRST_DEPENDENCY;

        DeployDependency[] memory dependencies = new DeployDependency[](1);
        dependencies[0] = DeployDependency({deployedAddress: FIRST_DEPENDENCY, runtimeCode: hex""});

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, false, address(0)));
        this.externalDeriveDeployment(dependentSuite(dependentCreationCode(addresses), dependencies));
    }
}
