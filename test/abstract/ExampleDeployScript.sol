// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ExampleDeploySuites} from "./ExampleDeploySuites.sol";
import {ExternalDeployBroadcast} from "./ExternalDeployBroadcast.sol";

/// @title ExampleDeployScript
/// A deploy repo's whole script — a suite declaration plus `RainDeployBroadcast`
/// and nothing else, which is exactly what `script/Deploy.sol` is. The external
/// wrappers let a plain `Test` contract drive the internals without inheriting
/// `Script`.
abstract contract ExampleDeployScript is ExampleDeploySuites, ExternalDeployBroadcast {}
