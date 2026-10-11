// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployCandidate, DeployMechanism} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    CLONE_ARTIFACT_PATH,
    CLONE_UNANCHORABLE_REASON,
    CloneDeploy,
    CloneTarget,
    LibRainDeployClone
} from "../../../src/lib/LibRainDeployClone.sol";
import {DeployDependency} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {
    exampleCloneDependencies,
    exampleCloneFactory,
    exampleCloneImplementation
} from "../../abstract/ExampleCloneDeploys.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";

/// @title LibRainDeployMechanismTest
/// Tests for `LibRainDeployMechanism`.
contract LibRainDeployMechanismTest is Test {
    /// A salt with bytes set across the whole word, so a derivation that
    /// truncated it or used only its low bytes would be caught.
    bytes32 constant TEST_SALT = 0x1122334455667788990011223344556677889900112233445566778899001122;

    /// Init data that is neither empty nor a single word.
    bytes constant TEST_DATA = hex"deadbeefcafe0102030405060708090a0b0c0d0e0f";

    /// A clone declaration over the given factory and implementation.
    /// @param suite The suite key.
    /// @param factory The factory to clone through.
    /// @param implementation The implementation to clone.
    /// @param dependencies The dependencies declared beside the clone.
    /// @return The clone declaration.
    function declaredClone(
        string memory suite,
        address factory,
        address implementation,
        DeployDependency[] memory dependencies
    ) internal pure returns (CloneDeploy memory) {
        return CloneDeploy({
            suite: suite,
            factory: factory,
            implementation: implementation,
            data: TEST_DATA,
            salt: TEST_SALT,
            dependencies: dependencies
        });
    }

    /// The target a clone declaration deploys.
    /// @param clone The clone declaration.
    /// @return The target.
    function targetOf(CloneDeploy memory clone) internal pure returns (CloneTarget memory) {
        return
            CloneTarget({
                factory: clone.factory, implementation: clone.implementation, data: clone.data, salt: clone.salt
            });
    }

    /// The suite key MUST NOT move the address. It names the clone in the
    /// declaration; it is not part of what gets deployed, and a derivation that
    /// hashed it in would make a rename a redeploy to a new address.
    function testCloneAddressIgnoresTheSuiteKey() external pure {
        DeployCandidate memory named = LibRainDeployMechanism.cloneCandidate(
            declaredClone(
                "local-clone", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies()
            )
        );
        DeployCandidate memory renamed = LibRainDeployMechanism.cloneCandidate(
            declaredClone(
                "renamed-clone", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies()
            )
        );
        assertEq(renamed.snapshot.storedDeployedAddress, named.snapshot.storedDeployedAddress);
        assertEq(renamed.snapshot.mechanismData, named.snapshot.mechanismData);
    }

    /// `cloneCandidate` MUST derive every field of the candidate from the clone,
    /// and MUST carry the standard unanchorable reason. Each field asserted
    /// against its own derivation, because the point of the builder is that a
    /// consumer no longer writes these by hand.
    function testCloneCandidateDerivesEveryField() external pure {
        CloneDeploy memory clone = declaredClone(
            "local-clone", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies()
        );
        CloneTarget memory target = targetOf(clone);
        DeployCandidate memory candidate = LibRainDeployMechanism.cloneCandidate(clone);

        assertEq(candidate.snapshot.suite, clone.suite);
        assertEq(candidate.snapshot.creationCode, LibRainDeployClone.cloneCreationCode(clone.implementation));
        assertEq(candidate.snapshot.storedDeployedAddress, LibRainDeployClone.cloneDeployedAddress(target));
        assertEq(candidate.snapshot.storedBytecodeHash, LibRainDeployClone.cloneDeployedCodehash(clone.implementation));
        assertEq(candidate.snapshot.storedRuntimeCode, LibRainDeployClone.cloneRuntimeCode(clone.implementation));
        assertEq(candidate.snapshot.artifactPath, CLONE_ARTIFACT_PATH);
        assertEq(uint256(candidate.snapshot.mechanism), uint256(DeployMechanism.Clone));
        assertEq(candidate.snapshot.mechanismData, abi.encode(target));
        assertEq(candidate.snapshot.dependencies.length, clone.dependencies.length);
        for (uint256 i = 0; i < clone.dependencies.length; i++) {
            assertEq(candidate.snapshot.dependencies[i].deployedAddress, clone.dependencies[i].deployedAddress);
            assertEq(candidate.snapshot.dependencies[i].runtimeCode, clone.dependencies[i].runtimeCode);
        }
        assertEq(candidate.unanchorableReason, CLONE_UNANCHORABLE_REASON);

        // The reason has to be NON-empty: an empty one is what says a candidate
        // IS anchorable, which would send the source anchor looking for an
        // artifact that cannot exist.
        assertNotEq(bytes(candidate.unanchorableReason).length, 0);
    }

    /// The recorded code hash MUST be the hash of the recorded runtime code, and
    /// the recorded address MUST be where the recorded creation code lands. The
    /// candidate's internal consistency, which the verification abstracts assume.
    function testCloneCandidateIsInternallyConsistent() external {
        MockCloneFactory factory = new MockCloneFactory();
        MockCloneable implementation = new MockCloneable();
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({deployedAddress: address(factory), runtimeCode: address(factory).code});
        dependencies[1] =
            DeployDependency({deployedAddress: address(implementation), runtimeCode: address(implementation).code});
        CloneDeploy memory clone = declaredClone("local-clone", address(factory), address(implementation), dependencies);
        DeployCandidate memory candidate = LibRainDeployMechanism.cloneCandidate(clone);

        assertEq(candidate.snapshot.storedBytecodeHash, keccak256(candidate.snapshot.storedRuntimeCode));
        address deployed = factory.cloneDeterministicOpenSalt(clone.implementation, clone.data, clone.salt);
        assertEq(deployed, candidate.snapshot.storedDeployedAddress);
        assertEq(deployed.codehash, candidate.snapshot.storedBytecodeHash);
    }
}
