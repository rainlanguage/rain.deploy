// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../../src/generated/candidate/AddressRegistry.sol";

/// @title RainDeployVerifyChainCandidateTest
/// @notice A repo between releases: source has moved on, so the candidate is a
/// different contract from the last release and is deployed nowhere. The
/// inherited matrix MUST pass anyway.
///
/// This is the ordinary state of a deploy repo, not a fault in one. A candidate
/// is what the NEXT release will be; requiring it to already be on chain asks
/// the repo to have deployed something it has not released, and would make
/// every repo permanently red for as long as its source was ahead of its last
/// deploy — which is most of the time.
///
/// It needs its own declaration because `ExampleDeploySuites` cannot say it:
/// its candidate shares creation code with a release, so every address it names
/// is live whichever scope the matrix uses, and the two are indistinguishable
/// there. Here the released suite is made live and the candidate deliberately
/// is not, at a DIFFERENT address, which is the only configuration that can
/// tell them apart.
///
/// It is its own contract in its own file rather than a second declaration
/// beside `RainDeployVerifyChainTest`, because the suites a contract inherits
/// are the whole of what the matrix runs over: a contract has exactly one
/// declaration, so a second scope is a second contract.
contract RainDeployVerifyChainCandidateTest is RainDeployVerifyChain {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](1);
        suites[0] = DeploySuite({
            suite: "address-registry-0-0-1",
            creationCode: ADDRESS_REGISTRY_CREATION_CODE,
            storedDeployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            storedBytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH,
            storedRuntimeCode: ADDRESS_REGISTRY_RUNTIME_CODE,
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
            dependencies: new address[](0)
        });
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "second-address-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
    }

    /// The RELEASE is live everywhere and the CANDIDATE is nowhere, both by
    /// construction: each account is etched to the state this contract is about
    /// and made persistent, so every fork carries that state rather than
    /// whatever the network holds.
    ///
    /// The candidate's absence is etched for the same reason the release's
    /// presence is. Reading it off the real chain would make the premise of
    /// `testChainIgnoresAnUndeployedCandidate` a claim about the world, and the
    /// Zoltu factory is permissionless — anyone can put `MockDeployableV2` at
    /// that address, and this contract would then assert nothing while still
    /// passing right up until they did.
    function setUp() external {
        vm.etch(ADDRESS_REGISTRY_DEPLOYED_ADDRESS, ADDRESS_REGISTRY_RUNTIME_CODE);
        vm.makePersistent(ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        address candidateAddress = LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode);
        vm.etch(candidateAddress, hex"");
        vm.makePersistent(candidateAddress);
    }

    /// The matrix MUST pass with the candidate on no network at all, and the
    /// candidate MUST really be absent on each of them — otherwise this passes
    /// for the wrong reason and says nothing about the scope. The per-fork
    /// reads are what say `setUp`'s construction reached every fork, so a
    /// persistent empty account that stopped carrying would fail here rather
    /// than quietly hand the matrix a live network.
    function testChainIgnoresAnUndeployedCandidate() external {
        address candidateAddress = LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode);
        assertNotEq(candidateAddress, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        string[] memory networks = LibRainDeploy.supportedNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 forkId = vm.createSelectFork(networks[i]);
            (forkId);
            assertEq(candidateAddress.code.length, 0);
            assertEq(ADDRESS_REGISTRY_DEPLOYED_ADDRESS.code, ADDRESS_REGISTRY_RUNTIME_CODE);
        }

        this.testSuitesLiveOnEverySupportedNetwork();
    }
}
