// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The codeless address the mock mechanisms report their side-effect-free hooks to, so tests count them with
/// `vm.expectCall(MOCK_MECHANISM_PROBE, abi.encodeCall(IMockMechanismProbe.<hook>, (...)), count)`.
address constant MOCK_MECHANISM_PROBE = address(uint160(uint256(keccak256("rain.deploy.mock.mechanism.probe"))));

interface IMockMechanismProbe {
    function checkOnChain(bytes32 mechanismId, string memory suite, string memory network, uint256 chainId, address deployed)
        external
        view;

    function addRecordedNetworks(bytes32 mechanismId, string memory suite) external view;
}

/// @title LibMockMechanismProbe
library LibMockMechanismProbe {
    function checkOnChain(bytes32 mechanismId, string memory suite, string memory network, uint256 chainId, address deployed)
        internal
        view
    {
        probe(abi.encodeCall(IMockMechanismProbe.checkOnChain, (mechanismId, suite, network, chainId, deployed)));
    }

    function addRecordedNetworks(bytes32 mechanismId, string memory suite) internal view {
        probe(abi.encodeCall(IMockMechanismProbe.addRecordedNetworks, (mechanismId, suite)));
    }

    function probe(bytes memory data) private view {
        (bool success, bytes memory returned) = MOCK_MECHANISM_PROBE.staticcall(data);
        // A test makes a hook refuse with `vm.mockCallRevert` on the probe.
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returned, 0x20), mload(returned))
            }
        }
    }
}
