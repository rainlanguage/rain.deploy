// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeploySuite} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";
import {DeployBeacon, LibRainDeployBeacon} from "../lib/LibRainDeployBeacon.sol";

/// A beacon's implementation suite in each of its states, indexed as `LibRainDeployBeacon.stateAt`.
struct BeaconImplementations {
    DeploySuite[] suites;
    address[] addresses;
    DerivedDeploy[] derived;
}

/// @title RainDeployVerifyChain
/// @notice The only deploy-pin assertions anchored to something outside the repo.
abstract contract RainDeployVerifyChain is RainDeployVerifyBase {
    /// Checks every suite against every supported network.
    /// @param suites The suites to check.
    function checkDeployedOnSupportedNetworks(DeploySuite[] memory suites) internal {
        checkDeployedOnNetworks(LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), suites);
    }

    /// Checks every suite against every given network, forking each network once and checking every
    /// suite on it.
    /// @param networks The catalogue entry of each network to check on.
    /// @param suites The suites to check.
    function checkDeployedOnNetworks(SupportedNetwork[] memory networks, DeploySuite[] memory suites) internal {
        DeployBeacon[][] memory networkBeacons = new DeployBeacon[][](networks.length);
        BeaconImplementations[][] memory implementations = new BeaconImplementations[][](networks.length);
        bool anyBeacons = false;
        for (uint256 i = 0; i < networks.length; i++) {
            networkBeacons[i] = beacons(networks[i].chainId);
            implementations[i] = new BeaconImplementations[](networkBeacons[i].length);
            for (uint256 b = 0; b < networkBeacons[i].length; b++) {
                implementations[i][b] = beaconImplementations(networkBeacons[i][b], networks[i].chainId);
            }
            anyBeacons = anyBeacons || networkBeacons[i].length > 0;
        }

        // Nothing to check is not a reason to touch every RPC endpoint. Forking
        // to check nothing turns an outage into the failure of an assertion
        // that has no subject, which is the one failure this contract is
        // supposed to be legible against.
        if (suites.length == 0 && !anyBeacons) {
            return;
        }

        DeploySuite[] memory onNetworks = new DeploySuite[](suites.length);
        for (uint256 j = 0; j < suites.length; j++) {
            onNetworks[j] = onSupportedNetworks(suites[j]);
        }
        suites = onNetworks;

        DerivedDeploy[] memory derived = deriveDeployments(suites);
        address[][] memory addresses = new address[][](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            addresses[i] = new address[](suites.length);
            for (uint256 j = 0; j < suites.length; j++) {
                addresses[i][j] = LibRainDeployMechanism.deployedAddress(suites[j], networks[i].chainId);
            }
        }

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, LibRainDeploy.networkNames(networks));
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            LibRainDeploy.checkNetworkChainId(networks[i]);
            for (uint256 j = 0; j < suites.length; j++) {
                checkSuiteOnNetwork(networks[i].name, suites[j], derived[j], addresses[i][j]);
            }
            for (uint256 b = 0; b < networkBeacons[i].length; b++) {
                DeployBeacon memory beacon = networkBeacons[i][b];
                BeaconImplementations memory implementation = implementations[i][b];
                uint256 state = LibRainDeployBeacon.appliedState(beacon);
                LibRainDeployBeacon.checkBeacon(
                    networks[i].name,
                    beacon,
                    implementation.addresses[state],
                    LibRainDeployBeacon.stateAt(beacon, state).owner
                );
                checkSuiteOnNetwork(
                    networks[i].name,
                    implementation.suites[state],
                    implementation.derived[state],
                    implementation.addresses[state]
                );
            }
        }
    }

    /// The selected fork MUST hold `suite` at `deployedAddress` with its derived code and its declared dependencies.
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

    /// The implementation suite of each of `beacon`'s states, resolved on `chainId` before anything forks.
    function beaconImplementations(DeployBeacon memory beacon, uint256 chainId)
        internal
        returns (BeaconImplementations memory)
    {
        uint256 states = beacon.transitions.length + 1;
        DeploySuite[] memory stateSuites = new DeploySuite[](states);
        address[] memory stateAddresses = new address[](states);
        for (uint256 state = 0; state < states; state++) {
            stateSuites[state] =
                onSupportedNetworks(suiteByName(LibRainDeployBeacon.stateAt(beacon, state).implementation));
            stateAddresses[state] = LibRainDeployMechanism.deployedAddress(stateSuites[state], chainId);
        }
        return BeaconImplementations({
            suites: stateSuites, addresses: stateAddresses, derived: deriveDeployments(stateSuites)
        });
    }

    /// Every RELEASED suite MUST be live, with the code its creation code produces and its declared
    /// dependencies under it, on every supported network.
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
