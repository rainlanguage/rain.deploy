// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../src/abstract/RainDeployBroadcast.sol";
import {RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";

/// @title Deploy
/// @notice The on-chain deploy. Broadcasts whichever suite `DEPLOYMENT_SUITE`
/// names, through the Zoltu factory, to every supported network. One suite per
/// dispatch, so this repo's two registries are two dispatches.
///
/// Empty on purpose. The suites come from `RegistryDeploySuites`, which
/// is the same declaration the verification tests inherit, and the dispatch,
/// the key handling and the broadcast come from `RainDeployBroadcast`. A deploy
/// repo writes its declaration and this pair of base contracts, and nothing
/// else — no per-suite branch, no per-network list.
///
/// This is the missing half of the deploy lifecycle `package-release.yaml`
/// assumes: `rainix-tag-release` verifies and publishes pins for a deployment
/// that already exists, so something has to put it on chain first, and a
/// `sol-v*` tag is not it. Run manually via the `Manual sol artifacts`
/// workflow, before tagging.
///
/// Deploying is idempotent by construction. `deployToNetworks` checks the
/// recorded address against the creation code before it forks anything, then
/// skips any network that already has code there, so a partial run — five
/// chains of seven, one RPC down — is fixed by running it again rather than by
/// unpicking anything.
contract Deploy is RegistryDeploySuites, RainDeployBroadcast {}
