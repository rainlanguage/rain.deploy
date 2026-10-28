// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {StdConstants} from "forge-std-1.17.0/src/StdConstants.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";

// `DeployDependency` is imported rather than declared here, and is therefore
// importable FROM here: this is the path every declaration and every generated
// released lib names, and the struct lives beside `deployToNetworks`, which is
// what holds a declared pair to a chain.
import {DeployDependency, LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "../lib/LibRainDeploySnapshot.sol";
import {LibRainDeployDeclaration} from "../lib/LibRainDeployDeclaration.sol";

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

/// Thrown when a candidate's `artifactPath` is not `<path>:<Name>`.
///
/// `vm.getCode` resolves a BARE contract name to whichever same-named artifact
/// it finds first, and answers rather than reverting when several match. So a
/// bare name anchors the candidate against a contract that merely shares a
/// name, silently, and the only check that catches a snapshot of the wrong
/// contract is the one it defeats. Refused on the path rather than detected
/// afterwards, because a resolved artifact carries nothing saying which of the
/// same-named files it came from.
///
/// Raised from `checkedCandidateSuites`, for the reason `NoDeployCandidates`
/// is: every candidate reader goes through that one read. `.sol:` and not any
/// colon: forge reads `Name:0.8.25` as a name plus a compiler version, which
/// qualifies nothing.
/// @param index Position in the candidate list. The path may be shared by two
/// candidates, or empty, so the position is what names the entry.
/// @param artifactPath The refused path.
error UnqualifiedCandidateArtifactPath(uint256 index, string artifactPath);

/// Thrown when a candidate's recorded creation code is not the creation code
/// this repo currently compiles. Hashes rather than the bytes themselves, which
/// run to tens of kilobytes.
/// @param suite The candidate's key.
/// @param storedCreationCodeHash Hash of the creation code the candidate
/// records.
/// @param sourceCreationCodeHash Hash of the creation code the contract the
/// candidate NAMES — its `artifactPath` — currently compiles to.
error CandidateSourceMismatch(string suite, bytes32 storedCreationCodeHash, bytes32 sourceCreationCodeHash);

/// Thrown when a candidate declares an `unanchorableReason` and its
/// `artifactPath` resolves anyway. An artifact is the claim being false, and
/// taking it at its word would make the anchor opt-out for any candidate.
/// @param suite The candidate's key.
/// @param artifactPath The artifact id that resolved.
error CandidateSourceCompiles(string suite, string artifactPath);

/// Thrown when the state snapshot taken around a local deploy could not be
/// reverted. A local deploy plants code at the derived address, clears its
/// nonce and etches the suite's declared dependencies; if that cannot be
/// undone, every later local deploy reads state this one created, and the
/// chain-anchored checks compare a locally planted deployment against itself,
/// and the broadcast seat check reads a deployment planted under an earlier
/// target's chain id.
/// There is no safe way to continue.
/// @param suite The suite deployed locally when the revert failed.
/// @param snapshotId The snapshot that could not be reverted.
error DerivationSnapshotRevertFailed(string suite, uint256 snapshotId);

/// Thrown when the pure `LibRainDeploy.zoltuAddress` formula and an actual deploy through the
/// etched Zoltu factory bytecode disagree about where a creation code lands.
/// @param suite The suite whose creation code was being derived.
/// @param formulaAddress The address `zoltuAddress` computed.
/// @param factoryAddress The address the factory bytecode actually deployed to.
error ZoltuDerivationMismatch(string suite, address formulaAddress, address factoryAddress);

/// Thrown when a Zoltu suite carries mechanism data other than Zoltu's own.
/// @param suite The suite carrying the data.
error UnexpectedMechanismData(string suite);

/// Thrown when a Zoltu release's frozen record declares `MECHANISM_DATA`.
/// @param path The record file.
error FrozenSnapshotMechanismDataUnexpected(string path);

/// Thrown when no mechanism in the declaration has the id a suite or a released record declares.
/// @param suite The suite's key, or the record file.
error MechanismUnclaimed(string suite);

/// Thrown when two of the declaration's mechanisms share an id.
/// @param id The shared id.
error DuplicateMechanism(bytes32 id);

/// One deployable unit.
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
    /// The deploy address recorded for this suite, on every network.
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
    /// resolves it through `vm.getCode`, so a path that resolves to no artifact
    /// fails at the anchor before the broadcast, and a path that is not
    /// `<path>:<Name>` is refused before that — see
    /// `UnqualifiedCandidateArtifactPath`. A candidate declaring an
    /// `unanchorableReason` inverts the anchor: resolving to no artifact is the
    /// declared state, and resolving to one refuses it. It is still held to
    /// `<path>:<Name>`, which it spells against the file it WOULD have.
    string artifactPath;
    /// What MUST already be on a network before this suite is broadcast there:
    /// an address and the runtime code that belongs at it, per dependency.
    /// Ordinarily other suites' recorded pins — a constructor that bakes in a
    /// beacon, or a fallback that delegatecalls a facet, silently produces a
    /// broken deployment if its target is absent.
    ///
    /// The code half is a CLAIM about every network, and it is checked as one.
    /// `RainDeployVerifyBase.deriveDeployment` etches it so that such a
    /// constructor can run at all, which makes this suite's derived code hash a
    /// function of what is declared here; `LibRainDeploy.deployToNetworks`
    /// hashes the live code at each address against it, per network, before it
    /// broadcasts anything. So a wrong declaration is a red deploy run rather
    /// than a wrong hash frozen into a release.
    DeployDependency[] dependencies;
    /// What the suite's mechanism needs: `abi.encode(id, payload)` for the mechanism with that id, Zoltu's included.
    bytes mechanismData;
    /// The networks, as `[rpc_endpoints]` aliases, the suite has an address on and the chain group requires it live
    /// on. A suite required on none of the networks checked is refused with `SuiteRequiredNowhere`.
    string[] networks;
}

