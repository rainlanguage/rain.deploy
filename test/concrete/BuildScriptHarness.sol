// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {BuildScript, GeneratedContract} from "../../src/abstract/BuildScript.sol";
import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployConfig} from "../../src/lib/LibRainDeployConfig.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";

/// @dev The contract the harness's one candidate snapshots.
string constant BUILD_SCRIPT_HARNESS_CONTRACT = "MockDeployableV2";

/// @dev The harness's one candidate's key.
string constant BUILD_SCRIPT_HARNESS_SUITE = "harness-candidate";

/// @title BuildScriptHarness
/// @notice A `BuildScript` over a fixture record root with one candidate, so
/// `run()` and `cutRelease()` can be called and what each one wrote read back.
/// Its libs go under `fixture-lib/`, which nothing compiles; the test that runs
/// it creates and removes that directory.
contract BuildScriptHarness is BuildScript {
    /// The fixture record root. Empty defers to `BuildScript`'s own.
    string internal sRoot;

    /// The fixture lib directory. Empty defers to `BuildScript`'s own.
    string internal sLibDir;

    /// The declared network set, or empty for `LibRainDeployDeclaration.extend`'s
    /// default. Set by `declareNetworks` and only by it, so the default case is
    /// the one every other test here drives.
    string[] internal sNetworks;

    /// A rolling snapshot the release freezes beside the generated contract's,
    /// or empty for none.
    string internal sExtraRecord;

    /// @param root The fixture record root, or empty for `BuildScript`'s own.
    constructor(string memory root) {
        sRoot = root;
        if (bytes(root).length > 0) {
            string[] memory components = vm.split(root, "/");
            sLibDir = string.concat("fixture-lib/buildscript-harness/", components[components.length - 1]);
        }
    }

    /// Narrows what this harness declares, which is what the config is
    /// generated from.
    /// @param networks The network names to declare.
    function declareNetworks(string[] memory networks) external {
        sNetworks = networks;
    }

    /// @param name A rolling snapshot `regenerateSnapshots` also writes and
    /// `releaseRecordNames` also names.
    function declareExtraRecord(string memory name) external {
        sExtraRecord = name;
    }

    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        if (sNetworks.length > 0) {
            LibRainDeployDeclaration.setNetworks(d, sNetworks);
        }
        LibRainDeployZoltuMechanism.extend(d);
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                networks: new string[](0),
                suite: BUILD_SCRIPT_HARNESS_SUITE,
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new DeployDependency[](0),
                mechanismData: LibRainDeployZoltuMechanism.mechanismData()
            }),
            unanchorableReason: ""
        });
        LibRainDeployDeclaration.addCandidates(d, candidates);
        return d;
    }

    /// @inheritdoc BuildScript
    function generatedContracts(DeployDeclaration memory d)
        internal
        pure
        override
        returns (GeneratedContract[] memory)
    {
        GeneratedContract[] memory generated = new GeneratedContract[](1);
        generated[0] = GeneratedContract({
            contractName: BUILD_SCRIPT_HARNESS_CONTRACT,
            constantPrefix: "",
            candidate: declaredCandidate(d, BUILD_SCRIPT_HARNESS_SUITE)
        });
        return generated;
    }

    /// @inheritdoc BuildScript
    function recordRoot() internal view override returns (string memory) {
        return bytes(sRoot).length > 0 ? sRoot : super.recordRoot();
    }

    /// @inheritdoc BuildScript
    function libDir() internal view override returns (string memory) {
        return bytes(sLibDir).length > 0 ? sLibDir : super.libDir();
    }

    /// The root a release cut from this harness is frozen into.
    /// @return The record root.
    function externalRecordRoot() external view returns (string memory) {
        return recordRoot();
    }

    /// @return The lib directory.
    function externalLibDir() external view returns (string memory) {
        return libDir();
    }

    /// @return The paths `run()` declares.
    function externalGeneratedPaths() external view returns (string[] memory) {
        DeployDeclaration memory d = declaration();
        return generatedPaths(d, checkedGeneratedContracts(d));
    }

    /// @inheritdoc BuildScript
    /// @dev The fixture root, never the repo's own. A `run()` here would
    /// otherwise read the committed config and stage a spliced copy of it,
    /// which the next install would put in place.
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
        return LibRainDeploySnapshot.pathForSnapshot(
            recordRoot(), LibRainDeploySnapshot.CANDIDATE, BUILD_SCRIPT_HARNESS_CONTRACT
        );
    }

    /// Where the release freezes that snapshot to.
    /// @return The frozen snapshot path.
    function frozenPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(
            recordRoot(), LibRainDeploySnapshot.deployTag(vm), BUILD_SCRIPT_HARNESS_CONTRACT
        );
    }

    /// Where `regenerateLibs` writes the candidate's released-suites lib.
    /// @return The released lib path.
    function releasedLibPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForLib(
            libDir(), LibRainDeploySnapshot.releasedLibraryName(BUILD_SCRIPT_HARNESS_CONTRACT)
        );
    }

    /// Where `regenerateLibs` writes the aggregate.
    /// @return The aggregate path.
    function aggregatePath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForLib(libDir(), LibRainDeploySnapshot.RELEASED_SUITES_LIBRARY);
    }

    /// A comment-only fixture file.
    /// @param body What distinguishes this marker from the others.
    /// @return The marker.
    function marker(string memory body) public pure returns (string memory) {
        // Split so `reuse lint` reads this as a fixture rather than as this
        // file's own license declaration.
        return string.concat("// SPDX-License", "-Identifier: LicenseRef-DCL-1.0\n// ", body, "\n");
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {
        LibRainDeploySnapshot.writeSnapshot(
            vm,
            recordRoot(),
            LibRainDeploySnapshot.CANDIDATE,
            BUILD_SCRIPT_HARNESS_CONTRACT,
            type(MockDeployableV2).creationCode,
            new DeployDependency[](0)
        );
        if (bytes(sExtraRecord).length > 0) {
            LibRainDeploySnapshot.writeSnapshot(
                vm,
                recordRoot(),
                LibRainDeploySnapshot.CANDIDATE,
                sExtraRecord,
                type(MockDeployableV2).creationCode,
                new DeployDependency[](0)
            );
        }
    }

    /// @inheritdoc BuildScript
    function releaseRecordNames(DeployDeclaration memory d, GeneratedContract[] memory generated)
        internal
        view
        override
        returns (string[] memory)
    {
        string[] memory names = super.releaseRecordNames(d, generated);
        if (bytes(sExtraRecord).length == 0) {
            return names;
        }
        string[] memory extended = new string[](names.length + 1);
        for (uint256 i = 0; i < names.length; i++) {
            extended[i] = names[i];
        }
        extended[names.length] = sExtraRecord;
        return extended;
    }

    /// Where the release freezes `name`'s rolling snapshot to.
    /// @param name The snapshot name.
    /// @return The frozen snapshot path.
    function frozenPathOf(string memory name) external view returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(recordRoot(), LibRainDeploySnapshot.deployTag(vm), name);
    }

    /// Writes a fixture file, creating the directories above it.
    /// @param path The file to write.
    /// @param content The content to write there.
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
