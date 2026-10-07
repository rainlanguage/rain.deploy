// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {ICloneableFactoryV3} from "rain-factory-0.1.30/src/interface/deprecated/ICloneableFactoryV3.sol";
import {LibICloneableFactoryV4} from "rain-factory-0.1.30/src/lib/LibICloneableFactoryV4.sol";

/// @title MockCloneFactory
/// @notice A real `ICloneableFactoryV4`, not a stub: every entry point is one
/// delegation into `LibICloneableFactoryV4`, which is the whole of a factory's
/// logic and the same library `LibRainDeployClone` derives against.
///
/// `rain-factory` 0.1.30 publishes the interfaces and that library and NO
/// concrete factory — the deployed one is pinned in `rain-factory-deploy`, which
/// depends on this package — so a test here has to supply the factory, and this
/// is the same one-delegation-per-entry-point shape the published concrete has.
///
/// Being real rather than stubbed is what makes the derivation tests mean
/// anything. `LibRainDeployClone.cloneDeployedAddress` predicts where a clone
/// lands; a stub returning a canned address would agree with any prediction,
/// including a wrong one. This factory actually `CREATE2`s the EIP-1167 proxy, so
/// the address a test compares against is one the EVM produced.
contract MockCloneFactory is ICloneableFactoryV4 {
    /// @inheritdoc ICloneableFactoryV4
    function cloneDeterministicOpenSalt(address implementation, bytes calldata data, bytes32 salt)
        external
        returns (address)
    {
        return LibICloneableFactoryV4.cloneDeterministicOpenSalt(implementation, data, salt);
    }

    /// @inheritdoc ICloneableFactoryV4
    function predictDeterministicAddressOpenSalt(address implementation, bytes calldata data, bytes32 salt)
        external
        view
        returns (address)
    {
        return LibICloneableFactoryV4.predictDeterministicAddressOpenSalt(implementation, data, salt);
    }

    /// @inheritdoc ICloneableFactoryV3
    /// @dev The inherited NAMESPACED pair. Carried because the interface declares
    /// it and a factory that reverted here would not be an
    /// `ICloneableFactoryV4` — and because its presence is the premise of the
    /// disjointness `ICloneableFactoryV4` argues for, so a factory under test
    /// that lacked it could not exhibit the hazard the open salt is chosen over.
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
