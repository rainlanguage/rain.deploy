// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {AddressRegistry} from "../src/concrete/AddressRegistry.sol";
import {LibAddressRegistryDeploy} from "../src/lib/LibAddressRegistryDeploy.sol";
import {LibRainDeploy} from "../src/lib/LibRainDeploy.sol";

/// @dev Hash of the "address-registry" deployment suite string. MUST match the
/// `suite:` input of `.github/workflows/manual-sol-artifacts.yaml`, which is
/// what supplies `DEPLOYMENT_SUITE`.
bytes32 constant DEPLOYMENT_SUITE_ADDRESS_REGISTRY = keccak256("address-registry");

/// @title Deploy
/// @notice Broadcasts `AddressRegistry` to every network in
/// `LibRainDeploy.supportedNetworks()`, at the deterministic address
/// `LibAddressRegistryDeploy` pins.
///
/// This is the missing half of the deploy lifecycle `package-release.yaml`
/// assumes: `rainix-tag-release` verifies and publishes pins for a deployment
/// that already exists, so something has to put it on chain first, and a
/// `sol-v*` tag is not it. Run manually via the `Manual sol artifacts`
/// workflow, before tagging.
///
/// Deploying is idempotent by construction. `deployToNetworks` checks the
/// derived address against the creation code before it forks anything, then
/// skips any network that already has code there, so a partial run — three
/// chains of five, one RPC down — is fixed by running it again rather than by
/// unpicking anything.
///
/// `AddressRegistryDeployPinsChainTest` is what says whether this has been run
/// and worked. It fails until every supported network has the registry, which
/// is the state this repo is in right now.
contract Deploy is Script {
    /// Deploys the suite named by `DEPLOYMENT_SUITE`.
    ///
    /// The suite is read before the key so that a mistyped `suite:` input fails
    /// in seconds, naming what it should have been, rather than failing on a
    /// missing `DEPLOYMENT_KEY` and sending the reader after the wrong thing.
    function run() external {
        bytes32 suite = keccak256(bytes(vm.envOr("DEPLOYMENT_SUITE", string("address-registry"))));
        if (suite != DEPLOYMENT_SUITE_ADDRESS_REGISTRY) {
            revert(
                "Invalid deployment suite specified. Please set the DEPLOYMENT_SUITE environment variable to 'address-registry'."
            );
        }

        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        // `AddressRegistry` reads nothing and calls nothing, so it depends on
        // no other deployment. The Zoltu factory itself is not a dependency
        // here: `deployToNetworks` checks it on every network it actually
        // deploys to.
        address[] memory dependencies = new address[](0);

        LibRainDeploy.deployAndBroadcast(
            vm,
            LibRainDeploy.supportedNetworks(),
            deployerPrivateKey,
            type(AddressRegistry).creationCode,
            "src/concrete/AddressRegistry.sol:AddressRegistry",
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
            dependencies
        );
    }
}
