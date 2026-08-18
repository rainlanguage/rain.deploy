// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Thrown when two suites share a key. The key selects what gets broadcast, so
/// a duplicate makes the selection ambiguous and one of the two unreachable.
/// @param suite The key declared more than once.
error DuplicateDeploySuite(string suite);

/// Thrown when `DEPLOYMENT_SUITE` names no declared suite. Carries the valid
/// keys, because the whole point of a registry is that the answer is not one
/// hardcoded string the caller has to already know.
/// @param requested The key that was asked for.
/// @param validSuites The declared keys, comma separated.
error UnknownDeploymentSuite(string requested, string validSuites);

/// Thrown when a declaration names no candidate at all.
///
/// The source anchor is the ONLY check that catches a snapshot of the wrong
/// contract, and it runs over the candidates and nothing else. A declaration
/// with an empty candidate list is therefore not a repo with nothing to say —
/// it is a declaration that has quietly opted out of that check while every
/// other assertion stays green.
///
/// A deploy repo always compiles a current source, so there is always something
/// to declare. When the candidate was a single struct this was true by
/// construction; a list has to say it.
///
/// Raised from `checkedCandidateSuites` — see there for why the guard sits at
/// that one read rather than at each reader.
///
/// `releasedSuites` is read directly by the chain group and by the frozen
/// record check, and is untouched by this: a repo with no release is an
/// ordinary state, and it is the CANDIDATE that the source anchor needs.
error NoDeployCandidates();

/// Thrown when a candidate's recorded creation code is not the creation code
/// this repo currently compiles. Hashes rather than the bytes themselves, which
/// run to tens of kilobytes.
/// @param suite The candidate's key.
/// @param storedCreationCodeHash Hash of the creation code the candidate
/// records.
/// @param sourceCreationCodeHash Hash of `type(X).creationCode` for the
/// contract the candidate claims to be.
error CandidateSourceMismatch(string suite, bytes32 storedCreationCodeHash, bytes32 sourceCreationCodeHash);

