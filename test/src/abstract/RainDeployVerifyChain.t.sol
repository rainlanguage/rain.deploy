// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DerivedDeploy} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {
    CodeHashMismatchOnNetwork,
    NotDeployedOnNetwork,
    RainDeployVerifyChain
} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeployVersions} from "../../abstract/MockDeployVersions.sol";
import {
    BYTECODE_HASH as MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1,
    DEPLOYED_ADDRESS as MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
    RUNTIME_CODE as MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1
} from "../../fixtures/0_0_1/MockDeployable.pointers.sol";
import {
    DEPLOYED_ADDRESS as MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2,
    RUNTIME_CODE as MOCK_DEPLOYABLE_V2_RUNTIME_CODE_0_0_2
} from "../../fixtures/0_0_2/MockDeployableV2.pointers.sol";

/// @title RainDeployVerifyChainTest
/// @notice `RainDeployVerifyChain` inherited by a fixture repo whose versions
/// are made live on every network by `setUp`, so the inherited
/// `testDeployPinsLiveOnEverySupportedNetwork` is the passing case: it forks all
/// five supported networks and finds all three versions.
///
/// `setUp` places the code with a persistent `vm.etch` rather than pointing the
/// fixture at some real deployment in another repo. A real one would make this
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
contract RainDeployVerifyChainTest is MockDeployVersions, RainDeployVerifyChain {
    /// Makes every fixture version live on every fork, which is what the
    /// inherited test then verifies. Persistent so it survives each
    /// `createSelectFork` inside the loop.
    function setUp() external {
        vm.etch(MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1, MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1);
        vm.makePersistent(MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1);
        vm.etch(MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2, MOCK_DEPLOYABLE_V2_RUNTIME_CODE_0_0_2);
        vm.makePersistent(MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2);
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
        vm.revokePersistent(MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1);

        vm.expectRevert(
            abi.encodeWithSelector(
                NotDeployedOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                "0_0_1",
                MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1
            )
        );
        this.testDeployPinsLiveOnEverySupportedNetwork();
    }

    /// EVERY version MUST be checked, not just the first one the matrix
    /// reaches. The version missing here is the second and third, so a matrix
    /// that stopped after the first version would pass.
    function testChainNotDeployedRevertsForALaterVersion() external {
        vm.revokePersistent(MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2);

        vm.expectRevert(
            abi.encodeWithSelector(
                NotDeployedOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                "0_0_2",
                MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2
            )
        );
        this.testDeployPinsLiveOnEverySupportedNetwork();
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

        this.testDeployPinsLiveOnEverySupportedNetwork();

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
        vm.etch(MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1, hex"6001");

        vm.expectRevert(
            abi.encodeWithSelector(
                CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                "0_0_1",
                MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
                MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1,
                keccak256(hex"6001")
            )
        );
        this.testDeployPinsLiveOnEverySupportedNetwork();
    }

    /// The network in the failure MUST be the network that failed, not a fixed
    /// string. Checked on a different network from the one the matrix reaches
    /// first, against a derivation that is deliberately expecting the wrong
    /// hash.
    function testChainFailureNamesTheNetworkChecked() external {
        vm.createSelectFork(LibRainDeploy.BASE);

        DerivedDeploy memory derived = DerivedDeploy({
            version: "0_0_1", deployedAddress: MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1, bytecodeHash: bytes32(uint256(1))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.BASE,
                "0_0_1",
                MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
                bytes32(uint256(1)),
                MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1
            )
        );
        this.externalCheckDeployedOnNetwork(LibRainDeploy.BASE, derived);
    }

    /// Deriving MUST NOT disturb what is deployed at the derived address. The
    /// derivation clears that address to run the creation code there, so if it
    /// did not put things back, a persistent deployment would be destroyed
    /// before the networks were ever read — and the matrix would report every
    /// version missing everywhere.
    function testDerivationRestoresCodeAtDerivedAddress() external {
        assertEq(MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1.code, MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1);
        assertEq(MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2.code, MOCK_DEPLOYABLE_V2_RUNTIME_CODE_0_0_2);

        DerivedDeploy[] memory derived = deriveDeployments(allVersions());
        assertEq(derived.length, 3);

        assertEq(MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1.code, MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1);
        assertEq(MOCK_DEPLOYABLE_V2_DEPLOYED_ADDRESS_0_0_2.code, MOCK_DEPLOYABLE_V2_RUNTIME_CODE_0_0_2);
    }

    /// The matrix MUST cover every supported network, not a subset one repo
    /// happened to list. A network added to `LibRainDeploy.supportedNetworks()`
    /// is checked for every recorded version from the moment it is added, which
    /// is the case no per-chain test function can cover.
    function testChainMatrixCoversEverySupportedNetwork() external {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            // Live on every network except this one.
            vm.etch(MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1, MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1);
            vm.makePersistent(MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1);

            uint256 forkId = vm.createSelectFork(networks[i]);
            (forkId);
            vm.etch(MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1, hex"");

            DerivedDeploy memory derived = DerivedDeploy({
                version: "0_0_1",
                deployedAddress: MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
                bytecodeHash: MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1
            });

            vm.expectRevert(
                abi.encodeWithSelector(
                    NotDeployedOnNetwork.selector, networks[i], "0_0_1", MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1
                )
            );
            this.externalCheckDeployedOnNetwork(networks[i], derived);
        }
    }
}
