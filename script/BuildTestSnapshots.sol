// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {LibRainDeploySnapshot} from "../src/lib/LibRainDeploySnapshot.sol";
import {MockDeployable} from "../test/concrete/MockDeployable.sol";
import {MockDeployableV2} from "../test/concrete/MockDeployableV2.sol";

/// @title BuildTestSnapshots
/// @notice Generates the deploy snapshots the verification abstracts are
/// exercised against, into `test/generated/`.
///
/// Same generator as `script/Build.sol` — both call
/// `LibRainDeploySnapshot.writeSnapshot`, which is parameterised on the
/// declaration and the output root. This is not a helper, not a reference and
/// not hand-maintained: it is the production code path pointed at test
/// contracts, so `GeneratedSnapshotShapeTest`'s assertions describe the same
/// emitter that writes real deploy records.
///
/// `test/` is excluded by `.soldeerignore`, so these never ship in the package —
/// which is the whole reason they are not under `src/generated/`.
///
/// Run as `forge script script/BuildTestSnapshots.sol`.
contract BuildTestSnapshots is Script {
    /// @notice Where test snapshots live.
    string constant TEST_GENERATED_ROOT = "test/generated";

    /// @notice Regenerate every test snapshot. Two contracts, so the abstracts
    /// see two suites at two different addresses — which is what a repo with a
    /// version history actually looks like.
    function run() external {
        LibRainDeploySnapshot.writeSnapshot(
            vm, TEST_GENERATED_ROOT, "0_0_1", "MockDeployable", type(MockDeployable).creationCode
        );
        LibRainDeploySnapshot.writeSnapshot(
            vm, TEST_GENERATED_ROOT, "0_0_2", "MockDeployableV2", type(MockDeployableV2).creationCode
        );
    }
}
