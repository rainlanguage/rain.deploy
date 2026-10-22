// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript, GeneratedContract} from "../../src/abstract/BuildScript.sol";
import {RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {CloneNetwork} from "../../src/lib/LibRainDeployClone.sol";
import {LibRainDeployMechanism} from "../../src/lib/LibRainDeployMechanism.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {
    PER_NETWORK_CLONE_RECORD_CONTRACT,
    PerNetworkCloneDeploys,
    perNetworkCloneChainIds,
    perNetworkCloneRelease
} from "../abstract/PerNetworkCloneDeploys.sol";

/// @title PerNetworkCloneBuildScriptHarness
/// @notice A per-network clone deploy repo's build script over a fixture record root.
contract PerNetworkCloneBuildScriptHarness is PerNetworkCloneDeploys, BuildScript {
    string internal sRoot;

    string internal sLibDir;

    /// The networks `extendedNetworks` declares for the release. Empty by default.
    CloneNetwork[] internal sExtendedNetworks;

    /// The licence `extendedNetworksSpdxLicenseIdentifier` gives once `setExtendedNetworksLicence` has run.
    string internal sSpdxLicenseIdentifier;

    /// The copyright text `extendedNetworksCopyrightText` gives once `setExtendedNetworksLicence` has run.
    string internal sCopyrightText;

    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// @param root The record root to regenerate and cut into.
    /// @param libDirectory The directory the released-suites lib is written to.
    constructor(string memory root, string memory libDirectory) {
        sRoot = root;
        sLibDir = libDirectory;
    }

    /// @inheritdoc BuildScript
    function recordRoot() internal view override returns (string memory) {
        return sRoot;
    }

    /// @inheritdoc BuildScript
    /// @dev The fixture root, so a `run()` here stages no config over the repo's own.
    function configRoot() internal view override returns (string memory) {
        return sRoot;
    }

    /// @inheritdoc BuildScript
    function generatedContracts() internal view override returns (GeneratedContract[] memory) {
        GeneratedContract[] memory generated = new GeneratedContract[](1);
        generated[0] = GeneratedContract({
            contractName: PER_NETWORK_CLONE_RECORD_CONTRACT, constantPrefix: "", candidate: candidateSuites()[0]
        });
        return generated;
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {
        LibRainDeploySnapshot.writeSnapshot(
            vm,
            recordRoot(),
            LibRainDeploySnapshot.CANDIDATE,
            PER_NETWORK_CLONE_RECORD_CONTRACT,
            LibRainDeployMechanism.cloneCandidate(perNetworkCloneRelease(), perNetworkCloneChainIds()).snapshot
        );
    }

    /// @inheritdoc BuildScript
    function libDir() internal view override returns (string memory) {
        return sLibDir;
    }

    /// Sets what `extendedNetworks` declares for the release.
    /// @param networks The networks.
    function setExtendedNetworks(CloneNetwork[] memory networks) external {
        delete sExtendedNetworks;
        for (uint256 i = 0; i < networks.length; i++) {
            sExtendedNetworks.push(networks[i]);
        }
    }

    /// Sets the licence the extended networks records declare.
    /// @param spdxLicenseIdentifier The SPDX licence identifier.
    /// @param copyrightText The copyright text.
    function setExtendedNetworksLicence(string memory spdxLicenseIdentifier, string memory copyrightText) external {
        sSpdxLicenseIdentifier = spdxLicenseIdentifier;
        sCopyrightText = copyrightText;
    }

    /// @inheritdoc RainDeploySuitesBase
    function extendedNetworks(string memory suite) internal view virtual override returns (CloneNetwork[] memory) {
        if (keccak256(bytes(suite)) != keccak256("per-network-clone@0_0_1")) {
            return new CloneNetwork[](0);
        }
        return sExtendedNetworks;
    }

    /// @inheritdoc RainDeploySuitesBase
    function extendedNetworksRoot() internal view override returns (string memory) {
        return sRoot;
    }

    /// @inheritdoc BuildScript
    function extendedNetworksSpdxLicenseIdentifier() internal view override returns (string memory) {
        if (bytes(sSpdxLicenseIdentifier).length == 0) {
            return BuildScript.extendedNetworksSpdxLicenseIdentifier();
        }
        return sSpdxLicenseIdentifier;
    }

    /// @inheritdoc BuildScript
    function extendedNetworksCopyrightText() internal view override returns (string memory) {
        if (bytes(sCopyrightText).length == 0) {
            return BuildScript.extendedNetworksCopyrightText();
        }
        return sCopyrightText;
    }

    /// External wrapper for `regenerateExtendedNetworks`.
    function externalRegenerateExtendedNetworks() external {
        regenerateExtendedNetworks();
    }

    /// @return The paths `run()` declares.
    function externalGeneratedPaths() external view returns (string[] memory) {
        return generatedPaths();
    }

    /// @return The rolling snapshot's path.
    function rollingPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(
            recordRoot(), LibRainDeploySnapshot.CANDIDATE, PER_NETWORK_CLONE_RECORD_CONTRACT
        );
    }

    /// @return The path `cutRelease()` freezes the rolling snapshot to.
    function frozenPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(
            recordRoot(), LibRainDeploySnapshot.deployTag(vm), PER_NETWORK_CLONE_RECORD_CONTRACT
        );
    }

    /// @return The released-suites lib's path.
    function releasedLibPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForLib(
            sLibDir, LibRainDeploySnapshot.releasedLibraryName(PER_NETWORK_CLONE_RECORD_CONTRACT)
        );
    }
}
