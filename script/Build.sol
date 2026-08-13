// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.4/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.4/src/lib/LibFs.sol";
import {LibRainDeploy} from "../src/lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "../src/lib/LibRainDeploySnapshot.sol";
import {AddressRegistry} from "../src/concrete/AddressRegistry.sol";

/// @title Build
/// @notice Generates the deterministic-deploy pins for `AddressRegistry`.
///
/// Two entry points, because there are two different things to do and only one
/// of them happens on an ordinary build:
///
/// - `run()` — every build. Regenerates the ROLLING snapshot
///   `src/generated/candidate/AddressRegistry.sol` from current source,
///   and the alias lib that points at it. Nothing here is frozen, so a source
///   change simply moves it.
/// - `cutRelease()` — a release. Regenerates the rolling snapshot and freezes
///   it as `src/generated/<tag>/`, in ONE call, in that order.
///
/// The alias lib always points at `candidate`, so consumers' import path never
/// moves and `LibAddressRegistry` always resolves against what this repo
/// currently compiles. The frozen `<tag>/` directories are the historical
/// record — what each release actually deployed — which is what
/// `AddressRegistryDeploySuites.releasedSuites()` enumerates.
///
/// The tag, both snapshot paths and the freeze come from
/// `LibRainDeploySnapshot`; every constant is emitted by `LibCodeGen`; the file
/// itself is written by `LibFs`. Nothing here restates any of them.
contract Build is Script {
    string constant GEN_LIB_PATH = "src/lib/LibAddressRegistryDeploy.sol";

    /// @notice The NatSpec emitted above the generated `DEPLOYED_ADDRESS`
    /// constant. An argument to `LibCodeGen.addressConstantString` rather than
    /// hardcoded into a local copy of it.
    string constant DEPLOYED_ADDRESS_COMMENT =
        "/// @dev The deterministic deploy address of the contract when deployed via\n/// the Zoltu factory.";

    // REUSE-IgnoreStart  (the two SPDX lines below are the header EMITTED into the
    // generated lib, not this script's own license — hide from reuse lint)
    string constant GEN_SPDX_LICENSE = "// SPDX-License-Identifier: LicenseRef-DCL-1.0";
    string constant GEN_SPDX_COPYRIGHT = "// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd";

    // REUSE-IgnoreEnd

    /// @notice Every build: regenerate the rolling snapshot and its alias lib.
    function run() external {
        regenerateCandidate();
        genLibAddressRegistryDeploy();
    }

    /// @notice A release: regenerate the rolling snapshot, then freeze it as
    /// this release's immutable record.
    ///
    /// One invocation, so the ordering is a property of the tool rather than of
    /// whoever wrote the release command. `LibRainDeploySnapshot.freeze` takes
    /// the regeneration and runs it FIRST; there is no entry point that freezes
    /// without regenerating, so a stale freeze has nowhere to come from.
    ///
    /// Not yet wired into `package-release.yaml`, whose `snapshot-generate-cmd`
    /// still calls `run()`. Changing that input is out of scope here.
    function cutRelease() external {
        string[] memory contractNames = new string[](1);
        contractNames[0] = "AddressRegistry";
        LibRainDeploySnapshot.freeze(vm, regenerateCandidate, contractNames);
        genLibAddressRegistryDeploy();
    }

    /// @notice Rewrite `src/generated/candidate/AddressRegistry.sol`
    /// from what this repo currently compiles.
    function regenerateCandidate() internal {
        LibRainDeploy.etchZoltuFactory(vm);

        // A fresh checkout has no `candidate/` dir yet, and `vm.writeFile`
        // won't create one.
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(LibRainDeploySnapshot.dirForSnapshot(LibRainDeploySnapshot.CANDIDATE), true);

        bytes memory creationCode = type(AddressRegistry).creationCode;
        address deployed = LibRainDeploy.deployZoltu(creationCode);

        LibFs.buildFileForContract(
            vm,
            deployed,
            LibRainDeploySnapshot.snapshotName(LibRainDeploySnapshot.CANDIDATE, "AddressRegistry"),
            string.concat(
                LibCodeGen.addressConstantString(vm, DEPLOYED_ADDRESS_COMMENT, "DEPLOYED_ADDRESS", deployed),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The creation bytecode of the contract.", "CREATION_CODE", creationCode
                ),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The runtime bytecode of the contract.", "RUNTIME_CODE", deployed.code
                )
            )
        );
    }

    /// @notice (Re)generate `src/lib/LibAddressRegistryDeploy.sol`, aliasing the
    /// ROLLING candidate snapshot's `DEPLOYED_ADDRESS` + `BYTECODE_HASH` as the
    /// current constants — that snapshot stays the single source of truth
    /// (never a duplicated literal), and the import path never moves because
    /// `candidate` never moves. Emitted line-by-line to match the
    /// generated-file convention.
    function genLibAddressRegistryDeploy() internal {
        string memory importPath =
            string.concat("../generated/", LibRainDeploySnapshot.CANDIDATE, "/AddressRegistry.sol");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(GEN_LIB_PATH, "");
        vm.writeLine(GEN_LIB_PATH, GEN_SPDX_LICENSE);
        vm.writeLine(GEN_LIB_PATH, GEN_SPDX_COPYRIGHT);
        vm.writeLine(GEN_LIB_PATH, "pragma solidity ^0.8.25;");
        vm.writeLine(GEN_LIB_PATH, "");
        vm.writeLine(GEN_LIB_PATH, "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.");
        vm.writeLine(GEN_LIB_PATH, "");
        vm.writeLine(GEN_LIB_PATH, "import {");
        vm.writeLine(GEN_LIB_PATH, "    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_ADDR,");
        vm.writeLine(GEN_LIB_PATH, "    BYTECODE_HASH as ADDRESS_REGISTRY_HASH");
        vm.writeLine(GEN_LIB_PATH, string.concat("} from \"", importPath, "\";"));
        vm.writeLine(GEN_LIB_PATH, "");
        vm.writeLine(GEN_LIB_PATH, "/// @title LibAddressRegistryDeploy");
        vm.writeLine(GEN_LIB_PATH, "/// @notice The deterministic Zoltu deploy address and code hash of");
        vm.writeLine(GEN_LIB_PATH, "/// `AddressRegistry` as this repo currently compiles it, aliased from the");
        vm.writeLine(GEN_LIB_PATH, "/// rolling `src/generated/candidate/AddressRegistry.sol` snapshot so");
        vm.writeLine(GEN_LIB_PATH, "/// that snapshot stays the single source of truth.");
        vm.writeLine(GEN_LIB_PATH, "library LibAddressRegistryDeploy {");
        vm.writeLine(GEN_LIB_PATH, "    address constant ADDRESS_REGISTRY_DEPLOYED_ADDRESS = ADDRESS_REGISTRY_ADDR;");
        vm.writeLine(GEN_LIB_PATH, "    bytes32 constant ADDRESS_REGISTRY_DEPLOYED_CODEHASH = ADDRESS_REGISTRY_HASH;");
        vm.writeLine(GEN_LIB_PATH, "}");
    }
}
