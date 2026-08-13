// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.3/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.3/src/lib/LibFs.sol";
import {LibSnapshot} from "rain-sol-codegen-0.1.3/src/lib/LibSnapshot.sol";
import {LibRainDeploy} from "../src/lib/LibRainDeploy.sol";
import {AddressRegistry} from "../src/concrete/AddressRegistry.sol";

/// @title Build
/// @notice Generates the deterministic-deploy pins for `AddressRegistry`:
///   1. A frozen per-release snapshot
///      `src/generated/<tag>/AddressRegistry.pointers.sol` (`BYTECODE_HASH`,
///      `DEPLOYED_ADDRESS`, `CREATION_CODE`, `RUNTIME_CODE`) for the current
///      `LibSnapshot.deployTag`. Historical tags are never regenerated; a
///      release bump writes a new `<tag>/` snapshot beside them.
///   2. `src/lib/LibAddressRegistryDeploy.sol` — the current-release address and
///      codehash, aliased from the current tag's snapshot so that
///      snapshot stays the single source of truth (never a duplicated literal).
///      Kept in `src/lib` so consumers' import path is stable across releases.
///
/// The tag, the snapshot directory and the address-constant formatting all come
/// from `rain-sol-codegen` rather than being restated here — `LibSnapshot` calls
/// itself the single definition of the tag form, and a second definition in this
/// file is exactly the drift that would make a release freeze the wrong dir.
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

    /// @notice The NatSpec emitted above the generated `DEPLOYED_ADDRESS`
    /// constant. An argument to `LibCodeGen.addressConstantString` rather than
    /// hardcoded into a local copy of it.
    string constant DEPLOYED_ADDRESS_COMMENT =
        "/// @dev The deterministic deploy address of the contract when deployed via\n/// the Zoltu factory.";

    function run() external {
        LibRainDeploy.etchZoltuFactory(vm);

        string memory tag = LibSnapshot.deployTag(vm);

        // A fresh version slot has no `<tag>/` dir yet, and `vm.writeFile`
        // won't create one.
        vm.createDir(LibSnapshot.dirForTag(tag), true);

        bytes memory creationCode = type(AddressRegistry).creationCode;
        address deployed = LibRainDeploy.deployZoltu(creationCode);

        // Frozen per-tag snapshot. The tag is folded into the contract name so
        // `LibFs` places it at `LibSnapshot.frozenPathForContract(tag,
        // "AddressRegistry")`, which is the same path — `LibFs` owns writing a
        // generated file, including its header and the idempotent removal of an
        // existing one, and there is no variant of it that takes a path.
        LibFs.buildFileForContract(
            vm,
            deployed,
            string.concat(tag, "/AddressRegistry"),
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

        // Current-release pin lib.
        genLibAddressRegistryDeploy(tag);
    }

    /// @notice (Re)generate `src/lib/LibAddressRegistryDeploy.sol`, aliasing the
    /// current tag's snapshot `DEPLOYED_ADDRESS` + `BYTECODE_HASH` as the
    /// current-release constants — the snapshot stays the single source of
    /// truth (never a duplicated literal). Emitted line-by-line to match the
    /// generated-file convention.
    /// @param tag The release tag, from `LibSnapshot.deployTag`.
    function genLibAddressRegistryDeploy(string memory tag) internal {
        string memory importPath = string.concat("../generated/", tag, "/AddressRegistry.pointers.sol");
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
