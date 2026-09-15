// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {CreditHyperCore} from "../../script/CreditHyperCore.sol";

/// @title CreditHyperCoreTest
/// @notice The three lines of `script/CreditHyperCore.sol` that move real money,
/// asserted as a shape rather than driven.
///
/// THESE ASSERTIONS ARE THE SPECIFICATION of that body: the deployer is the key
/// `DEPLOYMENT_KEY` holds, the amount is what `HYPERCORE_CREDIT_WEI` holds, and
/// those two go to the `LibHyperCore` entry that takes the HyperEVM fork itself.
/// Both names are the ones `.github/workflows/manual-credit-hypercore.yaml`
/// exports to the step that runs this script, so they are a contract with the
/// dispatcher rather than a copy of the implementation: a read of any other name
/// is a dispatch that arrives with the variable it needs unset.
///
/// Driven is what this cannot be. `run()` reads `DEPLOYMENT_KEY`, so a test that
/// drove it would `vm.setEnv` a process-wide variable that `rainix-sol-test`
/// exports onto the job and that `RainDeployBroadcastTest` already sequences its
/// own writes of, having lost that race once already. Nothing here writes an env
/// var, forks anything or reaches an RPC.
///
/// The compiler's AST rather than the source text, for the reason
/// `GeneratedSnapshotShapeTest` reads it: this is about the body's STRUCTURE and
/// not its formatting. Here there is a second reason — both env names appear
/// repeatedly in the NatSpec above the body, so a text search for either is
/// satisfied by a comment while the line that reads it says something else.
contract CreditHyperCoreTest is Test {
    /// The artifact forge writes for the script, which carries the AST because
    /// `foundry.toml` sets `ast = true`.
    string constant ARTIFACT_PATH = "out/CreditHyperCore.sol/CreditHyperCore.json";

    /// The source file that AST has to be describing.
    string constant SOURCE_PATH = "script/CreditHyperCore.sol";

    /// The artifact JSON.
    /// @return The whole file.
    function artifact() internal view returns (string memory) {
        return vm.readFile(ARTIFACT_PATH);
    }

    /// The JSON path of the source unit's only contract.
    ///
    /// Walked rather than indexed: the top-level nodes are the pragma, the
    /// imports and then the contract, so an import added or removed moves the
    /// index of everything asserted below.
    /// @param json The artifact JSON.
    /// @return The path.
    function contractNodePath(string memory json) internal view returns (string memory) {
        string memory found = "";
        uint256 count = 0;
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat("$.ast.nodes[", vm.toString(i), "].nodeType")); i++) {
            string memory path = string.concat("$.ast.nodes[", vm.toString(i), "]");
            if (
                keccak256(bytes(vm.parseJsonString(json, string.concat(path, ".nodeType"))))
                    == keccak256("ContractDefinition")
            ) {
                found = path;
                count++;
            }
        }

        assertEq(count, 1, "the script does not declare exactly one contract");
        assertEq(
            vm.parseJsonString(json, string.concat(found, ".name")), "CreditHyperCore", "the contract is not the one"
        );
        return found;
    }

    /// The JSON path of `run`'s node.
    /// @param json The artifact JSON.
    /// @return The path.
    function runNodePath(string memory json) internal view returns (string memory) {
        string memory contractPath = contractNodePath(json);
        string memory found = "";
        uint256 count = 0;
        for (
            uint256 i = 0;
            vm.keyExistsJson(json, string.concat(contractPath, ".nodes[", vm.toString(i), "].nodeType"));
            i++
        ) {
            string memory path = string.concat(contractPath, ".nodes[", vm.toString(i), "]");
            if (
                keccak256(bytes(vm.parseJsonString(json, string.concat(path, ".nodeType"))))
                        == keccak256("FunctionDefinition")
                    && keccak256(bytes(vm.parseJsonString(json, string.concat(path, ".name")))) == keccak256("run")
            ) {
                found = path;
                count++;
            }
        }

        assertEq(count, 1, "the script does not declare exactly one run()");
        return found;
    }

    /// The JSON path of one statement of `run`'s body.
    /// @param json The artifact JSON.
    /// @param index The statement's position in the body.
    /// @return The path.
    function statementPath(string memory json, uint256 index) internal view returns (string memory) {
        return string.concat(runNodePath(json), ".body.statements[", vm.toString(index), "]");
    }

    /// PROPERTY: the AST every assertion here reads is the compiled
    /// `script/CreditHyperCore.sol`, and that file is the contract this test
    /// imports.
    ///
    /// Everything below is a claim about a file named by a hard-coded path. An
    /// artifact left behind by a moved or renamed source parses exactly as well
    /// as a live one, and every assertion would then hold about a file no
    /// dispatch runs. The creation code is what ties the JSON to the contract
    /// this suite compiled — and the import that lets it be written is also what
    /// puts the script into the compilation at all, since nothing else under
    /// `test/` reaches it and `forge test` compiles what the tests import.
    function testTheAstIsThisScriptsOwn() external view {
        assertEq(
            vm.parseJsonString(artifact(), "$.ast.absolutePath"), SOURCE_PATH, "the artifact describes another file"
        );
        assertEq(
            keccak256(vm.getCode(string.concat(SOURCE_PATH, ":CreditHyperCore"))),
            keccak256(type(CreditHyperCore).creationCode),
            "the artifact is not this contract"
        );
    }

    /// PROPERTY: the script is `run()` and nothing else, and `run()` is exactly
    /// three statements.
    ///
    /// Every other assertion here addresses a statement by position, and a loop
    /// over three statements says nothing about a fourth. A second member, or a
    /// fourth line, is code in a real-money script that nothing in this repo
    /// looks at — and `forge script` runs the body it is pointed at whatever is
    /// in it.
    function testTheScriptIsExactlyRunAndRunIsExactlyThreeStatements() external view {
        string memory json = artifact();

        assertEq(runNodePath(json), string.concat(contractNodePath(json), ".nodes[0]"), "run() is not the first member");
        assertFalse(
            vm.keyExistsJson(json, string.concat(contractNodePath(json), ".nodes[1]")),
            "the script declares something besides run()"
        );

        assertTrue(vm.keyExistsJson(json, statementPath(json, 2)), "run() is fewer than three statements");
        assertFalse(vm.keyExistsJson(json, statementPath(json, 3)), "run() has a fourth statement");
    }

    /// PROPERTY: the deployer is `DEPLOYMENT_KEY`, read with no default and
    /// turned into an `address` before anything else sees it.
    ///
    /// `vm.envUint` rather than `vm.envOr` is the no-default half: a key that
    /// fell back would sign as an address nobody chose and nobody funded, and
    /// the dispatch would fail on gas rather than on the missing secret.
    ///
    /// `address` rather than `uint256` is the transposition half — the reason
    /// the key gets a line of its own. Both env reads are `uint256`, so a key
    /// and an amount swapped between them would send a private key's worth of
    /// HYPE; once the key is an `address` the two arguments do not have the same
    /// type and the swap does not compile. That defence is a property of the
    /// declared TYPE, so it is asserted here rather than assumed to stay.
    ///
    /// The name itself is what nothing could see before. A read of any other
    /// name compiles, and `LibHyperCore` refuses what follows for a reason —
    /// `InsufficientBalance` against an address derived from whatever that
    /// variable held — that names neither this file nor the variable.
    function testTheDeployerIsTheDeploymentKeyAsAnAddress() external view {
        string memory json = artifact();
        string memory statement = statementPath(json, 0);

        assertEq(
            vm.parseJsonString(json, string.concat(statement, ".nodeType")),
            "VariableDeclarationStatement",
            "the first statement does not declare the deployer"
        );
        assertEq(
            vm.parseJsonString(json, string.concat(statement, ".declarations[0].typeName.name")),
            "address",
            "the deployer is not an address"
        );

        assertEq(
            vm.parseJsonString(json, string.concat(statement, ".initialValue.expression.expression.name")),
            "vm",
            "the key is not turned into an address by the cheatcode vm"
        );
        assertEq(
            vm.parseJsonString(json, string.concat(statement, ".initialValue.expression.memberName")),
            "rememberKey",
            "the deployer is not the wallet the key derives"
        );

        string memory read = string.concat(statement, ".initialValue.arguments[0]");
        assertEq(
            vm.parseJsonString(json, string.concat(read, ".expression.memberName")),
            "envUint",
            "the key is read with something other than envUint"
        );
        assertEq(
            vm.parseJsonString(json, string.concat(read, ".arguments[0].value")),
            "DEPLOYMENT_KEY",
            "the key is read from the wrong variable"
        );
    }

    /// PROPERTY: the amount is `HYPERCORE_CREDIT_WEI`, read with no default.
    ///
    /// Required rather than defaulted is the whole of the amount's design: a
    /// default is an amount of real money nobody typed, and `vm.envOr` is the
    /// one-line edit that installs one. A zero default is refused downstream by
    /// `LibHyperCore.ZeroCredit`, but every other default is spent.
    ///
    /// The name is the other half, and it is the half `LibHyperCore` cannot
    /// check: the workflow's typed `credit-wei` input arrives under this name
    /// and nothing else carries it, so a read of another name is a dispatch that
    /// credits whatever that variable happened to hold.
    function testTheAmountIsHyperCoreCreditWeiWithNoDefault() external view {
        string memory json = artifact();
        string memory statement = statementPath(json, 1);

        assertEq(
            vm.parseJsonString(json, string.concat(statement, ".nodeType")),
            "VariableDeclarationStatement",
            "the second statement does not declare the amount"
        );
        assertEq(
            vm.parseJsonString(json, string.concat(statement, ".declarations[0].typeName.name")),
            "uint256",
            "the amount is not a uint256"
        );
        assertEq(
            vm.parseJsonString(json, string.concat(statement, ".initialValue.expression.memberName")),
            "envUint",
            "the amount is read with something other than envUint"
        );
        assertEq(
            vm.parseJsonString(json, string.concat(statement, ".initialValue.arguments[0].value")),
            "HYPERCORE_CREDIT_WEI",
            "the amount is read from the wrong variable"
        );
    }

    /// PROPERTY: the credit goes through `creditCoreOnHyperEvm`, carrying the
    /// deployer of the first statement and the amount of the second.
    ///
    /// `creditCore` is the sibling that credits on the SELECTED chain and it is
    /// one word shorter, so dropping the fork selection is a one-line edit that
    /// compiles and that no guard in `LibHyperCore` can distinguish from a
    /// caller that meant it. What it costs is the whole point of the alias:
    /// `creditCoreOnHyperEvm` is where `hyperevm` — the repo's own declaration
    /// of which endpoint HyperEVM is — is read, so without it the script credits
    /// on whatever chain forge happened to be on, which for a dispatch is no
    /// chain at all.
    ///
    /// The two arguments are matched to the declarations they must come from by
    /// AST id rather than by identifier text, so a rename of either local is not
    /// a failure here and a call reaching for some other value is. That they are
    /// identifiers at all is asserted first: an argument computed at the call
    /// site has no declaration to match, and would otherwise fail as a cheatcode
    /// revert naming a JSON path rather than as the wiring defect it is.
    function testTheCreditTakesTheHyperEvmForkWithBothReads() external view {
        string memory json = artifact();
        string memory call = string.concat(statementPath(json, 2), ".expression");

        assertEq(
            vm.parseJsonString(json, string.concat(call, ".expression.expression.name")),
            "LibHyperCore",
            "the credit is not LibHyperCore's"
        );
        assertEq(
            vm.parseJsonString(json, string.concat(call, ".expression.memberName")),
            "creditCoreOnHyperEvm",
            "the credit does not take the hyperevm fork"
        );

        assertEq(
            vm.parseJsonString(json, string.concat(call, ".arguments[0].name")), "vm", "the credit is not given vm"
        );
        assertEq(
            vm.parseJsonString(json, string.concat(call, ".arguments[1].nodeType")),
            "Identifier",
            "the account credited is computed at the call rather than declared"
        );
        assertEq(
            vm.parseJsonString(json, string.concat(call, ".arguments[2].nodeType")),
            "Identifier",
            "the amount sent is computed at the call rather than declared"
        );
        assertEq(
            vm.parseJsonUint(json, string.concat(call, ".arguments[1].referencedDeclaration")),
            vm.parseJsonUint(json, string.concat(statementPath(json, 0), ".declarations[0].id")),
            "the account credited is not the deployer the key derives"
        );
        assertEq(
            vm.parseJsonUint(json, string.concat(call, ".arguments[2].referencedDeclaration")),
            vm.parseJsonUint(json, string.concat(statementPath(json, 1), ".declarations[0].id")),
            "the amount sent is not the one the env read holds"
        );
        assertFalse(
            vm.keyExistsJson(json, string.concat(call, ".arguments[3]")), "the credit is given a fourth argument"
        );
    }
}
