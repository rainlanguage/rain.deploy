// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {AddressRegistryDeploySuites} from "../../../src/abstract/AddressRegistryDeploySuites.sol";

/// @title AddressRegistryDeployChainTest
/// @notice Whether `AddressRegistry` is actually live, with the code this repo
/// compiles, on every supported network.
///
/// It is not. `AddressRegistry` has never been deployed and
/// `ADDRESS_REGISTRY_ROOT` is still a placeholder, so this fails on the first
/// network with `NotDeployedOnNetwork` and keeps failing until the contract is
/// deployed to every supported network.
///
/// That failure is the check working. "Nothing is deployed at the address
/// `LibAddressRegistry` reads" is true, it is the single most important fact
/// about these pins, and no snapshot assertion can discover it — a perfectly
/// consistent set of pins for a contract that exists nowhere passes every one
/// of them. A green here would only mean nobody asked.
///
/// It is a separate contract from `AddressRegistryDeploySnapshotTest`
/// precisely so that it says this and nothing more: `forge test
/// --no-match-contract Chain` still runs every snapshot assertion,
/// whether the deployment is missing or the RPC endpoints are merely
/// unreachable.
contract AddressRegistryDeployChainTest is AddressRegistryDeploySuites, RainDeployVerifyChain {}