/// Everything a repo declares, as data. A declaration starts empty and every contribution is a layer's `extend(d)`.
struct DeployDeclaration {
    /// Every FROZEN released suite, in any order, never regenerated nor anchored to current source.
    DeploySuite[] released;
    /// The rolling candidates, one per contract this repo compiles; MUST NOT be empty (`NoDeployCandidates`).
    DeployCandidate[] candidates;
    /// The mechanisms its suites deploy through, in any order, ids unique.
    DeployMechanismHandler[] mechanisms;
    /// Every network this repo deals with, as `[rpc_endpoints]` aliases: what a broadcast targets, what every
    /// network-scoped assertion is made over, and what the network config is generated from.
    string[] networks;
}

/// The rolling candidate: a snapshot that tracks current source rather than a
/// frozen release, and that MUST equal what the contract it names currently
/// compiles to.
struct DeployCandidate {
    /// The candidate's own recorded snapshot, checked exactly as any other
    /// suite is, and anchored to what its `artifactPath` compiles to.
    DeploySuite snapshot;
    /// Why no compiler produces this candidate's source — a vendored third
    /// party deployment, or a data contract assembled from generated tables.
    /// Empty for an ordinary candidate.
    ///
    /// Prose rather than a flag because the justification is the point.
    /// Nothing checks what it says, only that it is non-empty, and it is
    /// refused wherever `artifactPath` resolves.
    string unanchorableReason;
}

