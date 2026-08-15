// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DerivedDeploy} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {
    CodeHashMismatchOnNetwork,
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
/// The etch does not make the passing case circular. It writes the runtime code
/// the compiler emits, while the expectation is derived independently by running
/// the recorded CREATION code through the Zoltu factory. That the two agree is
/// the assertion. `testChainCodeHashMismatchReverts` is what proves it: it
/// leaves the etch in place and changes only the code, and the check still
/// fails, which it could not do if the expectation were read from the etch.
contract RainDeployVerifyChainTest is ExampleDeploySuites, RainDeployVerifyChain {
    /// The second suite's address, derived from the only other creation code in
    /// this repo.
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
    /// release that reached four chains of five, or a chain added after a
    /// release that therefore never got it, is invisible to every other check.
    function testChainNotDeployedReverts() external {
        // Present locally, but no longer carried onto forks.
        vm.revokePersistent(ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(
                NotDeployedOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                "address-registry-0-0-1",
                ADDRESS_REGISTRY_DEPLOYED_ADDRESS
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// EVERY suite MUST be checked, not just the first one the matrix
    /// reaches. The version missing here is the LAST one, so a matrix that
    /// stopped after the first version would pass.
    function testChainNotDeployedRevertsForALaterSuite() external {
        vm.revokePersistent(secondDeployedAddress());

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
                "address-registry-0-0-1",
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
            suite: "address-registry-0-0-1",
            deployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            bytecodeHash: bytes32(uint256(1))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.BASE,
                "address-registry-0-0-1",
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
                suite: "address-registry-0-0-1",
                deployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                bytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH
            });

            vm.expectRevert(
                abi.encodeWithSelector(
                    NotDeployedOnNetwork.selector,
                    networks[i],
                    "address-registry-0-0-1",
                    ADDRESS_REGISTRY_DEPLOYED_ADDRESS
                )
            );
            this.externalCheckDeployedOnNetwork(networks[i], derived);
        }
    }
}
