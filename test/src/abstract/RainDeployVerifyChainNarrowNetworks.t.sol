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
/// @notice The chain group is made over the networks the declaration names and
/// no others. The inherited tests run here on the narrowed set and pass, so the
/// binding is bindable.
///
/// Passing alone cannot show the set was narrowed — a group walking all nine
/// would pass too. The tests below read the narrowing instead: neither group
/// restores the fork it was on, so a run ends on the last network it walked,
/// and fork ids are handed out from zero, so an id of 1 existing means a
/// network was forked that the declaration does not name.
///
/// Its own contract because a contract has exactly one declaration, so a second
/// scope is a second contract.
contract RainDeployVerifyChainNarrowNetworksTest is ExampleDeploySuites, RainDeployVerifyChain {
    /// Base's chain id, as a fact of the world rather than a second read of the
    /// alias this contract declares: an `[rpc_endpoints]` entry pointed at some
    /// other chain would agree with itself and assert nothing.
    uint256 constant BASE_CHAIN_ID = 8453;

    /// @inheritdoc RainDeploySuitesBase
    /// @dev ONE network, and base rather than either end of the library's
    /// list, so a run that ignored the declaration ends on arbitrum or polygon.
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

    /// The matrix forks the declared networks and nothing else.
    function testChainMatrixForksOnlyTheDeclaredNetworks() external {
        assertNarrowerThanTheLibrary();

        this.testSuitesLiveOnEverySupportedNetwork();

        assertEq(block.chainid, BASE_CHAIN_ID, "the matrix ended on a network the declaration does not name");

        (bool extraFork,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(1)));
        assertFalse(extraFork, "the matrix forked a network the declaration does not name");
    }

    /// The chain id check reads the declared networks' `[etherscan]` entries
    /// and nothing else.
    function testChainIdBindingReadsOnlyTheDeclaredNetworks() external {
        assertNarrowerThanTheLibrary();

        this.testSupportedNetworkChainIdsAreBound();

        assertEq(block.chainid, BASE_CHAIN_ID, "the check ended on a network the declaration does not name");

        (bool extraFork,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(1)));
        assertFalse(extraFork, "the check forked a network the declaration does not name");
    }
}
