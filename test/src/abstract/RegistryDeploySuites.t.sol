// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {DeployCandidate} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";

/// @title RegistryDeploySuitesTest
/// @notice The fields of this repo's declaration that nothing derives and no
/// chain check can reach without an RPC.
///
/// The recorded address, code hash and runtime code are all checked against
/// what the recorded creation code derives, and the suite key, the artifact
/// path and the candidate set are all checked against the generator. The
/// dependency list is the one field with none of that behind it: it is not
/// derived from anything, the generator neither writes it nor reads it, and the
/// only thing that consumes it is `deployToNetworks`, on a fork, under an RPC
/// this suite does not have.
contract RegistryDeploySuitesTest is RegistryDeploySuites, Test {
    /// PROPERTY: neither registry declares a deploy-time dependency.
    ///
    /// A dependency is an address that MUST already have code on a network
    /// before the suite is broadcast there, and both of these contracts are
    /// declared to have none: `AddressRegistry` reads nothing and calls nothing
    /// at construction, and `MigrationRegistry` takes no constructor argument
    /// and resolves its namespace from `msg.sender` at call time. Neither can
    /// therefore be broken by what is or is not on chain when it lands, which
    /// is why both are deployable to a network the day that network is added.
    ///
    /// A dependency that is not really one is not inert. `deployToNetworks`
    /// refuses to broadcast on any network where a declared dependency has no
    /// code, so an entry added here takes both registries off every new chain
    /// until something nobody needs is deployed there first — and it fails at
    /// dispatch, per network, after the fork, where nothing in this suite is
    /// watching.
    function testCandidatesDeclareNoDependencies() external pure {
        DeployCandidate[] memory candidates = checkedCandidateSuites();
        for (uint256 i = 0; i < candidates.length; i++) {
            assertEq(
                candidates[i].snapshot.dependencies.length,
                0,
                string.concat("candidate declares a dependency: ", candidates[i].snapshot.suite)
            );
        }
    }
}
