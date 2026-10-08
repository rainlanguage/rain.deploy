// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {ICloneableFactoryV3} from "rain-factory-0.1.30/src/interface/deprecated/ICloneableFactoryV3.sol";
import {LibICloneableFactoryV4} from "rain-factory-0.1.30/src/lib/LibICloneableFactoryV4.sol";

/// @title MockUncloneableMispredictingCloneFactory
/// @notice `MockMispredictingCloneFactory` with its clone path shut: the
/// prediction is one address high, and cloning reverts rather than cloning.
///
/// Both at once, because together they are the only thing that makes the ORDER of
/// `LibRainDeployClone.cloneDeployStep` observable. A clone a step deployed
/// before refusing the prediction is rolled back WITH the refusal — the call
/// reverts, so no assertion afterwards can see the code it left behind, and
/// `code.length == 0` is true whether the guard ran first or last. A factory that
/// cannot clone turns that invisible side effect into a DIFFERENT error: reaching
/// the broadcast window answers `CloneWasReached`, so
/// `CloneFactoryPredictionMismatch` coming back instead is proof the guard ran
/// before it.
///
/// This does not replace `MockMispredictingCloneFactory`, for that mock's own
/// reason: a factory that cannot deploy cannot show that what the step refuses is
/// the DISAGREEMENT rather than a broken factory. One mock per claim — that one
/// owns "the prediction is what is refused", this one owns "it is refused before
/// anything is broadcast".
contract MockUncloneableMispredictingCloneFactory is ICloneableFactoryV4 {
    /// Thrown by every clone path, so reaching one is reportable.
    error CloneWasReached();

    /// @inheritdoc ICloneableFactoryV4
    /// @dev Wrong by the smallest representable margin, as the mispredicting mock
    /// is, so this factory is refused for its disagreement and not for its size.
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
    /// @dev Shut, so a step that opens the broadcast window before checking the
    /// prediction says so instead of silently cloning.
    function cloneDeterministicOpenSalt(address, bytes calldata, bytes32) external pure returns (address) {
        revert CloneWasReached();
    }

    /// @inheritdoc ICloneableFactoryV3
    /// @dev Shut for the same reason, because a step reaching the NAMESPACED pair
    /// instead would be the same defect.
    function cloneDeterministic(address, bytes calldata, bytes32) external pure returns (address) {
        revert CloneWasReached();
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
