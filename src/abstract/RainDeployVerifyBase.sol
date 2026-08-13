// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibRainDeploy} from "../lib/LibRainDeploy.sol";

/// Thrown when the pure `LibRainDeploy.zoltuAddress` formula and an actual
/// deploy through the etched Zoltu factory bytecode disagree about where a
/// creation code lands. Both are `LibRainDeploy`'s, so this is a defect in the
/// library rather than in any snapshot, and it invalidates every derivation
/// made from it.
/// @param version The version label whose creation code was being derived.
/// @param formulaAddress The address `zoltuAddress` computed.
/// @param factoryAddress The address the factory bytecode actually deployed to.
error ZoltuDerivationMismatch(string version, address formulaAddress, address factoryAddress);

/// One recorded deployment of one version of one contract.
///
/// `creationCode` is the ONLY input. Everything else is an OUTPUT that gets
/// checked against it: the Zoltu factory is `CREATE2` over its calldata under a
/// zero salt, so the deploy address is a pure function of the creation code and
/// identical on every network, and running that creation code once locally
/// yields the runtime code and its hash. A pointers file records all four, but
/// only one of them is a parameter.
///
/// `creationCode` comes from wherever this version's creation code is recorded:
/// the frozen `CREATION_CODE` constant of a released snapshot, or
/// `type(X).creationCode` for a version that has no frozen snapshot yet.
struct DeployVersion {
    /// The version label, e.g. `0_1_5` or `candidate`. Carried into every error
    /// so a failure names the version that failed rather than an array index.
    string version;
    /// The creation code this version is a snapshot of. The only parameter.
    bytes creationCode;
    /// The deploy address recorded for this version, to be checked against the
    /// address `creationCode` derives.
    address storedDeployedAddress;
    /// The deployed code hash recorded for this version, to be checked against
    /// the hash `creationCode` produces.
    bytes32 storedBytecodeHash;
    /// The runtime code recorded for this version, to be checked against
    /// `storedBytecodeHash`. A frozen `RUNTIME_CODE` constant for a released
    /// snapshot, or `type(X).runtimeCode` where nothing is frozen yet.
    bytes storedRuntimeCode;
}

/// The rolling candidate: the snapshot that tracks current source rather than a
/// frozen release, paired with the current source's creation code it MUST
/// equal.
///
/// This pairing is the ONLY thing that catches a snapshot of the wrong
/// contract. Every check internal to a snapshot is satisfied by a consistent
/// snapshot of the wrong thing, so without an anchor to source there is nothing
/// that says the recorded bytes belong to the contract this repo compiles.
///
/// It is deliberately absent from `DeployVersion` and therefore from released
/// versions: a released tag is MEANT to diverge from current source, so
/// anchoring one to source would fail on every release that is not the newest.
/// That is a property of the assertion, not an opt-out — there is no way for a
/// caller to spell "released, and also skip the checks that do apply".
struct DeployCandidate {
    /// The candidate's own recorded snapshot, checked exactly as any other.
    DeployVersion snapshot;
    /// `type(X).creationCode` for the contract the candidate claims to be.
    bytes sourceCreationCode;
}

/// What a version's creation code derives, offline and by itself. Computed
/// once and then compared against whatever claims to hold it, whether that is a
/// recorded constant or a live chain.
struct DerivedDeploy {
    /// The version label the derivation came from.
    string version;
    /// The address the creation code deploys to, on every network.
    address deployedAddress;
    /// The code hash the creation code leaves behind at that address.
    bytes32 bytecodeHash;
}

