// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeployExtendedNetworks} from "../../src/lib/LibRainDeployExtendedNetworks.sol";

/// @title LibExtendedNetworksFixture
/// @notice Fixture record roots for tests that write extended networks records.
library LibExtendedNetworksFixture {
    /// `<dir>/<label>`, emptied of the record for `suite` an earlier run left there.
    /// @param vm The Vm instance for file operations.
    /// @param dir The directory holding one fixture root per test.
    /// @param label The test's fixture root under `dir`.
    /// @param suite The release's suite key.
    /// @return The root.
    function freshRoot(Vm vm, string memory dir, string memory label, string memory suite)
        internal
        returns (string memory)
    {
        string memory root = string.concat(dir, "/", label);
        (,, string memory path) = LibRainDeployExtendedNetworks.extendedNetworksPath(root, suite);
        if (vm.exists(path)) {
            vm.removeFile(path);
        }
        return root;
    }
}