/// One deployable unit: a named snapshot of one contract.
///
/// `creationCode` is the ONLY input. The Zoltu factory is `CREATE2` over its
/// calldata under a zero salt, so the deploy address is a pure function of it
/// and identical on every network, and running it once locally yields the
/// runtime code and its hash. The address, code hash and runtime code recorded
/// beside it are checked OUTPUTS, which is what the verification abstracts
/// check them as.
///
/// They are recorded rather than derived on purpose. `LibRainDeploy` compares
/// the recorded address against the creation code before it forks anything, so
/// a snapshot whose pins have gone stale fails BEFORE broadcasting rather than
/// deploying to wherever the code happens to land. Deriving them here would
/// make that comparison derived-against-derived, and a guard that compares a
/// value to itself is not a guard.
struct DeploySuite {
    /// The key. Unique across every suite a repo declares: it is what
    /// `DEPLOYMENT_SUITE` selects for broadcasting, and the label every
    /// verification error names.
    ///
    /// A repo with one contract and several frozen releases gives each release
    /// its own key, because each is separately deployable — a chain added after
    /// a release is exactly the case where an OLD snapshot has to be broadcast
    /// on its own.
    string suite;
    /// The creation code this suite is a snapshot of. The only parameter.
    ///
    /// A frozen `CREATION_CODE` constant for a released snapshot, or
    /// `type(X).creationCode` where nothing is frozen yet. Frozen matters: a
    /// released suite broadcasts the exact bytes its audit covered, whatever
    /// the current source now compiles to.
    bytes creationCode;
    /// The deploy address recorded for this suite.
    address storedDeployedAddress;
    /// The deployed code hash recorded for this suite.
    bytes32 storedBytecodeHash;
    /// The runtime code recorded for this suite. A frozen `RUNTIME_CODE`
    /// constant, or `type(X).runtimeCode` where nothing is frozen yet.
    bytes storedRuntimeCode;
    /// `<path>:<Name>`, for the explorer verification command.
    ///
    /// Declared rather than derived from the contract name. `src/concrete/`
    /// holds only the flattest repos; a repo that groups concretes into
    /// subdirectories has paths no naming convention recovers.
    string artifactPath;
    /// Addresses that MUST already have code on a network before this suite is
    /// broadcast there. Ordinarily other suites' recorded addresses: a
    /// constructor that bakes in a beacon, or a fallback that delegatecalls a
    /// facet, silently produces a broken deployment if its target is absent.
    address[] dependencies;
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
/// It is deliberately absent from `DeploySuite` and therefore from released
/// suites: a released tag is MEANT to diverge from current source, so anchoring
/// one to source would fail on every release that is not the newest. That is a
/// property of the assertion, not an opt-out — there is no way for a caller to
/// spell "released, and also skip the checks that do apply".
struct DeployCandidate {
    /// The candidate's own recorded snapshot, checked exactly as any other.
    DeploySuite snapshot;
    /// `type(X).creationCode` for the contract the candidate claims to be.
    bytes sourceCreationCode;
}

/// @title RainDeploySuitesBase
/// @notice The ONE declaration of what a repo deploys, consumed by both the
/// broadcasting abstract and the verification abstracts.
///
/// That sharing is the point. A repo that declared its suites twice — once for
/// the deploy script, once for the verification tests — could broadcast one
/// contract while verifying another and have every test pass, because nothing
/// would connect the two lists. Here there is one list, so the deployment and
/// the thing checked against the chain cannot disagree: not because it is
/// checked, but because there is nothing to disagree with.
///
/// A repo overrides `releasedSuites` and `candidateSuites` on one abstract
/// contract and inherits that into its deploy script and its test contracts.
/// Nothing else is per suite, and nothing anywhere is per network.
abstract contract RainDeploySuitesBase {
    /// Every FROZEN released suite, in any order. A released snapshot is
    /// immutable: its recorded bytes describe a deployment that already
    /// happened, so it is never regenerated and never anchored to current
    /// source.
    /// @return The released suites.
    function releasedSuites() internal pure virtual returns (DeploySuite[] memory);

    /// The rolling candidates — one snapshot per contract this repo compiles
    /// right now, each paired with the source it MUST equal.
    ///
    /// A list because a repo deploys as many contracts as it deploys, and each
    /// of them has its own rolling snapshot and its own source to be anchored
    /// to. A single candidate leaves a repo's second deployed contract either
    /// undeclared or declared as a release it is not, and in both cases the one
    /// check that catches a snapshot of the wrong contract is never handed it.
    ///
    /// Two suites abstracts cannot be composed into that gap either: both would
    /// override this, and a repo inherits exactly one declaration. So the list
    /// is here rather than left to the consumer to assemble.
    ///
    /// MUST NOT be empty, which `checkedCandidateSuites` enforces. A deploy
    /// repo always compiles a current source, so there is always something to
    /// anchor to — see `NoDeployCandidates` for why an empty list is worse
    /// than it looks.
    /// @return The candidates.
    function candidateSuites() internal pure virtual returns (DeployCandidate[] memory);

    /// The declared candidates, refusing an empty list.
    ///
    /// The ONE place `NoDeployCandidates` is raised, and the only way anything
    /// reads the candidates. `allSuites` goes through it, and so does
    /// `checkCandidatesAnchoredToSource` — which matters, because the source
    /// anchor loops over the candidates and a loop over an empty list passes.
    /// Guarding each reader separately would be two spellings of one rule, and
    /// the reader that got the second spelling wrong is the one that silently
    /// stops asserting.
    /// @return The candidates.
    function checkedCandidateSuites() internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = candidateSuites();
        if (candidates.length == 0) {
            revert NoDeployCandidates();
        }
        return candidates;
    }

