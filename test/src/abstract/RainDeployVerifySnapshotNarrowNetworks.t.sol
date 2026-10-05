// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifySnapshot} from "../../../src/abstract/RainDeployVerifySnapshot.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";

/// @title RainDeployVerifySnapshotNarrowNetworksTest
/// @notice The config group MUST hold `foundry.toml` to the networks the
/// DECLARATION names, not to this package's list.
///
/// Scope is the whole of what this says. `testSupportedNetworksAreFullyConfigured`
/// asserts membership in both directions, so a repo that deploys to five
/// networks and configures five is held to the other four as well — and fails
/// on a config that is exactly right for it. That failure is why
/// `st0x.deploy` binds no chain group and this half's `[rpc_endpoints]`
/// assertion reaches it through nothing.
///
/// ## Why the scope is a flag rather than a narrower declaration
///
/// The only config on disk is this repo's own, and it names all nine. A
/// contract whose declaration was statically narrow would therefore fail the
/// very test it exists to drive, every run, as its own inherited test — so the
/// narrowing has to be something a test turns ON, which is what makes the
/// scoped failure reachable and leaves the default passing beside it.
///
/// The default case passing is not incidental: it is what makes the narrowed
/// failure discriminating. A group reading this package's list passes both, and
/// a group that could not pass at all fails both.
///
/// ## Why it binds at all
///
/// The assertion takes no argument and is not `virtual` — it reads the binder's
/// own file, which is the point of it — so binding is the only way to drive it.
/// That brings the rest of the snapshot group with it, which is a second run of
/// tests `RegistryDeployVerifyTest` already runs over this same declaration.
/// `checkNetworksConfigured` is where the assertions themselves are pinned,
/// against configs a test builds; the one thing that cannot be handed in is
/// WHICH networks the inherited test reads, and that is what this is.
///
/// This repo's real declaration rather than an exemplar, because
/// `RainDeployVerifySnapshot` carries the frozen-record test, whose subject is
/// this repo's real record and never the inheriting contract's fixture — see
/// `RainDeployVerifySnapshotBase` for why asking an exemplar that asserts
/// something false.
contract RainDeployVerifySnapshotNarrowNetworksTest is RegistryDeploySuites, RainDeployVerifySnapshot {
    /// Set by the test below, and only by it. Off, this contract is the
    /// ordinary binding every consumer has.
    bool internal sNarrow;

    /// @inheritdoc RainDeploySuitesBase
    /// @dev Base alone once narrowed. It is configured in this repo's
    /// `foundry.toml` like every other supported network, so the forward
    /// direction still holds and the failure can only come from the eight
    /// aliases the narrowed declaration no longer names — the direction that
    /// makes a correct consumer config red.
    function supportedNetworks() internal view override returns (string[] memory networks) {
        if (!sNarrow) {
            return super.supportedNetworks();
        }
        networks = new string[](1);
        networks[0] = LibRainDeploy.BASE;
    }

    /// A `[rpc_endpoints]` alias the DECLARATION does not name MUST fail,
    /// naming the alias — which is only true of a check reading the
    /// declaration, since every alias in this repo's config is one the
    /// library's list names.
    ///
    /// Arbitrum is the first such alias in the section and so is the one
    /// reported; which it is does not matter here, only that the networks
    /// compared against moved with the declaration.
    function testConfigIsHeldToTheDeclaredNetworks() external {
        sNarrow = true;

        vm.expectRevert(
            abi.encodeWithSignature(
                "CheatcodeError(string)", "[rpc_endpoints] alias is not a supported network: arbitrum"
            )
        );
        this.testSupportedNetworksAreFullyConfigured();
    }
}
