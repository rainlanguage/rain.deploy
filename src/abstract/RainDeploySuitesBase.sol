// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {StdConstants} from "forge-std-1.17.0/src/StdConstants.sol";

import {LibRainDeploy} from "../lib/LibRainDeploy.sol";

/// Thrown when two suites share a key. The key selects what gets broadcast, so
/// a duplicate makes the selection ambiguous and one of the two unreachable.
/// @param suite The key declared more than once.
error DuplicateDeploySuite(string suite);

/// Thrown when a suite declares a key outside the key alphabet.
///
/// A key is a NAME, or a name and a release TAG joined by an at sign: the name
/// lowercase letters and hyphens, the tag those plus digits and underscores,
/// neither half empty and at most one at sign. Digits and underscores after the
/// at sign only, which is where a tag needs them and where nothing else does.
///
/// That is the kebab case a repo declares by hand, and it is what
/// `LibRainDeploySnapshot` emits a released entry as — the candidate key the
/// release was cut from, the at sign, and the record directory's tag, which
/// `isTag` already holds to `X_Y_Z` — so a generated declaration needs no
/// exemption from the rule a hand written one is held to. The at sign cannot
/// appear in a name, so that emission carries exactly one however many releases
/// a repo cuts.
///
/// The key list is why an alphabet exists at all. `suiteNames()` joins the
/// declared keys on `", "` for `UnknownDeploymentSuite`, which exists so a
/// caller who does NOT already know the valid keys is told them; a key free to
/// carry either of those characters renders as two, so the reader is told a
/// different number of suites exist than do and is sent after a key that is
/// declared nowhere. A list that cannot be read back as the set it names is the
/// hardcoded string the registry exists to replace, spelled differently.
///
/// The EMPTY key is refused by the same rule, and is the one refusal with a
/// broadcast behind it: it is the value `RainDeployBroadcast.run()` substitutes
/// for an absent `DEPLOYMENT_SUITE`, so a declaration allowed to answer it
/// turns "told nothing" into a selection, and `CREATE2` under a zero salt puts
/// those bytes at their own permanent address on every chain that dispatch
/// reached. An alphabet admitting no zero byte key already says that; a length
/// check beside it would be a second rule for one property, free to drift.
///
/// Held on the DECLARATION rather than beside the substitution, for the reason
/// `NoDeployCandidates` is: a rule bound in the consumer is a rule most
/// consumers do not run, and here every `suiteByName` caller pays for it rather
/// than only `run()`.
/// @param index Position in `allSuites()`: the released suites in declaration
/// order, then the candidates. An empty key names nothing, so the position is
/// the only thing that can.
/// @param suite The refused key.
error InvalidDeploySuiteKey(uint256 index, string suite);

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
/// @param sourceCreationCodeHash Hash of the creation code the contract the
/// candidate NAMES — its `artifactPath` — currently compiles to.
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
    /// The key. Unique across every suite a repo declares, and held to the key
    /// alphabet — see `InvalidDeploySuiteKey`. It is what
    /// `DEPLOYMENT_SUITE` selects for broadcasting, the label every
    /// verification error names, and what the valid-key list an unknown suite
    /// reports has to read back as.
    ///
    /// A repo with one contract and several frozen releases gives each release
    /// its own key, because each is separately deployable — a chain added after
    /// a release is exactly the case where an OLD snapshot has to be broadcast
    /// on its own.
    string suite;
    /// The creation code this suite is a snapshot of. The only parameter.
    ///
    /// A generated `CREATION_CODE` constant: a frozen one for a released
    /// snapshot, the rolling one for a candidate. Frozen matters: a released
    /// suite broadcasts the exact bytes its audit covered, whatever the current
    /// source now compiles to.
    ///
    /// Spelling `type(X).creationCode` here puts both operands of
    /// `checkCandidatesAnchoredToSource` on the source side and leaves the one
    /// check that catches a snapshot of the wrong contract comparing source to
    /// itself, green.
    bytes creationCode;
    /// The deploy address recorded for this suite.
    address storedDeployedAddress;
    /// The deployed code hash recorded for this suite.
    bytes32 storedBytecodeHash;
    /// The runtime code recorded for this suite. A generated `RUNTIME_CODE`
    /// constant.
    bytes storedRuntimeCode;
    /// `<path>:<Name>`: the contract this suite is a snapshot OF.
    ///
    /// Declared rather than derived from the contract name. `src/concrete/`
    /// holds only the flattest repos; a repo that groups concretes into
    /// subdirectories has paths no naming convention recovers.
    ///
    /// For a candidate this is load-bearing: `checkCandidatesAnchoredToSource`
    /// resolves it through `vm.getCode`, so a path that resolves to no
    /// artifact, or to more than one, fails at the anchor before the broadcast.
    string artifactPath;
    /// Addresses that MUST already have code on a network before this suite is
    /// broadcast there. Ordinarily other suites' recorded addresses: a
    /// constructor that bakes in a beacon, or a fallback that delegatecalls a
    /// facet, silently produces a broken deployment if its target is absent.
    address[] dependencies;
}

