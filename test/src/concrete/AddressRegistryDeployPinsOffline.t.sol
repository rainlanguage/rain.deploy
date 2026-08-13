// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployVerifyOffline} from "../../../src/abstract/RainDeployVerifyOffline.sol";
import {AddressRegistryDeploySuites} from "../../../src/abstract/AddressRegistryDeploySuites.sol";

/// @title AddressRegistryDeployPinsOfflineTest
/// @notice The deploy-pin assertions for `AddressRegistry` that need no
/// network: what `LibAddressRegistryDeploy` records is what the creation code
/// this repo compiles derives, and the candidate is a snapshot of that source
/// rather than of some other contract.
///
/// The pins are a pure function of the creation code, which is a pure function
/// of this repo's compiler settings — and the contract, the settings and the
/// pins are all in this repo, so this closes the loop rather than asserting
/// across a boundary. The root authority is a constant in that creation code,
/// so changing the root moves both pins and turns this red until they follow.
///
/// Both assertions are inherited. There is nothing to write here, which is the
/// point: `AddressRegistryDeploySuites` says which versions exist and
/// `RainDeployVerifyOffline` says what is true of them.
contract AddressRegistryDeployPinsOfflineTest is AddressRegistryDeploySuites, RainDeployVerifyOffline {}