/// A deploy mechanism, one function per mechanism step. It handles exactly the suites and records declaring its `id`
/// as the first word of their `mechanismData`. The `add*` steps mutate the suite they are given.
struct DeployMechanismHandler {
    bytes32 id;
    function(DeploySuite memory, uint256) internal view returns (address) deployedAddress;
    function(DeploySuite memory, uint256) internal view returns (address) recordedAddress;
    function(DeploySuite memory, uint256) internal view returns (bytes memory) deployStepData;
    function(DeploySuite memory)
        internal
        view returns (function(Vm, string memory, address, bytes memory) internal returns (address)) deployStep;
    function(Vm, DeploySuite memory) internal returns (address[] memory) deployLocally;
    function(Vm, DeploySuite memory) internal deployLocallyOnChain;
    function(DeploySuite memory, DeploySuite memory, uint256[] memory) internal view addUnrecordedNetworks;
    function(DeploySuite memory) internal view addRecordedNetworks;
    function(DeploySuite memory, string memory, uint256, address) internal view checkNetworkFrozen;
    function(DeploySuite memory, string memory, uint256, address) internal view checkOnChain;
    function(Vm, string[] memory, DeploySuite memory, address[] memory) internal logVerification;
    function(Vm, string memory, string memory, string memory, string memory, string memory, DeploySuite memory)
        internal returns (string memory) writeSuiteSnapshot;
    function(Vm, string memory, string memory) internal view returns (string memory) releasedMechanismData;
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
/// reason: `supportedNetworks` is what the broadcast targets, what every
/// network-scoped assertion is made over, and what the generated
/// `[rpc_endpoints]`, `[etherscan]` and `.env.example` blocks are emitted from,
/// so a repo cannot be verified on a different set of networks than it deploys
/// to, nor configured for a set it does neither on.
///
/// A repo implements `declaration` on one abstract contract and inherits that into its deploy script, its build
/// script and its test contracts. It is the one override: the roles read every declared fact through it.
abstract contract RainDeploySuitesBase {
    /// Everything this repo declares.
    /// @return The declaration.
    function declaration() internal view virtual returns (DeployDeclaration memory);

    /// Whether a suite declares a network among its `networks`.
    /// @param suite The suite.
    /// @param network The network, as an `[rpc_endpoints]` alias.
    /// @return True if the suite MUST be live on the network.
    function requiresSuiteOn(DeploySuite memory suite, string memory network) internal pure returns (bool) {
        for (uint256 i = 0; i < suite.networks.length; i++) {
            if (keccak256(bytes(suite.networks[i])) == keccak256(bytes(network))) {
                return true;
            }
        }
        return false;
    }

    /// @param suite The suite.
    /// @return The chain id of each of its `networks`, in order.
    function suiteChainIds(DeploySuite memory suite) internal pure returns (uint256[] memory) {
        return LibRainDeploy.networkChainIds(LibRainDeploy.declaredNetworkConfigs(suite.networks));
    }

    /// The candidate a suite key names.
    /// @param suite The suite key.
    /// @return The snapshot of the candidate whose key is `suite`'s name half, freshly read from the declaration.
    /// @return Whether there is one.
    function candidateOf(DeployDeclaration memory d, string memory suite)
        internal
        view
        returns (DeploySuite memory, bool)
    {
        bytes32 name = keccak256(bytes(suiteKeyName(suite)));
        DeployCandidate[] memory candidates = checkedCandidateSuites(d);
        for (uint256 i = 0; i < candidates.length; i++) {
            if (keccak256(bytes(candidates[i].snapshot.suite)) == name) {
                return (candidates[i].snapshot, true);
            }
        }
        DeploySuite memory none;
        return (none, false);
    }

    /// Adds to `suite` the networks among `chainIds` its candidate takes it to, the candidate being a copy of `suite`
    /// when its key names none.
    /// @param suite The suite, mutated.
    /// @param chainIds The chain ids in play.
    function addCandidateNetworks(DeployDeclaration memory d, DeploySuite memory suite, uint256[] memory chainIds)
        internal
        view
    {
        (DeploySuite memory candidate, bool found) = candidateOf(d, suite.suite);
        if (!found) {
            candidate = abi.decode(abi.encode(suite), (DeploySuite));
        }
        addUnrecordedNetworks(d, suite, candidate, chainIds);
    }

    /// The mechanism id a suite's `mechanismData` declares: its first word. Refuses `MechanismUnclaimed` for data
    /// shorter than a word.
    /// @param suite The suite.
    /// @return The id.
    function mechanismIdOf(DeploySuite memory suite) internal pure returns (bytes32) {
        bytes memory data = suite.mechanismData;
        if (data.length < 0x20) {
            revert MechanismUnclaimed(suite.suite);
        }
        bytes32 id;
        assembly ("memory-safe") {
            id := mload(add(data, 0x20))
        }
        return id;
    }

    /// @param suite The suite.
    /// @return The handler of the mechanism its data declares.
    function mechanismOf(DeployDeclaration memory d, DeploySuite memory suite)
        internal
        view
        returns (DeployMechanismHandler memory)
    {
        return LibRainDeployDeclaration.mechanismById(d, mechanismIdOf(suite), suite.suite);
    }

    function deployedAddress(DeployDeclaration memory d, DeploySuite memory suite, uint256 chainId)
        internal
        view
        returns (address)
    {
        return mechanismOf(d, suite).deployedAddress(suite, chainId);
    }

    function recordedAddress(DeployDeclaration memory d, DeploySuite memory suite, uint256 chainId)
        internal
        view
        returns (address)
    {
        return mechanismOf(d, suite).recordedAddress(suite, chainId);
    }

    function deployStepData(DeployDeclaration memory d, DeploySuite memory suite, uint256 chainId)
        internal
        view
        returns (bytes memory)
    {
        return mechanismOf(d, suite).deployStepData(suite, chainId);
    }

    function deployStep(DeployDeclaration memory d, DeploySuite memory suite)
        internal
        view
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        return mechanismOf(d, suite).deployStep(suite);
    }