    /// EVERY candidate MUST record the creation code this repo compiles.
    ///
    /// This is the ONLY check that catches a snapshot of the wrong contract.
    /// Everything else a snapshot is asked is internal to the snapshot — the
    /// recorded address is what the recorded creation code derives, the
    /// recorded code hash is what it produces — and a consistent snapshot of
    /// the wrong thing satisfies all of it, because the wrong contract's bytes
    /// agree with each other perfectly.
    ///
    /// It lives on the DECLARATION rather than on the verification abstract
    /// because the broadcast runs it too. `RainDeployBroadcast` deploys the
    /// bytes a candidate records, and the only guard between it and the Zoltu
    /// factory is `LibRainDeploy`'s recorded-address-against-recorded-creation-
    /// code comparison — both sides of which come out of the same generated
    /// file, so it proves that file is internally consistent and nothing more.
    /// A source anchor reachable only from a test contract is an anchor the
    /// irreversible action does not run: broadcasting is `workflow_dispatch` on
    /// a ref with no required-green gate, so "CI is red on that ref" is a
    /// signal a human may not have read, and CREATE2 at a zero salt puts the
    /// wrong bytes at their own permanent address on every chain the dispatch
    /// reached. One definition, both callers, no way to deploy past it.
    ///
    /// EVERY candidate, because a candidate the loop never reaches is a
    /// contract whose snapshot nothing anywhere anchors — and a repo with
    /// several contracts is exactly where a snapshot generated from the wrong
    /// one comes from.
    ///
    /// Read through `checkedCandidateSuites` rather than `candidateSuites`: a
    /// loop over an empty list passes, so a declaration with no candidate at
    /// all would turn this into a green check that asserts nothing.
    ///
    /// Candidates alone, and there is no way to spell an exemption. A released
    /// suite is MEANT to diverge from current source — it records bytes that
    /// are already on chain — so anchoring one to source asserts something
    /// false by design, which is why `DeploySuite` carries no source at all and
    /// only `DeployCandidate` does.
    function checkCandidatesAnchoredToSource() internal pure {
        DeployCandidate[] memory candidates = checkedCandidateSuites();
        for (uint256 i = 0; i < candidates.length; i++) {
            bytes32 stored = keccak256(candidates[i].snapshot.creationCode);
            bytes32 source = keccak256(candidates[i].sourceCreationCode);
            if (stored != source) {
                revert CandidateSourceMismatch(candidates[i].snapshot.suite, stored, source);
            }
        }
    }

    /// Every suite this repo declares: the released ones followed by the
    /// candidates. This is the verification set and the deploy registry, which
    /// are the same set because they are the same declaration.
    ///
    /// Keys are checked unique here rather than anywhere more specific, so both
    /// sides pay for the check and neither can be handed an ambiguous registry.
    /// One pairwise pass over the whole set, so a candidate colliding with
    /// another candidate is caught by the same code that catches a candidate
    /// colliding with a release — there is no second rule to keep in step.
    /// @return Every declared suite.
    function allSuites() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory released = releasedSuites();
        DeployCandidate[] memory candidates = checkedCandidateSuites();

        DeploySuite[] memory suites = new DeploySuite[](released.length + candidates.length);
        for (uint256 i = 0; i < released.length; i++) {
            suites[i] = released[i];
        }
        for (uint256 i = 0; i < candidates.length; i++) {
            suites[released.length + i] = candidates[i].snapshot;
        }

        for (uint256 i = 0; i < suites.length; i++) {
            for (uint256 j = i + 1; j < suites.length; j++) {
                if (keccak256(bytes(suites[i].suite)) == keccak256(bytes(suites[j].suite))) {
                    revert DuplicateDeploySuite(suites[i].suite);
                }
            }
        }

        return suites;
    }

    /// Every declared key, comma separated, for the unknown-suite error.
    /// @return The declared keys.
    function suiteNames() internal pure returns (string memory) {
        DeploySuite[] memory suites = allSuites();
        string memory names;
        for (uint256 i = 0; i < suites.length; i++) {
            names = i == 0 ? suites[i].suite : string.concat(names, ", ", suites[i].suite);
        }
        return names;
    }

    /// The suite a key selects.
    ///
    /// Iterating the registry rather than branching on a hash: a repo adds a
    /// suite by adding an array entry, and the set of valid keys the failure
    /// reports follows from the same array rather than from a string somebody
    /// remembered to update.
    /// @param requested The key to select, from `DEPLOYMENT_SUITE`.
    /// @return The selected suite.
    function suiteByName(string memory requested) internal pure returns (DeploySuite memory) {
        DeploySuite[] memory suites = allSuites();
        bytes32 requestedHash = keccak256(bytes(requested));
        for (uint256 i = 0; i < suites.length; i++) {
            if (keccak256(bytes(suites[i].suite)) == requestedHash) {
                return suites[i];
            }
        }
        revert UnknownDeploymentSuite(requested, suiteNames());
    }
}
