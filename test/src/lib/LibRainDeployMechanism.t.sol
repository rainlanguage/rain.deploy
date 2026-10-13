// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {DeployCandidate, DeployMechanism, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    CLONE_ARTIFACT_PATH,
    CLONE_UNANCHORABLE_REASON,
    CloneDeploy,
    CloneNetworkData,
    CloneTarget,
    LibRainDeployClone
} from "../../../src/lib/LibRainDeployClone.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    CloneCreationCodeMismatch,
    CloneDerivationMismatch,
    LibRainDeployMechanism,
    UnexpectedMechanismData
} from "../../../src/lib/LibRainDeployMechanism.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
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
            networkData: new CloneNetworkData[](0),
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

    /// @param suite The suite whose address is wanted.
    /// @return The address the suite's mechanism derives.
    function externalDeployedAddress(DeploySuite memory suite) external pure returns (address) {
        return LibRainDeployMechanism.deployedAddresses(suite)[0];
    }

    /// @param suite The suite to deploy locally.
    /// @return The address the suite was deployed to.
    function externalDeployLocally(DeploySuite memory suite) external returns (address) {
        return LibRainDeployMechanism.deployLocally(vm, suite)[0];
    }

    /// @param networks The networks to broadcast to.
    /// @param suite The suite to broadcast.
    /// @return forkIds The fork each network was deployed on.
    function externalDeployAndBroadcast(string[] memory networks, DeploySuite memory suite)
        external
        returns (uint256[] memory forkIds)
    {
        (, forkIds) = LibRainDeployMechanism.deployAndBroadcast(vm, networks, 1, suite);
    }

    /// The example clone over its declared factory and implementation, as a
    /// suite.
    /// @return The clone suite.
    function exampleCloneSuite() internal pure returns (DeploySuite memory) {
        return LibRainDeployMechanism.cloneCandidate(
            declaredClone("example", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies())
        )
        .snapshot;
    }

    /// A clone suite deploys locally to the address its mechanism derives, and
    /// what lands there is the proxy. The positive half every refusal below is
    /// measured against.
    function testCloneSuiteDeploysLocallyToItsDerivedAddress() external {
        DeploySuite memory suite = exampleCloneSuite();
        address deployed = this.externalDeployLocally(suite);
        assertEq(deployed, suite.storedDeployedAddress);
        assertEq(deployed, this.externalDeployedAddress(suite));
        assertEq(deployed.code, suite.storedRuntimeCode);
    }

    /// A clone's factory and implementation are what its address and code are
    /// functions of, so a suite that does not declare either is refused before
    /// an address is derived from it — by the address derivation and the local
    /// deploy alike.
    function testCloneSuiteMissingADeclaredDependencyIsRefused() external {
        DeploySuite memory suite = exampleCloneSuite();
        DeployDependency[] memory declared = suite.dependencies;

        suite.dependencies = new DeployDependency[](1);
        suite.dependencies[0] = declared[1];
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, declared[0].deployedAddress)
        );
        this.externalDeployedAddress(suite);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, declared[0].deployedAddress)
        );
        this.externalDeployLocally(suite);

        suite.dependencies[0] = declared[0];
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, declared[1].deployedAddress)
        );
        this.externalDeployedAddress(suite);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, declared[1].deployedAddress)
        );
        this.externalDeployLocally(suite);
    }

    /// A Zoltu suite has no mechanism data. One that carries some is a suite
    /// declared as one mechanism and filled in as another, so every dispatch
    /// refuses it rather than deploying the creation code and ignoring the
    /// rest — the broadcast before any network is forked.
    function testZoltuSuiteCarryingMechanismDataIsRefused() external {
        DeploySuite memory suite = DeploySuite({
            suite: "zoltu-with-data",
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
        assertEq(this.externalDeployedAddress(suite), suite.storedDeployedAddress);

        suite.mechanismData = hex"00";
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        this.externalDeployedAddress(suite);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        this.externalDeployLocally(suite);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        this.externalDeployAndBroadcast(networks, suite);
    }

    /// A factory whose clone lands somewhere other than the address the formula
    /// derives is refused, naming both: a release recorded at the formula's
    /// address would otherwise be a release of a clone that is not there.
    function testCloneFactoryLandingOffTheFormulaIsRefused() external {
        DeploySuite memory suite = exampleCloneSuite();
        address elsewhere = address(uint160(suite.storedDeployedAddress) + 1);
        vm.mockCall(
            exampleCloneFactory(),
            abi.encodeWithSelector(ICloneableFactoryV4.cloneDeterministicOpenSalt.selector),
            abi.encode(elsewhere)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                CloneDerivationMismatch.selector, suite.suite, suite.storedDeployedAddress, elsewhere
            )
        );
        this.externalDeployLocally(suite);
    }

    /// A clone suite's creation code MUST be the EIP-1167 proxy over its own
    /// implementation: it is what the record states the clone was made from,
    /// and the factory never reads it, so nothing else would catch a suite
    /// carrying the creation code of something else.
    function testCloneCreationCodeThatIsNotTheProxyIsRefused() external {
        DeploySuite memory suite = exampleCloneSuite();
        suite.creationCode = type(MockCloneable).creationCode;
        vm.expectRevert(abi.encodeWithSelector(CloneCreationCodeMismatch.selector, suite.suite));
        this.externalDeployLocally(suite);

        // The proxy over a DIFFERENT implementation is still not this clone's.
        suite.creationCode = LibRainDeployClone.cloneCreationCode(exampleCloneFactory());
        vm.expectRevert(abi.encodeWithSelector(CloneCreationCodeMismatch.selector, suite.suite));
        this.externalDeployLocally(suite);
    }
}
