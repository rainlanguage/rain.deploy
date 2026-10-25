// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

// `MockDeployable`'s Zoltu address.
address constant MOCK_DEPLOYABLE_ADDRESS = 0x7DA611e4146dCf0107407Bb331599acC53E8B62c;

// An external deployment with a leading zero byte, so solc pushes it narrower than 20 bytes.
address constant MOCK_EXTERNAL_ADDRESS = 0x00C0fFeE0000000000000000000000000000C0dE;

contract MockReachingDeployable {
    function reached() external pure returns (address, address) {
        return (MOCK_DEPLOYABLE_ADDRESS, MOCK_EXTERNAL_ADDRESS);
    }
}
