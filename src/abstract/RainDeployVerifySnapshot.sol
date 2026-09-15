// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployVerifySnapshotBase} from "./RainDeployVerifySnapshotBase.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "../lib/LibRainDeploySnapshot.sol";

/// @title RainDeployVerifySnapshot
/// @notice What a deploy repo inherits: every assertion that needs no network,
/// bound to that repo. `RainDeployVerifySnapshotBase` is where the three
/// deploy-pin groups are defined and documented; this adds the tests whose
/// subject is the repo's own state on disk — its frozen record, and its
/// `foundry.toml` — rather than anything the inheriting contract declares.
///
/// The split is which contract carries those tests, and nothing else. A
/// consumer inherits this and gets all three groups, exactly as it does when
/// they are one contract. The base is for a contract whose declaration is a
/// FIXTURE — the record is not its subject, and see the base for why asking it
/// about the record asserts something false.
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

    /// `[rpc_endpoints]` and `[etherscan]` in the binding repo's `foundry.toml`
    /// MUST be EXACTLY `supportedNetworks()`, which makes the three lists one
    /// list.
    ///
    /// The deploy forks by the first and `--verify` resolves the second, so a
    /// supported network missing from either broadcasts and then fails after
    /// the gas is spent, and a section entry no supported network names is
    /// config nothing ever reads. Both are the same defect — the lists having
    /// drifted — so both directions are asserted, by membership: containment
    /// one way alone passes for a section carrying an alias nothing deploys
    /// to, and the other way alone passes for a network with no config at all.
    /// Membership rather than position, because a config section is keyed
    /// rather than ordered and there is no order in it to assert.
    ///
    /// This is what makes the `[etherscan]` half enforced at all. The RPC half
    /// is enforced only incidentally, by the fork tests, and only forwards.
    ///
    /// Membership is necessary and not sufficient for that half, so the SHAPE
    /// of each `[etherscan]` entry is asserted beside it by
    /// `checkEtherscanEntriesResolvable`: foundry resolves the whole section, so
    /// an entry it cannot resolve fails `--verify` for the other entries as
    /// well, after the gas is spent, while satisfying every membership
    /// assertion here.
    ///
    /// The raw file is read rather than forge's resolved config because the
    /// values are `${VAR}` interpolations that exist only in CI. Nothing
    /// asserted here is a value — the keys, and that each `[etherscan]` entry
    /// carries enough to resolve at all, are both in the text — so this needs
    /// no RPC and fails on the PR that drifts rather than at dispatch time.
    ///
    /// `vm.readFile` resolves against the project root of whatever runs it, so
    /// the file read is the binder's own and the networks are this package's.
    /// A binding repo therefore needs `{ access = "read", path =
    /// "./foundry.toml" }` in `fs_permissions`, and one without it fails here
    /// rather than passing on a file it never opened.
    ///
    /// The assertions themselves are `checkNetworksConfigured`, in the base,
    /// because they take the config as an argument and so can be handed one a
    /// test builds. Reading the binder's own file is the part that cannot be,
    /// and it is all that is left here.
    function testSupportedNetworksAreFullyConfigured() external view {
        checkNetworksConfigured(vm.readFile("foundry.toml"), LibRainDeploy.supportedNetworks());
    }
}
