// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration, DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {MOCK_CREATE2_MECHANISM_ID} from "../lib/LibMockCreate2Mechanism.sol";
import {MockCreate2Deploy} from "./MockCreate2Deploy.sol";

/// @title UnrecordedMockCreate2Deploy
/// @notice `MockCreate2Deploy` whose mock mechanism derives every network it has data for and records none.
contract UnrecordedMockCreate2Deploy is MockCreate2Deploy {
    function recordsNothing(DeployDeclaration memory, DeploySuite memory, uint256)
        internal
        pure
        returns (bool, address)
    {
        // forge-lint: disable-next-line(boolean-cst)
        return (false, address(0));
    }

    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d = super.declaration();
        for (uint256 i = 0; i < d.mechanisms.length; i++) {
            if (d.mechanisms[i].id == MOCK_CREATE2_MECHANISM_ID) {
                d.mechanisms[i].recordedAddress = recordsNothing;
            }
        }
        return d;
    }
}
