// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeployDeclaration, DeploySuite} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {LibRainDeployDescribedByMeta} from "../lib/LibRainDeployDescribedByMeta.sol";

/// Thrown when `requiresSuiteOn` requires a suite on none of the networks
/// checked, which would pass the suite having checked it nowhere.
/// @param suite The suite.
error SuiteRequiredNowhere(string suite);

/// @title RainDeployVerifyChain
/// @notice The only deploy-pin assertions anchored to something outside the repo.
abstract contract RainDeployVerifyChain is RainDeployVerifyBase {
    /// Checks every suite against every supported network.
    /// @param suites The suites to check.
    function checkDeployedOnSupportedNetworks(DeployDeclaration memory d, DeploySuite[] memory suites) internal {
        checkDeployedOnNetworks(d, LibRainDeploy.declaredNetworkConfigs(d.networks), suites);
    }

    /// Checks every suite on the given networks against each, forking with `vm`.
    /// @param networks The catalogue entry of each network to check on.
    /// @param suites The suites to check.
    function checkDeployedOnNetworks(
        DeployDeclaration memory d,
        SupportedNetwork[] memory networks,
        DeploySuite[] memory suites
    ) internal {
        checkDeployedOnNetworks(d, vm, networks, suites);
    }

    /// Checks every suite on the given networks against each, forking each network once with `forkVm`. Every
    /// mechanism's `checkNetworks` runs first, before the frozen checks, derivations and forks; with no suites only
    /// the networks some mechanism returned are forked, and with none nothing is. Each suite is checked with its
    /// recorded networks (`addRecordedNetworks`) and the networks in play its candidate adds (`addCandidateNetworks`);
    /// the caller's suites are not changed. A suite is refused `checkNetworkFrozen`'s refusals before any network
    /// is forked on each network it is required on, and `checkOnChain`'s on each selected fork it is required on.
    /// A suite carrying a described-by meta is refused `MetaBoardUndeclared` before forking, and on each network it is
    /// required on `checkEmittedAt`'s refusals at its declared emission block and `checkDescribes`'s at its address.
    /// @param forkVm The Vm instance to fork with.
    /// @param networks The catalogue entry of each network to check on.
    /// @param suites The suites to check.
    function checkDeployedOnNetworks(
        DeployDeclaration memory d,
        Vm forkVm,
        SupportedNetwork[] memory networks,
        DeploySuite[] memory suites
    ) internal {
        {
            uint256[][] memory needed = new uint256[][](d.mechanisms.length);
            for (uint256 k = 0; k < d.mechanisms.length; k++) {
                needed[k] = d.mechanisms[k].checkNetworks(d, networks);
            }
            // Nothing to check is not a reason to touch every RPC endpoint.
            if (suites.length == 0) {
                networks = networksNeeded(networks, needed);
                if (networks.length == 0) {
                    return;
                }
            }
        }
        // With no networks every suite is required nowhere, which would name a suite for what is a fault of the
        // roster.
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }

        uint256[] memory chainIds = LibRainDeploy.networkChainIds(networks);
        DeploySuite[] memory frozen = new DeploySuite[](suites.length);
        DeploySuite[] memory onNetworks = new DeploySuite[](suites.length);
        for (uint256 j = 0; j < suites.length; j++) {
            frozen[j] = abi.decode(abi.encode(suites[j]), (DeploySuite));
            addRecordedNetworks(d, frozen[j]);
            onNetworks[j] = abi.decode(abi.encode(frozen[j]), (DeploySuite));
            addCandidateNetworks(d, onNetworks[j], chainIds);
        }
        suites = onNetworks;

        for (uint256 j = 0; j < suites.length; j++) {
            bool requiredSomewhere = false;
            for (uint256 i = 0; i < networks.length; i++) {
                if (requiresSuiteOn(suites[j], networks[i].name)) {
                    requiredSomewhere = true;
                    break;
                }
            }
            if (!requiredSomewhere) {
                revert SuiteRequiredNowhere(suites[j].suite);
            }
            checkedMetaBoard(d, suites[j]);
        }

        address[][] memory addresses = new address[][](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            addresses[i] = new address[](suites.length);
            for (uint256 j = 0; j < suites.length; j++) {
                if (requiresSuiteOn(suites[j], networks[i].name)) {
                    addresses[i][j] = deployedAddress(d, suites[j], networks[i].chainId);
                    checkNetworkFrozen(d, frozen[j], networks[i].name, networks[i].chainId, addresses[i][j]);
                }
            }
        }

        DerivedDeploy[] memory derived = deriveDeployments(d, suites);
        uint256[] memory forkIds = LibRainDeploy.createForks(forkVm, LibRainDeploy.networkNames(networks));
        for (uint256 i = 0; i < networks.length; i++) {
            forkVm.selectFork(forkIds[i]);
            LibRainDeploy.checkNetworkChainId(networks[i]);
            for (uint256 k = 0; k < d.mechanisms.length; k++) {
                d.mechanisms[k].checkNetwork(d, networks[i].name, networks[i].chainId);
            }
            for (uint256 j = 0; j < suites.length; j++) {
                if (!requiresSuiteOn(suites[j], networks[i].name)) {
                    console2.log("Not required on network:", derived[j].suite, networks[i].name);
                    continue;
                }
                checkSuiteOnNetwork(networks[i].name, suites[j], derived[j], addresses[i][j]);
                checkOnChain(d, suites[j], networks[i].name, networks[i].chainId, addresses[i][j]);
                checkDescribedByMetaEmitted(d, forkVm, networks[i], suites[j], addresses[i][j]);
            }
        }
    }

    /// `LibRainDeployDescribedByMeta.checkEmittedAt` at the block `d` declares for `suite` on `network`, then
    /// `LibRainDeployDescribedByMeta.checkDescribes` on `described` on the selected fork.
    /// @param d The declaration.
    /// @param forkVm The Vm instance to read logs with.
    /// @param network The selected fork's network.
    /// @param suite The suite.
    /// @param described The suite's address on the network.
    function checkDescribedByMetaEmitted(
        DeployDeclaration memory d,
        Vm forkVm,
        SupportedNetwork memory network,
        DeploySuite memory suite,
        address described
    ) internal view {
        (bool declared, uint256 blockNumber) = describedByMetaEmissionBlock(d, suite.suite, network.chainId);
        LibRainDeployDescribedByMeta.checkEmittedAt(
            forkVm,
            network.name,
            suite.suite,
            network.chainId,
            d.metaBoard,
            declared,
            blockNumber,
            described,
            suite.describedByMeta
        );
        LibRainDeployDescribedByMeta.checkDescribes(suite.suite, described, suite.describedByMeta);
    }

    /// @param networks The networks.
    /// @param needed The chain ids each mechanism's `checkNetworks` returned.
    /// @return The networks whose chain id is in some `needed`, in `networks` order.
    function networksNeeded(SupportedNetwork[] memory networks, uint256[][] memory needed)
        internal
        pure
        returns (SupportedNetwork[] memory)
    {
        bool[] memory keep = new bool[](networks.length);
        uint256 count = 0;
        for (uint256 i = 0; i < networks.length; i++) {
            for (uint256 k = 0; k < needed.length && !keep[i]; k++) {
                for (uint256 m = 0; m < needed[k].length; m++) {
                    if (needed[k][m] == networks[i].chainId) {
                        keep[i] = true;
                        count++;
                        break;
                    }
                }
            }
        }
        SupportedNetwork[] memory kept = new SupportedNetwork[](count);
        uint256 n = 0;
        for (uint256 i = 0; i < networks.length; i++) {
            if (keep[i]) {
                kept[n++] = networks[i];
            }
        }
        return kept;
    }

    /// The selected fork MUST hold `suite` at `deployedAddress` with its derived code and its declared dependencies.
    /// @param network The network's name, for the refusal.
    /// @param suite The suite.
    /// @param derived The suite's derivation.
    /// @param deployedAddress The suite's address on the network.
    function checkSuiteOnNetwork(
        string memory network,
        DeploySuite memory suite,
        DerivedDeploy memory derived,
        address deployedAddress
    ) internal view {
        console2.log("Checking suite on network:", derived.suite, network);
        LibRainDeploy.checkDeclaredDependencies(network, suite.dependencies);
        LibRainDeploy.checkDeployedCode(network, deployedAddress, derived.bytecodeHash);
    }

    /// Every RELEASED suite MUST be live, with the code its creation code produces and its declared
    /// dependencies under it, on every network it is required on, with `checkOnChain`'s refusals there.
    function testSuitesLiveOnEverySupportedNetwork() external {
        DeployDeclaration memory d = declaration();
        checkDeployedOnSupportedNetworks(d, d.released);
    }

    /// Checks every network's declared chain id against the endpoint bound to its `[rpc_endpoints]`
    /// alias, by `LibRainDeploy.checkNetworkChainId`.
    /// @param networks The roster to check.
    function checkNetworkChainIds(SupportedNetwork[] memory networks) internal {
        // An empty roster is a repo that deploys nowhere, not a repo with
        // nothing to check, and it would pass here having forked nothing.
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, LibRainDeploy.networkNames(networks));
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            LibRainDeploy.checkNetworkChainId(networks[i]);
        }
    }

    /// Every declared network's chain id MUST be the one the endpoint bound to
    /// its alias reports.
    ///
    /// The one thing about the config that generating it cannot settle. The
    /// sections are written from the same declaration this reads, so an alias
    /// missing from one of them is a tree `Git is clean` fails rather than an
    /// assertion anything makes — but which chain an endpoint actually serves
    /// is a claim about the world, and `chain` is what `--verify` submits to. A
    /// wrong id there is config that resolves, passes every check that reads
    /// the text, and verifies a deployment against the wrong explorer.
    ///
    /// Here rather than beside the catalogue because the subject is the
    /// endpoint: this is the contract that already forks every declared
    /// network, and the snapshot half is the one a credential-free job binds.
    function testSupportedNetworkChainIdsAreBound() external {
        checkNetworkChainIds(LibRainDeploy.declaredNetworkConfigs(declaration().networks));
    }
}
