// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration, DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {MockCreate2Deploy} from "./MockCreate2Deploy.sol";

/// `broadcastSuite` over a suite the caller still holds.
contract CallerHeldMockBroadcast is MockCreate2Deploy {
    /// @return The hashes of the caller's suite and declaration before, then after, the broadcast.
    function broadcastRelease(string[] memory networks, uint256 key)
        external
        returns (bytes32, bytes32, bytes32, bytes32)
    {
        DeployDeclaration memory d = declaration();
        DeploySuite memory suite = mockRelease();
        bytes32 suiteBefore = keccak256(abi.encode(suite));
        bytes32 declarationBefore = keccak256(abi.encode(d.released, d.candidates, d.networks));
        broadcastSuite(d, suite, networks, key);
        return (
            suiteBefore,
            keccak256(abi.encode(suite)),
            declarationBefore,
            keccak256(abi.encode(d.released, d.candidates, d.networks))
        );
    }
}
