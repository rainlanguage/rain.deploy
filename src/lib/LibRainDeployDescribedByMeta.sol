// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IDescribedByMetaV1} from "rain-metadata-0.1.43/src/interface/IDescribedByMetaV1.sol";
import {IMetaBoardV1_2} from "rain-metadata-0.1.43/src/interface/unstable/IMetaBoardV1_2.sol";
import {IMetaV1_2} from "rain-metadata-0.1.43/src/interface/unstable/IMetaV1_2.sol";
import {LibDescribedByMeta} from "rain-metadata-0.1.43/src/lib/LibDescribedByMeta.sol";

/// @notice A suite carrying a described-by meta MUST be declared with a `metaBoard()`.
/// @param suite The suite.
error MetaBoardUndeclared(string suite);

/// @notice The declared `metaBoard()` MUST have code on every network a suite carrying a described-by meta is
/// broadcast to or checked on.
/// @param network The network.
/// @param metaBoard The declared metaboard.
error MetaBoardNotDeployed(string network, address metaBoard);

/// @notice A suite's deployment MUST answer `describedByMetaV1()` with the hash of the meta the suite carries.
/// @param suite The suite.
/// @param described Where the suite's mechanism deployed it locally.
/// @param answered Whether `describedByMetaV1()` returned a word.
/// @param describedByMetaHash The word it returned, zero when it returned none.
/// @param metaHash The hash of the meta the suite carries.
error DescribedByMetaMismatch(
    string suite, address described, bool answered, bytes32 describedByMetaHash, bytes32 metaHash
);

/// @notice The metaboard MUST hold an emission of a suite's described-by meta about its deployment on every network
/// the suite is required on.
/// @param network The network.
/// @param suite The suite.
/// @param described The suite's address on the network.
error DescribedByMetaNotEmitted(string network, string suite, address described);

/// @title LibRainDeployDescribedByMeta
/// @notice A suite's described-by meta on the metaboard: the emission `RainDeployBroadcast` makes, and the lookup that
/// makes it idempotent and that the chain group checks.
library LibRainDeployDescribedByMeta {
    /// Whether the selected fork's metaboard holds a `MetaV1_2` about `described` carrying exactly `meta`, from any
    /// sender, at any block up to the fork's. Reads the fork's endpoint, so emissions made on the fork since it was
    /// created are not seen.
    /// @param vm The Vm instance to read logs with.
    /// @param metaBoard The metaboard.
    /// @param described The subject.
    /// @param meta The meta.
    /// @return True if the metaboard holds the emission.
    function isEmitted(Vm vm, address metaBoard, address described, bytes memory meta) internal view returns (bool) {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = IMetaV1_2.MetaV1_2.selector;
        Vm.EthGetLogs[] memory logs = vm.eth_getLogs(0, block.number, metaBoard, topics);
        bytes32 subject = bytes32(uint256(uint160(described)));
        bytes32 metaHash = keccak256(meta);
        for (uint256 i = 0; i < logs.length; i++) {
            (, bytes32 loggedSubject, bytes memory loggedMeta) = abi.decode(logs[i].data, (address, bytes32, bytes));
            if (loggedSubject == subject && keccak256(loggedMeta) == metaHash) {
                return true;
            }
        }
        return false;
    }

    /// Refuses `MetaBoardNotDeployed` when the selected fork has no code at `metaBoard`.
    /// @param network The network, for the refusal.
    /// @param metaBoard The metaboard.
    function checkMetaBoardDeployed(string memory network, address metaBoard) internal view {
        if (metaBoard.code.length == 0) {
            revert MetaBoardNotDeployed(network, metaBoard);
        }
    }

    /// On the selected fork, broadcasts `meta` about `described` on `metaBoard` as `deployer`, through
    /// `LibDescribedByMeta.emitForDescribedAddress`, unless the metaboard already holds that emission. Nothing for an
    /// empty `meta`.
    /// @param vm The Vm instance to read logs and broadcast with.
    /// @param network The network, for the refusal and the log.
    /// @param metaBoard The metaboard.
    /// @param described The deployment the meta describes.
    /// @param meta The described-by meta.
    /// @param deployer The address to broadcast as.
    function emitUnlessEmitted(
        Vm vm,
        string memory network,
        address metaBoard,
        address described,
        bytes memory meta,
        address deployer
    ) internal {
        if (meta.length == 0) {
            return;
        }
        checkMetaBoardDeployed(network, metaBoard);
        if (isEmitted(vm, metaBoard, described, meta)) {
            console2.log(" - Described-by meta already emitted, skipping:", network);
            return;
        }
        console2.log(" - Emitting described-by meta:", network);
        vm.startBroadcast(deployer);
        LibDescribedByMeta.emitForDescribedAddress(IMetaBoardV1_2(metaBoard), IDescribedByMetaV1(described), meta);
        vm.stopBroadcast();
    }

    /// Refuses `DescribedByMetaNotEmitted` when the selected fork's metaboard holds no emission of a non-empty `meta`
    /// about `described`, and `MetaBoardNotDeployed` when it has no metaboard.
    /// @param vm The Vm instance to read logs with.
    /// @param network The network, for the refusal.
    /// @param suite The suite, for the refusal.
    /// @param metaBoard The metaboard.
    /// @param described The suite's address on the network.
    /// @param meta The described-by meta.
    function checkEmitted(
        Vm vm,
        string memory network,
        string memory suite,
        address metaBoard,
        address described,
        bytes memory meta
    ) internal view {
        if (meta.length == 0) {
            return;
        }
        checkMetaBoardDeployed(network, metaBoard);
        if (!isEmitted(vm, metaBoard, described, meta)) {
            revert DescribedByMetaNotEmitted(network, suite, described);
        }
    }

    /// Refuses `DescribedByMetaMismatch` when `described` does not answer `describedByMetaV1()` with the hash of a
    /// non-empty `meta`.
    /// @param suite The suite, for the refusal.
    /// @param described The suite's deployment.
    /// @param meta The described-by meta.
    function checkDescribes(string memory suite, address described, bytes memory meta) internal view {
        if (meta.length == 0) {
            return;
        }
        (bool answered, bytes32 describedByMetaHash) = describedByMetaHashOf(described);
        if (!answered || describedByMetaHash != keccak256(meta)) {
            revert DescribedByMetaMismatch(suite, described, answered, describedByMetaHash, keccak256(meta));
        }
    }

    /// What `described` answers `describedByMetaV1()` with.
    /// @param described The deployment.
    /// @return Whether it answered a word.
    /// @return The word, zero when it answered none.
    function describedByMetaHashOf(address described) internal view returns (bool, bytes32) {
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory answer) =
            described.staticcall(abi.encodeCall(IDescribedByMetaV1.describedByMetaV1, ()));
        if (!success || answer.length < 0x20) {
            return (false, bytes32(0));
        }
        return (true, abi.decode(answer, (bytes32)));
    }
}
