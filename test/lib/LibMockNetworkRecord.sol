// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// One network a per-network mock suite deploys to with its own data, and therefore its own address.
struct MockNetworkDeploy {
    uint256 chainId;
    bytes data;
    address deployedAddress;
}

/// @title LibMockNetworkRecord
/// @notice The test-only record of the networks a per-network mock suite is recorded on beyond its declaration:
/// `<root>/mock-networks/<keccak256(suite)>`, the networks abi-encoded.
library LibMockNetworkRecord {
    function dir(string memory root) internal pure returns (string memory) {
        return string.concat(root, "/mock-networks");
    }

    function path(Vm vm, string memory root, string memory suite) internal pure returns (string memory) {
        return string.concat(dir(root), "/", vm.toString(keccak256(bytes(suite))));
    }

    function write(Vm vm, string memory root, string memory suite, MockNetworkDeploy[] memory networks) internal {
        vm.createDir(dir(root), true);
        vm.writeFileBinary(path(vm, root, suite), abi.encode(networks));
    }

    /// @return The networks recorded for `suite` under `root`, or none when there is no record.
    function read(Vm vm, string memory root, string memory suite) internal view returns (MockNetworkDeploy[] memory) {
        string memory recordPath = path(vm, root, suite);
        if (!vm.exists(recordPath)) {
            return new MockNetworkDeploy[](0);
        }
        return abi.decode(vm.readFileBinary(recordPath), (MockNetworkDeploy[]));
    }
}
