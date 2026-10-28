// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerify} from "../../../src/abstract/RainDeployVerify.sol";
import {TwoMechanismDeploySuites} from "../../abstract/TwoMechanismDeploySuites.sol";

/// @title RainDeployVerifyTwoMechanismsTest
/// @notice The chain and snapshot groups run over a declaration of two non-Zoltu mechanisms with no override.
contract RainDeployVerifyTwoMechanismsTest is TwoMechanismDeploySuites, RainDeployVerify {}
