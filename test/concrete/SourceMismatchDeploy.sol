// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {SourceMismatchDeploySuites} from "../abstract/SourceMismatchDeploySuites.sol";

/// @title SourceMismatchDeploy
/// A deploy repo's whole script, over a declaration whose candidate is a
/// snapshot of the wrong contract — `ExampleDeploy` with one thing wrong, and
/// the thing that is wrong is the one nothing about a snapshot can see by
/// itself.
///
/// It is a real script rather than a declaration fixture because that is the
/// claim under test: the anchor has to run on the path that BROADCASTS, not
/// only on the path that tests. A fixture that could only be driven through
/// external wrappers would leave `run()` — the irreversible, multi-chain,
/// key-custody action — asserted about by nothing.
contract SourceMismatchDeploy is SourceMismatchDeploySuites, ExternalDeploySuites, RainDeployBroadcast {}
