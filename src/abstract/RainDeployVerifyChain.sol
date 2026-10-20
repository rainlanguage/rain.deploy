// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeploySuite} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";

/// Thrown when `requiresSuiteOn` requires a suite on none of the networks
/// checked, which would pass the suite having checked it nowhere.
/// @param suite The suite.
error SuiteRequiredNowhere(string suite);

/// @title RainDeployVerifyChain
/// @notice The only deploy-pin assertions anchored to something outside the repo.
abstract contract RainDeployVerifyChain is RainDeployVerifyBase {
    /// Checks every suite against every supported network.
    /// @param suites The suites to check.
    function checkDeployedOnSupportedNetworks(DeploySuite[] memory suites) internal {
        checkDeployedOnNetworks(LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), suites);
    }

    /// Checks every suite against every given network, forking with `vm`.
    /// @param networks The catalogue entry of each network to check on.
    /// @param suites The suites to check.
    function checkDeployedOnNetworks(SupportedNetwork[] memory networks, DeploySuite[] memory suites) internal {
        checkDeployedOnNetworks(vm, networks, suites);
    }

    /// Checks every suite against every given network, forking each network once with `forkVm` and checking every
    /// suite on it.
    /// A per-network suite is checked on the networks it records and those `extendedNetworks` declares for it. On any
    /// other network it is refused before any network is forked: with `ExtendedNetworkUnfrozen`, naming the address its
    /// candidate's init data derives there, whether or not anything is live at it, or with `CloneNetworkUndeclared` where
    /// its candidate has no entry there.
    /// @param forkVm The Vm instance to fork with.
    /// @param networks The catalogue entry of each network to check on.
    /// @param suites The suites to check.
    function checkDeployedOnNetworks(Vm forkVm, SupportedNetwork[] memory networks, DeploySuite[] memory suites)
        internal
    {
        // Nothing to check is not a reason to touch every RPC endpoint. Forking
        // to check nothing turns an outage into the failure of an assertion
        // that has no subject, which is the one failure this contract is
        // supposed to be legible against.
        if (suites.length == 0) {
            return;
        }

        // With no networks every suite is required nowhere, which would name a
        // suite for what is a fault of the roster.
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }

        uint256[] memory chainIds = LibRainDeploy.networkChainIds(networks);
        DeploySuite[] memory frozen = new DeploySuite[](suites.length);
        DeploySuite[] memory onNetworks = new DeploySuite[](suites.length);
        for (uint256 j = 0; j < suites.length; j++) {
            frozen[j] = withExtendedNetworks(suites[j]);
            onNetworks[j] = onSupportedNetworks(frozen[j], chainIds);
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
        }

        address[][] memory addresses = new address[][](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            addresses[i] = new address[](suites.length);
            for (uint256 j = 0; j < suites.length; j++) {
                addresses[i][j] = LibRainDeployMechanism.deployedAddress(suites[j], networks[i].chainId);
                LibRainDeployMechanism.checkNetworkFrozen(
                    frozen[j], networks[i].name, networks[i].chainId, addresses[i][j]
                );
            }
        }

        DerivedDeploy[] memory derived = deriveDeployments(suites);
        uint256[] memory forkIds = LibRainDeploy.createForks(forkVm, LibRainDeploy.networkNames(networks));
        for (uint256 i = 0; i < networks.length; i++) {
            forkVm.selectFork(forkIds[i]);
            LibRainDeploy.checkNetworkChainId(networks[i]);
            for (uint256 j = 0; j < suites.length; j++) {
                if (!requiresSuiteOn(suites[j], networks[i].name)) {
                    console2.log("Not required on network:", derived[j].suite, networks[i].name);
                    continue;
                }
                console2.log("Checking suite on network:", derived[j].suite, networks[i].name);
                LibRainDeploy.checkDeclaredDependencies(networks[i].name, suites[j].dependencies);
                LibRainDeploy.checkDeployedCode(networks[i].name, addresses[i][j], derived[j].bytecodeHash);
            }
        }
    }

    /// Every RELEASED suite MUST be live, with the code its creation code produces and its declared
    /// dependencies under it, on every supported network `requiresSuiteOn` requires it on.
    function testSuitesLiveOnEverySupportedNetwork() external {
        checkDeployedOnSupportedNetworks(releasedSuites());
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
        checkNetworkChainIds(LibRainDeploy.declaredNetworkConfigs(supportedNetworks()));
    }
}
