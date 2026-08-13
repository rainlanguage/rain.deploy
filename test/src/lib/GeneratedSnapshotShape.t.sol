// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

/// @title GeneratedSnapshotShapeTest
/// @notice THE EXEMPLAR OWNS THE SHAPE. THE COMPILER OWNS THE VALUES. This is
/// what makes the first half true rather than aspirational.
///
/// It checks the REAL generator's committed output —
/// `src/generated/candidate/AddressRegistry.sol`, written by
/// `script/Build.sol` — against `test/exemplars/`, which is hand-written.
///
/// The independence is the whole instrument. The exemplar is evidence about the
/// generator precisely because the generator did not emit it: a helper that
/// regenerated exemplars through `LibCodeGen` and `LibFs` — the emitters
/// `Build.sol` itself uses — would reduce every assertion below to "the
/// generator is deterministic", which nobody doubted. So the exemplars are
/// maintained by hand and this reads both files as text.
///
/// It asserts NAMED STRUCTURAL PROPERTIES rather than diffing whole files. A
/// diff fails for reasons nobody can read, and one exemplar compared once is
/// already a weak instrument; naming each property means a failure says which
/// one broke. Values are deliberately not compared — the two files describe
/// different contracts, and a solc bump moves every literal in both without
/// changing anything this test is about.
contract GeneratedSnapshotShapeTest is Test {
    /// The real generator's output, as committed.
    /// @return The file contents.
    function generated() internal view returns (string memory) {
        return vm.readFile("src/generated/candidate/AddressRegistry.sol");
    }

    /// The hand-written exemplar.
    /// @return The file contents.
    function exemplar() internal view returns (string memory) {
        return vm.readFile("test/exemplars/0_0_1/MockDeployable.sol");
    }

    /// The ordered constant DECLARATIONS in a file, values stripped:
    /// `bytes32 constant BYTECODE_HASH` and so on. This is the shape.
    /// @param content The file to read.
    /// @return declarations One entry per constant, in file order.
    function constantDeclarations(string memory content) internal pure returns (string[] memory declarations) {
        string[] memory lines = vm.split(content, "\n");
        string[] memory found = new string[](lines.length);
        uint256 count = 0;
        for (uint256 i = 0; i < lines.length; i++) {
            // A declaration line, not a comment describing one.
            if (!vm.contains(lines[i], " constant ") || vm.contains(lines[i], "//")) {
                continue;
            }
            // Everything before the assignment is the declaration; everything
            // after it is a value, which this test has no opinion about.
            found[count] = vm.split(lines[i], " =")[0];
            count++;
        }
        declarations = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            declarations[i] = found[i];
        }
    }

    /// PROPERTY: the generator emits exactly the four constants a deploy
    /// snapshot is for, in this order. Named literally, because the exemplar's
    /// authority comes from a human having written down what a snapshot SHOULD
    /// be — not from whatever the generator currently does.
    function testGeneratorEmitsTheDeploySnapshotConstantsInOrder() external view {
        string[] memory declarations = constantDeclarations(generated());

        assertEq(declarations.length, 4, "generator emitted an unexpected number of constants");
        assertEq(declarations[0], "bytes32 constant BYTECODE_HASH");
        assertEq(declarations[1], "address constant DEPLOYED_ADDRESS");
        assertEq(declarations[2], "bytes constant CREATION_CODE");
        assertEq(declarations[3], "bytes constant RUNTIME_CODE");
    }

    /// PROPERTY: the exemplar declares the same constants, of the same types,
    /// in the same order, as the generator's real output. This is the
    /// conformance itself — a fifth constant, a rename, a reorder or a changed
    /// type breaks it, and none of those is something a compiler can cause.
    function testExemplarDeclaresWhatTheGeneratorEmits() external view {
        string[] memory fromGenerator = constantDeclarations(generated());
        string[] memory fromExemplar = constantDeclarations(exemplar());

        assertEq(fromExemplar.length, fromGenerator.length, "exemplar and generator disagree on constant count");
        for (uint256 i = 0; i < fromGenerator.length; i++) {
            assertEq(fromExemplar[i], fromGenerator[i]);
        }
    }

    /// PROPERTY: both carry the generated-file header. It is what tells a
    /// reader the file is not to be hand-edited, and an exemplar without it
    /// would be describing something the generator does not produce.
    function testBothCarryTheGeneratedHeader() external view {
        string memory header = "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.";
        assertTrue(vm.contains(generated(), header), "generator stopped emitting the header");
        assertTrue(vm.contains(exemplar(), header), "exemplar is missing the generated header");
    }

    /// PROPERTY: a snapshot references no source contract. It is read by repos
    /// that do not have that source — which is the whole reason a frozen
    /// release stays verifiable after its contract has changed or gone — so an
    /// import, or the contract's own name, would make it unusable.
    function testNeitherReferencesASourceContract() external view {
        assertFalse(vm.contains(generated(), "import "), "generator emitted an import");
        assertFalse(vm.contains(generated(), "AddressRegistry"), "generator referenced its source contract");

        assertFalse(vm.contains(exemplar(), "import "), "exemplar carries an import");
        assertFalse(vm.contains(exemplar(), "MockDeployable"), "exemplar references a source contract");
    }

    /// PROPERTY: the exemplar carries the operating rule, because the rule is
    /// what someone reads when this suite goes red.
    function testExemplarCarriesTheOperatingRule() external view {
        assertTrue(
            vm.contains(exemplar(), "THE EXEMPLAR OWNS THE SHAPE. THE COMPILER OWNS THE VALUES."),
            "exemplar is missing the operating rule"
        );
        assertTrue(vm.contains(exemplar(), "This file is HAND-WRITTEN"), "exemplar no longer states it is hand-written");
    }
}
