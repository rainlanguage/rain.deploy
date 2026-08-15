// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";

/// @title RegistryDeployChainTest
/// @notice Whether every registry this repo has RELEASED is actually live, with
/// the code that release froze, on every supported network.
///
/// It has released none. The chain group reads `releasedSuites()`, which is
/// empty until the first release is cut, so there is nothing here to check: this
/// forks nothing and passes. It gets a subject the moment a release is frozen
/// and declared, and from then on it is red until that release is live on every
/// supported network — which is why the deploy is dispatched before the tag is
/// pushed.
///
/// That eventual failure is the check working. "Nothing is deployed at the
/// address `LibAddressRegistry` reads" is true today, it is the single most
/// important fact about these pins, and no snapshot assertion can discover it —
/// a perfectly consistent set of pins for a contract that exists nowhere passes
/// every one of them.
///
/// It is a separate contract from `RegistryDeploySnapshotTest` precisely so that
/// it says this and nothing more: a missing deployment or an unreachable
/// endpoint fails here alone, leaving every snapshot assertion to answer for
/// itself.
contract RegistryDeployChainTest is RegistryDeploySuites, RainDeployVerifyChain {}
