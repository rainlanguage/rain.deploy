// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The codeless address the mock mechanisms report their side-effect-free hooks to, so tests count them with
/// `vm.expectCall(MOCK_MECHANISM_PROBE, abi.encodeCall(IMockMechanismProbe.<hook>, (...)), count)`.
address constant MOCK_MECHANISM_PROBE = address(uint160(uint256(keccak256("rain.deploy.mock.mechanism.probe"))));

interface IMockMechanismProbe {
    function checkOnChain(
        bytes32 mechanismId,
        string memory suite,
        string memory network,
        uint256 chainId,
        address deployed
    ) external view;

    function addRecordedNetworks(bytes32 mechanismId, string memory suite) external view;

    function checkDeclaration(bytes32 mechanismId) external view;

    function declaredConfig(bytes32 mechanismId, bytes memory config) external view;

    function checkNetwork(bytes32 mechanismId, string memory network, uint256 chainId, uint256 forkChainId)
        external
        view;

    function legacyRecordId(bytes32 mechanismId, string memory path) external view returns (bytes32);

    function checkNetworks(bytes32 mechanismId, uint256[] memory chainIds) external view returns (uint256[] memory);
}

/// @title LibMockMechanismProbe
library LibMockMechanismProbe {
    function checkOnChain(
        bytes32 mechanismId,
        string memory suite,
        string memory network,
        uint256 chainId,
        address deployed
    ) internal view {
        probe(abi.encodeCall(IMockMechanismProbe.checkOnChain, (mechanismId, suite, network, chainId, deployed)));
    }

    function addRecordedNetworks(bytes32 mechanismId, string memory suite) internal view {
        probe(abi.encodeCall(IMockMechanismProbe.addRecordedNetworks, (mechanismId, suite)));
    }

    function checkDeclaration(bytes32 mechanismId) internal view {
        probe(abi.encodeCall(IMockMechanismProbe.checkDeclaration, (mechanismId)));
    }

    /// Reports `block.chainid` beside `chainId` so a test pins which fork the hook ran on.
    function checkNetwork(bytes32 mechanismId, string memory network, uint256 chainId) internal view {
        probe(abi.encodeCall(IMockMechanismProbe.checkNetwork, (mechanismId, network, chainId, block.chainid)));
    }

    function declaredConfig(bytes32 mechanismId, bytes memory config) internal view {
        probe(abi.encodeCall(IMockMechanismProbe.declaredConfig, (mechanismId, config)));
    }

    /// @return The probe's answer, 0 until a test sets one with `vm.mockCall`.
    function legacyRecordId(bytes32 mechanismId, string memory path) internal view returns (bytes32) {
        bytes memory returned = probe(abi.encodeCall(IMockMechanismProbe.legacyRecordId, (mechanismId, path)));
        return returned.length == 0 ? bytes32(0) : abi.decode(returned, (bytes32));
    }

    /// @return The probe's answer, no chain ids until a test sets some with `vm.mockCall`.
    function checkNetworks(bytes32 mechanismId, uint256[] memory chainIds) internal view returns (uint256[] memory) {
        bytes memory returned = probe(abi.encodeCall(IMockMechanismProbe.checkNetworks, (mechanismId, chainIds)));
        return returned.length == 0 ? new uint256[](0) : abi.decode(returned, (uint256[]));
    }

    function probe(bytes memory data) private view returns (bytes memory) {
        (bool success, bytes memory returned) = MOCK_MECHANISM_PROBE.staticcall(data);
        // A test makes a hook refuse with `vm.mockCallRevert` on the probe.
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returned, 0x20), mload(returned))
            }
        }
        return returned;
    }
}
