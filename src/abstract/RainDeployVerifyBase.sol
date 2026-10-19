// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {DeploySuite, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";
import {LibRainDeployMechanism, ZoltuDerivationMismatch} from "../lib/LibRainDeployMechanism.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {ChainBeacon, DeployBeacon, LibRainDeployBeacon} from "../lib/LibRainDeployBeacon.sol";

/// Thrown when the state snapshot taken around a derivation could not be
/// reverted. The derivation plants code at the derived address, clears its
/// nonce and etches the suite's declared dependencies; if that cannot be
/// undone, every later derivation reads state this one created, and the
/// chain-anchored checks compare a locally planted deployment against itself.
/// There is no safe way to continue.
/// @param suite The suite being derived when the revert failed.
/// @param snapshotId The snapshot that could not be reverted.
error DerivationSnapshotRevertFailed(string suite, uint256 snapshotId);

/// What a suite derives, by itself, through its own mechanism.
struct DerivedDeploy {
    /// The suite the derivation came from.
    string suite;
    /// The addresses the suite's mechanism deploys it to, in the suite's address order (see
    /// `LibRainDeployMechanism`).
    address[] deployedAddresses;
    /// The code hash the mechanism leaves behind at those addresses.
    bytes32 bytecodeHash;
}

/// @notice A suite a beacon names, as its implementation or as itself, MUST be released.
/// @param suite The declared key.
error BeaconSuiteNotReleased(string suite);

/// @notice A beacon MUST NOT be named both by `beaconSuite` and by `beacon` or `beaconCodeHash`.
/// @param chainId The beacon's network.
/// @param beaconIndex The beacon's index in `beacons()`.
error BeaconNamedTwice(uint256 chainId, uint256 beaconIndex);

/// @notice A beacon MUST be named by `beaconSuite` or by both `beacon` and `beaconCodeHash`.
/// @param chainId The beacon's network.
/// @param beaconIndex The beacon's index in `beacons()`.
error BeaconUnnamed(uint256 chainId, uint256 beaconIndex);

/// @notice A beacon's chain id MUST be one of `supportedNetworks()`.
/// @param chainId The beacon's chain id.
/// @param beaconIndex The beacon's index in `beacons()`.
error BeaconOnUncheckedNetwork(uint256 chainId, uint256 beaconIndex);

/// @notice Each beacon on a network MUST be declared once.
/// @param chainId The beacon's network.
/// @param beaconIndex The index in `beacons()` of the later declaration.
error BeaconDeclaredTwice(uint256 chainId, uint256 beaconIndex);

/// A beacon with every suite it names resolved on its network.
/// @param chainId The beacon's network.
/// @param beacon The declaration, its `beacon` and `beaconCodeHash` derived when it names `beaconSuite`.
/// @param suite The beacon's suite when it names `beaconSuite`.
/// @param derived The beacon's suite's derivation when it names `beaconSuite`.
/// @param implementations Each state's implementation suite, indexed as `LibRainDeployBeacon.stateAt`.
/// @param implementationAddresses Each state's implementation address on the beacon's network.
/// @param implementationDerived Each state's implementation derivation.
struct ResolvedBeacon {
    uint256 chainId;
    DeployBeacon beacon;
    DeploySuite suite;
    DerivedDeploy derived;
    DeploySuite[] implementations;
    address[] implementationAddresses;
    DerivedDeploy[] implementationDerived;
}

