// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifySnapshot} from "../../../src/abstract/RainDeployVerifySnapshot.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";

/// @title RainDeployVerifySnapshotNarrowNetworksTest
/// @notice The config group holds `foundry.toml` to the networks the
/// declaration names, not to this package's list.
///
/// The narrowing is a flag a test turns on, not a statically narrow
/// declaration: the only config on disk names all nine, so a permanently
/// narrow binding would fail its own inherited test every run. The default
/// passing beside the narrowed failure is what makes the failure
/// discriminating.
///
/// Binding is the only way to drive the assertion — it takes no argument and
/// reads the binder's own file. This repo's real declaration rather than an
/// exemplar, because the group carries the frozen-record test, whose subject is
/// this repo's record.
contract RainDeployVerifySnapshotNarrowNetworksTest is RegistryDeploySuites, RainDeployVerifySnapshot {
    /// Set by the test below, and only by it. Off, this contract is the
    /// ordinary binding every consumer has.
    bool internal sNarrow;

    /// @inheritdoc RainDeploySuitesBase
    /// @dev Base alone once narrowed. It is configured here like every other
    /// network, so the only failure left is the eight aliases the narrowed
    /// declaration no longer names.
    function supportedNetworks() internal view override returns (string[] memory networks) {
        if (!sNarrow) {
            return super.supportedNetworks();
        }
        networks = new string[](1);
        networks[0] = LibRainDeploy.BASE;
    }

    /// An alias the declaration does not name fails, naming it. Arbitrum is
    /// simply the first such alias in the section.
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
