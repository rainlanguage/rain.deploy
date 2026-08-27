// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployVerifySnapshotBase} from "./RainDeployVerifySnapshotBase.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "../lib/LibRainDeploySnapshot.sol";
import {LibStringSet} from "../lib/LibStringSet.sol";

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
    /// the one a snapshot is WRITTEN to — `LIB_FS_ROOT` is the only spelling of
    /// it in `LibRainDeploySnapshot` and `testRecordRootIsTheRootTheWriterWritesTo`
    /// pins it against `LibFs`'s. Under the writer's own root, finding nothing
    /// means there is nothing; under any other, the walk returns an empty list
    /// forever, this passes with no subject, and the one check standing between
    /// a release dropping out of everything and a green suite is inert.
    ///
    /// That is also why the root is not a parameter and this is not `virtual`.
    /// Every way of pointing it somewhere else is a way of making it inert
    /// while it still reports green, so there is nothing for a caller to hand
    /// it and nothing to override. A contract that must not be asked this — a
    /// harness whose released declaration is a fixture — inherits
    /// `RainDeployVerifySnapshotBase` instead, which is a narrower contract in
    /// an inheritance list rather than an emptied test body.
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
        checkFrozenSnapshotsReleased(
            LibRainDeploySnapshot.frozenSnapshotPaths(vm, LibRainDeploySnapshot.LIB_FS_ROOT), releasedSuites()
        );
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
    /// The raw file is read rather than forge's resolved config because the
    /// values are `${VAR}` interpolations that exist only in CI. The KEYS are
    /// the whole contract here, and they are in the text — so this needs no
    /// RPC and fails on the PR that drifts rather than at dispatch time.
    ///
    /// `vm.readFile` resolves against the project root of whatever runs it, so
    /// the file read is the binder's own and the networks are this package's.
    /// A binding repo therefore needs `{ access = "read", path =
    /// "./foundry.toml" }` in `fs_permissions`, and one without it fails here
    /// rather than passing on a file it never opened.
    function testSupportedNetworksAreFullyConfigured() external view {
        string memory config = vm.readFile("foundry.toml");
        string[] memory networks = LibRainDeploy.supportedNetworks();

        for (uint256 i = 0; i < networks.length; i++) {
            assertTrue(
                vm.keyExistsToml(config, string.concat(".rpc_endpoints.", networks[i])),
                string.concat("supported network has no [rpc_endpoints] alias: ", networks[i])
            );
            assertTrue(
                vm.keyExistsToml(config, string.concat(".etherscan.", networks[i])),
                string.concat("supported network has no [etherscan] key: ", networks[i])
            );
        }

        string[] memory rpcAliases = vm.parseTomlKeys(config, ".rpc_endpoints");
        for (uint256 i = 0; i < rpcAliases.length; i++) {
            assertTrue(
                LibStringSet.holds(networks, rpcAliases[i]),
                string.concat("[rpc_endpoints] alias is not a supported network: ", rpcAliases[i])
            );
        }

        string[] memory etherscanKeys = vm.parseTomlKeys(config, ".etherscan");
        for (uint256 i = 0; i < etherscanKeys.length; i++) {
            assertTrue(
                LibStringSet.holds(networks, etherscanKeys[i]),
                string.concat("[etherscan] key is not a supported network: ", etherscanKeys[i])
            );
        }
    }
}
