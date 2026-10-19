// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ZoltuDerivationMismatch} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {
    CandidateSourceMismatch,
    DeployCandidate,
    DeployDependency,
    DeployMechanism,
    DeploySuite
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    FrozenCodeRecordAmbiguous,
    FrozenCodeRecordDeclaresDeployedAddress,
    FrozenCodeRecordInconsistent,
    FrozenCodeRecordUnreadable,
    FrozenSnapshotNotReleased,
    FrozenSnapshotsOutnumberReleases,
    RainDeployVerifySnapshotBase,
    StoredAddressMismatch,
    StoredCodeHashMismatch,
    StoredRuntimeCodeHashMismatch
} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {
    FrozenSnapshotAmbiguous,
    FrozenSnapshotUnreadable,
    LibRainDeploySnapshot
} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
import {PER_NETWORK_CLONE_RECORD_ROOT} from "../../abstract/PerNetworkCloneDeploys.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {SourceMismatchDeploy} from "../../concrete/SourceMismatchDeploy.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../../src/generated/candidate/AddressRegistry.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_0_1_10_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_0_1_10_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_0_1_10_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_0_1_10_RUNTIME_CODE
} from "../../../src/generated/0_1_10/AddressRegistry.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_0_1_11_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_0_1_11_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_0_1_11_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_0_1_11_RUNTIME_CODE
} from "../../../src/generated/0_1_11/AddressRegistry.sol";

