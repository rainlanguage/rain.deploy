// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    ApproveRegistryDelegateWiringTest,
    ILocalApproveRegistryDelegate
} from "../abstract/ApproveRegistryDelegateWiringTest.sol";
import {LibConfigRegistryDeploy} from "../../src/lib/LibConfigRegistryDeploy.sol";
import {LibConfigRegistryFork} from "../lib/LibConfigRegistryFork.sol";
import {LocalApproveConfigDelegate} from "../concrete/LocalApproveConfigDelegate.sol";

/// @title ApproveConfigDelegateTest
/// `ApproveRegistryDelegateWiringTest` on `ApproveConfigDelegate`.
contract ApproveConfigDelegateTest is ApproveRegistryDelegateWiringTest {
    function newScript() internal override returns (ILocalApproveRegistryDelegate) {
        return ILocalApproveRegistryDelegate(address(new LocalApproveConfigDelegate()));
    }

    function prefix() internal pure override returns (string memory) {
        return "CONFIG_DELEGATE";
    }

    function pinned() internal pure override returns (address, bytes32) {
        return (
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH
        );
    }

    function deployRegistry() internal override {
        LibConfigRegistryFork.ensureDeployed(vm);
    }
}
