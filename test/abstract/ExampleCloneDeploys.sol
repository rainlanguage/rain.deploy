// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployCloneSuitesBase} from "../../src/abstract/RainDeployCloneSuitesBase.sol";
import {CloneDeploy} from "../../src/lib/LibRainDeployClone.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockCloneFactory} from "../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../concrete/MockCloneable.sol";

/// The address the Zoltu factory derives for `MockCloneFactory`, which is where a
/// test puts it.
///
/// Derived rather than hard-coded so the fixture cannot drift from the mock, and
/// derived through ZOLTU specifically because that is the only way a clone's
/// factory is at the SAME address on every network — which `ICloneableFactoryV4`
/// names as the precondition for a clone being cross-network deterministic at all.
/// A factory at a nonce-dependent address would put every clone of it somewhere
/// different per chain, so a fixture pretending otherwise would be testing a
/// deploy shape this package cannot actually offer.
///
/// A `pure` FUNCTION and not a constant: a constant initializer has to be a
/// compile-time constant and an internal call is not one. Being pure is what
/// matters, because it keeps `cloneDeploys()` pure — a declaration is current
/// source and names addresses it COMPUTES, never addresses it reads.
/// @return The factory's deterministic address.
function exampleCloneFactory() pure returns (address) {
    return LibRainDeploy.zoltuAddress(type(MockCloneFactory).creationCode);
}

/// The address the Zoltu factory derives for `MockCloneable`, the implementation
/// the example clones delegate into. Zoltu for the same reason the factory is:
/// the implementation's address is embedded in the proxy's runtime code, so it is
/// the second of the two things `ICloneableFactoryV4` requires to match across
/// chains.
/// @return The implementation's deterministic address.
function exampleCloneImplementation() pure returns (address) {
    return LibRainDeploy.zoltuAddress(type(MockCloneable).creationCode);
}

/// @title ExampleCloneDeploys
/// @notice A clone deploy repo's declaration, as the abstracts see it: the clone
/// list and nothing else, with the candidates derived from it by
/// `RainDeployCloneSuitesBase`.
///
/// TWO entries, for the reason `ExampleDeploySuites` carries two: every loop here
/// runs over a list, and proving a loop does not stop at the first entry requires
/// a second entry at a DIFFERENT address. Without one, "the matrix silently
/// checks only the first clone" is undetectable — and that is the failure mode
/// that matters most to the repos this abstract exists for.
///
/// The two differ in salt AND data, and share a factory and an implementation.
/// That split is deliberate: the shared fields are what a clone repo actually
/// looks like — one audited implementation behind one factory — and the varying
/// ones are the two that the OPEN salt digest commits to, so two entries at two
/// addresses is a statement about `effectiveOpenSalt` covering both. A derivation
/// that dropped either would collapse the two onto one address, which
/// `allSuites`' uniqueness check would then refuse rather than let two keys
/// quietly name one clone.
///
/// The init data is EMPTY on the first entry, because
/// `ICloneableFactoryV4.cloneDeterministicOpenSalt` says `data` MAY be empty and
/// `keccak256("")` is a perfectly ordinary word in the salt digest. A derivation
/// that special-cased or skipped empty data would pass a fixture where every
/// entry had some.
abstract contract ExampleCloneDeploys is RainDeployCloneSuitesBase {
    /// @inheritdoc RainDeployCloneSuitesBase
    function cloneDeploys() internal pure override returns (CloneDeploy[] memory clones) {
        clones = new CloneDeploy[](2);
        clones[0] = CloneDeploy({
            suite: "example-clone",
            factory: exampleCloneFactory(),
            implementation: exampleCloneImplementation(),
            data: "",
            salt: bytes32(uint256(1))
        });
        clones[1] = CloneDeploy({
            suite: "example-clone-second-salt",
            factory: exampleCloneFactory(),
            implementation: exampleCloneImplementation(),
            data: hex"abcd",
            salt: bytes32(uint256(2))
        });
    }
}
