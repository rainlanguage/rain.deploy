// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";

/// @title RegistryDeployChainTest
/// @notice Whether every registry this repo has RELEASED is actually live, with
/// the code that release froze, on every supported network.
///
/// The chain group reads `releasedSuites()`, so this is red until every release
/// this repo has declared is live on every supported network — which is why the
/// deploy is dispatched before the tag is pushed. That failure is the check
/// working. "Nothing is deployed at the address `LibAddressRegistry` reads" is
/// the single most important fact about these pins, and no snapshot assertion
/// can discover it — a perfectly consistent set of pins for a contract that
/// exists nowhere passes every one of them.
///
/// The assertion is inherited. There is nothing to write here, which is the
/// point: `RegistryDeploySuites` says which releases exist and
/// `RainDeployVerifyChain` says what is true of them. What the matrix does with
/// a declaration is the abstract's business and is pinned against fixtures —
/// `RainDeployVerifyChainTest` for a set it must check on every network,
/// `RainDeployVerifyChainCandidateTest` for the candidate it must ignore, and
/// `RainDeployVerifyChainEmptyTest` for a set with nothing in it, which it must
/// not fork for.
///
/// It is a separate contract from `RegistryDeploySnapshotTest` precisely so that
/// it says this and nothing more: a missing deployment or an unreachable
/// endpoint fails here alone, leaving every snapshot assertion to answer for
/// itself.
contract RegistryDeployChainTest is RegistryDeploySuites, RainDeployVerifyChain {}
