// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifySnapshot} from "../../../src/abstract/RainDeployVerifySnapshot.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";

/// @title RegistryDeploySnapshotTest
/// @notice The deploy-pin assertions for every registry this repo deploys that
/// need no network: what each alias lib records is what the creation code this
/// repo compiles derives, and each candidate is a snapshot of its own source
/// rather than of some other contract.
///
/// The pins are a pure function of the creation code, which is a pure function
/// of this repo's compiler settings — and the contracts, the settings and the
/// pins are all in this repo, so this closes the loop rather than asserting
/// across a boundary. `AddressRegistry`'s root authority is a constant in its
/// creation code, so changing the root moves its pins and turns this red until
/// they follow.
///
/// Both assertions are inherited. There is nothing to write here, which is the
/// point: `RegistryDeploySuites` says which versions exist and
/// `RainDeployVerifySnapshot` says what is true of them.
contract RegistryDeploySnapshotTest is RegistryDeploySuites, RainDeployVerifySnapshot {}