/// The rolling candidate: a snapshot that tracks current source rather than a
/// frozen release, and that MUST equal what the contract it names currently
/// compiles to.
struct DeployCandidate {
    /// The candidate's own recorded snapshot, checked exactly as any other
    /// suite is, and anchored to what its `artifactPath` compiles to.
    DeploySuite snapshot;
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
/// The networks are here for the same reason, and are one list for the same
/// reason: `supportedNetworks` is what the broadcast targets and what every
/// network-scoped assertion is made over, so a repo cannot be verified on a
/// different set of networks than it deploys to either.
///
/// A repo overrides `releasedSuites` and `candidateSuites` on one abstract
/// contract and inherits that into its deploy script and its test contracts,
/// and overrides `supportedNetworks` there too if it deploys to fewer than all
/// of them. Nothing else is per suite and nothing else is per network.
abstract contract RainDeploySuitesBase {
    /// Every FROZEN released suite, in any order. A released snapshot is
    /// immutable: its recorded bytes describe a deployment that already
    /// happened, so it is never regenerated and never anchored to current
    /// source.
    /// @return The released suites.
    function releasedSuites() internal pure virtual returns (DeploySuite[] memory);

    /// The rolling candidates — one snapshot per contract this repo compiles
    /// right now, each naming the contract it MUST be the current compilation
    /// of.
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

    /// Every network this repo deals with: what a broadcast targets and the set
    /// every network-scoped assertion is made over. Defaults to all of Rain's.
    ///
    /// ONE hook, on the contract both sides inherit, because the set of networks
    /// a repo deals with is one fact. A `virtual` per verification function
    /// would be three ways for verification to end up narrower than what the
    /// repo broadcasts to, with nothing to catch it.
    ///
    /// `deployNetworks` narrowing this is a different thing and stays
    /// available: that is one dispatch's targets, not the repo's set.
    /// @return The network names, as `[rpc_endpoints]` aliases.
    function supportedNetworks() internal view virtual returns (string[] memory) {
        return LibRainDeploy.supportedNetworks();
    }

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

    /// EVERY candidate MUST record the creation code the contract it NAMES
    /// currently compiles to.
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
    /// false by design.
    function checkCandidatesAnchoredToSource() internal view {
        DeployCandidate[] memory candidates = checkedCandidateSuites();
        for (uint256 i = 0; i < candidates.length; i++) {
            bytes32 stored = keccak256(candidates[i].snapshot.creationCode);
            bytes32 source = keccak256(StdConstants.VM.getCode(candidates[i].snapshot.artifactPath));
            if (stored != source) {
                revert CandidateSourceMismatch(candidates[i].snapshot.suite, stored, source);
            }
        }
    }

    /// Refuses a key the registry cannot carry — see `InvalidDeploySuiteKey`.
    ///
    /// Held against the WHOLE key rather than against a name a released key is
    /// derived from, because `releasedSuites()` declares finished keys: a rule
    /// that only knew the name half could not be asked about a released entry
    /// at all, and this is the one place every key a repo declares is read.
    /// @param index Position in `allSuites()`, for the refusal to name.
    /// @param suite The key to check.
    function checkSuiteKey(uint256 index, string memory suite) internal pure {
        bytes memory key = bytes(suite);
        // Where the tag starts, and zero until an `@` is seen. Zero is not a
        // position a tag can start at, because an `@` opening the key leaves
        // the name half empty and is refused below.
        uint256 tagStart = 0;

        for (uint256 i = 0; i < key.length; i++) {
            bytes1 char = key[i];
            if (char == "@") {
                if (i == 0 || tagStart != 0) {
                    revert InvalidDeploySuiteKey(index, suite);
                }
                tagStart = i + 1;
            } else {
                bool nameAlphabet = (char >= "a" && char <= "z") || char == "-";
                bool tagAlphabet = (char >= "0" && char <= "9") || char == "_";
                if (!(nameAlphabet || (tagStart != 0 && tagAlphabet))) {
                    revert InvalidDeploySuiteKey(index, suite);
                }
            }
        }

        // The empty key and a trailing at sign: the loop only refuses bytes that are there.
        if (tagStart == key.length) {
            revert InvalidDeploySuiteKey(index, suite);
        }
    }

    /// Every suite this repo declares: the released ones followed by the
    /// candidates. This is the verification set and the deploy registry, which
    /// are the same set because they are the same declaration.
    ///
    /// Keys are checked here rather than anywhere more specific, so both sides
    /// pay for the check and neither can be handed a registry that is ambiguous
    /// or that answers the absent-sentinel. One pass over the whole set, so a
    /// candidate colliding with another candidate is caught by the same code
    /// that catches a candidate colliding with a release, and a key the
    /// alphabet refuses is refused wherever in the declaration it was spelled —
    /// there is no second rule to keep in step.
    ///
    /// Unique AND in the alphabet, because neither implies the other: a lone
    /// unreadable key collides with nothing, and two keys can be spelled
    /// perfectly and still be the same key.
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
            checkSuiteKey(i, suites[i].suite);
            for (uint256 j = i + 1; j < suites.length; j++) {
                if (keccak256(bytes(suites[i].suite)) == keccak256(bytes(suites[j].suite))) {
                    revert DuplicateDeploySuite(suites[i].suite);
                }
            }
        }

        return suites;
    }

    /// Every declared key, comma separated, for the unknown-suite error.
    ///
    /// Splitting the result on `", "` recovers exactly the declared keys,
    /// because the alphabet `allSuites` holds them to carries neither of those
    /// two characters anywhere but between two keys.
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
