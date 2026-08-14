// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

/// @title GeneratedSnapshotShapeTest
/// @notice What a generated deploy snapshot must look like, asserted against
/// the real generator's committed output.
///
/// THESE ASSERTIONS ARE THE SPECIFICATION. There is no second hand-written file
/// to compare against and therefore no question about that file's provenance:
/// "there is an `address` constant named `DEPLOYED_ADDRESS`" is stated here,
/// once, in test code, and checked against what `script/Build.sol` actually
/// emitted.
///
/// The check reads the compiler's AST rather than the source text, so it is
/// about the file's STRUCTURE and not its formatting. `forge build --ast`
/// writes the AST into the artifact JSON, and — usefully, since a snapshot
/// declares only file-level constants and no contract at all — foundry still
/// emits an artifact for such a file.
///
/// Values are deliberately not asserted. A solc or optimiser change moves every
/// literal without changing anything here, and a wrong literal is caught
/// immediately by the group 1 derivation checks in `RainDeployVerifySnapshot`.
contract GeneratedSnapshotShapeTest is Test {
    /// The artifact for the generated candidate snapshot, which carries its AST.
    string constant ARTIFACT = "out/candidate/AddressRegistry.sol/AddressRegistry.json";

    /// The node types of the generated snapshot's source unit, in file order.
    ///
    /// Indexed one at a time rather than with a `$.ast.nodes[*].nodeType`
    /// wildcard: foundry's JSON path support requires a path to resolve to
    /// exactly one value, so the wildcard is rejected outright.
    /// @return types One entry per top-level AST node.
    function nodeTypes() internal view returns (string[] memory types) {
        string memory json = vm.readFile(ARTIFACT);
        string[] memory found = new string[](64);
        uint256 count = 0;
        while (vm.keyExistsJson(json, string.concat("$.ast.nodes[", vm.toString(count), "].nodeType"))) {
            found[count] = vm.parseJsonString(json, string.concat("$.ast.nodes[", vm.toString(count), "].nodeType"));
            count++;
        }
        types = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            types[i] = found[i];
        }
    }

    /// The declared constants of the generated snapshot, in file order, as
    /// `<type> <NAME>` — read from the AST, so formatting cannot affect it.
    /// @return declarations One entry per file-level constant.
    function constantDeclarations() internal view returns (string[] memory declarations) {
        string memory json = vm.readFile(ARTIFACT);
        string[] memory types = nodeTypes();

        string[] memory found = new string[](types.length);
        uint256 count = 0;
        for (uint256 i = 0; i < types.length; i++) {
            if (keccak256(bytes(types[i])) != keccak256(bytes("VariableDeclaration"))) {
                continue;
            }
            string memory base = string.concat("$.ast.nodes[", vm.toString(i), "]");
            assertTrue(vm.parseJsonBool(json, string.concat(base, ".constant")), "snapshot declared a non-constant");
            found[count] = string.concat(
                vm.parseJsonString(json, string.concat(base, ".typeName.name")),
                " ",
                vm.parseJsonString(json, string.concat(base, ".name"))
            );
            count++;
        }
        declarations = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            declarations[i] = found[i];
        }
    }

    /// PROPERTY: the snapshot declares exactly the four constants a deploy
    /// record is for, of these types, in this order. A rename, a retype, a
    /// reorder or a fifth constant each fail here and name what broke.
    function testSnapshotDeclaresTheFourDeployConstantsInOrder() external view {
        string[] memory declarations = constantDeclarations();

        assertEq(declarations.length, 4, "snapshot declares an unexpected number of constants");
        assertEq(declarations[0], "bytes32 BYTECODE_HASH", "first constant is not bytes32 BYTECODE_HASH");
        assertEq(declarations[1], "address DEPLOYED_ADDRESS", "second constant is not address DEPLOYED_ADDRESS");
        assertEq(declarations[2], "bytes CREATION_CODE", "third constant is not bytes CREATION_CODE");
        assertEq(declarations[3], "bytes RUNTIME_CODE", "fourth constant is not bytes RUNTIME_CODE");
    }

    /// PROPERTY: the snapshot imports nothing. It is read by repos that do not
    /// have the contract it describes — that is the whole reason a frozen
    /// release stays verifiable after its source has changed or gone — so any
    /// import would make it unusable to exactly the readers it exists for.
    function testSnapshotImportsNothing() external view {
        string[] memory types = nodeTypes();
        for (uint256 i = 0; i < types.length; i++) {
            assertNotEq(types[i], "ImportDirective", "snapshot imports something");
        }
    }

    /// PROPERTY: the snapshot declares no contract, library or interface. It is
    /// a record, not code; anything deployable in it would be a second
    /// definition of something the record is supposed to describe.
    function testSnapshotDeclaresNoContract() external view {
        string[] memory types = nodeTypes();
        for (uint256 i = 0; i < types.length; i++) {
            assertNotEq(types[i], "ContractDefinition", "snapshot declares a contract");
        }
    }

    /// PROPERTY: the snapshot says it is generated. Someone who opens it must
    /// be told not to hand-edit it, because hand-editing is how a deploy record
    /// stops describing the deployment.
    function testSnapshotSaysItIsGenerated() external view {
        assertTrue(
            vm.contains(
                vm.readFile("src/generated/candidate/AddressRegistry.sol"),
                "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND."
            ),
            "snapshot is missing the generated-file header"
        );
    }
}
