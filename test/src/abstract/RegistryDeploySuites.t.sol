// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {DeployCandidate} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";

/// @title RegistryDeploySuitesTest
/// @notice The fields of this repo's declaration that nothing derives and no
/// chain check can reach without an RPC.
///
/// The recorded address, code hash and runtime code are all checked against
/// what the recorded creation code derives, and the suite key, the artifact
/// path and the candidate set are all checked against the generator. The
/// dependency list is the one field with none of that behind it: it is not
/// derived from anything, the generator neither writes it nor reads it, and the
/// only thing that consumes it is `deployToNetworks`, on a fork, under an RPC
/// this suite does not have.
///
/// The source anchor's two operands are the other thing nothing could reach.
/// `checkCandidatesAnchoredToSource` compares two `bytes`, and where they come
/// from is a property of how the declaration is SPELLED rather than of any
/// value it produces: a candidate that reads `type(X).creationCode` into the
/// recorded field compares source against itself, and on a green tree the two
/// spellings are byte-identical, so no runtime assertion can tell them apart.
/// The assertions below read the compiler's AST of the declaration itself, for
/// the reason `GeneratedSnapshotShapeTest` gives for reading it rather than the
/// source text: this is about structure, not formatting.
contract RegistryDeploySuitesTest is RegistryDeploySuites, Test {
    /// The compiled declaration, which carries its AST. `ast = true` in
    /// `foundry.toml` is what puts it there under a plain `forge test`.
    string constant DECLARATION_ARTIFACT = "out/RegistryDeploySuites.sol/RegistryDeploySuites.json";

    /// PROPERTY: neither registry declares a deploy-time dependency.
    ///
    /// A dependency is an address that MUST already have code on a network
    /// before the suite is broadcast there, and both of these contracts are
    /// declared to have none: `AddressRegistry` reads nothing and calls nothing
    /// at construction, and `MigrationRegistry` takes no constructor argument
    /// and resolves its namespace from `msg.sender` at call time. Neither can
    /// therefore be broken by what is or is not on chain when it lands, which
    /// is why both are deployable to a network the day that network is added.
    ///
    /// A dependency that is not really one is not inert. `deployToNetworks`
    /// refuses to broadcast on any network where a declared dependency has no
    /// code, so an entry added here takes both registries off every new chain
    /// until something nobody needs is deployed there first — and it fails at
    /// dispatch, per network, after the fork, where nothing in this suite is
    /// watching.
    function testCandidatesDeclareNoDependencies() external pure {
        DeployCandidate[] memory candidates = checkedCandidateSuites();
        for (uint256 i = 0; i < candidates.length; i++) {
            assertEq(
                candidates[i].snapshot.dependencies.length,
                0,
                string.concat("candidate declares a dependency: ", candidates[i].snapshot.suite)
            );
        }
    }

    /// PROPERTY: every candidate's RECORDED creation code and runtime code are
    /// read from the rolling `src/generated/candidate/` snapshot.
    ///
    /// This is the half of the source anchor that has to come from the record.
    /// Spelling it `type(X).creationCode` — to drop an import, or to make the
    /// two fields of a candidate read alike — puts both operands of
    /// `checkCandidatesAnchoredToSource` on the source side and makes the one
    /// check that catches a snapshot of the wrong contract a tautology for that
    /// candidate, with nothing red anywhere.
    ///
    /// The runtime code is held to the record by the same assertion because it
    /// is what would be left of the record side. A candidate whose creation
    /// code came from source is still caught by the internal-consistency check,
    /// which stops being internal the moment one operand is source; that only
    /// holds while the rest of the snapshot is the generated file, and a
    /// refactor reaching for the type expression reaches for both `bytes`
    /// fields at once.
    ///
    /// The identifier is matched against the declaration id the IMPORT resolved
    /// to, rather than against a constant name written here. A name asserts
    /// that something spelled `..._CREATION_CODE_CANDIDATE` is read; the id
    /// asserts it is the constant the generator wrote, so a hand-written
    /// `bytes` constant of the same name in this file is not a way past it.
    function testCandidatesRecordTheGeneratedConstants() external view {
        string memory json = vm.readFile(DECLARATION_ARTIFACT);
        string[] memory candidates = candidateLiteralPaths(json);
        assertEq(candidates.length, checkedCandidateSuites().length, "a declared candidate has no struct literal");

        uint256[] memory creationIds = importedConstantIds(json, "CREATION_CODE");
        uint256[] memory runtimeIds = importedConstantIds(json, "RUNTIME_CODE");

        for (uint256 i = 0; i < candidates.length; i++) {
            string memory snapshot = fieldPath(json, candidates[i], "snapshot");
            assertReadsImportedConstant(json, fieldPath(json, snapshot, "creationCode"), creationIds, "creationCode");
            assertReadsImportedConstant(
                json, fieldPath(json, snapshot, "storedRuntimeCode"), runtimeIds, "storedRuntimeCode"
            );
        }
    }

    /// PROPERTY: every candidate's `sourceCreationCode` is
    /// `type(X).creationCode`.
    ///
    /// The mirror of the assertion above, and undetectable at runtime for the
    /// same reason. A candidate whose source side reads the generated constant
    /// compares the record against itself, which is a tautology arrived at from
    /// the other direction — and it is the spelling a refactor lands on when it
    /// notices that the two fields hold equal bytes.
    function testCandidatesAnchorAgainstCurrentSource() external view {
        string memory json = vm.readFile(DECLARATION_ARTIFACT);
        string[] memory candidates = candidateLiteralPaths(json);
        assertEq(candidates.length, checkedCandidateSuites().length, "a declared candidate has no struct literal");

        for (uint256 i = 0; i < candidates.length; i++) {
            assertEq(
                expressionShape(json, fieldPath(json, candidates[i], "sourceCreationCode")),
                "type().creationCode",
                "candidate does not anchor to current source"
            );
        }
    }

    /// The JSON path of every `DeployCandidate` struct literal the declaration
    /// returns.
    ///
    /// Found by return type and by the kind of the returned expression, never
    /// by function name or position: a candidate this walk does not reach is a
    /// candidate whose spelling nothing above checks, and the count is asserted
    /// against the declaration itself for exactly that reason.
    /// @param json The declaration's artifact.
    /// @return One path per candidate literal.
    function candidateLiteralPaths(string memory json) internal view returns (string[] memory) {
        string memory contractPath = declarationPath(json);
        string[] memory found = new string[](64);
        uint256 count = 0;

        uint256 i = 0;
        while (vm.keyExistsJson(json, string.concat(contractPath, ".nodes[", vm.toString(i), "].nodeType"))) {
            string memory node = string.concat(contractPath, ".nodes[", vm.toString(i), "]");
            i++;

            string memory returnType = string.concat(node, ".returnParameters.parameters[0].typeName.pathNode.name");
            if (!vm.keyExistsJson(json, returnType)) {
                continue;
            }
            if (keccak256(bytes(vm.parseJsonString(json, returnType))) != keccak256("DeployCandidate")) {
                continue;
            }

            string memory literal = returnedStructLiteralPath(json, node);
            assertTrue(bytes(literal).length > 0, "candidate function returns no struct literal");
            found[count] = literal;
            count++;
        }

        string[] memory paths = new string[](count);
        for (uint256 j = 0; j < count; j++) {
            paths[j] = found[j];
        }
        return paths;
    }

    /// The JSON path of the struct literal a function returns, if it returns
    /// one directly.
    /// @param json The declaration's artifact.
    /// @param functionPath The function's own path.
    /// @return The literal's path, or the empty string.
    function returnedStructLiteralPath(string memory json, string memory functionPath)
        internal
        view
        returns (string memory)
    {
        uint256 i = 0;
        while (vm.keyExistsJson(json, string.concat(functionPath, ".body.statements[", vm.toString(i), "].nodeType"))) {
            string memory expression = string.concat(functionPath, ".body.statements[", vm.toString(i), "].expression");
            i++;

            string memory kind = string.concat(expression, ".kind");
            if (!vm.keyExistsJson(json, kind)) {
                continue;
            }
            if (keccak256(bytes(vm.parseJsonString(json, kind))) == keccak256("structConstructorCall")) {
                return expression;
            }
        }
        return "";
    }

    /// The declaration's own contract node.
    /// @param json The declaration's artifact.
    /// @return The contract's path.
    function declarationPath(string memory json) internal view returns (string memory) {
        uint256 i = 0;
        while (vm.keyExistsJson(json, string.concat("$.ast.nodes[", vm.toString(i), "].nodeType"))) {
            string memory node = string.concat("$.ast.nodes[", vm.toString(i), "]");
            i++;
            if (
                keccak256(bytes(vm.parseJsonString(json, string.concat(node, ".nodeType"))))
                    == keccak256("ContractDefinition")
            ) {
                return node;
            }
        }
        revert("declaration artifact holds no contract");
    }

    /// The JSON path of one named field's value within a struct literal.
    ///
    /// Selected by the literal's own `names` list rather than by position, so
    /// reordering the fields of a struct is not a way past any assertion here.
    /// @param json The declaration's artifact.
    /// @param literalPath The struct literal's path.
    /// @param field The field to read.
    /// @return The field value's path.
    function fieldPath(string memory json, string memory literalPath, string memory field)
        internal
        pure
        returns (string memory)
    {
        string[] memory names = vm.parseJsonStringArray(json, string.concat(literalPath, ".names"));
        for (uint256 i = 0; i < names.length; i++) {
            if (keccak256(bytes(names[i])) == keccak256(bytes(field))) {
                return string.concat(literalPath, ".arguments[", vm.toString(i), "]");
            }
        }
        revert(string.concat("candidate declares no field named ", field));
    }

    /// Every declaration id the declaration imports under `foreignName` from
    /// the rolling snapshot directory.
    ///
    /// The directory comes from `LibRainDeploySnapshot`, so it is the one the
    /// generator writes into rather than a second spelling of that path.
    /// @param json The declaration's artifact.
    /// @param foreignName The constant's name in the generated file.
    /// @return One id per import of that name.
    function importedConstantIds(string memory json, string memory foreignName)
        internal
        view
        returns (uint256[] memory)
    {
        string memory snapshotDir = string.concat(
            LibRainDeploySnapshot.dirForSnapshot(LibRainDeploySnapshot.CANDIDATE), "/"
        );
        uint256[] memory found = new uint256[](64);
        uint256 count = 0;

        uint256 i = 0;
        while (vm.keyExistsJson(json, string.concat("$.ast.nodes[", vm.toString(i), "].nodeType"))) {
            string memory node = string.concat("$.ast.nodes[", vm.toString(i), "]");
            i++;

            string memory absolutePath = string.concat(node, ".absolutePath");
            if (!vm.keyExistsJson(json, absolutePath)) {
                continue;
            }
            // A split on the directory leaves an empty first chunk only where
            // the path STARTS with it, which a `contains` would not say.
            if (bytes(vm.split(vm.parseJsonString(json, absolutePath), snapshotDir)[0]).length != 0) {
                continue;
            }

            uint256 k = 0;
            while (vm.keyExistsJson(json, string.concat(node, ".symbolAliases[", vm.toString(k), "].foreign.name"))) {
                string memory symbolAlias = string.concat(node, ".symbolAliases[", vm.toString(k), "]");
                k++;
                if (
                    keccak256(bytes(vm.parseJsonString(json, string.concat(symbolAlias, ".foreign.name"))))
                        != keccak256(bytes(foreignName))
                ) {
                    continue;
                }
                found[count] = vm.parseJsonUint(json, string.concat(symbolAlias, ".foreign.referencedDeclaration"));
                count++;
            }
        }

        assertGt(count, 0, string.concat("declaration imports no ", foreignName, " from the rolling snapshot"));
        uint256[] memory ids = new uint256[](count);
        for (uint256 j = 0; j < count; j++) {
            ids[j] = found[j];
        }
        return ids;
    }

    /// One field MUST be a plain read of one of the imported constants.
    /// @param json The declaration's artifact.
    /// @param path The field value's path.
    /// @param ids The declaration ids the imports resolved to.
    /// @param field The field's name, for the failure message.
    function assertReadsImportedConstant(
        string memory json,
        string memory path,
        uint256[] memory ids,
        string memory field
    ) internal pure {
        assertEq(
            vm.parseJsonString(json, string.concat(path, ".nodeType")),
            "Identifier",
            string.concat("candidate does not read a constant for ", field)
        );

        uint256 id = vm.parseJsonUint(json, string.concat(path, ".referencedDeclaration"));
        bool imported = false;
        for (uint256 i = 0; i < ids.length; i++) {
            imported = imported || ids[i] == id;
        }
        assertTrue(imported, string.concat("candidate does not read the rolling snapshot for ", field));
    }

    /// A field value's shape, as `<callee>().<member>` for a member access on a
    /// call and as its node type otherwise.
    ///
    /// One string compared once, rather than a walk that reads `memberName` off
    /// a node that may not have one: the assertion that would have caught it is
    /// then the assertion that reports it.
    /// @param json The declaration's artifact.
    /// @param path The field value's path.
    /// @return The shape.
    function expressionShape(string memory json, string memory path) internal view returns (string memory) {
        string memory nodeType = vm.parseJsonString(json, string.concat(path, ".nodeType"));
        string memory callee = string.concat(path, ".expression.expression.name");
        if (keccak256(bytes(nodeType)) != keccak256("MemberAccess") || !vm.keyExistsJson(json, callee)) {
            return nodeType;
        }
        return string.concat(
            vm.parseJsonString(json, callee), "().", vm.parseJsonString(json, string.concat(path, ".memberName"))
        );
    }
}