    function deployLocally(DeployDeclaration memory d, Vm vm, DeploySuite memory suite)
        internal
        returns (address[] memory)
    {
        return mechanismOf(d, suite).deployLocally(vm, suite);
    }

    function deployLocallyOnChain(DeployDeclaration memory d, Vm vm, DeploySuite memory suite) internal {
        mechanismOf(d, suite).deployLocallyOnChain(vm, suite);
    }

    function addUnrecordedNetworks(
        DeployDeclaration memory d,
        DeploySuite memory suite,
        DeploySuite memory candidate,
        uint256[] memory chainIds
    ) internal view {
        mechanismOf(d, suite).addUnrecordedNetworks(suite, candidate, chainIds);
    }

    function addRecordedNetworks(DeployDeclaration memory d, DeploySuite memory suite) internal view {
        mechanismOf(d, suite).addRecordedNetworks(suite);
    }

    function checkNetworkFrozen(
        DeployDeclaration memory d,
        DeploySuite memory frozen,
        string memory network,
        uint256 chainId,
        address where
    ) internal view {
        mechanismOf(d, frozen).checkNetworkFrozen(frozen, network, chainId, where);
    }

    function checkOnChain(
        DeployDeclaration memory d,
        DeploySuite memory suite,
        string memory network,
        uint256 chainId,
        address deployed
    ) internal view {
        mechanismOf(d, suite).checkOnChain(suite, network, chainId, deployed);
    }

    function logVerification(
        DeployDeclaration memory d,
        Vm vm,
        string[] memory networks,
        DeploySuite memory suite,
        address[] memory deployed
    ) internal {
        mechanismOf(d, suite).logVerification(vm, networks, suite, deployed);
    }

    function writeSuiteSnapshot(
        DeployDeclaration memory d,
        Vm vm,
        string memory root,
        string memory dir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory suite
    ) internal returns (string memory) {
        return mechanismOf(d, suite)
            .writeSuiteSnapshot(vm, root, dir, contractName, spdxLicenseIdentifier, copyrightText, suite);
    }

    /// @param suite The suite.
    /// @return The address its mechanism derives for it on each of its `networks`, in order.
    function deployedAddresses(DeployDeclaration memory d, DeploySuite memory suite)
        internal
        view
        returns (address[] memory)
    {
        uint256[] memory chainIds = suiteChainIds(suite);
        address[] memory addresses = new address[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            addresses[i] = deployedAddress(d, suite, chainIds[i]);
        }
        return addresses;
    }

    /// @param suite The suite.
    /// @return The address it records for itself on each of its `networks`, in order.
    function recordedAddresses(DeployDeclaration memory d, DeploySuite memory suite)
        internal
        view
        returns (address[] memory)
    {
        uint256[] memory chainIds = suiteChainIds(suite);
        address[] memory addresses = new address[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            addresses[i] = recordedAddress(d, suite, chainIds[i]);
        }
        return addresses;
    }

    /// `checkNetworkFrozen` on each of `networks` among `onNetworks`' networks, with its recorded address there.
    /// @param frozen The release with its recorded networks.
    /// @param onNetworks The release as it would be broadcast, with its candidate's unrecorded networks.
    /// @param networks The networks to broadcast to.
    function checkNetworksFrozen(
        DeployDeclaration memory d,
        DeploySuite memory frozen,
        DeploySuite memory onNetworks,
        string[] memory networks
    ) internal view {
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(networks);
        for (uint256 i = 0; i < configs.length; i++) {
            if (requiresSuiteOn(onNetworks, networks[i])) {
                checkNetworkFrozen(
                    d, frozen, networks[i], configs[i].chainId, recordedAddress(d, onNetworks, configs[i].chainId)
                );
            }
        }
    }

