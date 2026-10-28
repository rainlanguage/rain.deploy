// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {MockCreate2DeploySuites} from "../abstract/MockCreate2DeploySuites.sol";

contract MockCreate2Deploy is MockCreate2DeploySuites, ExternalDeploySuites, RainDeployBroadcast {
    function externalMockRelease() external pure returns (DeploySuite memory) {
        return mockRelease();
    }

    function externalMockCandidate() external pure returns (DeploySuite memory) {
        return mockCandidate();
    }

    function externalWithExtendedNetworks(DeploySuite memory suite) external view returns (DeploySuite memory) {
        return withExtendedNetworks(suite);
    }

    function externalOnSupportedNetworks(DeploySuite memory frozen, uint256[] memory chainIds)
        external
        view
        returns (DeploySuite memory)
    {
        return onSupportedNetworks(frozen, chainIds);
    }

    function externalDeployAndBroadcast(
        Vm forkVm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        DeploySuite memory frozen,
        DeploySuite memory candidate
    ) external returns (address[] memory, uint256[] memory) {
        return deployAndBroadcast(forkVm, networks, deployerPrivateKey, frozen, candidate);
    }

    function externalCheckSeatsNoDeployKey(DeploySuite memory suite, string[] memory networks, address deployer)
        external
    {
        checkSeatsNoDeployKey(suite, networks, deployer);
    }
}
