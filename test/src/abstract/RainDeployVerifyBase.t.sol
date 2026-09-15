// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
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
            dependencies: new address[](0)
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
    /// seven endpoints for a subject at address zero otherwise.
    function testDerivingNoSuitesDerivesNothing() external {
        DerivedDeploy[] memory derived = deriveDeployments(new DeploySuite[](0));
        assertEq(derived.length, 0);
    }
}
