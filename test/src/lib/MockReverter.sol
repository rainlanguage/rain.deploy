// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title MockReverter
/// Contract whose constructor always reverts, used to test DeployFailed with
/// success=false.
contract MockReverter {
    constructor() {
        revert();
    }
}