/// @title RainDeployVerifySnapshotBaseTest
/// @notice `RainDeployVerifySnapshotBase` inherited by a exemplar repo, so the
/// inherited tests themselves are the passing case: `ExampleDeploySuites`
/// declares two frozen releases and two candidates, and
/// `testSnapshotInternallyConsistent` /
/// `testSnapshotMatchesSource` run over them here exactly as they
/// would in a consumer.
///
/// The base rather than `RainDeployVerifySnapshot`, because that one adds
/// `testEveryFrozenSnapshotIsReleased`, whose subject is THIS repo's real
/// frozen record and never the declaration of whatever inherits it. Every
/// exemplar suite here is a fixture, so inheriting that test would assert that
/// this repo's real releases are declared by the exemplar — a claim that is
/// vacuously true while the repo has released nothing and false from its first
/// release, which is not a thing this contract is about either way. The real
/// record is bound where the real declaration is, in `RegistryDeployVerifyTest`.
///
/// The record check ITSELF is exercised here, at every position and against
/// every shape of declaration, because `checkFrozenSnapshotsReleased` takes the
/// record as an argument and so can be handed one this contract builds.
///
/// The rest is what each group CATCHES, and — for the internal group — what it
/// provably does not. Every case drives the same internal functions the
/// inherited tests do, at a call depth `vm.expectRevert` lands at.
///
/// The groups that take their subject as an argument are driven with the
/// exemplar data deliberately broken one field at a time. The source anchor
/// takes none: it reads the declaration, because `RainDeployBroadcast` runs it
/// with nothing to hand it. Its negative case is therefore a whole broken
/// DECLARATION — `SourceMismatchDeploy` — which is also the shape a repo holding
/// a stale generated file is actually in.
contract RainDeployVerifySnapshotBaseTest is ExampleDeploySuites, RainDeployVerifySnapshotBase {
    /// A declaration whose second candidate is a consistent snapshot of the
    /// wrong contract.
    ///
    /// A whole declaration rather than a candidate built here, because the
    /// source anchor reads the declaration itself — it has to, so that the
    /// broadcast can run the same definition without being handed anything.
    /// A set passed in as an argument would be a set only a test can supply.
    SourceMismatchDeploy internal sMismatch;

    /// The broken declaration, as a repo holding a stale generated file has it.
    function setUp() external {
        sMismatch = new SourceMismatchDeploy();
    }

    /// External wrapper for `checkInternallyConsistent` so `vm.expectRevert`
    /// works at the correct call depth.
    /// @param suite The suite to check.
    function externalCheckInternallyConsistent(DeploySuite memory suite) external {
        checkInternallyConsistent(suite);
    }

    /// External wrapper for `checkFrozenSnapshotsReleased` so `vm.expectRevert`
    /// works at the correct call depth.
    /// @param paths The frozen record's files.
    /// @param released The declared released suites.
    function externalCheckFrozenSnapshotsReleased(string[] memory paths, DeploySuite[] memory released) external view {
        checkFrozenSnapshotsReleased(paths, released);
    }

    /// External wrapper for `recordedDeployedAddresses` so `vm.expectRevert` works at the correct
    /// call depth, for a record declaring ONE `DEPLOYED_ADDRESS`.
    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    /// @return The address the record declares.
    function externalRecordedDeployedAddress(string memory path, string memory record) external pure returns (address) {
        (uint256[] memory chainIds, address[] memory addresses) =
            LibRainDeploySnapshot.recordedDeployedAddresses(vm, path, record);
        assertEq(chainIds.length, 0);
        assertEq(addresses.length, 1);
        return addresses[0];
    }

    /// A one-address list, as `FrozenSnapshotsOutnumberReleases` carries a record that declares
    /// `DEPLOYED_ADDRESS`.
    /// @param deployedAddress The address.
    /// @return The list.
    function oneAddress(address deployedAddress) internal pure returns (address[] memory) {
        address[] memory addresses = new address[](1);
        addresses[0] = deployedAddress;
        return addresses;
    }

    /// External wrapper for `checkFrozenCodeRecord` so `vm.expectRevert` works
    /// at the correct call depth.
    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    function externalCheckFrozenCodeRecord(string memory path, string memory record) external pure {
        checkFrozenCodeRecord(path, record);
    }

    /// External wrapper for `partitionFrozenRecords`.
    /// @param paths The frozen record's files.
    /// @param codeRecordNames The code records' names.
    /// @return The deploy records.
    /// @return The code records.
    function externalPartitionFrozenRecords(string[] memory paths, string[] memory codeRecordNames)
        external
        pure
        returns (string[] memory, string[] memory)
    {
        return partitionFrozenRecords(paths, codeRecordNames);
    }

    /// The real generated snapshot, standing in for a frozen record. It is the
    /// same file a freeze copies into `src/generated/<tag>/`, and the exemplar's
    /// first released suite is declared from it, so the pair below is a real
    /// record checked against a real declaration.
    /// @return The one-file record.
    function recordOfTheGeneratedSnapshot() internal pure returns (string[] memory) {
        string[] memory paths = new string[](1);
        paths[0] = LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "AddressRegistry");
        return paths;
    }

    /// A record of BOTH committed snapshots. `AddressRegistry` is what the
    /// exemplar's first released suite derives; `MigrationRegistry` is declared
    /// by no released suite here, so it is a real record file that really is
    /// undeclared, and the undeclared one is the LAST.
    /// @return The two-file record.
    function recordOfBothGeneratedSnapshots() internal pure returns (string[] memory) {
        string[] memory paths = new string[](2);
        paths[0] = LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "AddressRegistry");
        paths[1] = LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "MigrationRegistry");
        return paths;
    }

    /// A record declared by a released suite MUST pass, so the failing cases
    /// below are discriminating rather than a check that cannot succeed.
    function testFrozenSnapshotDeclaredPasses() external view {
        this.externalCheckFrozenSnapshotsReleased(recordOfTheGeneratedSnapshot(), releasedSuites());
    }

    /// A release in the record that the declaration does not name MUST fail,
    /// naming the file. This is the hole the check exists for: nothing else
    /// mentions that release, so without this it is simply never checked again
    /// and every other assertion stays green.
    function testFrozenSnapshotUndeclaredReverts() external {
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, recordOfTheGeneratedSnapshot()[0]));
        this.externalCheckFrozenSnapshotsReleased(recordOfTheGeneratedSnapshot(), new DeploySuite[](0));
    }

    /// The match MUST be against what each suite's creation code derives, not
    /// merely against a declaration existing. A repo that declares SOME
    /// releases and misses one is the case that actually happens, and it is
    /// indistinguishable from a full declaration to anything that only counts.
    function testFrozenSnapshotDeclaredByAnotherSuiteReverts() external {
        DeploySuite[] memory wrongRelease = new DeploySuite[](1);
        wrongRelease[0] = releasedSuites()[1];
        assertEq(wrongRelease[0].suite, "second-address");

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, recordOfTheGeneratedSnapshot()[0]));
        this.externalCheckFrozenSnapshotsReleased(recordOfTheGeneratedSnapshot(), wrongRelease);
    }

    function recordOfTheTwinReleases() internal pure returns (string[] memory) {
        string[] memory paths = new string[](2);
        paths[0] = LibRainDeploySnapshot.pathForSnapshot("0_1_10", "AddressRegistry");
        paths[1] = LibRainDeploySnapshot.pathForSnapshot("0_1_11", "AddressRegistry");
        return paths;
    }

    function declaredOlderTwin() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "address-registry@0_1_10",
            creationCode: ADDRESS_REGISTRY_0_1_10_CREATION_CODE,
            storedDeployedAddress: ADDRESS_REGISTRY_0_1_10_DEPLOYED_ADDRESS,
            storedBytecodeHash: ADDRESS_REGISTRY_0_1_10_BYTECODE_HASH,
            storedRuntimeCode: ADDRESS_REGISTRY_0_1_10_RUNTIME_CODE,
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
    }

    function declaredNewerTwin() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "address-registry@0_1_11",
            creationCode: ADDRESS_REGISTRY_0_1_11_CREATION_CODE,
            storedDeployedAddress: ADDRESS_REGISTRY_0_1_11_DEPLOYED_ADDRESS,
            storedBytecodeHash: ADDRESS_REGISTRY_0_1_11_BYTECODE_HASH,
            storedRuntimeCode: ADDRESS_REGISTRY_0_1_11_RUNTIME_CODE,
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
    }

    function testTwinReleasesFrozeTheSameCreationCode() external pure {
        assertEq(keccak256(ADDRESS_REGISTRY_0_1_10_CREATION_CODE), keccak256(ADDRESS_REGISTRY_0_1_11_CREATION_CODE));
        assertEq(ADDRESS_REGISTRY_0_1_10_DEPLOYED_ADDRESS, ADDRESS_REGISTRY_0_1_11_DEPLOYED_ADDRESS);
        assertEq(
            LibRainDeploy.zoltuAddress(ADDRESS_REGISTRY_0_1_10_CREATION_CODE),
            LibRainDeploy.zoltuAddress(ADDRESS_REGISTRY_0_1_11_CREATION_CODE)
        );
    }

    function testFrozenSnapshotTwinReleaseDroppedFromTheDeclarationReverts() external {
        DeploySuite[] memory released = new DeploySuite[](1);
        released[0] = declaredNewerTwin();

        vm.expectRevert(
            abi.encodeWithSelector(
                FrozenSnapshotsOutnumberReleases.selector,
                recordOfTheTwinReleases()[1],
                oneAddress(ADDRESS_REGISTRY_0_1_11_DEPLOYED_ADDRESS),
                uint256(2),
                uint256(1)
            )
        );
        this.externalCheckFrozenSnapshotsReleased(recordOfTheTwinReleases(), released);
    }

    function testFrozenSnapshotTwinReleasesBothDeclaredPasses() external view {
        DeploySuite[] memory released = new DeploySuite[](2);
        released[0] = declaredOlderTwin();
        released[1] = declaredNewerTwin();

        this.externalCheckFrozenSnapshotsReleased(recordOfTheTwinReleases(), released);
    }

    function testFrozenSnapshotMoreDeclarationsThanRecordFilesPasses() external view {
        string[] memory paths = new string[](1);
        paths[0] = recordOfTheTwinReleases()[1];

        DeploySuite[] memory released = new DeploySuite[](2);
        released[0] = declaredOlderTwin();
        released[1] = declaredNewerTwin();

        this.externalCheckFrozenSnapshotsReleased(paths, released);
    }

    /// A record in the generated shape that DECLARES one address and merely
    /// mentions another — in a comment, and in a second address constant.
    /// @param declared The address the record declares as its deploy address.
    /// @param mentioned The address the record only mentions.
    /// @return The record's contents.
    function recordDeclaring(address declared, address mentioned) internal pure returns (string memory) {
        return string.concat(
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            "/// @dev The deterministic deploy address of the contract, which is not\n/// ",
            vm.toString(mentioned),
            ".\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(declared),
            ");\n\n",
            "/// @dev Some other address this record carries.\n",
            "address constant OTHER_ADDRESS = address(",
            vm.toString(mentioned),
            ");\n"
        );
    }

    /// The address a record is matched on MUST be the one it DECLARES, never
    /// one that merely appears in its text. A record is two hex payloads
    /// thousands of digits long plus a comment or two, so "this address occurs
    /// somewhere in the file" is a question about characters rather than about
    /// what was deployed — and it answers yes for a release the declaration
    /// never named.
    ///
    /// Driven at the read rather than through a record on disk: a record whose
    /// text carries a released address it does not declare cannot be built out
    /// of this repo's real snapshots without grinding creation code for one,
    /// and a `.sol` fixture left behind by a failed run is a file the next
    /// build has to compile.
    function testFrozenSnapshotMatchesTheDeclarationNotTheText() external view {
        address released = LibRainDeploy.zoltuAddress(releasedSuites()[0].creationCode);
        assertEq(released, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        string memory record = recordDeclaring(address(0xdead), released);
        // The released address really is in there.
        assertTrue(vm.contains(record, vm.toString(released)));

        assertEq(this.externalRecordedDeployedAddress("record.sol", record), address(0xdead));
    }

    /// A record in the generated shape whose real declaration is preceded by a
    /// COMMENTED OUT one. The commented line is the declaration text verbatim,
    /// which is what separates this from a prose mention of an address.
    /// @param declared The address the record's real declaration carries.
    /// @param commented The address the commented-out declaration carries.
    /// @return The record's contents.
    function recordCommentingOutADeclaration(address declared, address commented)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            "/// @dev The deterministic deploy address of the contract.\n",
            "// address constant DEPLOYED_ADDRESS = address(",
            vm.toString(commented),
            ");\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(declared),
            ");\n"
        );
    }

    /// The declaration a record is read from MUST be the one the COMPILER
    /// would read. A commented-out declaration is text, and taking it would let
    /// a hand edit park a released address above a real declaration carrying
    /// something else — the file would then match a released suite while
    /// declaring an address no suite derives, which is precisely the hand edit
    /// this group exists to catch. The parser cannot be the thing that swallows
    /// it.
    function testFrozenSnapshotIgnoresACommentedOutDeclaration() external view {
        address released = LibRainDeploy.zoltuAddress(releasedSuites()[0].creationCode);
        assertEq(released, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        string memory record = recordCommentingOutADeclaration(address(0xdead), released);
        // The commented-out line really is the declaration text, carrying the
        // released address: only its position makes it a comment.
        assertTrue(vm.contains(record, string.concat("// ", LibRainDeploySnapshot.DEPLOYED_ADDRESS_DECLARATION)));
        assertTrue(vm.contains(record, vm.toString(released)));

        assertEq(this.externalRecordedDeployedAddress("record.sol", record), address(0xdead));
    }

    /// A record in the generated shape whose real declaration is preceded by a
    /// BLOCK COMMENTED OUT one. The commented copy is the declaration text
    /// verbatim and it STARTS its line, because `/*` and `*/` sit on their own
    /// lines rather than in front of what they comment out.
    /// @param declared The address the record's real declaration carries.
    /// @param commented The address the block-commented declaration carries.
    /// @return The record's contents.
    function recordBlockCommentingOutADeclaration(address declared, address commented)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            "/*\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(commented),
            ");\n",
            "*/\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(declared),
            ");\n"
        );
    }

    /// A BLOCK commented declaration MUST be ignored exactly as a `//` one is.
    /// The start-of-line rule alone does not reach it: a `/* ... */` does not
    /// indent the lines it swallows, so the commented copy starts its line
    /// character for character as the real declaration does. A hand edit can
    /// therefore park a released address above a real declaration carrying an
    /// address no suite derives, and the record then matches a released suite
    /// while recording something else — the undeclared-record case this group
    /// exists to fail on, passing.
    function testFrozenSnapshotIgnoresABlockCommentedDeclaration() external view {
        address released = LibRainDeploy.zoltuAddress(releasedSuites()[0].creationCode);
        assertEq(released, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        string memory record = recordBlockCommentingOutADeclaration(address(0xdead), released);
        // The commented-out copy really is the declaration text starting a
        // line, carrying the released address: only the block around it makes
        // it a comment.
        assertTrue(
            vm.contains(
                record,
                string.concat(
                    "\n", LibRainDeploySnapshot.DEPLOYED_ADDRESS_DECLARATION, " address(", vm.toString(released)
                )
            )
        );
        assertTrue(vm.contains(record, "/*\n"));

        assertEq(this.externalRecordedDeployedAddress("record.sol", record), address(0xdead));
    }

    /// A block comment carrying NO declaration MUST leave the record readable.
    /// Dropping the comment is only correct if what surrounds it survives, and
    /// a reader that gave up at the first `/*` would report every such record
    /// unreadable rather than wrong — a record that is append-only and cannot
    /// be regenerated to suit it.
    function testFrozenSnapshotReadsPastABlockComment() external view {
        string memory record = string.concat(
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            "/*\n",
            "Prose about the deployment.\n",
            "*/\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(address(0xbeef)),
            ");\n"
        );
        assertTrue(vm.contains(record, "/*\n"));

        assertEq(this.externalRecordedDeployedAddress("record.sol", record), address(0xbeef));
    }

    /// An UNCLOSED `/*` MUST leave the record unreadable. Everything after it
    /// is comment to the compiler, so a declaration below it is a declaration
    /// no compiler reads, and reading it anyway is the same hand edit spelled
    /// with one delimiter instead of two.
    function testFrozenSnapshotWithAnUnclosedBlockCommentReverts() external {
        string memory record = string.concat(
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            "/*\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(address(0xbeef)),
            ");\n"
        );
        assertTrue(vm.contains(record, LibRainDeploySnapshot.DEPLOYED_ADDRESS_DECLARATION));
        assertFalse(vm.contains(record, "*/"));

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddress("record.sol", record);
    }

    /// TWO real declarations MUST be refused, naming the file. Solidity rejects
    /// the second one, so no compiler reads this file at all, and any rule for
    /// picking between them — first, last — hands back an address the compiler
    /// never would. Refusing is also the only answer a hand edit cannot aim at
    /// by choosing which copy to put where.
    function testFrozenSnapshotWithTwoDeclarationsReverts() external {
        address released = LibRainDeploy.zoltuAddress(releasedSuites()[0].creationCode);
        assertEq(released, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        string memory record = string.concat(
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(released),
            ");\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(address(0xdead)),
            ");\n"
        );

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotAmbiguous.selector, "record.sol"));
        this.externalRecordedDeployedAddress("record.sol", record);
    }

    /// A record in the generated shape whose declaration carries a bare hex
    /// literal, with no `address(...)` wrapper around it.
    /// @param declared The address the record declares as its deploy address.
    /// @return The record's contents.
    function recordDeclaringABareLiteral(address declared) internal pure returns (string memory) {
        return string.concat(
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            "/// @dev The deterministic deploy address of the contract.\n",
            "address constant DEPLOYED_ADDRESS = ",
            vm.toString(declared),
            ";\n"
        );
    }

    /// A declaration carrying a bare hex literal MUST read as the same address
    /// as one wrapped in `address(...)`.
    ///
    /// Both spell the same constant to the compiler, so which one a generator
    /// emits is a question about the generator rather than about what the file
    /// records — and the record reader exists to answer the second. A reader
    /// that insisted on the wrapper would report every frozen release as
    /// unreadable the day the wrapper stopped being emitted, on a record that is
    /// append-only and cannot be regenerated to suit it.
    ///
    /// Driven at the read: the wrapper this repo's generator emits is the
    /// wrapped form, so the bare form is a record no committed file is in.
    function testFrozenSnapshotReadsABareAddressLiteral() external view {
        address released = LibRainDeploy.zoltuAddress(releasedSuites()[0].creationCode);
        assertEq(released, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        string memory bare = recordDeclaringABareLiteral(released);
        string memory wrapped = recordDeclaring(released, address(0xdead));
        // The two records really do differ in the wrapper and nowhere else that
        // matters: one carries it, the other does not.
        assertTrue(
            vm.contains(
                bare, string.concat(LibRainDeploySnapshot.DEPLOYED_ADDRESS_DECLARATION, " ", vm.toString(released), ";")
            )
        );
        assertTrue(vm.contains(wrapped, string.concat(LibRainDeploySnapshot.DEPLOYED_ADDRESS_DECLARATION, " address(")));
        assertFalse(vm.contains(bare, "address("));

        assertEq(this.externalRecordedDeployedAddress("record.sol", bare), released);
        assertEq(
            this.externalRecordedDeployedAddress("record.sol", bare),
            this.externalRecordedDeployedAddress("record.sol", wrapped)
        );
    }

    /// A file in the record that declares no deploy address at all MUST fail as
    /// unreadable, naming itself. Reporting it as undeclared would send the
    /// reader to `releasedSuites()` to add an entry for something that is not a
    /// snapshot.
    function testFrozenSnapshotWithoutADeployedAddressReverts() external {
        string[] memory paths = new string[](1);
        paths[0] = "src/concrete/AddressRegistry.sol";

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, paths[0]));
        this.externalCheckFrozenSnapshotsReleased(paths, releasedSuites());
    }

    /// EVERY file in the record MUST be checked, not just the first. The
    /// undeclared file here is the LAST one, behind a declared one, so a loop
    /// that stopped after the first path would pass — and a release that
    /// dropped out of the declaration is exactly what this check exists to
    /// catch, on a record that grows one file per release.
    function testFrozenSnapshotCheckReachesEveryRecordFile() external {
        // The first really is declared, so nothing fails before the loop has to
        // advance.
        string[] memory first = new string[](1);
        first[0] = recordOfBothGeneratedSnapshots()[0];
        this.externalCheckFrozenSnapshotsReleased(first, releasedSuites());

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, recordOfBothGeneratedSnapshots()[1]));
        this.externalCheckFrozenSnapshotsReleased(recordOfBothGeneratedSnapshots(), releasedSuites());
    }

    /// An unreadable file MUST be named as the file the loop is ON. Its path is
    /// carried into the read for that error alone, so a loop that advanced but
    /// kept handing the read `paths[0]` would send the reader to a file that
    /// reads perfectly well — and every position after the first is where a
    /// record spends its life from the second release onward.
    function testFrozenSnapshotUnreadableFileIsNamedAtEveryRecordPosition() external {
        string[] memory paths = new string[](2);
        // Declared and readable, so nothing fails before the loop has to
        // advance.
        paths[0] = recordOfTheGeneratedSnapshot()[0];
        paths[1] = "src/concrete/AddressRegistry.sol";

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, paths[1]));
        this.externalCheckFrozenSnapshotsReleased(paths, releasedSuites());
    }

    /// The inner search MUST reach every released suite, not just the first.
    /// The suite that declares the record here is the LAST one, so a match that
    /// only ever looked at `released[0]` would report a declared release as
    /// undeclared and make the check unusable the moment a repo releases twice.
    function testFrozenSnapshotCheckReachesEveryReleasedSuite() external view {
        DeploySuite[] memory released = releasedSuites();
        DeploySuite[] memory reordered = new DeploySuite[](2);
        reordered[0] = released[1];
        reordered[1] = released[0];
        assertEq(reordered[1].suite, "address-registry@0_0_1");

        this.externalCheckFrozenSnapshotsReleased(recordOfTheGeneratedSnapshot(), reordered);
    }

    /// An empty declaration against a record with several files fails on the
    /// FIRST file, naming it: a repo that declared nothing is not a repo with
    /// nothing frozen, and the file it names is the one it is on rather than
    /// the last one in the record.
    function testFrozenSnapshotEmptyDeclarationFailsOnTheFirstRecordFile() external {
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, recordOfBothGeneratedSnapshots()[0]));
        this.externalCheckFrozenSnapshotsReleased(recordOfBothGeneratedSnapshots(), new DeploySuite[](0));
    }

    /// A record with no files at all is a repo that has released nothing —
    /// which is this repo's own state — and MUST pass rather than fail on a
    /// declaration it has nothing to check against. This is the deliberate
    /// opposite of the source anchor, which refuses an empty candidate list:
    /// there, an empty list is a repo whose snapshots nothing anchors; here, it
    /// is a repo that has frozen nothing yet.
    function testFrozenSnapshotEmptyRecordPasses() external view {
        this.externalCheckFrozenSnapshotsReleased(new string[](0), releasedSuites());
        this.externalCheckFrozenSnapshotsReleased(new string[](0), new DeploySuite[](0));
    }

    /// The frozen `0_0_1` release, which every negative case below breaks one
    /// field of.
    /// @return The consistent `0_0_1` suite.
    function consistentSuite() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "address-registry@0_0_1",
            creationCode: ADDRESS_REGISTRY_CREATION_CODE,
            storedDeployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            storedBytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH,
            storedRuntimeCode: ADDRESS_REGISTRY_RUNTIME_CODE,
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
    }

    /// A recorded address that is not the one the recorded creation code
    /// derives MUST fail, naming the version and both addresses. This is the
    /// hand-edited constant, and the address copied from the wrong tag.
    function testStoredAddressMismatchReverts() external {
        DeploySuite memory suite = consistentSuite();
        suite.storedDeployedAddress = address(0xdead);

        vm.expectRevert(
            abi.encodeWithSelector(
                StoredAddressMismatch.selector,
                "address-registry@0_0_1",
                address(0xdead),
                ADDRESS_REGISTRY_DEPLOYED_ADDRESS
            )
        );
        this.externalCheckInternallyConsistent(suite);
    }

    /// A recorded code hash that is not the one the recorded creation code
    /// produces MUST fail, naming the version and both hashes. This is a
    /// snapshot regenerated for one field and not the others.
    function testStoredCodeHashMismatchReverts() external {
        DeploySuite memory suite = consistentSuite();
        suite.storedBytecodeHash = bytes32(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                StoredCodeHashMismatch.selector,
                "address-registry@0_0_1",
                bytes32(uint256(1)),
                ADDRESS_REGISTRY_BYTECODE_HASH
            )
        );
        this.externalCheckInternallyConsistent(suite);
    }

    /// Recorded runtime code that does not hash to the code hash recorded
    /// beside it MUST fail, naming the version and both hashes. The address and
    /// the code hash still agree with the creation code here, so this is the
    /// only check standing between a corrupted `RUNTIME_CODE` and a green
    /// suite.
    function testStoredRuntimeCodeHashMismatchReverts() external {
        DeploySuite memory suite = consistentSuite();
        suite.storedRuntimeCode = hex"00";

        vm.expectRevert(
            abi.encodeWithSelector(
                StoredRuntimeCodeHashMismatch.selector,
                "address-registry@0_0_1",
                ADDRESS_REGISTRY_BYTECODE_HASH,
                keccak256(hex"00")
            )
        );
        this.externalCheckInternallyConsistent(suite);
    }

    /// The internal group MUST NOT catch a consistent snapshot of the wrong
    /// contract, and this pins that it does not. It is not a gap to be closed
    /// there: every internal check asks the recorded bytes to agree with each
    /// other, and the wrong contract's bytes agree with each other perfectly.
    ///
    /// Pinning the miss is what stops the internal group from being read as
    /// covering the source-anchored one, and what makes the next test the only
    /// thing standing between a stale snapshot and a green suite.
    function testWrongContractSnapshotPassesInternalConsistency() external {
        DeployCandidate memory candidate = sMismatch.externalCheckedCandidateSuites()[1];

        // It really is the wrong contract: the snapshot records `MockDeployableV2`
        // while the contract it NAMES is `MockDeployable`.
        assertEq(keccak256(candidate.snapshot.creationCode), keccak256(type(MockDeployableV2).creationCode));
        assertEq(candidate.snapshot.artifactPath, "test/concrete/MockDeployable.sol:MockDeployable");
        assertEq(keccak256(vm.getCode(candidate.snapshot.artifactPath)), keccak256(type(MockDeployable).creationCode));
        assertNotEq(keccak256(candidate.snapshot.creationCode), keccak256(vm.getCode(candidate.snapshot.artifactPath)));

        // Every internal check passes anyway.
        this.externalCheckInternallyConsistent(candidate.snapshot);
    }

    /// The source-anchored group MUST catch exactly the snapshot the internal
    /// group just let through, MUST reach every candidate to do it, and MUST
    /// name the one that failed. This is the only check in the whole suite that
    /// can catch any of it.
    ///
    /// The broken candidate is the LAST one, behind a genuinely anchored one. A
    /// loop that stops early is invisible while a repo declares one candidate
    /// and silently stops anchoring the moment it declares two — and a repo with
    /// several contracts is precisely where a snapshot generated from the wrong
    /// one comes from. The failure naming the SECOND key is what separates a
    /// loop that reached it from one that reported a fixed entry or the first.
    ///
    /// The inherited `testSnapshotMatchesSource` is the passing case: it runs
    /// this same function over `ExampleDeploySuites`.
    function testWrongContractSnapshotCaughtBySource() external {
        DeployCandidate[] memory candidates = sMismatch.externalCheckedCandidateSuites();
        assertEq(candidates.length, 2);

        // The first is genuinely anchored, so nothing fails before the loop has
        // to advance, and it is a different contract at a different address
        // rather than the same entry under two keys.
        assertEq(candidates[0].snapshot.suite, "anchored-candidate");
        assertEq(
            keccak256(candidates[0].snapshot.creationCode), keccak256(vm.getCode(candidates[0].snapshot.artifactPath))
        );
        assertNotEq(candidates[0].snapshot.storedDeployedAddress, candidates[1].snapshot.storedDeployedAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                CandidateSourceMismatch.selector,
                "mismatched-candidate",
                keccak256(type(MockDeployableV2).creationCode),
                keccak256(type(MockDeployable).creationCode)
            )
        );
        sMismatch.externalCheckCandidatesAnchoredToSource();
    }

    /// Two suites that record the SAME creation code MUST both derive, which
    /// is the ordinary state of a repo between a release and the next source
    /// change.
    function testSuitesSharingCreationCodeAllDerive() external {
        DeploySuite[] memory suites = allSuites();
        assertEq(suites.length, 4);
        assertEq(suites[0].storedDeployedAddress, suites[2].storedDeployedAddress);
        assertEq(keccak256(suites[0].creationCode), keccak256(suites[2].creationCode));

        // Neither derivation is disturbed by the other.
        this.externalCheckInternallyConsistent(suites[0]);
        this.externalCheckInternallyConsistent(suites[2]);
    }

    /// The pure address formula and the factory bytecode the derivation etches
    /// MUST agree, and a disagreement MUST be named rather than left to surface
    /// as a code hash read from an address nothing was deployed to. Forced here
    /// by making the factory report an address it did not deploy to, which is
    /// otherwise unreachable — the derivation etches the factory bytecode
    /// itself, so only a `LibRainDeploy` whose constant and formula had drifted
    /// apart could produce it.
    function testZoltuDerivationMismatchReverts() external {
        DeploySuite memory suite = consistentSuite();

        // The factory answers with an address that does have code, but is not
        // the one the creation code derives.
        vm.mockCall(
            LibRainDeploy.ZOLTU_FACTORY,
            ADDRESS_REGISTRY_CREATION_CODE,
            abi.encodePacked(bytes20(LibRainDeploy.ZOLTU_FACTORY))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ZoltuDerivationMismatch.selector,
                "address-registry@0_0_1",
                ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                LibRainDeploy.ZOLTU_FACTORY
            )
        );
        this.externalCheckInternallyConsistent(suite);
    }

    /// The record is matched on the address a released suite's creation code
    /// DERIVES, never on the address that suite RECORDS.
    ///
    /// The two are the same in a consistent set, which is what makes this worth
    /// stating: a suite whose recorded address has gone stale still deployed
    /// what its creation code deploys, so it still declares that release — and
    /// the stale field is `checkInternallyConsistent`'s to catch, with an error
    /// that names it. Matching on the recorded field instead reports a declared
    /// release as one nobody declared, and sends the reader to
    /// `releasedSuites()` to add an entry that is already there.
    ///
    /// The suite here is the record's own release with that one field broken,
    /// so the derivation is the only thing left that can match it.
    function testFrozenSnapshotMatchesTheDerivationNotTheRecordedAddress() external view {
        DeploySuite[] memory released = new DeploySuite[](1);
        released[0] = consistentSuite();
        released[0].storedDeployedAddress = address(0xdead);

        // It really is the record's release, and it really does record
        // something else.
        assertEq(LibRainDeploy.zoltuAddress(released[0].creationCode), ADDRESS_REGISTRY_DEPLOYED_ADDRESS);
        assertNotEq(released[0].storedDeployedAddress, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        this.externalCheckFrozenSnapshotsReleased(recordOfTheGeneratedSnapshot(), released);
    }

    /// The inherited internal-consistency check MUST reach EVERY declared
    /// suite.
    ///
    /// Every negative case above drives `checkInternallyConsistent` with one
    /// suite handed to it, so all of them pass on a check that only ever looked
    /// at the first — and a repo declares one suite until the day it declares
    /// several, which is the day a snapshot regenerated for one contract and
    /// not the other appears. The suite broken here is not the first, so a loop
    /// that stopped there would find nothing to fail on.
    ///
    /// Broken through the factory rather than by editing a field, because the
    /// declaration this contract inherits is the passing case for the inherited
    /// tests and cannot be broken in place. The mock is
    /// `testZoltuDerivationMismatchReverts`'s, keyed on the creation code of the
    /// suite being reached rather than of the first one.
    function testSnapshotInternallyConsistentReachesEverySuite() external {
        DeploySuite[] memory suites = allSuites();
        assertEq(suites[1].suite, "second-address");
        assertNotEq(keccak256(suites[0].creationCode), keccak256(suites[1].creationCode));

        vm.mockCall(
            LibRainDeploy.ZOLTU_FACTORY, suites[1].creationCode, abi.encodePacked(bytes20(LibRainDeploy.ZOLTU_FACTORY))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ZoltuDerivationMismatch.selector,
                "second-address",
                suites[1].storedDeployedAddress,
                LibRainDeploy.ZOLTU_FACTORY
            )
        );
        this.testSnapshotInternallyConsistent();
    }

    /// The derivation MUST clear the derived address's NONCE, not only its
    /// code.
    ///
    /// `CREATE2` collides on a non-zero nonce exactly as it does on non-empty
    /// code, and the nonce is the half that leaves nothing to see: an account
    /// with a nonce and no code reads as empty everywhere else, so a derivation
    /// that cleared only the code would report a deployment failure for a
    /// creation code that deploys perfectly well. The Zoltu factory is
    /// permissionless, so whether anything has ever transacted from the address
    /// a suite derives is nobody's to control.
    function testDerivationClearsTheDerivedNonce() external {
        DeploySuite memory suite = consistentSuite();
        vm.setNonce(suite.storedDeployedAddress, 1);
        assertEq(vm.getNonce(suite.storedDeployedAddress), 1);
        assertEq(suite.storedDeployedAddress.code.length, 0);

        this.externalCheckInternallyConsistent(suite);
    }

    /// The derivation MUST leave nothing behind. A local deploy that survived
    /// would be compared against itself by the chain-anchored group, and every
    /// network would pass whether or not anything is deployed there.
    function testDerivationLeavesNoCodeBehind() external {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            assertEq(suites[i].storedDeployedAddress.code.length, 0);
        }

        this.externalCheckInternallyConsistent(suites[0]);

        for (uint256 i = 0; i < suites.length; i++) {
            assertEq(suites[i].storedDeployedAddress.code.length, 0);
        }
    }

    /// The committed code record: the parameterised `TimelockController`
    /// snapshot, as a freeze copies it.
    /// @return Its contents.
    function committedCodeRecord() internal view returns (string memory) {
        return vm.readFile(LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "TimelockController"));
    }

    /// A real code record passes: three code constants, no deploy address, the
    /// runtime code hashing to the recorded hash.
    function testFrozenCodeRecordConsistentPasses() external view {
        this.externalCheckFrozenCodeRecord("record.sol", committedCodeRecord());
    }

    /// A declaration inside a block comment is not one the compiler reads, so it neither marks a code record as a deploy record nor makes its code constants ambiguous.
    function testFrozenCodeRecordIgnoresBlockCommentedDeclarations() external view {
        string memory record = string.concat(
            committedCodeRecord(),
            "/*\naddress constant DEPLOYED_ADDRESS = address(0x000000000000000000000000000000000000dEaD);\n",
            "bytes32 constant BYTECODE_HASH = bytes32(0x0000000000000000000000000000000000000000000000000000000000000001);\n*/\n"
        );
        this.externalCheckFrozenCodeRecord("record.sol", record);
    }

    /// A code record whose runtime code was edited no longer hashes to its
    /// recorded hash, and is refused naming both hashes.
    function testFrozenCodeRecordRuntimeEditedReverts() external {
        string memory record = committedCodeRecord();
        string[] memory parts = vm.split(record, "bytes constant RUNTIME_CODE =\n    hex\"");
        assertEq(parts.length, 2, "the record's runtime code is not where the generator writes it");
        string memory edited = string.concat(parts[0], "bytes constant RUNTIME_CODE =\n    hex\"00", parts[1]);
        vm.expectPartialRevert(FrozenCodeRecordInconsistent.selector);
        this.externalCheckFrozenCodeRecord("record.sol", edited);
    }

    /// A wrapped `bytes` declaration takes its literal only from a line in the writer's wrapped format, never from
    /// another declaration's line, even one carrying the right code.
    function testFrozenCodeRecordWrappedOntoAnotherDeclarationIsUnreadable() external {
        string memory record = committedCodeRecord();
        string[] memory parts = vm.split(record, "bytes constant RUNTIME_CODE =\n    hex\"");
        assertEq(parts.length, 2, "the record's runtime code is not where the generator writes it");
        string memory edited =
            string.concat(parts[0], "bytes constant RUNTIME_CODE =\nbytes constant OTHER_CODE = hex\"", parts[1]);
        vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
        this.externalCheckFrozenCodeRecord("record.sol", edited);
    }

    /// A code record holding a carriage return, vertical tab, form feed, NEL, LS or PS is an unreadable code record, so
    /// no code is read from it.
    function testFrozenCodeRecordHoldingAnotherLineBreakIsUnreadable() external {
        string[] memory breaks = new string[](6);
        breaks[0] = "\r";
        breaks[1] = "\x0b";
        breaks[2] = "\x0c";
        breaks[3] = "\xc2\x85";
        breaks[4] = "\xe2\x80\xa8";
        breaks[5] = "\xe2\x80\xa9";
        for (uint256 i = 0; i < breaks.length; i++) {
            string memory record = string.concat("// note", breaks[i], committedCodeRecord());
            vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
            this.externalCheckFrozenCodeRecord("record.sol", record);
        }
    }

    /// A wrapped `bytes` literal is read only from a line that starts with the writer's indent and `hex"`, never from
    /// a comment line that holds the same text further along.
    function testFrozenCodeRecordWrappedOntoACommentIsUnreadable() external {
        string memory record = committedCodeRecord();
        string[] memory parts = vm.split(record, "bytes constant RUNTIME_CODE =\n    hex\"");
        assertEq(parts.length, 2, "the record's runtime code is not where the generator writes it");
        string memory edited =
            string.concat(parts[0], "bytes constant RUNTIME_CODE =\n    //    hex\"00\";\n    hex\"", parts[1]);
        vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
        this.externalCheckFrozenCodeRecord("record.sol", edited);
    }

    /// A `bytes` literal is read from the declaration's own line only as the fourth token after `=`, never from a
    /// trailing comment the compiler ignores, while the compiled value is on the next line.
    function testFrozenCodeRecordRuntimeCodeInATrailingCommentIsUnreadable() external {
        string memory record = committedCodeRecord();
        string[] memory parts = vm.split(record, "bytes constant RUNTIME_CODE =\n    hex\"");
        assertEq(parts.length, 2, "the record's runtime code is not where the generator writes it");
        string[] memory variants = new string[](2);
        variants[0] = "bytes constant RUNTIME_CODE = // hex\"";
        variants[1] = "bytes constant RUNTIME_CODE =//hex\"";
        for (uint256 i = 0; i < variants.length; i++) {
            string[] memory rest = vm.split(parts[1], "\n");
            string memory edited = string.concat(parts[0], variants[i], rest[0], "\n    hex\"00\";");
            for (uint256 j = 1; j < rest.length; j++) {
                edited = string.concat(edited, "\n", rest[j]);
            }
            vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
            this.externalCheckFrozenCodeRecord("record.sol", edited);
        }
    }

    /// The bytecode hash is read only as the fourth token after `=`, never from a trailing comment the compiler
    /// ignores, with or without spaces around the comment.
    function testFrozenCodeRecordHashInATrailingCommentIsUnreadable() external {
        string memory record = committedCodeRecord();
        string[] memory parts = vm.split(record, "bytes32 constant BYTECODE_HASH = ");
        assertEq(parts.length, 2, "the record's bytecode hash is not where the generator writes it");
        string[] memory variants = new string[](2);
        variants[0] =
            "bytes32 constant BYTECODE_HASH = bytes32(0x0000000000000000000000000000000000000000000000000000000000000001); // ";
        variants[1] =
            "bytes32 constant BYTECODE_HASH =bytes32(0x0000000000000000000000000000000000000000000000000000000000000001);// ";
        for (uint256 i = 0; i < variants.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
            this.externalCheckFrozenCodeRecord("record.sol", string.concat(parts[0], variants[i], parts[1]));
        }
    }

    /// Replaces the rest of the line `marker` ends with `value`.
    /// @param record The record.
    /// @param marker Text that occurs once in the record.
    /// @param value The line's new rest.
    /// @return The edited record.
    function withLineRest(string memory record, string memory marker, string memory value)
        internal
        pure
        returns (string memory)
    {
        string[] memory parts = vm.split(record, marker);
        assertEq(parts.length, 2, "the marker is not where the generator writes it");
        string[] memory rest = vm.split(parts[1], "\n");
        string memory edited = string.concat(parts[0], marker, value);
        for (uint256 j = 1; j < rest.length; j++) {
            edited = string.concat(edited, "\n", rest[j]);
        }
        return edited;
    }

    /// A bytecode hash outside one `bytes32(0x...);` of 32 bytes of hex is unreadable, never a raw parse error.
    function testFrozenCodeRecordMalformedHashIsUnreadable() external {
        string[] memory values = new string[](6);
        values[0] = "bytes32(0xzz00000000000000000000000000000000000000000000000000000000000000);";
        values[1] = "bytes32(0x00000000000000000000000000000000000000000000000000000000000001);";
        values[2] = "bytes32(0x000000000000000000000000000000000000000000000000000000000000000001);";
        values[3] = "0x0000000000000000000000000000000000000000000000000000000000000001;";
        values[4] = "bytes32(0x0000000000000000000000000000000000000000000000000000000000000001;)";
        values[5] = "bytes32((0x00000000000000000000000000000000000000000000000000000000000001));";
        for (uint256 i = 0; i < values.length; i++) {
            string memory edited = withLineRest(committedCodeRecord(), "bytes32 constant BYTECODE_HASH = ", values[i]);
            vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
            this.externalCheckFrozenCodeRecord("record.sol", edited);
        }
    }

    /// A `bytes` literal holding a non-hex digit or an odd number of digits is unreadable, never a raw parse error.
    function testFrozenCodeRecordMalformedBytesIsUnreadable() external {
        string[] memory values = new string[](2);
        values[0] = "hex\"zz\";";
        values[1] = "hex\"abc\";";
        for (uint256 i = 0; i < values.length; i++) {
            string memory edited = withLineRest(committedCodeRecord(), "bytes constant RUNTIME_CODE =\n    ", values[i]);
            vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
            this.externalCheckFrozenCodeRecord("record.sol", edited);
        }
    }

    /// A declaration line holding fewer than the writer's tokens, or no `=` as its fourth, is unreadable.
    function testFrozenCodeRecordDeclarationWithoutASpacedEqualsIsUnreadable() external {
        string memory record = committedCodeRecord();
        string[] memory parts = vm.split(record, "bytes32 constant BYTECODE_HASH = ");
        assertEq(parts.length, 2, "the record's bytecode hash is not where the generator writes it");
        string[] memory variants = new string[](2);
        variants[0] = "bytes32 constant BYTECODE_HASH =";
        variants[1] = "bytes32 constant BYTECODE_HASH =  ";
        for (uint256 i = 0; i < variants.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
            this.externalCheckFrozenCodeRecord("record.sol", string.concat(parts[0], variants[i], parts[1]));
        }
    }

    /// A declaration wrapped after its `=` takes its value from a following line of exactly the writer's indent and
    /// one token, and an unwrapped `bytes` literal is read from the declaration's own line: both forms compile and pass.
    function testFrozenCodeRecordWrappedHashAndUnwrappedCodePass() external view {
        string memory record = committedCodeRecord();
        record = vm.replace(record, "bytes32 constant BYTECODE_HASH = ", "bytes32 constant BYTECODE_HASH =\n    ");
        record = vm.replace(record, "bytes constant RUNTIME_CODE =\n    hex\"", "bytes constant RUNTIME_CODE = hex\"");
        this.externalCheckFrozenCodeRecord("record.sol", record);
    }

    /// A wrapped value line with another indent, or more than one token, is unreadable.
    function testFrozenCodeRecordWrappedOntoAnotherFormatIsUnreadable() external {
        string memory record = committedCodeRecord();
        string[] memory parts = vm.split(record, "bytes constant RUNTIME_CODE =\n    hex\"");
        assertEq(parts.length, 2, "the record's runtime code is not where the generator writes it");
        string[] memory variants = new string[](5);
        variants[0] = "bytes constant RUNTIME_CODE =\n   hex\"";
        variants[1] = "bytes constant RUNTIME_CODE =\n     hex\"";
        variants[2] = "bytes constant RUNTIME_CODE =\n    x hex\"";
        variants[3] = "bytes constant RUNTIME_CODE =\n    xhex\"";
        variants[4] = "bytes constant RUNTIME_CODE =\nx    hex\"";
        for (uint256 i = 0; i < variants.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
            this.externalCheckFrozenCodeRecord("record.sol", string.concat(parts[0], variants[i], parts[1]));
        }
    }

    /// A `bytes` declaration wrapped after its `=` on the record's last line has no value, and is unreadable.
    function testFrozenCodeRecordWrappedAtTheEndOfTheRecordIsUnreadable() external {
        string[] memory parts = vm.split(committedCodeRecord(), "bytes constant RUNTIME_CODE =\n    hex\"");
        assertEq(parts.length, 2, "the record's runtime code is not where the generator writes it");
        vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
        this.externalCheckFrozenCodeRecord("record.sol", string.concat(parts[0], "bytes constant RUNTIME_CODE ="));
    }

    /// A value token holding a second `hex"` literal, which the compiler concatenates, is unreadable rather than read
    /// as its first literal.
    function testFrozenCodeRecordConcatenatedLiteralIsUnreadable() external {
        string memory record = committedCodeRecord();
        string[] memory parts = vm.split(record, "bytes constant RUNTIME_CODE =\n    hex\"");
        assertEq(parts.length, 2, "the record's runtime code is not where the generator writes it");
        string[] memory rest = vm.split(parts[1], "\"");
        string memory edited = string.concat(parts[0], "bytes constant RUNTIME_CODE =\n    hex\"", rest[0], "\"hex\"00");
        for (uint256 j = 1; j < rest.length; j++) {
            edited = string.concat(edited, "\"", rest[j]);
        }
        vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
        this.externalCheckFrozenCodeRecord("record.sol", edited);
    }

    /// A `bytes` literal followed by anything but the writer's `;`, or with no closing quote, is unreadable, for
    /// `CREATION_CODE` and `RUNTIME_CODE` alike.
    function testFrozenCodeRecordLiteralNotEndingInTheWritersSemicolonIsUnreadable() external {
        string[] memory declarations = new string[](2);
        declarations[0] = "bytes constant CREATION_CODE =\n    hex\"";
        declarations[1] = "bytes constant RUNTIME_CODE =\n    hex\"";
        string[] memory endings = new string[](5);
        endings[0] = "\"";
        endings[1] = "\";;";
        endings[2] = "\"x;";
        endings[3] = "\";\"";
        endings[4] = "";
        for (uint256 i = 0; i < declarations.length; i++) {
            string[] memory parts = vm.split(committedCodeRecord(), declarations[i]);
            assertEq(parts.length, 2, "the record's code is not where the generator writes it");
            string[] memory rest = vm.split(parts[1], "\";");
            assertGt(rest.length, 1, "the record's literal does not end where the generator ends it");
            string memory tail = rest[1];
            for (uint256 k = 2; k < rest.length; k++) {
                tail = string.concat(tail, "\";", rest[k]);
            }
            assertEq(string.concat(parts[0], declarations[i], rest[0], "\";", tail), committedCodeRecord());
            for (uint256 j = 0; j < endings.length; j++) {
                string memory edited = string.concat(parts[0], declarations[i], rest[0], endings[j], tail);
                vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
                this.externalCheckFrozenCodeRecord("record.sol", edited);
            }
        }
    }

    /// `CREATION_CODE`'s value is held to the writer's format even though the check hashes only `RUNTIME_CODE`.
    function testFrozenCodeRecordUnreadableCreationCodeIsUnreadable() external {
        string[] memory parts = vm.split(committedCodeRecord(), "bytes constant CREATION_CODE =\n    hex\"");
        assertEq(parts.length, 2, "the record's creation code is not where the generator writes it");
        string[] memory variants = new string[](3);
        variants[0] = "bytes constant CREATION_CODE =\n   hex\"";
        variants[1] = "bytes constant CREATION_CODE = // hex\"";
        variants[2] = "bytes constant CREATION_CODE =\n    x\"";
        for (uint256 i = 0; i < variants.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
            this.externalCheckFrozenCodeRecord("record.sol", string.concat(parts[0], variants[i], parts[1]));
        }
    }

    /// A code record that declares a deploy address is a deploy record under a
    /// code record's name, and is refused.
    function testFrozenCodeRecordWithADeployedAddressReverts() external {
        string memory record = string.concat(
            committedCodeRecord(),
            "\naddress constant DEPLOYED_ADDRESS = address(0x000000000000000000000000000000000000dEaD);\n"
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordDeclaresDeployedAddress.selector, "record.sol"));
        this.externalCheckFrozenCodeRecord("record.sol", record);
    }

    /// A deploy record named as a code record is refused for its address, so a
    /// name cannot move a deploy record out of the deploy check.
    function testFrozenCodeRecordNamingADeployRecordReverts() external {
        string memory record =
            vm.readFile(LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "AddressRegistry"));
        vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordDeclaresDeployedAddress.selector, "record.sol"));
        this.externalCheckFrozenCodeRecord("record.sol", record);
    }

    /// A per-network deploy record named as a code record is refused for its
    /// `DEPLOYED_ADDRESS_<chainId>` addresses.
    function testFrozenCodeRecordNamingAPerNetworkDeployRecordReverts() external {
        string memory record = vm.readFile(
            LibRainDeploySnapshot.pathForSnapshot(PER_NETWORK_CLONE_RECORD_ROOT, "0_0_1", "PerNetworkClone")
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordDeclaresDeployedAddress.selector, "record.sol"));
        this.externalCheckFrozenCodeRecord("record.sol", record);
    }

    /// A code record missing one of its constants is unreadable.
    function testFrozenCodeRecordWithoutRuntimeCodeReverts() external {
        string memory record =
            vm.replace(committedCodeRecord(), "bytes constant RUNTIME_CODE =", "bytes constant OTHER_CODE =");
        vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordUnreadable.selector, "record.sol"));
        this.externalCheckFrozenCodeRecord("record.sol", record);
    }

    /// A code record declaring a constant twice is refused rather than read
    /// by position.
    function testFrozenCodeRecordWithTwoHashesReverts() external {
        string memory record = string.concat(
            committedCodeRecord(),
            "\nbytes32 constant BYTECODE_HASH = bytes32(0x0000000000000000000000000000000000000000000000000000000000000000);\n"
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenCodeRecordAmbiguous.selector, "record.sol"));
        this.externalCheckFrozenCodeRecord("record.sol", record);
    }

    /// The partition puts a path in the code records exactly when its file is
    /// a named code record, and keeps each side in the order given.
    function testPartitionFrozenRecordsSplitsByFileName() external view {
        string[] memory paths = new string[](4);
        paths[0] = "src/generated/0_1_17/AddressRegistry.sol";
        paths[1] = "src/generated/0_1_17/TimelockController.sol";
        paths[2] = "src/generated/0_1_18/MigrationRegistry.sol";
        paths[3] = "src/generated/0_1_18/TimelockController.sol";
        string[] memory names = new string[](1);
        names[0] = "TimelockController";

        (string[] memory deployRecords, string[] memory codeRecords) = this.externalPartitionFrozenRecords(paths, names);

        assertEq(deployRecords.length, 2);
        assertEq(deployRecords[0], paths[0]);
        assertEq(deployRecords[1], paths[2]);
        assertEq(codeRecords.length, 2);
        assertEq(codeRecords[0], paths[1]);
        assertEq(codeRecords[1], paths[3]);
    }

    /// With no names, every path is a deploy record: the default leaves a repo
    /// that freezes only suites exactly as it was.
    function testPartitionFrozenRecordsWithNoNamesIsAllDeploy() external view {
        string[] memory paths = new string[](2);
        paths[0] = "src/generated/0_1_18/AddressRegistry.sol";
        paths[1] = "src/generated/0_1_18/TimelockController.sol";

        (string[] memory deployRecords, string[] memory codeRecords) =
            this.externalPartitionFrozenRecords(paths, new string[](0));

        assertEq(deployRecords.length, 2);
        assertEq(codeRecords.length, 0);
    }
}