/// @title RainDeployVerifyBase
/// @notice The derivation and beacon resolution every deploy-verification group shares.
abstract contract RainDeployVerifyBase is RainDeploySuitesBase, Test {
    /// Derives where a suite's mechanism puts it and the code hash it leaves there, from the suite
    /// alone.
    /// @param suite The suite to derive from.
    /// @return The addresses and code hash the suite's mechanism produces.
    function deriveDeployment(DeploySuite memory suite) internal returns (DerivedDeploy memory) {
        uint256 snapshotId = vm.snapshotState();

        address[] memory deployedAddresses = LibRainDeployMechanism.deployLocally(vm, suite);
        DerivedDeploy memory derived = DerivedDeploy({
            suite: suite.suite, deployedAddresses: deployedAddresses, bytecodeHash: deployedAddresses[0].codehash
        });

        // A failed revert is unrecoverable, not a warning to silence. The etch
        // and the nonce reset would survive into every later derivation, whose
        // results would then look entirely plausible while describing state
        // this call planted.
        if (!vm.revertToState(snapshotId)) {
            revert DerivationSnapshotRevertFailed(suite.suite, snapshotId);
        }

        return derived;
    }

    /// Derives every suite once, before anything forks. Callers that compare
    /// against chains need the derivation to have already happened on a local
    /// EVM, because on a fork the derived address is exactly the address the
    /// deployment under test occupies.
    /// @param suites The suites to derive.
    /// @return The derivation of each, positionally paired.
    function deriveDeployments(DeploySuite[] memory suites) internal returns (DerivedDeploy[] memory) {
        DerivedDeploy[] memory derived = new DerivedDeploy[](suites.length);
        for (uint256 i = 0; i < suites.length; i++) {
            derived[i] = deriveDeployment(suites[i]);
        }
        return derived;
    }

    /// Refuses `BeaconOnUncheckedNetwork` for any of `beacons()` off `supportedNetworks()`, whether or not it is on
    /// `networks`, before resolving any; then, for each beacon on `networks`, `resolveBeacon`'s refusals and
    /// `BeaconDeclaredTwice` for one at an address an earlier one on its network resolved to.
    /// @param networks The networks whose beacons to resolve.
    /// @return Each of `beacons()` on one of `networks`, resolved on it, in declaration order.
    function resolveBeacons(SupportedNetwork[] memory networks) internal returns (ResolvedBeacon[] memory) {
        ChainBeacon[] memory chainBeacons = beacons();
        if (chainBeacons.length == 0) {
            return new ResolvedBeacon[](0);
        }
        SupportedNetwork[] memory supported = LibRainDeploy.declaredNetworkConfigs(supportedNetworks());
        uint256 onNetworks = 0;
        for (uint256 beaconIndex = 0; beaconIndex < chainBeacons.length; beaconIndex++) {
            uint256 chainId = chainBeacons[beaconIndex].chainId;
            if (!LibRainDeploy.hasChainId(supported, chainId)) {
                revert BeaconOnUncheckedNetwork(chainId, beaconIndex);
            }
            if (LibRainDeploy.hasChainId(networks, chainId)) {
                onNetworks++;
            }
        }
        DeploySuite[] memory released = releasedSuites();
        DerivedDeploy[] memory derived = new DerivedDeploy[](released.length);
        ResolvedBeacon[] memory resolved = new ResolvedBeacon[](onNetworks);
        uint256 resolvedIndex = 0;
        for (uint256 beaconIndex = 0; beaconIndex < chainBeacons.length; beaconIndex++) {
            uint256 chainId = chainBeacons[beaconIndex].chainId;
            if (LibRainDeploy.hasChainId(networks, chainId)) {
                ResolvedBeacon memory beacon =
                    resolveBeacon(chainBeacons[beaconIndex].beacon, chainId, beaconIndex, released, derived);
                for (uint256 earlier = 0; earlier < resolvedIndex; earlier++) {
                    if (resolved[earlier].chainId == chainId && resolved[earlier].beacon.beacon == beacon.beacon.beacon)
                    {
                        revert BeaconDeclaredTwice(chainId, beaconIndex);
                    }
                }
                resolved[resolvedIndex++] = beacon;
            }
        }
        return resolved;
    }

    /// Refuses `BeaconNamedTwice` and `BeaconUnnamed`, `BeaconSuiteNotReleased` through `resolveReleased`, and
    /// `LibRainDeployBeacon.checkTransitionMigrations`'s refusals.
    /// @param declaration The beacon, left unwritten so one declaration can be resolved on several networks.
    /// @param chainId The beacon's network.
    /// @param beaconIndex The beacon's index in `beacons()`, for the refusal.
    /// @param released `releasedSuites()`, as `resolveReleased` takes it.
    /// @param derived Each released suite's derivation, as `resolveReleased` takes it.
    /// @return The beacon, resolved on `chainId`.
    function resolveBeacon(
        DeployBeacon memory declaration,
        uint256 chainId,
        uint256 beaconIndex,
        DeploySuite[] memory released,
        DerivedDeploy[] memory derived
    ) internal returns (ResolvedBeacon memory) {
        DeployBeacon memory beacon = DeployBeacon({
            beaconSuite: declaration.beaconSuite,
            beacon: declaration.beacon,
            beaconCodeHash: declaration.beaconCodeHash,
            initial: declaration.initial,
            transitions: declaration.transitions
        });
        ResolvedBeacon memory resolved;
        if (bytes(beacon.beaconSuite).length != 0) {
            if (beacon.beacon != address(0) || beacon.beaconCodeHash != bytes32(0)) {
                revert BeaconNamedTwice(chainId, beaconIndex);
            }
            uint256 releasedIndex = resolveReleased(beacon.beaconSuite, released, derived);
            resolved.suite = released[releasedIndex];
            resolved.derived = derived[releasedIndex];
            beacon.beacon = LibRainDeployMechanism.deployedAddress(released[releasedIndex], chainId);
            beacon.beaconCodeHash = derived[releasedIndex].bytecodeHash;
        } else if (beacon.beacon == address(0) || beacon.beaconCodeHash == bytes32(0)) {
            revert BeaconUnnamed(chainId, beaconIndex);
        }
        LibRainDeployBeacon.checkTransitionMigrations(chainId, beacon);
        resolved.chainId = chainId;
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

    /// Refuses `BeaconSuiteNotReleased` when `key` is not in `released`.
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
}
