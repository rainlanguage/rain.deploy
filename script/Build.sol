// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.0/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.0/src/lib/LibFs.sol";
import {LibRainDeploy} from "../src/lib/LibRainDeploy.sol";
import {AddressRegistry} from "../src/concrete/AddressRegistry.sol";

/// @title Build
/// @notice Generates the deterministic-deploy pins for `AddressRegistry`:
///   1. A frozen per-release snapshot
///      `src/generated/<tag>/AddressRegistry.pointers.sol` (`BYTECODE_HASH`,
///      `DEPLOYED_ADDRESS`, `CREATION_CODE`, `RUNTIME_CODE`) for the current
///      `deployTag()`. Historical tags are never regenerated; a release bump
///      writes a new `<tag>/` snapshot beside them.
///   2. `src/lib/LibAddressRegistryDeploy.sol` — the current-release address and
///      codehash, aliased from the current `deployTag()` snapshot so that
///      snapshot stays the single source of truth (never a duplicated literal).
///      Kept in `src/lib` so consumers' import path is stable across releases.
///
/// Run as `forge script script/Build.sol`. Wired into
/// `rainix-tag-release`'s `snapshot-generate-cmd`, so a release regenerates the
/// pins for the version the tag names.
contract Build is Script {
    string constant GEN_LIB_PATH = "src/lib/LibAddressRegistryDeploy.sol";

    // REUSE-IgnoreStart  (the two SPDX lines below are the header EMITTED into the
    // generated lib, not this script's own license — hide from reuse lint)
    string constant GEN_SPDX_LICENSE = "// SPDX-License-Identifier: LicenseRef-DCL-1.0";
    string constant GEN_SPDX_COPYRIGHT = "// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd";

    // REUSE-IgnoreEnd

    /// @notice The canonical release tag. Read from `foundry.toml`
    /// `[package].version` — the single source of truth — with dots converted to
    /// underscores for the Solidity dir form (`0.1.6` -> `0_1_6`).
    /// @return The tag in its Solidity directory form.
    function deployTag() internal view returns (string memory) {
        string memory version = vm.parseTomlString(vm.readFile("foundry.toml"), ".package.version");
        bytes memory b = bytes(version);
        bytes memory out = new bytes(b.length);
        for (uint256 i = 0; i < b.length; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            out[i] = b[i] == "." ? bytes1("_") : b[i];
        }
        return string(out);
    }

    /// @notice The generated `DEPLOYED_ADDRESS` constant declaration.
    /// @param addr The deterministic deploy address.
    /// @return The Solidity source for the constant.
    function addressConstantString(address addr) internal pure returns (string memory) {
        return string.concat(
            "\n",
            "/// @dev The deterministic deploy address of the contract when deployed via\n",
            "/// the Zoltu factory.\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(addr),
            ");\n"
        );
    }

    function run() external {
        LibRainDeploy.etchZoltuFactory(vm);

        // A fresh version slot has no `<tag>/` dir yet, and `vm.writeFile`
        // won't create one.
        vm.createDir(string.concat("src/generated/", deployTag()), true);

        bytes memory creationCode = type(AddressRegistry).creationCode;
        address deployed = LibRainDeploy.deployZoltu(creationCode);

        // Frozen per-tag snapshot.
        LibFs.buildFileForContract(
            vm,
            deployed,
            string.concat(deployTag(), "/AddressRegistry"),
            string.concat(
                addressConstantString(deployed),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The creation bytecode of the contract.", "CREATION_CODE", creationCode
                ),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The runtime bytecode of the contract.", "RUNTIME_CODE", deployed.code
                )
            )
        );

        // Current-release pin lib.
        genLibAddressRegistryDeploy();
    }

    /// @notice (Re)generate `src/lib/LibAddressRegistryDeploy.sol`, aliasing the
    /// current `deployTag()` snapshot's `DEPLOYED_ADDRESS` + `BYTECODE_HASH` as
    /// the current-release constants — the snapshot stays the single source of
    /// truth (never a duplicated literal). Emitted line-by-line to match the
    /// generated-file convention.
    function genLibAddressRegistryDeploy() internal {
        string memory importPath = string.concat("../generated/", deployTag(), "/AddressRegistry.pointers.sol");
        vm.writeFile(GEN_LIB_PATH, "");
        vm.writeLine(GEN_LIB_PATH, GEN_SPDX_LICENSE);
        vm.writeLine(GEN_LIB_PATH, GEN_SPDX_COPYRIGHT);
        vm.writeLine(GEN_LIB_PATH, "pragma solidity ^0.8.25;");
        vm.writeLine(GEN_LIB_PATH, "");
        vm.writeLine(GEN_LIB_PATH, "// THIS FILE IS AUTOGENERATED BY ./script/Build.sol");
        vm.writeLine(GEN_LIB_PATH, "");
        vm.writeLine(GEN_LIB_PATH, "import {");
        vm.writeLine(GEN_LIB_PATH, "    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_ADDR,");
        vm.writeLine(GEN_LIB_PATH, "    BYTECODE_HASH as ADDRESS_REGISTRY_HASH");
        vm.writeLine(GEN_LIB_PATH, string.concat("} from \"", importPath, "\";"));
        vm.writeLine(GEN_LIB_PATH, "");
        vm.writeLine(GEN_LIB_PATH, "/// @title LibAddressRegistryDeploy");
        vm.writeLine(GEN_LIB_PATH, "/// @notice The deterministic Zoltu deploy address and code hash of the current");
        vm.writeLine(GEN_LIB_PATH, "/// `AddressRegistry` release, aliased from the frozen per-release snapshot in");
        vm.writeLine(GEN_LIB_PATH, "/// `src/generated/<tag>/AddressRegistry.pointers.sol` so that snapshot stays the");
        vm.writeLine(GEN_LIB_PATH, "/// single source of truth.");
        vm.writeLine(GEN_LIB_PATH, "library LibAddressRegistryDeploy {");
        vm.writeLine(GEN_LIB_PATH, "    address constant ADDRESS_REGISTRY_DEPLOYED_ADDRESS = ADDRESS_REGISTRY_ADDR;");
        vm.writeLine(GEN_LIB_PATH, "    bytes32 constant ADDRESS_REGISTRY_DEPLOYED_CODEHASH = ADDRESS_REGISTRY_HASH;");
        vm.writeLine(GEN_LIB_PATH, "}");
    }
}
