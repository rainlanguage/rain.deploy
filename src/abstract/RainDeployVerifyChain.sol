// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeploySuite} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";
import {DeployBeacon, LibRainDeployBeacon} from "../lib/LibRainDeployBeacon.sol";

/// @notice A suite a beacon names, as its implementation or as itself, MUST be released.
/// @param suite The declared key.
error BeaconSuiteNotReleased(string suite);

/// @notice A beacon MUST NOT be named both by `beaconSuite` and by `beacon` or `beaconCodeHash`.
/// @param chainId The beacon's network.
/// @param beaconIndex The beacon's index in `beacons(chainId)`.
error BeaconNamedTwice(uint256 chainId, uint256 beaconIndex);

/// @notice A beacon MUST be named by `beaconSuite` or by `beacon` and `beaconCodeHash`.
/// @param chainId The beacon's network.
/// @param beaconIndex The beacon's index in `beacons(chainId)`.
error BeaconUnnamed(uint256 chainId, uint256 beaconIndex);

/// @notice A catalogue network outside `supportedNetworks()` MUST have no beacons.
/// @param chainId The unchecked network.
error BeaconsOnUncheckedNetwork(uint256 chainId);

/// A beacon with every suite it names resolved on its network.
/// @param beacon The declaration, its `beacon` and `beaconCodeHash` derived when it names `beaconSuite`.
/// @param suite The beacon's suite when it names `beaconSuite`.
/// @param derived The beacon's suite's derivation when it names `beaconSuite`.
/// @param implementations Each state's implementation suite, indexed as `LibRainDeployBeacon.stateAt`.
/// @param implementationAddresses Each state's implementation address on the beacon's network.
/// @param implementationDerived Each state's implementation derivation.
struct ResolvedBeacon {
    DeployBeacon beacon;
    DeploySuite suite;
    DerivedDeploy derived;
    DeploySuite[] implementations;
    address[] implementationAddresses;
    DerivedDeploy[] implementationDerived;
}

