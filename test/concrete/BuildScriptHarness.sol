// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../../src/abstract/BuildScript.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";

/// @title BuildScriptHarness
/// @notice A `BuildScript` whose hooks write markers into a fixture record
/// instead of real generated sources, so `run()` and `cutRelease()` can be
/// called and what each one wrote — and what the record held when it wrote it —
/// read back.
///
/// The markers are comment-only `.sol` files, because a failing test leaves its
/// fixture behind and `forge test` compiles everything under `test/`.
contract BuildScriptHarness is BuildScript {
    /// The fixture record root. Empty defers to `BuildScript`'s own.
    string internal sRoot;

    /// The single contract this fixture release freezes.
    string internal sContractName;

    /// @param root The fixture record root, or empty for `BuildScript`'s own.
    /// @param contractName The contract the fixture snapshot describes.
    constructor(string memory root, string memory contractName) {
        sRoot = root;
        sContractName = contractName;
    }

    /// @inheritdoc BuildScript
    function recordRoot() internal view override returns (string memory) {
        return bytes(sRoot).length > 0 ? sRoot : super.recordRoot();
    }

    /// The root a release cut from this harness is frozen into.
    /// @return The record root.
    function externalRecordRoot() external view returns (string memory) {
        return recordRoot();
    }

    /// Where `regenerateSnapshots` writes.
    /// @return The rolling snapshot path.
    function rollingPath() public view returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(recordRoot(), LibRainDeploySnapshot.CANDIDATE, sContractName);
    }

    /// Where the release freezes that snapshot to.
    /// @return The frozen snapshot path.
    function frozenPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(recordRoot(), LibRainDeploySnapshot.deployTag(vm), sContractName);
    }

    /// Where `regenerateLibs` writes. Directly under the root, so the record
    /// walk — which reads tag directories — never sees it.
    /// @return The lib marker path.
    function libsPath() public view returns (string memory) {
        return string.concat(recordRoot(), "/libs.sol");
    }

    /// A fixture file's content.
    /// @param body What distinguishes this marker from the others.
    /// @return The marker.
    function marker(string memory body) public pure returns (string memory) {
        // Split so `reuse lint` reads this as a fixture rather than as this
        // file's own license declaration.
        return string.concat("// SPDX-License", "-Identifier: LicenseRef-DCL-1.0\n// ", body, "\n");
    }

    /// What `regenerateSnapshots` writes over whatever was there.
    /// @return The regenerated rolling snapshot.
    function regeneratedSnapshot() external pure returns (string memory) {
        return marker("regenerated");
    }

    /// What `regenerateLibs` writes: the record it could see, and whether the
    /// rolling snapshot had been regenerated, at the moment it ran.
    /// @param frozenCount Frozen record files visible to it.
    /// @param rollingExists Whether the rolling snapshot existed.
    /// @return The lib marker.
    function libsMarker(uint256 frozenCount, bool rollingExists) public pure returns (string memory) {
        return
            marker(
                string.concat("frozen ", vm.toString(frozenCount), " rolling ", rollingExists ? "present" : "absent")
            );
    }

    /// @inheritdoc BuildScript
    function snapshotContractNames() internal view override returns (string[] memory contractNames) {
        contractNames = new string[](1);
        contractNames[0] = sContractName;
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {
        writeFixture(rollingPath(), marker("regenerated"));
    }

    /// @inheritdoc BuildScript
    function regenerateLibs() internal override {
        writeFixture(
            libsPath(),
            libsMarker(LibRainDeploySnapshot.frozenSnapshotPaths(vm, recordRoot()).length, vm.exists(rollingPath()))
        );
    }

    /// Writes a marker, creating the directories above it.
    /// @param path The file to write.
    /// @param content The marker to write there.
    function writeFixture(string memory path, string memory content) internal {
        string[] memory components = vm.split(path, "/");
        string memory dir = components[0];
        for (uint256 i = 1; i < components.length - 1; i++) {
            dir = string.concat(dir, "/", components[i]);
        }
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(dir, true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, content);
    }
}
