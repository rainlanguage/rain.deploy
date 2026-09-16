// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DerivedDeploy} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {
    CodeHashMismatchOnNetwork,
    DeclaredChainId,
    NetworkChainIdMismatch,
    NoDeclaredChainIds,
    NotDeployedOnNetwork,
    RainDeployVerifyChain
} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_BYTECODE_HASH,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../../src/generated/candidate/AddressRegistry.sol";

/// @title RainDeployVerifyChainTest
/// @notice `RainDeployVerifyChain` inherited by a exemplar repo whose versions
/// are made live on every network by `setUp`, so the inherited
/// `testSuitesLiveOnEverySupportedNetwork` is the passing case: it forks
/// every network `supportedNetworks()` returns and finds both released suites.
/// The candidate is etched too, so nothing here depends on whether the matrix
/// happens to reach it — `RainDeployVerifyChainCandidateTest`, in
/// `RainDeployVerifyChainCandidate.t.sol`, is what says it does not.
///
/// `setUp` places the code with a persistent `vm.etch` rather than pointing the
/// exemplar at some real deployment in another repo. A real one would make this
/// suite fail whenever that unrelated deployment moved — which is precisely the
/// signal this group exists to raise for its own repo, and precisely the wrong
/// thing to import into this one.
///
/// ## Absence is CONSTRUCTED here, never assumed
///
/// Every state this contract puts the matrix in is one it etches: present, wrong
/// code, and — the case below — absent. Absent is `vm.etch(addr, hex"")` on an
/// account that STAYS persistent, so each fork the matrix creates carries the
/// empty account no matter what that network holds.
///
/// Revoking persistence instead hands the matrix the real network, which turns
/// "nothing is deployed at this address" from something the fixture arranged
/// into a claim about the world. That claim is false here: the exemplar's
/// addresses come from `src/generated/candidate/`, which is exactly what
/// `Manual sol artifacts` broadcasts, and `AddressRegistry` is already live on
/// supported networks. A negative case resting on it asserts nothing and
/// reports `next call did not revert as expected` — a fixture that only worked
/// while the repo had not yet done the thing it exists to do.
///
/// Pointing the fixture at a mock nobody deploys would move that dependency
/// rather than remove it: the Zoltu factory is permissionless, so no address is
/// structurally unoccupiable. Etching the state the assertion is about is what
/// removes it.
///
/// The etch does not make the passing case circular. It writes the runtime code
/// the compiler emits, while the expectation is derived independently by running
/// the recorded CREATION code through the Zoltu factory. That the two agree is
/// the assertion. `testChainCodeHashMismatchReverts` is what proves it: it
/// leaves the etch in place and changes only the code, and the check still
/// fails, which it could not do if the expectation were read from the etch.
contract RainDeployVerifyChainTest is ExampleDeploySuites, RainDeployVerifyChain {
    /// The second suite's address, derived from `MockDeployableV2`'s creation
    /// code by the same derivation `ExampleDeploySuites` declares, so the etch
    /// in `setUp` lands on the address the matrix reads.
    /// @return The address.
    function secondDeployedAddress() internal pure returns (address) {
        return LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode);
    }

    /// The second suite's runtime code.
    /// @return The runtime code.
    function secondRuntimeCode() internal pure returns (bytes memory) {
        return type(MockDeployableV2).runtimeCode;
    }

    /// Makes every exemplar version live on every fork, which is what the
    /// inherited test then verifies. Persistent so it survives each
    /// `createSelectFork` inside the loop.
    function setUp() external {
        vm.etch(ADDRESS_REGISTRY_DEPLOYED_ADDRESS, ADDRESS_REGISTRY_RUNTIME_CODE);
        vm.makePersistent(ADDRESS_REGISTRY_DEPLOYED_ADDRESS);
        vm.etch(secondDeployedAddress(), secondRuntimeCode());
        vm.makePersistent(secondDeployedAddress());
    }

    /// External wrapper for `checkDeployedOnNetwork` so `vm.expectRevert` works
    /// at the correct call depth.
    /// @param network The network name, for the error only.
    /// @param derived The derivation to check for.
    function externalCheckDeployedOnNetwork(string memory network, DerivedDeploy memory derived) external view {
        checkDeployedOnNetwork(network, derived);
    }

    /// A version that is not on a network MUST fail, naming the network, the
    /// version and the address. This is the whole reason the group exists: a
    /// release that reached some chains and not others, or a chain added after
    /// a release that therefore never got it, is invisible to every other
    /// check.
    function testChainNotDeployedReverts() external {
        // Emptied, and left persistent, so every fork carries an empty account
        // here rather than whatever the network holds.
        vm.etch(ADDRESS_REGISTRY_DEPLOYED_ADDRESS, hex"");

        vm.expectRevert(
            abi.encodeWithSelector(
                NotDeployedOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                "address-registry@0_0_1",
                ADDRESS_REGISTRY_DEPLOYED_ADDRESS
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// The matrix MUST create every fork BEFORE it checks anything on any of
    /// them, for the reason `LibRainDeploy.createForks` gives: a fork created
    /// after the first select is seeded with whatever was read before it, so a
    /// deployed address the caller touched first would read as absent on every
    /// network but the one the matrix reaches first.
    ///
    /// A run that fails on that FIRST network is what makes the order visible.
    /// The matrix never reached the last supported network, so a fork of it
    /// exists only if it was created up front.
    function testChainMatrixCreatesEveryForkFirst() external {
        vm.etch(ADDRESS_REGISTRY_DEPLOYED_ADDRESS, hex"");

        vm.expectRevert(
            abi.encodeWithSelector(
                NotDeployedOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                "address-registry@0_0_1",
                ADDRESS_REGISTRY_DEPLOYED_ADDRESS
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();

        // This test forks nothing of its own, so the matrix's forks are ids 0
        // upwards in `supportedNetworks()` order. Selecting the last of them at
        // all is the assertion; the chain ids say it is a different network
        // from the one the failure named, rather than another fork of it.
        uint256 lastNetwork = LibRainDeploy.supportedNetworks().length - 1;
        vm.selectFork(0);
        uint256 firstChainId = block.chainid;
        vm.selectFork(lastNetwork);
        assertNotEq(block.chainid, firstChainId);
    }

    /// EVERY suite MUST be checked, not just the first one the matrix
    /// reaches. The version missing here is the LAST one, so a matrix that
    /// stopped after the first version would pass.
    function testChainNotDeployedRevertsForALaterSuite() external {
        vm.etch(secondDeployedAddress(), hex"");

        vm.expectRevert(
            abi.encodeWithSelector(
                NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, "second-address", secondDeployedAddress()
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// EVERY network MUST be forked, not just the first. A completed matrix
    /// leaves the LAST supported network selected, which a matrix that stopped
    /// early cannot do — and unlike a missing deployment, nothing about the
    /// passing case itself distinguishes the two.
    function testChainMatrixReachesTheLastSupportedNetwork() external {
        string[] memory networks = LibRainDeploy.supportedNetworks();

        uint256 lastForkId = vm.createSelectFork(networks[networks.length - 1]);
        (lastForkId);
        uint256 lastChainId = block.chainid;

        // Start somewhere the matrix does not end, so arriving at `lastChainId`
        // means the matrix moved rather than that it never forked at all.
        uint256 firstForkId = vm.createSelectFork(networks[0]);
        (firstForkId);
        assertNotEq(block.chainid, lastChainId);

        this.testSuitesLiveOnEverySupportedNetwork();

        assertEq(block.chainid, lastChainId);
    }

    /// A bad cell ends the run AT that cell. The matrix does not run the rest
    /// of itself out and report the first failure once it gets to the end,
    /// which is a different contract with identical revert data: the same
    /// error, after every remaining fork has been selected and read.
    ///
    /// The selected fork is what separates them, and it is the failing-case
    /// half of `testChainMatrixReachesTheLastSupportedNetwork`. A run that
    /// stopped is still on the network its error names; one that ran to the
    /// end is on the last supported network. Starting on the last network is
    /// what makes staying an observation rather than an accident: arriving at
    /// the first network says the matrix moved, and the assertion says that is
    /// where it stopped.
    function testChainFailureEndsTheRunAtThatCell() external {
        // Emptied before anything forks, and left persistent, so every fork the
        // matrix creates carries an empty account here.
        vm.etch(ADDRESS_REGISTRY_DEPLOYED_ADDRESS, hex"");

        string[] memory networks = LibRainDeploy.supportedNetworks();

        uint256 firstForkId = vm.createSelectFork(networks[0]);
        (firstForkId);
        uint256 firstChainId = block.chainid;

        uint256 lastForkId = vm.createSelectFork(networks[networks.length - 1]);
        (lastForkId);
        assertNotEq(block.chainid, firstChainId);

        vm.expectRevert(
            abi.encodeWithSelector(
                NotDeployedOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                "address-registry@0_0_1",
                ADDRESS_REGISTRY_DEPLOYED_ADDRESS
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();

        assertEq(block.chainid, firstChainId);
    }

    /// The early return for an empty set is about having NOTHING to check, not
    /// about the networks: handed ONE derivation, the matrix forks.
    ///
    /// The count is the whole point of the case. Every other test here runs the
    /// matrix over this contract's TWO released suites, so a guard keyed
    /// anywhere below two — `derived.length < 2` — returns early on every
    /// subject in the repo and is caught by none of them:
    /// `RainDeployVerifyChainCandidateTest` is the only other contract that
    /// reaches the matrix with a subject, at exactly one, and it forks on its own
    /// before calling, so a matrix that returned without forking is
    /// indistinguishable there. `RainDeployVerifyChainEmptyTest`'s empty case
    /// reads as satisfied under that guard, which is what makes one subject the
    /// length that discriminates.
    ///
    /// This contract is where it belongs because it already forks every
    /// supported network. Asserting it from the empty-set side would hand the
    /// contract that exists to need no RPC endpoint the whole-roster dependency
    /// the early return removes from it.
    function testChainWithASingleSubjectDoesFork() external {
        (bool activeBefore,) = address(vm).call(abi.encodeWithSignature("activeFork()"));
        assertFalse(activeBefore, "a fork was selected before the call");

        // One subject, and `setUp` left it etched persistently, so it is live
        // with its recorded hash on whichever forks the matrix creates and the
        // check itself passes on all of them.
        DerivedDeploy[] memory derived = new DerivedDeploy[](1);
        derived[0] = DerivedDeploy({
            suite: "address-registry@0_0_1",
            deployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            bytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH
        });

        checkDeployedOnSupportedNetworks(derived);

        (bool activeAfter,) = address(vm).call(abi.encodeWithSignature("activeFork()"));
        assertTrue(activeAfter, "the matrix checked a subject without forking");
    }

    /// Code on a network that is not the code the version's creation code
    /// produces MUST fail hard, naming the network and BOTH hashes.
    ///
    /// This is also the shape of a chain-dependent runtime — a constructor that
    /// reads `block.chainid` deploys different code per network — which is a
    /// defect in the contract rather than something to record a hash per chain
    /// for.
    ///
    /// It doubles as the proof that the expectation is derived rather than
    /// observed: the wrong code is etched at the address the check reads, so if
    /// the derivation took its expectation from there this would pass.
    function testChainCodeHashMismatchReverts() external {
        vm.etch(ADDRESS_REGISTRY_DEPLOYED_ADDRESS, hex"6001");

        vm.expectRevert(
            abi.encodeWithSelector(
                CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                "address-registry@0_0_1",
                ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                ADDRESS_REGISTRY_BYTECODE_HASH,
                keccak256(hex"6001")
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// The network in the failure MUST be the network that failed, not a fixed
    /// string. Checked on a different network from the one the matrix reaches
    /// first, against a derivation that is deliberately expecting the wrong
    /// hash.
    function testChainFailureNamesTheNetworkChecked() external {
        vm.createSelectFork(LibRainDeploy.BASE);

        DerivedDeploy memory derived = DerivedDeploy({
            suite: "address-registry@0_0_1",
            deployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            bytecodeHash: bytes32(uint256(1))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.BASE,
                "address-registry@0_0_1",
                ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                bytes32(uint256(1)),
                ADDRESS_REGISTRY_BYTECODE_HASH
            )
        );
        this.externalCheckDeployedOnNetwork(LibRainDeploy.BASE, derived);
    }

    /// Deriving MUST leave the derived address exactly as it found it. The
    /// derivation clears that address to run the creation code there, so if it
    /// did not put things back, a persistent deployment would be destroyed
    /// before the networks were ever read — and the matrix would report every
    /// suite missing everywhere.
    ///
    /// The nonce is checked as well as the code, and it is the part that
    /// discriminates. A local deploy that survived would leave the SAME runtime
    /// code sitting there, so comparing code alone cannot tell "put back" from
    /// "deployed over the top" — but a `CREATE2` deploy leaves the account at
    /// nonce 1, while a restored etch is at nonce 0.
    function testDerivationRestoresCodeAtDerivedAddress() external {
        assertEq(ADDRESS_REGISTRY_DEPLOYED_ADDRESS.code, ADDRESS_REGISTRY_RUNTIME_CODE);
        assertEq(secondDeployedAddress().code, secondRuntimeCode());
        assertEq(vm.getNonce(ADDRESS_REGISTRY_DEPLOYED_ADDRESS), 0);
        assertEq(vm.getNonce(secondDeployedAddress()), 0);

        DerivedDeploy[] memory derived = deriveDeployments(allSuites());
        assertEq(derived.length, 4);

        assertEq(ADDRESS_REGISTRY_DEPLOYED_ADDRESS.code, ADDRESS_REGISTRY_RUNTIME_CODE);
        assertEq(secondDeployedAddress().code, secondRuntimeCode());
        assertEq(vm.getNonce(ADDRESS_REGISTRY_DEPLOYED_ADDRESS), 0);
        assertEq(vm.getNonce(secondDeployedAddress()), 0);
    }

    /// The matrix MUST cover every supported network, not a subset one repo
    /// happened to list. A network added to `LibRainDeploy.supportedNetworks()`
    /// is checked for every declared suite from the moment it is added, which
    /// is the case no per-chain test function can cover.
    function testChainMatrixCoversEverySupportedNetwork() external {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            // Live on every network except this one.
            vm.etch(ADDRESS_REGISTRY_DEPLOYED_ADDRESS, ADDRESS_REGISTRY_RUNTIME_CODE);
            vm.makePersistent(ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

            uint256 forkId = vm.createSelectFork(networks[i]);
            (forkId);
            vm.etch(ADDRESS_REGISTRY_DEPLOYED_ADDRESS, hex"");

            DerivedDeploy memory derived = DerivedDeploy({
                suite: "address-registry@0_0_1",
                deployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                bytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH
            });

            vm.expectRevert(
                abi.encodeWithSelector(
                    NotDeployedOnNetwork.selector,
                    networks[i],
                    "address-registry@0_0_1",
                    ADDRESS_REGISTRY_DEPLOYED_ADDRESS
                )
            );
            this.externalCheckDeployedOnNetwork(networks[i], derived);
        }
    }

    /// The derivations MUST be computed before anything forks, which is why
    /// the matrix takes them as an argument rather than computing them: a
    /// derivation is a local deploy at the very address the checks read, so one
    /// that happened with a fork selected would either collide with the
    /// deployment under test or read it back as its own expectation.
    ///
    /// "Before anything forks" is observable as a COUNT. The whole run opens
    /// exactly one fork per supported network and not one more, so a fork
    /// opened to derive on is an extra one. Fork ids are handed out in creation
    /// order from zero and this test creates none of its own, so the run's ids
    /// are exactly `0 .. supportedNetworks().length - 1`: selecting the last of
    /// them says the matrix really did open one per network, and the id past
    /// the end not existing is what says nothing else opened one. `selectFork`
    /// reverts on an id that was never created, so the low-level call failing
    /// IS "there is no such fork".
    ///
    /// The empty-set case cannot say this. It asserts that a matrix with
    /// nothing to check forks nothing at all, which a derivation over an empty
    /// list satisfies however it is ordered — this contract is where there are
    /// suites to derive.
    function testChainDerivationOpensNoForkOfItsOwn() external {
        uint256 networkCount = LibRainDeploy.supportedNetworks().length;

        this.testSuitesLiveOnEverySupportedNetwork();

        vm.selectFork(networkCount - 1);

        (bool extraFork,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", networkCount));
        assertFalse(extraFork, "the run opened a fork that is not one of the supported networks");
    }

    function exampleEtherscanConfig() internal pure returns (string memory) {
        return "[etherscan]\n" "arbitrum = { key = \"k\", chain = 11 }\n"
            "base = { key = \"k\", url = \"https://example.com/api\" }\n" "ethereum = { key = \"k\", chain = 33 }\n";
    }

    /// External wrapper for `checkNetworkChainId` so `vm.expectRevert` works at
    /// the correct call depth.
    function externalCheckNetworkChainId(string memory network, uint256 declared, uint256 reported) external pure {
        checkNetworkChainId(network, declared, reported);
    }

    /// External wrapper for `checkNetworkChainIds` so `vm.expectRevert` works
    /// at the correct call depth.
    function externalCheckNetworkChainIds(DeclaredChainId[] memory declared) external {
        checkNetworkChainIds(declared);
    }

    /// A declared chain id that is not the reported one MUST fail, naming the
    /// network and BOTH ids. Which one is wrong — the declaration or the alias
    /// the endpoint is bound to — is not something the check can know, and the
    /// two are opposite fixes, so both ids are in the failure.
    function testChainIdMismatchReverts() external {
        vm.expectRevert(abi.encodeWithSelector(NetworkChainIdMismatch.selector, "arbitrum", 11, 22));
        this.externalCheckNetworkChainId("arbitrum", 11, 22);
    }

    /// A declared chain id that IS the reported one MUST pass. Without this a
    /// comparison that rejected every pair would satisfy the case above.
    function testChainIdMatchPasses() external view {
        this.externalCheckNetworkChainId("arbitrum", 11, 11);
    }

    /// The reported id MUST come from a fork of the network's own
    /// `[rpc_endpoints]` alias.
    ///
    /// The inherited `testSupportedNetworkChainIdsAreBound` passing cannot say
    /// that: a comparison reading `block.chainid` off the unforked 31337 EVM
    /// fails there for every network, and so does one reading it off the wrong
    /// fork, and a green run tells the two apart from neither. So this declares
    /// an id no network has, for an alias that really resolves, and the id in
    /// the failure is the one THAT endpoint answers with — `1`, which is
    /// Ethereum's and is neither 31337 nor the declared value.
    function testChainIdIsReadFromTheForkedEndpoint() external {
        DeclaredChainId[] memory declared = new DeclaredChainId[](1);
        declared[0] = DeclaredChainId({network: LibRainDeploy.ETHEREUM, chainId: 987654});

        vm.expectRevert(abi.encodeWithSelector(NetworkChainIdMismatch.selector, LibRainDeploy.ETHEREUM, 987654, 1));
        this.externalCheckNetworkChainIds(declared);
    }

    /// EVERY declaration MUST be checked, not just the first. The wrong id here
    /// is on the LAST entry, behind one that is right, so a loop that stopped
    /// at the first agreement would pass.
    function testChainIdChecksEveryDeclaration() external {
        DeclaredChainId[] memory declared = new DeclaredChainId[](2);
        declared[0] = DeclaredChainId({network: LibRainDeploy.ETHEREUM, chainId: 1});
        declared[1] = DeclaredChainId({network: LibRainDeploy.BASE, chainId: 987654});

        vm.expectRevert(abi.encodeWithSelector(NetworkChainIdMismatch.selector, LibRainDeploy.BASE, 987654, 8453));
        this.externalCheckNetworkChainIds(declared);
    }

    /// Nothing declared MUST fail rather than pass having forked nothing. It is
    /// the one input that satisfies the loop without a subject, and it is what
    /// a config whose every entry resolves through a `url` alone hands in.
    function testChainIdNoDeclarationsReverts() external {
        vm.expectRevert(NoDeclaredChainIds.selector);
        this.externalCheckNetworkChainIds(new DeclaredChainId[](0));
    }

    /// The declarations MUST be the ids the config text states, paired with the
    /// networks that state them. Distinct values, so a pairing that slipped by
    /// one is a different number rather than the same one twice.
    function testDeclaredChainIdsReadsTheConfigText() external view {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.ETHEREUM;

        DeclaredChainId[] memory declared = declaredChainIds(exampleEtherscanConfig(), networks);

        assertEq(declared.length, 2);
        assertEq(declared[0].network, LibRainDeploy.ARBITRUM_ONE);
        assertEq(declared[0].chainId, 11);
        assertEq(declared[1].network, LibRainDeploy.ETHEREUM);
        assertEq(declared[1].chainId, 33);
    }

    /// An entry that states no `chain` MUST be skipped rather than read as a
    /// zero. The config group requires only `chain` OR `url` of an entry, so an
    /// entry resolving through its `url` claims no chain id — and a zero
    /// standing in for the absent claim is a mismatch against every network
    /// there is.
    ///
    /// The skipped entry is in the MIDDLE, so the entry after it is still read
    /// and still paired with its own network.
    function testDeclaredChainIdsSkipsEntriesWithNoChain() external view {
        string[] memory networks = new string[](3);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.BASE;
        networks[2] = LibRainDeploy.ETHEREUM;

        DeclaredChainId[] memory declared = declaredChainIds(exampleEtherscanConfig(), networks);

        assertEq(declared.length, 2);
        assertEq(declared[0].network, LibRainDeploy.ARBITRUM_ONE);
        assertEq(declared[0].chainId, 11);
        assertEq(declared[1].network, LibRainDeploy.ETHEREUM);
        assertEq(declared[1].chainId, 33);
    }

    /// A config where nothing states a `chain` MUST produce nothing to check,
    /// which `checkNetworkChainIds` then refuses. Read through the same pair of
    /// calls the inherited test makes, so the refusal is reachable from config
    /// text rather than only from an array a test built.
    function testDeclaredChainIdsOfUrlOnlyEntriesIsRefused() external {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.BASE;

        DeclaredChainId[] memory declared = declaredChainIds(exampleEtherscanConfig(), networks);
        assertEq(declared.length, 0);

        vm.expectRevert(NoDeclaredChainIds.selector);
        this.externalCheckNetworkChainIds(declared);
    }

    /// A network with no `[etherscan]` entry at all MUST be skipped here rather
    /// than reverting on the read. Membership is the config group's assertion
    /// and it names the missing network; a parse error here would fail first,
    /// on a network, with nothing about the section it is missing from.
    function testDeclaredChainIdsSkipsNetworksWithNoEntry() external view {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.FLARE;
        networks[1] = LibRainDeploy.ETHEREUM;

        DeclaredChainId[] memory declared = declaredChainIds(exampleEtherscanConfig(), networks);

        assertEq(declared.length, 1);
        assertEq(declared[0].network, LibRainDeploy.ETHEREUM);
        assertEq(declared[0].chainId, 33);
    }
}
