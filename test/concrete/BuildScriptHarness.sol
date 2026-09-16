// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../../src/abstract/BuildScript.sol";
import {LibRainDeployConfig} from "../../src/lib/LibRainDeployConfig.sol";
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

    /// @inheritdoc BuildScript
    /// @dev The fixture root, never the repo's own. A `run()` here would
    /// otherwise read the committed config and stage a spliced copy of it,
    /// which the next `script/build.sh` would install.
    function configRoot() internal view override returns (string memory) {
        return sRoot;
    }

    /// The seeded `foundry.toml` `regenerateConfig` reads.
    /// @return The fixture config path.
    function externalConfigPath() external view returns (string memory) {
        return LibRainDeployConfig.configPath(configRoot());
    }

    /// The seeded `.env.example` `regenerateConfig` reads.
    /// @return The fixture `.env.example` path.
    function externalEnvExamplePath() external view returns (string memory) {
        return LibRainDeployConfig.envExamplePath(configRoot());
    }

    /// Where `regenerateConfig` stages the spliced config.
    /// @return The staged config path.
    function externalStagedConfigPath() external view returns (string memory) {
        return LibRainDeployConfig.stagedPath(configRoot(), LibRainDeployConfig.CONFIG_NAME);
    }

    /// Where `regenerateConfig` stages the spliced `.env.example`.
    /// @return The staged `.env.example` path.
    function externalStagedEnvExamplePath() external view returns (string memory) {
        return LibRainDeployConfig.stagedPath(configRoot(), LibRainDeployConfig.ENV_EXAMPLE_NAME);
    }

    /// The staging directory, so a test can assert whether anything was staged
    /// at all.
    /// @return The staging directory.
    function externalStagedDir() external view returns (string memory) {
        return LibRainDeployConfig.stagedDir(configRoot());
    }

    /// A fixture file carrying both `foundry.toml` blocks, with a stale body in
    /// each and hand-written text around them.
    /// @return The seed config.
    function configSeed() public pure returns (string memory) {
        return string.concat(
            "# hand written\n",
            "# rain-deploy:generated:rpc_endpoints:begin\n",
            "STALE\n",
            "# rain-deploy:generated:rpc_endpoints:end\n",
            "# rain-deploy:generated:etherscan:begin\n",
            "STALE\n",
            "# rain-deploy:generated:etherscan:end\n"
        );
    }

    /// A fixture file carrying the `.env.example` block.
    /// @return The seed `.env.example`.
    function envExampleSeed() public pure returns (string memory) {
        return string.concat(
            "# hand written\n", "# rain-deploy:generated:env:begin\n", "STALE=1\n", "# rain-deploy:generated:env:end\n"
        );
    }

    /// Writes both config fixtures, so `run()` has markers to splice into.
    function seedConfig() external {
        writeFixture(LibRainDeployConfig.configPath(configRoot()), configSeed());
        writeFixture(LibRainDeployConfig.envExamplePath(configRoot()), envExampleSeed());
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
    function regeneratedSnapshot() public pure returns (string memory) {
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
    function snapshotContractNames() internal view override returns (string[] memory) {
        string[] memory contractNames = new string[](1);
        contractNames[0] = sContractName;
        return contractNames;
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {
        writeFixture(rollingPath(), regeneratedSnapshot());
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
