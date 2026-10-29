// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IMetaBoardV1_2} from "rain-metadata-0.1.43/src/interface/unstable/IMetaBoardV1_2.sol";

struct RecordedMetaEmission {
    uint256 chainId;
    address sender;
    bytes32 subject;
    bytes meta;
}

contract RecordingMetaBoard is IMetaBoardV1_2 {
    RecordedMetaEmission[] internal sEmissions;

    function emitMeta(bytes32 subject, bytes calldata meta) external {
        sEmissions.push(
            RecordedMetaEmission({chainId: block.chainid, sender: msg.sender, subject: subject, meta: meta})
        );
        emit MetaV1_2(msg.sender, subject, meta);
    }

    function emissions() external view returns (RecordedMetaEmission[] memory) {
        return sEmissions;
    }
}
