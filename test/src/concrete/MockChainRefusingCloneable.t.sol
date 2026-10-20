// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {ICLONEABLE_V2_SUCCESS} from "rain-factory-pr271-4379965/src/interface/ICloneableV2.sol";
import {
    MockChainRefusingCloneable,
    MockChainRefusingCloneableRefusedChain
} from "../../concrete/MockChainRefusingCloneable.sol";

/// @title MockChainRefusingCloneableTest
/// @notice `MockChainRefusingCloneable` initializes under every chain id but the one its init data names.
contract MockChainRefusingCloneableTest is Test {
    function testInitializeRefusesTheNamedChain(uint64 chainId) external {
        MockChainRefusingCloneable cloneable = new MockChainRefusingCloneable();
        vm.chainId(chainId);
        vm.expectRevert(abi.encodeWithSelector(MockChainRefusingCloneableRefusedChain.selector, uint256(chainId)));
        cloneable.initialize(abi.encode(uint256(chainId)));
    }

    function testInitializeSucceedsUnderAnotherChain(uint64 chainId, uint256 refused) external {
        vm.assume(refused != chainId);
        MockChainRefusingCloneable cloneable = new MockChainRefusingCloneable();
        vm.chainId(chainId);
        assertEq(cloneable.initialize(abi.encode(refused)), ICLONEABLE_V2_SUCCESS);
    }

    function testOwnerIsNobody() external {
        assertEq(new MockChainRefusingCloneable().owner(), address(0));
    }
}
