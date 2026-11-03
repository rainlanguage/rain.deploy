// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration, DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {SupportedNetwork} from "../../src/lib/LibRainDeploy.sol";
import {MockCreate2Deploy} from "./MockCreate2Deploy.sol";

/// One `preDeployCheck` call, as the hook saw it.
/// @param suite The suite's key.
/// @param network The network's name.
/// @param networkChainId The network's catalogue chain id.
/// @param forkChainId The selected fork's chain id.
/// @param recordedCodeLength The code length at the suite's recorded address on that network.
struct PreDeployCheckCall {
    string suite;
    string network;
    uint256 networkChainId;
    uint256 forkChainId;
    uint256 recordedCodeLength;
}

/// @param network The network refused.
/// @param forkChainId The selected fork's chain id.
error PreDeployCheckRefused(string network, uint256 forkChainId);

/// @title PreDeployCheckRecordingDeploy
/// @notice `MockCreate2Deploy` whose `preDeployCheck` records every call and refuses the network set by `refuseOn`.
contract PreDeployCheckRecordingDeploy is MockCreate2Deploy {
    PreDeployCheckCall[] internal sPreDeployChecks;
    uint256 internal sRefusedChainId;

    function refuseOn(uint256 chainId) external {
        sRefusedChainId = chainId;
    }

    function preDeployChecks() external view returns (PreDeployCheckCall[] memory) {
        return sPreDeployChecks;
    }

    function preDeployCheck(DeployDeclaration memory d, DeploySuite memory suite, SupportedNetwork memory network)
        internal
        override
    {
        if (network.chainId == sRefusedChainId) {
            revert PreDeployCheckRefused(network.name, block.chainid);
        }
        sPreDeployChecks.push(
            PreDeployCheckCall({
                suite: suite.suite,
                network: network.name,
                networkChainId: network.chainId,
                forkChainId: block.chainid,
                recordedCodeLength: recordedAddress(d, suite, network.chainId).code.length
            })
        );
    }
}
