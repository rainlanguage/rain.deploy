// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {META_MAGIC_NUMBER_V1} from "rain-metadata-0.1.43/src/interface/unstable/IMetaV1_2.sol";

/// @dev `body` behind the rain meta magic number, so the registries accept it.
/// @param body Anything.
/// @return The rain metadata.
function rainMeta(bytes memory body) pure returns (bytes memory) {
    return abi.encodePacked(META_MAGIC_NUMBER_V1, body);
}

/// @dev Whether `meta` is non-empty and does not start with the rain meta magic
/// number, compared byte by byte.
/// @param meta Anything.
/// @return True if the registries must refuse `meta`.
function isNotRainMeta(bytes memory meta) pure returns (bool) {
    if (meta.length == 0) return false;
    if (meta.length < 8) return true;
    bytes8 magic = bytes8(META_MAGIC_NUMBER_V1);
    for (uint256 i = 0; i < 8; i++) {
        if (meta[i] != magic[i]) return true;
    }
    return false;
}
