// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockCreate2Factory
/// @notice CREATE2 factory for the test-only mechanism in `MockCreate2DeploySuites`.
contract MockCreate2Factory {
    error MockCreate2Failed(bytes32 salt);

    /// @param salt The CREATE2 salt.
    /// @param creationCode The creation code.
    /// @return Where it landed.
    function deploy(bytes32 salt, bytes memory creationCode) external returns (address) {
        address deployed;
        assembly ("memory-safe") {
            deployed := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
        }
        if (deployed == address(0)) {
            revert MockCreate2Failed(salt);
        }
        return deployed;
    }
}
