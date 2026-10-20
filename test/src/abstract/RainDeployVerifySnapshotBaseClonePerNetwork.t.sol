// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    FrozenSnapshotNotReleased,
    FrozenSnapshotsOutnumberReleases,
    RainDeployVerifySnapshotBase,
    StoredAddressMismatch
} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {CloneNetworks} from "../../../src/lib/LibRainDeployClone.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {
    FrozenSnapshotAmbiguous,
    FrozenSnapshotUnreadable,
    LibRainDeploySnapshot
} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PER_NETWORK_CLONE_RECORD_ROOT,
    PerNetworkCloneDeploys,
    perNetworkCloneChainIds,
    perNetworkCloneRelease
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {LibForeignLineBreaks} from "../../lib/LibForeignLineBreaks.sol";

/// @title RainDeployVerifySnapshotBaseClonePerNetworkTest
/// @notice The snapshot group over a per-network clone deploy repo.
contract RainDeployVerifySnapshotBaseClonePerNetworkTest is PerNetworkCloneDeploys, RainDeployVerifySnapshotBase {
    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// @param paths The frozen record paths.
    /// @param released The released suites.
    function externalCheckFrozenSnapshotsReleased(string[] memory paths, DeploySuite[] memory released) external view {
        checkFrozenSnapshotsReleased(paths, released);
    }

    /// @param suite The suite to check.
    function externalCheckInternallyConsistent(DeploySuite memory suite) external {
        checkInternallyConsistent(suite);
    }

    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    /// @return The chain id each address is for.
    /// @return The addresses the record declares.
    function externalRecordedDeployedAddresses(string memory path, string memory record)
        external
        pure
        returns (uint256[] memory, address[] memory)
    {
        return LibRainDeploySnapshot.recordedDeployedAddresses(vm, path, record);
    }

    /// The committed record's one file.
    /// @return The record's paths.
    function recordPaths() internal view returns (string[] memory) {
        string[] memory paths = LibRainDeploySnapshot.frozenSnapshotPaths(vm, PER_NETWORK_CLONE_RECORD_ROOT);
        assertEq(paths.length, 1, "the fixture record holds one release");
        return paths;
    }

    /// The release really is at a different address on each network, and each is the address its
    /// declaration derives for that network.
    function testFrozenPerNetworkReleaseIsAtADifferentAddressPerNetwork() external view {
        DeploySuite memory release = releasedSuites()[0];
        address[] memory addresses = LibRainDeployMechanism.deployedAddresses(release);
        assertEq(addresses.length, 2);
        assertNotEq(addresses[0], addresses[1]);
        assertEq(release.storedDeployedAddress, address(0));

        DeploySuite memory declared =
        LibRainDeployMechanism.cloneCandidate(perNetworkCloneRelease(), perNetworkCloneChainIds()).snapshot;
        assertEq(release.mechanismData, declared.mechanismData);
        assertEq(addresses[0], LibRainDeployMechanism.deployedAddress(release, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID));
        assertEq(addresses[1], LibRainDeployMechanism.deployedAddress(release, PER_NETWORK_CLONE_POLYGON_CHAIN_ID));
    }

    /// A recorded address that is not the one its network's init data derives is refused, naming
    /// that network's recorded and derived addresses.
    function testPerNetworkRecordedAddressMismatchIsRefusedPerNetwork() external {
        DeploySuite memory release = releasedSuites()[0];
        address[] memory derived = LibRainDeployMechanism.deployedAddresses(release);
        CloneNetworks memory clones = abi.decode(release.mechanismData, (CloneNetworks));
        address staled = address(uint160(derived[1]) + 1);
        clones.networks[1].deployedAddress = staled;
        release.mechanismData = abi.encode(clones);

        vm.expectRevert(abi.encodeWithSelector(StoredAddressMismatch.selector, release.suite, staled, derived[1]));
        this.externalCheckInternallyConsistent(release);
    }

    /// The committed per-network record is accounted for by the release declared from it.
    function testFrozenPerNetworkRecordIsReleased() external view {
        checkFrozenSnapshotsReleased(recordPaths(), releasedSuites());
    }

    /// The record without its release is refused.
    function testFrozenPerNetworkRecordWithoutItsReleaseIsRefused() external {
        string[] memory paths = recordPaths();

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, paths[0]));
        this.externalCheckFrozenSnapshotsReleased(paths, new DeploySuite[](0));

        DeploySuite[] memory candidates = new DeploySuite[](1);
        candidates[0] = candidateSuites()[0].snapshot;
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, paths[0]));
        this.externalCheckFrozenSnapshotsReleased(paths, candidates);
    }

    /// A release that derives the record's addresses but labels them with each other's chain ids is
    /// NOT that record's release.
    function testFrozenPerNetworkRecordRefusesSwappedChainIds() external {
        DeploySuite[] memory released = releasedSuites();
        CloneNetworks memory clones = abi.decode(released[0].mechanismData, (CloneNetworks));
        assertEq(clones.networks[0].chainId, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        assertEq(clones.networks[1].chainId, PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        clones.networks[0].chainId = PER_NETWORK_CLONE_POLYGON_CHAIN_ID;
        clones.networks[1].chainId = PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID;
        DeploySuite memory swapped = released[0];
        swapped.mechanismData = abi.encode(clones);

        assertEq(
            abi.encode(LibRainDeployMechanism.deployedAddresses(swapped)),
            abi.encode(LibRainDeployMechanism.deployedAddresses(releasedSuites()[0])),
            "the swapped release derives the same address list"
        );
        this.externalCheckInternallyConsistent(swapped);

        DeploySuite[] memory swappedReleased = new DeploySuite[](1);
        swappedReleased[0] = swapped;
        string[] memory paths = recordPaths();
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, paths[0]));
        this.externalCheckFrozenSnapshotsReleased(paths, swappedReleased);
    }

    /// Two copies of the per-network record against one release is a record outnumbering its
    /// declarations, and the refusal carries the record's whole address list in file order.
    function testFrozenPerNetworkRecordsOutnumberingReleasesCarryEveryAddress() external {
        string[] memory paths = new string[](2);
        paths[0] = recordPaths()[0];
        paths[1] = paths[0];

        vm.expectRevert(
            abi.encodeWithSelector(
                FrozenSnapshotsOutnumberReleases.selector,
                paths[1],
                LibRainDeployMechanism.deployedAddresses(releasedSuites()[0]),
                uint256(2),
                uint256(1)
            )
        );
        this.externalCheckFrozenSnapshotsReleased(paths, releasedSuites());
    }

    /// One per-network declaration line.
    /// @param chainId The chain id it is for.
    /// @param declared The address it declares.
    /// @return The line.
    function perNetworkLine(uint256 chainId, address declared) internal pure returns (string memory) {
        return string.concat(
            "address constant DEPLOYED_ADDRESS_", vm.toString(chainId), " = address(", vm.toString(declared), ");\n"
        );
    }

    /// The single-address declaration line.
    /// @param declared The address it declares.
    /// @return The line.
    function everyNetworkLine(address declared) internal pure returns (string memory) {
        return string.concat("address constant DEPLOYED_ADDRESS = address(", vm.toString(declared), ");\n");
    }

    /// A per-network record reads as each declaration's chain id and address in FILE order,
    /// whatever order the chain ids sort in, and a declaration in a block comment is not read.
    function testPerNetworkRecordReadsEveryDeclarationInFileOrder() external view {
        string memory record = string.concat(
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            perNetworkLine(42161, address(0xbeef)),
            "/*\n",
            perNetworkLine(10, address(0xdead)),
            "*/\n",
            perNetworkLine(137, address(0xcafe))
        );
        (uint256[] memory chainIds, address[] memory addresses) =
            this.externalRecordedDeployedAddresses("record.sol", record);
        assertEq(chainIds.length, 2);
        assertEq(addresses.length, 2);
        assertEq(chainIds[0], 42161);
        assertEq(addresses[0], address(0xbeef));
        assertEq(chainIds[1], 137);
        assertEq(addresses[1], address(0xcafe));
    }

    /// One chain id declared twice is refused.
    function testPerNetworkRecordWithAChainIdTwiceIsAmbiguous() external {
        string memory record = string.concat(
            perNetworkLine(42161, address(0xbeef)),
            perNetworkLine(137, address(0xcafe)),
            perNetworkLine(42161, address(0xdead))
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotAmbiguous.selector, "record.sol"));
        this.externalRecordedDeployedAddresses("record.sol", record);
    }

    /// `DEPLOYED_ADDRESS` beside any `DEPLOYED_ADDRESS_<chainId>` is refused, whichever comes
    /// first.
    function testRecordMixingBothFormsIsAmbiguous() external {
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotAmbiguous.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", string.concat(everyNetworkLine(address(0xbeef)), perNetworkLine(137, address(0xcafe)))
        );

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotAmbiguous.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", string.concat(perNetworkLine(137, address(0xcafe)), everyNetworkLine(address(0xbeef)))
        );
    }

    /// A record whose only per-network declaration is commented out declares nothing, and is
    /// unreadable rather than an empty list.
    function testPerNetworkRecordWithEveryDeclarationCommentedOutIsUnreadable() external {
        string memory record = string.concat("/*\n", perNetworkLine(137, address(0xcafe)), "*/\n");
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses("record.sol", record);
    }

    /// A per-network declaration line whose constant is named `DEPLOYED_ADDRESS_<suffix>`, with the
    /// suffix as given.
    /// @param suffix What follows `DEPLOYED_ADDRESS_` in the name.
    /// @return The line.
    function suffixedLine(string memory suffix) internal pure returns (string memory) {
        return string.concat(
            "address constant DEPLOYED_ADDRESS_", suffix, " = address(", vm.toString(address(0xcafe)), ");\n"
        );
    }

    /// A `DEPLOYED_ADDRESS_<x>` whose `<x>` is not a decimal chain id makes the record unreadable,
    /// typed and naming the file.
    function testPerNetworkDeclarationWithANonDecimalChainIdIsUnreadable() external {
        string[] memory suffixes = new string[](5);
        suffixes[0] = "0x89";
        suffixes[1] = "polygon";
        suffixes[2] = "";
        suffixes[3] = "DEPLOYED_ADDRESS_137";
        suffixes[4] = "115792089237316195423570985008687907853269984665640564039457584007913129639936";
        for (uint256 i = 0; i < suffixes.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
            this.externalRecordedDeployedAddresses(
                "record.sol", string.concat(perNetworkLine(42161, address(0xbeef)), suffixedLine(suffixes[i]))
            );
        }
    }

    /// A chain id of more than one digit with a leading zero is unreadable: `vm.toString` never writes one, and
    /// solc reads `DEPLOYED_ADDRESS_0137` as a name other than `DEPLOYED_ADDRESS_137`. Chain id 0 alone reads.
    function testPerNetworkDeclarationWithALeadingZeroIsUnreadable() external {
        string[] memory suffixes = new string[](3);
        suffixes[0] = "0137";
        suffixes[1] = "00";
        suffixes[2] = "01";
        for (uint256 i = 0; i < suffixes.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
            this.externalRecordedDeployedAddresses(
                "record.sol", string.concat(perNetworkLine(42161, address(0xbeef)), suffixedLine(suffixes[i]))
            );
        }
        (uint256[] memory chainIds, address[] memory addresses) = this.externalRecordedDeployedAddresses(
            "record.sol", string.concat(perNetworkLine(42161, address(0xbeef)), suffixedLine("0"))
        );
        assertEq(chainIds.length, 2);
        assertEq(chainIds[1], 0);
        assertEq(addresses[1], address(0xcafe));
    }

    /// A line naming `DEPLOYED_ADDRESS` anywhere but at the start of the writer's declaration is unreadable rather
    /// than skipped: solc compiles an indented or otherwise spaced declaration as the constant, which the reader would
    /// otherwise hold to nothing.
    function testDeployedAddressOutsideTheWritersDeclarationIsUnreadable() external {
        string memory value = string.concat("address(", vm.toString(address(0xcafe)), ");\n");
        string[] memory lines = new string[](6);
        lines[0] = string.concat(" address constant DEPLOYED_ADDRESS_137 = ", value);
        lines[1] = string.concat("\taddress constant DEPLOYED_ADDRESS_137 = ", value);
        lines[2] = string.concat("address  constant DEPLOYED_ADDRESS_137 = ", value);
        lines[3] = string.concat("address\tconstant DEPLOYED_ADDRESS_137 = ", value);
        lines[4] = string.concat(" address constant DEPLOYED_ADDRESS = ", value);
        lines[5] = "// DEPLOYED_ADDRESS_137\n";
        for (uint256 i = 0; i < lines.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
            this.externalRecordedDeployedAddresses(
                "record.sol", string.concat(perNetworkLine(42161, address(0xbeef)), lines[i])
            );
        }
    }

    /// The largest chain id a `uint256` holds, in the declaration the writer emits for it, reads as itself.
    function testPerNetworkDeclarationWithTheLargestChainIdReads() external view {
        DeploySuite memory suite = releasedSuites()[0];
        CloneNetworks memory clones = abi.decode(suite.mechanismData, (CloneNetworks));
        uint256 secondChainId = clones.networks[1].chainId;
        clones.networks[0].chainId = type(uint256).max;
        suite.mechanismData = abi.encode(clones);
        address[] memory deployed = new address[](clones.networks.length);
        deployed[0] = address(0xcafe);
        deployed[1] = address(0xbeef);
        (string memory constants,) = LibRainDeploySnapshot.perNetworkAddressConstants(vm, deployed, suite);
        assertTrue(vm.contains(constants, " =\n    address("));

        (uint256[] memory chainIds, address[] memory addresses) =
            this.externalRecordedDeployedAddresses("record.sol", constants);
        assertEq(chainIds.length, 2);
        assertEq(chainIds[0], type(uint256).max);
        assertEq(addresses[0], address(0xcafe));
        assertEq(chainIds[1], secondChainId);
        assertEq(addresses[1], address(0xbeef));
    }

    /// A declaration wrapped after `=` with nothing after it is unreadable, typed and naming the record.
    function testPerNetworkDeclarationWrappedAtTheEndOfTheRecordIsUnreadable() external {
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses("record.sol", "address constant DEPLOYED_ADDRESS_1 =");
    }

    /// A wrapped declaration whose next line is not an address is unreadable.
    function testPerNetworkDeclarationWrappedOntoANonAddressIsUnreadable() external {
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses("record.sol", "address constant DEPLOYED_ADDRESS_1 =\n    hex\"00\";\n");
    }

    /// A declaration ending in `=` takes no address from a following line the writer did not wrap onto, even another declaration's.
    function testPerNetworkDeclarationWrappedOntoAnotherDeclarationIsUnreadable() external {
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol",
            "address constant DEPLOYED_ADDRESS_1 =\naddress constant OTHER = address(0x000000000000000000000000000000000000bEEF);\n"
        );
    }

    /// A declaration ending in `=` takes no address from a following line that does not start with the writer's
    /// `    address(`: another indentation, a comment, the prefix later in the line, or a bare literal.
    function testPerNetworkDeclarationWrappedOntoAnotherFormatIsUnreadable() external {
        string[] memory wrapped = new string[](4);
        wrapped[0] = "        address(0x000000000000000000000000000000000000bEEF);";
        wrapped[1] = "    // address(0x000000000000000000000000000000000000bEEF);";
        wrapped[2] = "x    address(0x000000000000000000000000000000000000bEEF);";
        wrapped[3] = "    0x000000000000000000000000000000000000bEEF;";
        for (uint256 i = 0; i < wrapped.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
            this.externalRecordedDeployedAddresses(
                "record.sol", string.concat("address constant DEPLOYED_ADDRESS_1 =\n", wrapped[i], "\n")
            );
        }
    }

    /// A wrapped value that does not end at the writer's `);` is unreadable, rather than read as its first address
    /// while solc compiles the expression it continues into.
    function testPerNetworkDeclarationWrappedValueContinuingIsUnreadable() external {
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol",
            "address constant DEPLOYED_ADDRESS_137 =\n    address(0x1111111111111111111111111111111111111111)\n    != address(0) ? address(0x2222222222222222222222222222222222222222) : address(0x3333333333333333333333333333333333333333);\n"
        );
    }

    /// A value other than `0x` and 40 hex digits, bare or in `address(...)`, then `;` is unreadable, on the
    /// declaration's line in both forms and wrapped for the `address(...)` form: 40 hex digits without `0x`, which
    /// names an identifier to solc, other than 40 digits, or anything before, inside or after the value.
    function testDeclarationValueOutsideTheWritersShapeIsUnreadable() external {
        string[] memory values = new string[](18);
        values[0] = "address(abcdefabcdefabcdefabcdefabcdefabcdefabcd);";
        values[1] = "address(0x000000000000000000000000000000000000bEEF)";
        values[2] = "address(0x000000000000000000000000000000000000bEEF);;";
        values[3] = "address(0x000000000000000000000000000000000000bEEF));";
        values[4] = "xaddress(0x000000000000000000000000000000000000bEEF);";
        values[5] = "address(0x000000000000000000000000000000000000bEEF;);";
        values[6] = "abcdefabcdefabcdefabcdefabcdefabcdefabcd;";
        values[7] = "0x000000000000000000000000000000000000bEEF;;";
        values[8] = "0x000000000000000000000000000000000000bEEF";
        values[9] = "0x00000000000000000000000000000000000bEEF;";
        values[10] = "0x0000000000000000000000000000000000000bEEF;";
        values[11] = "address(0x00000000000000000000000000000000000bEEF);";
        values[12] = "address(0x0000000000000000000000000000000000000bEEF);";
        values[13] = "0x000000000000000000000000000000000000bEEF;0x";
        values[14] = "address(0x000000000000000000000000000000000000bEEF);0x";
        values[15] = "address(0x000000000000000000000000000000000000bEEF);address(0x";
        values[16] = "x0x000000000000000000000000000000000000bEEF;";
        values[17] = "(0x000000000000000000000000000000000000bEEF);";
        for (uint256 i = 0; i < values.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
            this.externalRecordedDeployedAddresses(
                "record.sol", string.concat("address constant DEPLOYED_ADDRESS = ", values[i], "\n")
            );
            vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
            this.externalRecordedDeployedAddresses(
                "record.sol", string.concat("address constant DEPLOYED_ADDRESS_1 = ", values[i], "\n")
            );
        }
        for (uint256 i = 0; i < values.length; i++) {
            if (vm.indexOf(values[i], "address(") != 0) {
                continue;
            }
            vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
            this.externalRecordedDeployedAddresses(
                "record.sol", string.concat("address constant DEPLOYED_ADDRESS_1 =\n    ", values[i], "\n")
            );
        }
        (, address[] memory addresses) = this.externalRecordedDeployedAddresses(
            "record.sol",
            "address constant DEPLOYED_ADDRESS_1 =\n    address(0x000000000000000000000000000000000000bEEF);\n"
        );
        assertEq(addresses[0], address(0xbeef));
    }

    /// A declaration followed by a line comment is unreadable rather than read as the comment's last token, in the
    /// every-network form, the per-network form and the wrapped form.
    function testDeclarationFollowedByALineCommentIsUnreadable() external {
        string memory value =
            "address(0x0000000000000000000000000000000000000001); // address(0x0000000000000000000000000000000000000002);\n";
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", string.concat("address constant DEPLOYED_ADDRESS = ", value)
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", string.concat("address constant DEPLOYED_ADDRESS_1 = ", value)
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", string.concat("address constant DEPLOYED_ADDRESS_1 =\n    ", value)
        );
    }

    /// A declaration whose value is followed by exactly one more token is unreadable, not read as its fifth token, in
    /// the every-network form, the per-network form and the wrapped form.
    function testDeclarationOfSixTokensIsUnreadable() external {
        string memory value =
            "address(0x0000000000000000000000000000000000000001); //address(0x0000000000000000000000000000000000000002);\n";
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", string.concat("address constant DEPLOYED_ADDRESS = ", value)
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", string.concat("address constant DEPLOYED_ADDRESS_1 = ", value)
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", string.concat("address constant DEPLOYED_ADDRESS_1 =\n    ", value)
        );
    }

    /// A record holding a carriage return, vertical tab, form feed, NEL, LS or PS, each of which ends a line comment for
    /// the compiler but not for the reader, is unreadable, so a declaration after one in a comment is never missed.
    function testRecordHoldingAnotherLineBreakIsUnreadable() external {
        string[] memory breaks = LibForeignLineBreaks.foreignLineBreaks();
        for (uint256 i = 0; i < breaks.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
            this.externalRecordedDeployedAddresses(
                "record.sol",
                string.concat(
                    "address constant DEPLOYED_ADDRESS_1 = address(0x000000000000000000000000000000000000bEEF);\n// note",
                    breaks[i],
                    "address constant DEPLOYED_ADDRESS_2 = address(0x000000000000000000000000000000000000cAFE);\n"
                )
            );
        }
    }

    /// A declaration whose value is not an address makes the record unreadable, typed and naming
    /// the file, in both the every-network and the per-network form.
    function testDeclarationWithAMalformedAddressIsUnreadable() external {
        string[] memory values = new string[](4);
        values[0] = "=";
        values[1] = "address(0xnothex);";
        values[2] = "address(0x000000000000000000000000000000000000cafe00);";
        values[3] = "address(0x00000000000000000000000000000000cafe);";
        for (uint256 i = 0; i < values.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
            this.externalRecordedDeployedAddresses(
                "record.sol", string.concat("address constant DEPLOYED_ADDRESS = ", values[i], "\n")
            );
            vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
            this.externalRecordedDeployedAddresses(
                "record.sol",
                string.concat(
                    perNetworkLine(42161, address(0xbeef)), "address constant DEPLOYED_ADDRESS_137 = ", values[i], "\n"
                )
            );
        }
    }

    /// A declaration line with fewer than the writer's five tokens is unreadable, in both forms and with the per-network
    /// form's `=` joined to the name.
    function testDeclarationOfFewerThanFiveTokensIsUnreadable() external {
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", "address constant DEPLOYED_ADDRESS_1= address(0x0000000000000000000000000000000000000001);\n"
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", "address constant DEPLOYED_ADDRESS =address(0x0000000000000000000000000000000000000001);\n"
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", "address constant DEPLOYED_ADDRESS_1=address(0x0000000000000000000000000000000000000001);\n"
        );
    }

    /// A declaration of five tokens whose fourth is not `=` is unreadable rather than read as a trailing comment's
    /// last token, in both forms.
    function testDeclarationWithoutASpacedEqualsIsUnreadable() external {
        string memory value =
            "=address(0x0000000000000000000000000000000000000001);// address(0x0000000000000000000000000000000000000002);\n";
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses("record.sol", string.concat("address constant DEPLOYED_ADDRESS ", value));
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses(
            "record.sol", string.concat("address constant DEPLOYED_ADDRESS_1 ", value)
        );
    }
}
