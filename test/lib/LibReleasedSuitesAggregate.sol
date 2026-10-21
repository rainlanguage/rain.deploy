// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// @title LibReleasedSuitesAggregate
/// @notice Reading a generated released-suites aggregate back: which contracts
/// the committed file actually declares.
///
/// The aggregate is the one generated file whose CONTENT is nothing but a list
/// of contracts — every release it declares comes from the per-contract libs it
/// imports, so the imports are the whole of what it says. Two assertions are
/// about that list and they are about different halves of it: that the file is
/// what the generator makes of the contracts it names, and that those are the
/// contracts this repo generates. Both need the list read off the file rather
/// than restated, because a list restated in a test is another place a contract
/// has to be added to — which is the defect the aggregate exists to remove.
library LibReleasedSuitesAggregate {
    /// The contracts an emitted aggregate declares, in the order it imports
    /// them.
    ///
    /// Split on the sibling-import close rather than parsed, because the text
    /// is generated: `aggregateImportBlock` emits exactly
    /// `import {Lib<Contract>Released} from "./...` on a line of its own, one
    /// per contract, and no other import in the file is a sibling `Released`
    /// lib. The name is what follows the last `import {Lib` before each close.
    /// @param vm The Vm instance for string operations.
    /// @param source An emitted aggregate.
    /// @return The contract names, in the order imported.
    function declaredContractNames(Vm vm, string memory source) internal pure returns (string[] memory) {
        string[] memory chunks = vm.split(source, "Released} from \"./");

        string[] memory names = new string[](chunks.length - 1);
        for (uint256 i = 0; i < names.length; i++) {
            string[] memory opens = vm.split(chunks[i], "\nimport {Lib");
            names[i] = opens[opens.length - 1];
        }
        return names;
    }
}