/// @title RainDeployVerifyChain
/// @notice The only deploy-pin assertions anchored to something outside the repo.
abstract contract RainDeployVerifyChain is RainDeployVerifyBase {
    /// Checks every suite against every supported network.
    /// @param suites The suites to check.
    function checkDeployedOnSupportedNetworks(DeploySuite[] memory suites) internal {
        SupportedNetwork[] memory networks = LibRainDeploy.declaredNetworkConfigs(supportedNetworks());
        SupportedNetwork[] memory catalogue = LibRainDeploy.supportedNetworkConfigs();
        for (uint256 i = 0; i < catalogue.length; i++) {
            bool isChecked = false;
            for (uint256 j = 0; j < networks.length; j++) {
                isChecked = isChecked || networks[j].chainId == catalogue[i].chainId;
            }
            if (!isChecked && beacons(catalogue[i].chainId).length > 0) {
                revert BeaconsOnUncheckedNetwork(catalogue[i].chainId);
            }
        }
        checkDeployedOnNetworks(networks, suites);
    }

    /// Checks every suite against every given network, forking each network once and checking every
    /// suite on it.
    /// @param networks The catalogue entry of each network to check on.
    /// @param suites The suites to check.
    function checkDeployedOnNetworks(SupportedNetwork[] memory networks, DeploySuite[] memory suites) internal {
        (ResolvedBeacon[][] memory resolved, bool anyBeacons) = resolveBeacons(networks);

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
            for (uint256 beaconIndex = 0; beaconIndex < resolved[i].length; beaconIndex++) {
                checkResolvedBeacon(networks[i].name, resolved[i][beaconIndex]);
            }
        }
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

    /// The selected fork MUST hold the beacon at its applied state, with every suite it names live.
    /// @param network The network's name, for the refusal.
    /// @param resolved The beacon.
    function checkResolvedBeacon(string memory network, ResolvedBeacon memory resolved) internal view {
        DeployBeacon memory beacon = resolved.beacon;
        if (bytes(beacon.beaconSuite).length != 0) {
            checkSuiteOnNetwork(network, resolved.suite, resolved.derived, beacon.beacon);
        }
        uint256 state = LibRainDeployBeacon.appliedState(beacon);
        LibRainDeployBeacon.checkBeacon(
            network, beacon, resolved.implementationAddresses[state], LibRainDeployBeacon.stateAt(beacon, state).owner
        );
        checkSuiteOnNetwork(
            network,
            resolved.implementations[state],
            resolved.implementationDerived[state],
            resolved.implementationAddresses[state]
        );
    }

    /// @param networks The networks.
    /// @return Each network's `beacons`, resolved.
    /// @return Whether any network has a beacon.
    function resolveBeacons(SupportedNetwork[] memory networks) internal returns (ResolvedBeacon[][] memory, bool) {
        DeploySuite[] memory released = releasedSuites();
        DerivedDeploy[] memory derived = new DerivedDeploy[](released.length);
        ResolvedBeacon[][] memory resolved = new ResolvedBeacon[][](networks.length);
        bool anyBeacons = false;
        for (uint256 i = 0; i < networks.length; i++) {
            DeployBeacon[] memory networkBeacons = beacons(networks[i].chainId);
            resolved[i] = new ResolvedBeacon[](networkBeacons.length);
            for (uint256 beaconIndex = 0; beaconIndex < networkBeacons.length; beaconIndex++) {
                resolved[i][beaconIndex] =
                    resolveBeacon(networkBeacons[beaconIndex], networks[i].chainId, beaconIndex, released, derived);
            }
            anyBeacons = anyBeacons || networkBeacons.length > 0;
        }
        return (resolved, anyBeacons);
    }

    /// @param beacon The beacon.
    /// @param chainId The beacon's network.
    /// @param beaconIndex The beacon's index in `beacons(chainId)`, for the refusal.
    /// @param released `releasedSuites()`, as `resolveReleased` takes it.
    /// @param derived Each released suite's derivation, as `resolveReleased` takes it.
    /// @return The beacon, resolved on `chainId`.
    function resolveBeacon(
        DeployBeacon memory beacon,
        uint256 chainId,
        uint256 beaconIndex,
        DeploySuite[] memory released,
        DerivedDeploy[] memory derived
    ) internal returns (ResolvedBeacon memory) {
        bool byAddress =
            beacon.beacon != address(0) || beacon.beaconCodeHash != bytes32(0);
        ResolvedBeacon memory resolved;
        if (bytes(beacon.beaconSuite).length != 0) {
            if (byAddress) {
                revert BeaconNamedTwice(chainId, beaconIndex);
            }
            uint256 releasedIndex = resolveReleased(beacon.beaconSuite, released, derived);
            resolved.suite = released[releasedIndex];
            resolved.derived = derived[releasedIndex];
            beacon.beacon = LibRainDeployMechanism.deployedAddress(released[releasedIndex], chainId);
            beacon.beaconCodeHash = derived[releasedIndex].bytecodeHash;
        } else if (!byAddress) {
            revert BeaconUnnamed(chainId, beaconIndex);
        }
        resolved.beacon = beacon;
        uint256 states = beacon.transitions.length + 1;
        resolved.implementations = new DeploySuite[](states);
        resolved.implementationAddresses = new address[](states);
        resolved.implementationDerived = new DerivedDeploy[](states);
        for (uint256 state = 0; state < states; state++) {
            uint256 releasedIndex =
                resolveReleased(LibRainDeployBeacon.stateAt(beacon, state).implementation, released, derived);
            resolved.implementations[state] = released[releasedIndex];
            resolved.implementationAddresses[state] =
                LibRainDeployMechanism.deployedAddress(released[releasedIndex], chainId);
            resolved.implementationDerived[state] = derived[releasedIndex];
        }
        return resolved;
    }

    /// @param key The key a beacon names.
    /// @param released `releasedSuites()`, each replaced by its `onSupportedNetworks` form when first resolved.
    /// @param derived Each released suite's derivation, filled when first resolved.
    /// @return The index of `key` in `released`.
    function resolveReleased(string memory key, DeploySuite[] memory released, DerivedDeploy[] memory derived)
        internal
        returns (uint256)
    {
        uint256 releasedIndex = suiteIndex(released, key);
        if (releasedIndex == released.length) {
            revert BeaconSuiteNotReleased(key);
        }
        if (bytes(derived[releasedIndex].suite).length == 0) {
            released[releasedIndex] = onSupportedNetworks(released[releasedIndex]);
            derived[releasedIndex] = deriveDeployment(released[releasedIndex]);
        }
        return releasedIndex;
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
