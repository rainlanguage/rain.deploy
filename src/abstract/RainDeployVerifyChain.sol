// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {DerivedDeploy, RainDeployVerifyBase, ResolvedBeacon} from "./RainDeployVerifyBase.sol";
import {DeploySuite} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";
import {DeployBeacon, LibRainDeployBeacon} from "../lib/LibRainDeployBeacon.sol";

/// @title RainDeployVerifyChain
/// @notice The only deploy-pin assertions anchored to something outside the repo.
abstract contract RainDeployVerifyChain is RainDeployVerifyBase {
    /// Checks every suite and every beacon against every supported network.
    /// @param suites The suites to check.
    function checkDeployedOnSupportedNetworks(DeploySuite[] memory suites) internal {
        checkDeployedOnNetworks(LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), suites);
    }

    /// Checks every suite and every beacon on the given networks against each, forking each network once, with
    /// `resolveBeacons`'s refusals raised before forking. With no suites, only the networks a beacon is on are forked.
    /// @param networks The catalogue entry of each network to check on.
    /// @param suites The suites to check.
    function checkDeployedOnNetworks(SupportedNetwork[] memory networks, DeploySuite[] memory suites) internal {
        ResolvedBeacon[] memory resolved = resolveBeacons(networks);

        // Nothing to check is not a reason to touch every RPC endpoint. Forking
        // to check nothing turns an outage into the failure of an assertion
        // that has no subject, which is the one failure this contract is
        // supposed to be legible against. With no suites only the networks a
        // beacon is on are forked, none when no beacon is on them.
        if (suites.length == 0) {
            networks = beaconNetworks(networks, resolved);
        }

        DeploySuite[] memory onNetworks = new DeploySuite[](suites.length);
        for (uint256 j = 0; j < suites.length; j++) {
            onNetworks[j] = onSupportedNetworks(suites[j]);
        }
        suites = onNetworks;

        DerivedDeploy[] memory derived = new DerivedDeploy[](suites.length);
        for (uint256 j = 0; j < suites.length; j++) {
            derived[j] = deriveUnlessResolved(suites[j], resolved);
        }
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
            checkBeaconsOnNetwork(networks[i], resolved);
        }
    }

    /// Each beacon in `resolved` on `network` goes through `checkResolvedBeacon`, in order; the others are not read.
    /// @param network The selected fork's network.
    /// @param resolved The resolved beacons.
    function checkBeaconsOnNetwork(SupportedNetwork memory network, ResolvedBeacon[] memory resolved) internal view {
        for (uint256 beaconIndex = 0; beaconIndex < resolved.length; beaconIndex++) {
            if (resolved[beaconIndex].chainId == network.chainId) {
                checkResolvedBeacon(network.name, resolved[beaconIndex]);
            }
        }
    }

    /// @param networks The networks to check.
    /// @param resolved The resolved beacons.
    /// @return The networks in `networks`, in order, whose chain id a beacon in `resolved` is on.
    function beaconNetworks(SupportedNetwork[] memory networks, ResolvedBeacon[] memory resolved)
        internal
        pure
        returns (SupportedNetwork[] memory)
    {
        bool[] memory kept = new bool[](networks.length);
        uint256 count = 0;
        for (uint256 i = 0; i < networks.length; i++) {
            for (uint256 j = 0; j < resolved.length; j++) {
                if (resolved[j].chainId == networks[i].chainId) {
                    kept[i] = true;
                    count++;
                    break;
                }
            }
        }
        SupportedNetwork[] memory onBeacons = new SupportedNetwork[](count);
        count = 0;
        for (uint256 i = 0; i < networks.length; i++) {
            if (kept[i]) {
                onBeacons[count] = networks[i];
                count++;
            }
        }
        return onBeacons;
    }

    /// `suite`'s derivation, reused from a beacon in `resolved` that resolved `suite` itself, else derived.
    /// @param suite The suite.
    /// @param resolved The resolved beacons.
    /// @return The derivation.
    function deriveUnlessResolved(DeploySuite memory suite, ResolvedBeacon[] memory resolved)
        internal
        returns (DerivedDeploy memory)
    {
        bytes32 encoded = keccak256(abi.encode(suite));
        for (uint256 i = 0; i < resolved.length; i++) {
            // `resolved[i].suite` is unset when the beacon names no `beaconSuite`.
            if (
                bytes(resolved[i].beacon.beaconSuite).length != 0 && keccak256(abi.encode(resolved[i].suite)) == encoded
            ) {
                return resolved[i].derived;
            }
            for (uint256 state = 0; state < resolved[i].implementations.length; state++) {
                if (keccak256(abi.encode(resolved[i].implementations[state])) == encoded) {
                    return resolved[i].implementationDerived[state];
                }
            }
        }
        return deriveDeployment(suite);
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

    /// The selected fork MUST hold the beacon at its applied state, with its own suite, when it names one, and that
    /// state's implementation suite live. Reverts as `checkSuiteOnNetwork`, `LibRainDeployBeacon.appliedState` and
    /// `LibRainDeployBeacon.checkBeacon` do.
    /// @param network The network's name, for the refusal.
    /// @param resolved The beacon.
    function checkResolvedBeacon(string memory network, ResolvedBeacon memory resolved) internal view {
        DeployBeacon memory beacon = resolved.beacon;
        // Deliberately rechecked by `checkBeacon`, which holds a beacon to its code hash on its own.
        if (bytes(beacon.beaconSuite).length != 0) {
            checkSuiteOnNetwork(network, resolved.suite, resolved.derived, beacon.beacon);
        }
        uint256 state = LibRainDeployBeacon.appliedState(network, beacon);
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

    /// Every RELEASED suite MUST be live, with the code its creation code produces and its declared
    /// dependencies under it, on every supported network, and every declared beacon MUST hold its applied
    /// state there.
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
