// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {ICloneableFactoryV3} from "rain-factory-0.1.30/src/interface/deprecated/ICloneableFactoryV3.sol";
import {LibICloneableFactoryV4} from "rain-factory-0.1.30/src/lib/LibICloneableFactoryV4.sol";

/// @title MockMispredictingCloneFactory
/// @notice `MockCloneFactory` differing in EXACTLY the one function under test:
/// `predictDeterministicAddressOpenSalt` answers one address higher than the
/// truth. Everything else, the clone included, is the same delegation.
///
/// Off by ONE rather than wildly wrong, deliberately. It is the smallest possible
/// disagreement, so a test using it proves
/// `LibRainDeployClone.cloneDeployStep` compares the two addresses EXACTLY — a
/// guard with any tolerance in it, or one that only checked for a zero or an
/// obviously-bogus answer, would pass a factory this close and still admit a
/// factory whose domain tag or proxy layout differed.
///
/// Differing in one function is the point of a second mock rather than a flag on
/// the first. The clone path still works, so what the test observes is the
/// PREDICTION being refused and not a factory that simply cannot deploy: the
/// refusal has to come from the disagreement, before the broadcast window, which
/// is the whole reason `CloneFactoryPredictionMismatch` exists.
contract MockMispredictingCloneFactory is ICloneableFactoryV4 {
    /// @inheritdoc ICloneableFactoryV4
    /// @dev Deliberately wrong, by the smallest representable margin.
    function predictDeterministicAddressOpenSalt(address implementation, bytes calldata data, bytes32 salt)
        external
        view
        returns (address)
    {
        return address(
            uint160(LibICloneableFactoryV4.predictDeterministicAddressOpenSalt(implementation, data, salt)) + 1
        );
    }

    /// @inheritdoc ICloneableFactoryV4
    /// @dev Honest, so the mismatch is the only thing wrong with this factory.
    function cloneDeterministicOpenSalt(address implementation, bytes calldata data, bytes32 salt)
        external
        returns (address)
    {
        return LibICloneableFactoryV4.cloneDeterministicOpenSalt(implementation, data, salt);
    }

    /// @inheritdoc ICloneableFactoryV3
    function cloneDeterministic(address implementation, bytes calldata data, bytes32 salt) external returns (address) {
        return LibICloneableFactoryV4.cloneDeterministic(implementation, data, salt);
    }

    /// @inheritdoc ICloneableFactoryV3
    function predictDeterministicAddress(address implementation, bytes32 salt, address deployer)
        external
        view
        returns (address)
    {
        return LibICloneableFactoryV4.predictDeterministicAddress(implementation, salt, deployer);
    }
}
