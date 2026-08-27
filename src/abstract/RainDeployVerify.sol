// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployVerifyChain} from "./RainDeployVerifyChain.sol";
import {RainDeployVerifySnapshot} from "./RainDeployVerifySnapshot.sol";

/// @title RainDeployVerify
/// @notice The ONE contract a deploy repo binds: every deploy verification this
/// package has, network-free and chain-anchored alike, over that repo's own
/// declaration.
///
/// A check a repo has to opt into is a check most repos do not run. Binding is
/// a downstream edit, every repo owes it independently, and nothing red-lines
/// the one that skips it — so an assertion added to a contract nobody binds
/// ships without arriving. Bound here it arrives on a version bump with no
/// downstream edit, which puts delivering it on the author who knows it exists.
///
/// That holds only while this is the whole of what there is to bind. A new
/// check therefore goes into a contract this already inherits, or into this. An
/// abstract added beside it, that every consumer has to remember, reproduces
/// the gap this exists to close.
///
/// `RainDeployVerifyChain` and `RainDeployVerifySnapshot` stay separate
/// contracts underneath, because that split is runtime rather than binding: the
/// chain group forks every supported network and the snapshot group touches
/// none, so binding one of them alone is what runs the offline half with no RPC
/// credentials. `--match-contract` selects at a contract boundary, so the pair
/// has to remain two contracts for that to be selectable at all. This is what a
/// repo binds; that pair is what a job narrows to.
abstract contract RainDeployVerify is RainDeployVerifyChain, RainDeployVerifySnapshot {}
