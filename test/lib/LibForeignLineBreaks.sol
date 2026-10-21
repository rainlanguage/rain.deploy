// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibForeignLineBreaks
/// @notice The line breaks solc honours other than `\n`, which every record reader refuses.
library LibForeignLineBreaks {
    /// Carriage return, vertical tab, form feed, NEL, LS and PS.
    /// @return The six breaks.
    function foreignLineBreaks() internal pure returns (string[] memory) {
        string[] memory breaks = new string[](6);
        breaks[0] = "\r";
        breaks[1] = "\x0b";
        breaks[2] = "\x0c";
        breaks[3] = "\xc2\x85";
        breaks[4] = "\xe2\x80\xa8";
        breaks[5] = "\xe2\x80\xa9";
        return breaks;
    }
}
