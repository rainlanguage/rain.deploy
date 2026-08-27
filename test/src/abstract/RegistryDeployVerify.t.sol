// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerify} from "../../../src/abstract/RainDeployVerify.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";

/// @title RegistryDeployVerifyTest
/// @notice This repo's own registry declaration bound to `RainDeployVerify` —
/// the same single line a consumer writes, so a check that reaches this
/// contract reaches every consumer that has bumped, and one that does not reach
/// it never shipped.
///
/// Everything is inherited. There is nothing to write here, which is the point:
/// `RegistryDeploySuites` says which registries and which releases exist and
/// `RainDeployVerify` says what is true of them.
///
/// The chain half is red until every release declared here is live on every
/// supported network, which is why the deploy is dispatched before the tag is
/// pushed. That is the check working: "nothing is deployed at the address
/// `LibAddressRegistry` reads" is the single most important fact about these
/// pins, and no snapshot assertion can discover it — a perfectly consistent set
/// of pins for a contract that exists nowhere passes every one of them.
///
/// What the inherited assertions do with a declaration is the abstracts'
/// business and is pinned against fixtures rather than here:
/// `RainDeployVerifyChainTest` for a set the matrix must check on every
/// network, `RainDeployVerifyChainCandidateTest` for the candidate it must
/// ignore, `RainDeployVerifyChainEmptyTest` for a set with nothing in it, which
/// it must not fork for, and `RainDeployVerifySnapshotBaseTest` for the
/// snapshot groups at every position and every shape of declaration.
contract RegistryDeployVerifyTest is RegistryDeploySuites, RainDeployVerify {}
