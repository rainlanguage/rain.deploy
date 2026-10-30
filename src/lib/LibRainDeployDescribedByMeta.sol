// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IDescribedByMetaV1} from "rain-metadata-0.1.43/src/interface/IDescribedByMetaV1.sol";
import {IMetaBoardV1_2} from "rain-metadata-0.1.43/src/interface/unstable/IMetaBoardV1_2.sol";
import {IMetaV1_2} from "rain-metadata-0.1.43/src/interface/unstable/IMetaV1_2.sol";

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

/// @notice The block a declaration names as a suite's described-by meta emission on a chain MUST hold that emission
/// on the metaboard.
/// @param suite The suite.
/// @param chainId The chain.
/// @param blockNumber The declared emission block.
error DescribedByMetaNotEmittedAt(string suite, uint256 chainId, uint256 blockNumber);

/// @notice A suite carrying a described-by meta MUST have its emission block declared for every chain it is checked
/// on.
/// @param network The network.
/// @param suite The suite.
/// @param chainId The chain.
error DescribedByMetaEmissionUndeclared(string network, string suite, uint256 chainId);

/// @title LibRainDeployDescribedByMeta
/// @notice A suite's described-by meta on the metaboard: the emission `RainDeployBroadcast` makes, and the one-block
/// lookup at its declared emission block that the broadcast and the chain group make.
library LibRainDeployDescribedByMeta {
    /// Whether block `blockNumber` of the selected fork's chain holds a `MetaV1_2` on `metaBoard` about `described`
    /// carrying exactly `meta`, from any sender.
    /// @param vm The Vm instance to read logs with.
    /// @param metaBoard The metaboard.
    /// @param blockNumber The block to read.
    /// @param described The subject.
    /// @param meta The meta.
    /// @return True if the block holds the emission.
    function isEmittedAt(Vm vm, address metaBoard, uint256 blockNumber, address described, bytes memory meta)
        internal
        view
        returns (bool)
    {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = IMetaV1_2.MetaV1_2.selector;
        Vm.EthGetLogs[] memory logs = vm.eth_getLogs(blockNumber, blockNumber, metaBoard, topics);
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

    /// On the selected fork, for a non-empty `meta`: with an emission block declared, refuses
    /// `DescribedByMetaNotEmittedAt` unless that block holds the emission; with none declared, broadcasts `meta` about
    /// `described` on `metaBoard` as `deployer` once `checkDescribes` holds, and logs what to declare.
    /// @param vm The Vm instance to read logs and broadcast with.
    /// @param suite The suite.
    /// @param network The network, for the refusal and the log.
    /// @param chainId The chain.
    /// @param metaBoard The metaboard.
    /// @param declared Whether an emission block is declared for the suite on the chain.
    /// @param blockNumber The declared emission block.
    /// @param described The deployment the meta describes.
    /// @param meta The described-by meta.
    /// @param deployer The address to broadcast as.
    function emitUnlessDeclared(
        Vm vm,
        string memory suite,
        string memory network,
        uint256 chainId,
        address metaBoard,
        bool declared,
        uint256 blockNumber,
        address described,
        bytes memory meta,
        address deployer
    ) internal {
        if (meta.length == 0) {
            return;
        }
        checkMetaBoardDeployed(network, metaBoard);
        if (declared) {
            if (!isEmittedAt(vm, metaBoard, blockNumber, described, meta)) {
                revert DescribedByMetaNotEmittedAt(suite, chainId, blockNumber);
            }
            console2.log(" - Described-by meta emitted at its declared block, skipping:", network, blockNumber);
            return;
        }
        checkDescribes(suite, described, meta);
        console2.log(" - Emitting described-by meta:", network);
        vm.startBroadcast(deployer);
        IMetaBoardV1_2(metaBoard).emitMeta(bytes32(uint256(uint160(described))), meta);
        vm.stopBroadcast();
        console2.log(" - Declare the emitMeta receipt's blockNumber as the emission block of suite on chain id:");
        console2.log(suite, chainId);
    }

    /// For a non-empty `meta`, refuses `DescribedByMetaEmissionUndeclared` when no emission block is declared,
    /// `MetaBoardNotDeployed` when the selected fork has no metaboard, and `DescribedByMetaNotEmittedAt` when the
    /// declared block holds no emission of `meta` about `described`.
    /// @param vm The Vm instance to read logs with.
    /// @param network The network, for the refusal.
    /// @param suite The suite, for the refusal.
    /// @param chainId The chain.
    /// @param metaBoard The metaboard.
    /// @param declared Whether an emission block is declared for the suite on the chain.
    /// @param blockNumber The declared emission block.
    /// @param described The suite's address on the network.
    /// @param meta The described-by meta.
    function checkEmittedAt(
        Vm vm,
        string memory network,
        string memory suite,
        uint256 chainId,
        address metaBoard,
        bool declared,
        uint256 blockNumber,
        address described,
        bytes memory meta
    ) internal view {
        if (meta.length == 0) {
            return;
        }
        if (!declared) {
            revert DescribedByMetaEmissionUndeclared(network, suite, chainId);
        }
        checkMetaBoardDeployed(network, metaBoard);
        if (!isEmittedAt(vm, metaBoard, blockNumber, described, meta)) {
            revert DescribedByMetaNotEmittedAt(suite, chainId, blockNumber);
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
        bool answered = success && answer.length >= 0x20;
        bytes32 describedByMetaHash = answered ? abi.decode(answer, (bytes32)) : bytes32(0);
        return (answered, describedByMetaHash);
    }
}
