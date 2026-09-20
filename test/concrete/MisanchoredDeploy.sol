// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {MisanchoredDeploySuites} from "../abstract/MisanchoredDeploySuites.sol";

/// @title MisanchoredDeploy
/// A deploy repo's whole script over a declaration that names one contract and
/// records another.
///
/// A real script rather than a declaration fixture, for the reason
/// `SourceMismatchDeploy` is one: the claim under test is that the anchor holds
/// on the path that BROADCASTS. A declaration that could only be driven through
/// the external wrappers would leave `run()` — the irreversible, multi-chain,
/// key-custody action — asserted about by nothing, and `run()` is exactly where
/// a neutered anchor costs a permanent `CREATE2` address on every chain the
/// dispatch reached.
contract MisanchoredDeploy is MisanchoredDeploySuites, ExternalDeploySuites, RainDeployBroadcast {}