    /// The name half of a suite key.
    /// @param suite The suite key.
    /// @return The name half.
    function suiteKeyName(string memory suite) internal pure returns (string memory) {
        bytes memory key = bytes(suite);
        uint256 length = key.length;
        for (uint256 i = 0; i < key.length; i++) {
            if (key[i] == "@") {
                length = i;
                break;
            }
        }
        bytes memory name = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            name[i] = key[i];
        }
        return string(name);
    }

    /// The declared candidates, refusing an empty list and an `artifactPath`
    /// that is not `<path>:<Name>`.
    ///
    /// The ONE place `NoDeployCandidates` and
    /// `UnqualifiedCandidateArtifactPath` are raised, and the only way anything
    /// reads the candidates. `allSuites` goes through it, and so does
    /// `checkCandidatesAnchoredToSource` — which matters, because the source
    /// anchor loops over the candidates and a loop over an empty list passes.
    /// Guarding each reader separately would be two spellings of one rule, and
    /// the reader that got the second spelling wrong is the one that silently
    /// stops asserting.
    /// @return The candidates.
    function checkedCandidateSuites(DeployDeclaration memory d) internal view returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = d.candidates;
        if (candidates.length == 0) {
            revert NoDeployCandidates();
        }
        for (uint256 i = 0; i < candidates.length; i++) {
            bytes memory path = bytes(candidates[i].snapshot.artifactPath);
            // `.sol:` and not merely a colon, because forge reads `Name:0.8.25`
            // as a contract name plus a compiler version — a colon that
            // qualifies nothing, and a path that still resolves to whichever
            // same-named artifact comes first. Measured: `Dup2:0.8.25` resolves
            // to the same bytes as `File.sol:Dup2` with two `Dup2` compiled.
            bool qualified = false;
            for (uint256 j = 0; j + 5 <= path.length; j++) {
                if (
                    path[j] == "." && path[j + 1] == "s" && path[j + 2] == "o" && path[j + 3] == "l"
                        && path[j + 4] == ":"
                ) {
                    qualified = true;
                    break;
                }
            }
            if (!qualified) {
                revert UnqualifiedCandidateArtifactPath(i, candidates[i].snapshot.artifactPath);
            }
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
    /// Candidates alone. A released suite is MEANT to diverge from current
    /// source — it records bytes that are already on chain — so anchoring one
    /// to source asserts something false by design.
    ///
    /// `unanchorableReason` is not an exemption from the comparison but a
    /// declaration that there is no second operand to make one with, refused
    /// wherever `vm.getCode` can make one.
    function checkCandidatesAnchoredToSource(DeployDeclaration memory d) internal view {
        DeployCandidate[] memory candidates = checkedCandidateSuites(d);
        for (uint256 i = 0; i < candidates.length; i++) {
            if (bytes(candidates[i].unanchorableReason).length != 0) {
                // `vm.getCode` reverts rather than answering, so reading the
                // artifact is the only way to ask whether there is one.
                bool compiles = true;
                try StdConstants.VM.getCode(candidates[i].snapshot.artifactPath) returns (bytes memory) {}
                catch {
                    compiles = false;
                }
                if (compiles) {
                    revert CandidateSourceCompiles(candidates[i].snapshot.suite, candidates[i].snapshot.artifactPath);
                }
                // The next candidate, not the end of the loop.
                continue;
            }
            bytes32 stored = keccak256(candidates[i].snapshot.creationCode);
            // Direct, not through the `try` above, so a path that resolves to
            // nothing and claims nothing fails as the cheatcode's own revert —
            // which is a NO match only: a name matching several resolves to
            // whichever comes first, which `checkedCandidateSuites` refuses.
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
    function allSuites(DeployDeclaration memory d) internal view returns (DeploySuite[] memory) {
        DeploySuite[] memory released = d.released;
        DeployCandidate[] memory candidates = checkedCandidateSuites(d);

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
    function suiteNames(DeployDeclaration memory d) internal view returns (string memory) {
        DeploySuite[] memory suites = allSuites(d);
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
    function suiteByName(DeployDeclaration memory d, string memory requested)
        internal
        view
        returns (DeploySuite memory)
    {
        DeploySuite[] memory suites = allSuites(d);
        uint256 index = suiteIndex(suites, requested);
        if (index == suites.length) {
            revert UnknownDeploymentSuite(requested, suiteNames(d));
        }
        return suites[index];
    }

    /// @param suites The suites to search.
    /// @param requested The key to select.
    /// @return The index in `suites` of the suite `requested` selects, `suites.length` if none.
    function suiteIndex(DeploySuite[] memory suites, string memory requested) internal pure returns (uint256) {
        bytes32 requestedHash = keccak256(bytes(requested));
        for (uint256 i = 0; i < suites.length; i++) {
            if (keccak256(bytes(suites[i].suite)) == requestedHash) {
                return i;
            }
        }
        return suites.length;
    }
}
