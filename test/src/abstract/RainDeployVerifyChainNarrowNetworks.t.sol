// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../../src/generated/candidate/AddressRegistry.sol";

/// @title RainDeployVerifyChainNarrowNetworksTest
/// @notice A repo that deploys to FEWER networks than Rain supports: the chain
/// group MUST be made over the networks that repo declares, and over no others.
///
/// This is the consumer `supportedNetworks()` is a hook for. `st0x.deploy`
/// broadcasts to five of the nine, so a chain group hardwired to the nine holds
/// every one of its releases to four networks it never reaches — and the repo's
/// only way out is to bind no chain group at all, which is how that tree is
/// green today.
///
/// Both of this contract's inherited tests run here on the narrowed set and
/// pass, which is the whole of the consumer-facing claim: the binding is
/// bindable. What the tests below add is that the set was really narrowed,
/// because passing cannot say it — the subject is etched live on every fork and
/// this repo's `[etherscan]` ids are right on all nine, so a group that ignored
/// the declaration and walked the nine would pass too.
///
/// ## The narrowing is observable as the fork COUNT and the chain LEFT selected
///
/// Neither group restores the fork it was on, so a completed run ends on the
/// LAST network it walked: base here, polygon for the library's nine. And ids
/// are handed out in creation order from zero, so with one network declared an
/// id of 1 existing at all is a network that was forked and never declared.
/// `selectFork` reverts on an id that was never created, so a low-level call
/// failing IS "there is no such fork".
///
/// Its own contract for the reason `RainDeployVerifyChainEmptyTest` is its own
/// contract: the networks a contract declares are the whole of what the groups
/// run over, and a contract has exactly one declaration, so a second scope is a
/// second contract.
contract RainDeployVerifyChainNarrowNetworksTest is ExampleDeploySuites, RainDeployVerifyChain {
    /// Base's chain id, as a fact of the world rather than a second read of the
    /// alias this contract declares: an `[rpc_endpoints]` entry pointed at some
    /// other chain would agree with itself and assert nothing.
    uint256 constant BASE_CHAIN_ID = 8453;

    /// @inheritdoc RainDeploySuitesBase
    /// @dev ONE network, and base rather than either end of the library's list.
    /// The groups leave the last network they walked selected, so a run that
    /// took the nine ends on polygon and one that took only their first entry
    /// ends on arbitrum. Neither reads as base.
    function supportedNetworks() internal pure override returns (string[] memory networks) {
        networks = new string[](1);
        networks[0] = LibRainDeploy.BASE;
    }

    /// The second suite's address, derived from `MockDeployableV2`'s creation
    /// code by the same derivation `ExampleDeploySuites` declares.
    /// @return The address.
    function secondDeployedAddress() internal pure returns (address) {
        return LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode);
    }

    /// Makes both exemplar releases live on every fork, so the matrix passing
    /// is about the networks it walked rather than about what is on them.
    /// Persistent, for the reason `RainDeployVerifyChainTest.setUp` gives.
    function setUp() external {
        vm.etch(ADDRESS_REGISTRY_DEPLOYED_ADDRESS, ADDRESS_REGISTRY_RUNTIME_CODE);
        vm.makePersistent(ADDRESS_REGISTRY_DEPLOYED_ADDRESS);
        vm.etch(secondDeployedAddress(), type(MockDeployableV2).runtimeCode);
        vm.makePersistent(secondDeployedAddress());
    }

    /// The declaration MUST really be narrower than the library's list, or
    /// every assertion below holds for a group that ignored it.
    function assertNarrowerThanTheLibrary() internal pure {
        assertLt(
            supportedNetworks().length,
            LibRainDeploy.supportedNetworks().length,
            "this fixture declares every supported network, so a group that ignored it would read the same"
        );
    }

    /// The matrix MUST fork the declared networks and nothing else. A network
    /// this repo does not deploy to is one every release would be reported
    /// missing from, release after release, with the repo correct.
    function testChainMatrixForksOnlyTheDeclaredNetworks() external {
        assertNarrowerThanTheLibrary();

        this.testSuitesLiveOnEverySupportedNetwork();

        assertEq(block.chainid, BASE_CHAIN_ID, "the matrix ended on a network the declaration does not name");

        (bool extraFork,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(1)));
        assertFalse(extraFork, "the matrix forked a network the declaration does not name");
    }

    /// The chain id check MUST read the declared networks' `[etherscan]`
    /// entries and nothing else. The entries it would otherwise read are a
    /// consumer's config for networks it never verifies on, and an alias it has
    /// no endpoint for fails the fork rather than the comparison.
    function testChainIdBindingReadsOnlyTheDeclaredNetworks() external {
        assertNarrowerThanTheLibrary();

        this.testSupportedNetworkChainIdsAreBound();

        assertEq(block.chainid, BASE_CHAIN_ID, "the check ended on a network the declaration does not name");

        (bool extraFork,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(1)));
        assertFalse(extraFork, "the check forked a network the declaration does not name");
    }
}
