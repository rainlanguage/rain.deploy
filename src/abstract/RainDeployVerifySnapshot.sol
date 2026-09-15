// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployVerifySnapshotBase} from "./RainDeployVerifySnapshotBase.sol";
import {LibRainDeploySnapshot} from "../lib/LibRainDeploySnapshot.sol";

/// @title RainDeployVerifySnapshot
/// @notice What a deploy repo inherits: every assertion that needs no network,
/// bound to that repo. `RainDeployVerifySnapshotBase` is where the three
/// deploy-pin groups are defined and documented; this adds the test whose
/// subject is the repo's own state on disk — its frozen record — rather than
/// anything the inheriting contract declares.
///
/// The split is which contract carries that test, and nothing else. A consumer
/// inherits this and gets all three groups, exactly as it does when they are
/// one contract. The base is for a contract whose declaration is a FIXTURE —
/// the record is not its subject, and see the base for why asking it about the
/// record asserts something false.
abstract contract RainDeployVerifySnapshot is RainDeployVerifySnapshotBase {
    /// Every release in the frozen record MUST be declared, so that the set the
    /// chain group checks is every release this repo has ever cut rather than
    /// the ones somebody remembered to list.
    ///
    /// An empty walk passes, and is meant to: that is the state of every deploy
    /// repo before its first release. What makes it safe is that the root is
    /// the one a snapshot is WRITTEN to. Under the writer's own root, finding
    /// nothing means there is nothing; under any other, the walk returns an
    /// empty list forever, this passes with no subject, and the one check
    /// standing between a release dropping out of everything and a green suite
    /// is inert.
    ///
    /// So the root is not spelled here at all: the walk is the overload that
    /// takes none. Every step from this call to the writer is asserted rather
    /// than conventional — `testFrozenSnapshotPathsDefaultToTheWritersRecord`
    /// holds that default to `LibFs`'s own record paths, and
    /// `testRecordRootIsTheRootTheWriterWritesTo` holds the layout
    /// `LIB_FS_ROOT` is interpolated into to the one the writer writes.
    ///
    /// This is not `virtual` for the same reason. Every way of pointing it
    /// somewhere else is a way of making it inert while it still reports green,
    /// so there is nothing for a caller to hand it and nothing to override. A
    /// contract that must not be asked this — a harness whose released
    /// declaration is a fixture — inherits `RainDeployVerifySnapshotBase`
    /// instead, which is a narrower contract in an inheritance list rather than
    /// an emptied test body.
    ///
    /// Deliberately NOT also guarded by comparing the record's size against the
    /// declaration's. The two are emitted one-for-one by `writeReleasedSuitesLib`
    /// for a repo that generates its declaration from its record, but this is
    /// inherited by any repo that overrides `releasedSuites`, and a declaration
    /// with no record behind it is a state such a repo is legitimately in: a
    /// release deployed before it adopted this machinery has no frozen record
    /// and never will. A size check would red-line that permanently with no way
    /// to spell the exemption, while the release it names goes on being checked
    /// by everything anchored to a chain.
    function testEveryFrozenSnapshotIsReleased() external view {
        checkFrozenSnapshotsReleased(LibRainDeploySnapshot.frozenSnapshotPaths(vm), releasedSuites());
    }
}
