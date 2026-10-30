// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IDescribedByMetaV1} from "rain-metadata-0.1.43/src/interface/IDescribedByMetaV1.sol";

/// @title MockDescribedByMeta
/// @notice Answers `describedByMetaV1()` with the hash it was constructed with. Held in storage, not an immutable, so
/// every instance shares one runtime code.
contract MockDescribedByMeta is IDescribedByMetaV1 {
    bytes32 internal sDescribedByMetaHash;

    /// @param describedByMetaHash The hash to answer with.
    constructor(bytes32 describedByMetaHash) {
        sDescribedByMetaHash = describedByMetaHash;
    }

    /// @inheritdoc IDescribedByMetaV1
    function describedByMetaV1() external view returns (bytes32) {
        return sDescribedByMetaHash;
    }
}