/// @title RainDeployVerifyBase
/// @notice The parameterization shared by every deploy-verification group: a
/// repo declares its versions once, and the derivation from creation code to
/// (address, code hash) happens in one place rather than being restated per
/// version and per chain.
///
/// This is not inherited directly. `RainDeployVerifyOffline` and
/// `RainDeployVerifyChain` each inherit it and contribute the checks that need
/// no network and the checks that do, respectively. A repo declares its
/// versions on one abstract contract and inherits that into one of each, so
/// running the offline checks never touches an RPC endpoint — an outage is then
/// a failure of one contract that plainly is about the chain, and can never be
/// confused with, or take down, the assertions that hold offline.
///
/// ## Chain-independent runtime code is a requirement, not a caveat
///
/// A single `storedBytecodeHash` per version can only be true if the runtime
/// code is the same on every network. A constructor that reads `block.chainid`,
/// or anything else that varies per chain, produces a different code hash per
/// chain and cannot be described by these snapshots at all. Deploying through
/// Zoltu buys address predictability; a constructor that reads chain state
/// spends it. So a per-chain code hash difference is a DEFECT in the contract,
/// reported as a hard failure naming the chain and both hashes, and there is
/// deliberately no per-chain code hash to record.
abstract contract RainDeployVerifyBase is Test {
    /// Every FROZEN released version, in any order. A released snapshot is
    /// immutable: its recorded bytes describe a deployment that already
    /// happened, so it is never regenerated and never anchored to current
    /// source.
    /// @return The released versions to verify.
    function releasedVersions() internal pure virtual returns (DeployVersion[] memory);

    /// The rolling candidate — the snapshot describing what this repo compiles
    /// right now. Required rather than optional: a deploy repo always compiles
    /// a current source, so there is always something for the source-anchored
    /// check to anchor to, and making it optional would let the only check that
    /// catches a wrong-contract snapshot be silently skipped.
    /// @return The candidate to verify.
    function candidateVersion() internal pure virtual returns (DeployCandidate memory);

    /// Every version this repo records: the released ones plus the candidate.
    /// The checks that apply to a version regardless of its status run over
    /// this.
    /// @return versions The released versions followed by the candidate.
    function allVersions() internal pure returns (DeployVersion[] memory versions) {
        DeployVersion[] memory released = releasedVersions();
        versions = new DeployVersion[](released.length + 1);
        for (uint256 i = 0; i < released.length; i++) {
            versions[i] = released[i];
        }
        versions[released.length] = candidateVersion().snapshot;
    }

    /// Derives what a version's creation code deploys to, from the creation
    /// code alone.
    ///
    /// The address comes from the pure `LibRainDeploy.zoltuAddress` formula and
    /// the code hash from actually running the creation code through the Zoltu
    /// factory bytecode locally, because the code hash cannot be known without
    /// executing the constructor. The two are cross-checked against each other,
    /// so a formula that drifted from the factory bytecode is caught here
    /// rather than silently poisoning every downstream comparison.
    ///
    /// The whole derivation runs inside a state snapshot that is reverted, and
    /// clears the derived address first, so that it reads ONLY what the
    /// creation code produces. Both matter:
    ///
    /// - Two versions can legitimately share creation code (a release that
    ///   changed nothing that compiles), and `CREATE2` to an occupied address
    ///   fails. Clearing makes the second derivation work, and reverting means
    ///   the first never occupied it in the first place.
    /// - The local deploy must not survive into the chain-anchored checks. A
    ///   locally deployed contract that leaked into a fork would be compared
    ///   against itself, and every chain would pass whether or not anything is
    ///   deployed there.
    /// @param version The version to derive from.
    /// @return derived The address and code hash the creation code produces.
    function deriveDeployment(DeployVersion memory version) internal returns (DerivedDeploy memory derived) {
        address formulaAddress = LibRainDeploy.zoltuAddress(version.creationCode);

        uint256 snapshotId = vm.snapshotState();

        // Whatever is at the derived address is not part of the derivation.
        // The nonce goes too: `CREATE2` collides on a non-zero nonce as well as
        // on non-empty code.
        vm.etch(formulaAddress, hex"");
        vm.resetNonce(formulaAddress);

        LibRainDeploy.etchZoltuFactory(vm);
        address factoryAddress = LibRainDeploy.deployZoltu(version.creationCode);
        if (factoryAddress != formulaAddress) {
            revert ZoltuDerivationMismatch(version.version, formulaAddress, factoryAddress);
        }

        derived = DerivedDeploy({
            version: version.version, deployedAddress: formulaAddress, bytecodeHash: factoryAddress.codehash
        });

        // revertToState returns whether the snapshot existed; it was taken
        // above, so bind and reference it to satisfy the unused-return lint
        // rather than asserting on it.
        bool reverted = vm.revertToState(snapshotId);
        (reverted);
    }

    /// Derives every version once, before anything forks. Callers that compare
    /// against chains need the derivation to have already happened on a local
    /// EVM, because on a fork the derived address is exactly the address the
    /// deployment under test occupies.
    /// @param versions The versions to derive.
    /// @return derived The derivation of each, positionally paired.
    function deriveDeployments(DeployVersion[] memory versions) internal returns (DerivedDeploy[] memory derived) {
        derived = new DerivedDeploy[](versions.length);
        for (uint256 i = 0; i < versions.length; i++) {
            derived[i] = deriveDeployment(versions[i]);
        }
    }
}
