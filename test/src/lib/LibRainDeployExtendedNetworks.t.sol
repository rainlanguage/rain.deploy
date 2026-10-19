// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    LibCodeGen,
    RAIN_COPYRIGHT_TEXT,
    RAIN_SPDX_LICENSE_IDENTIFIER
} from "rain-sol-codegen-0.1.39/src/lib/LibCodeGen.sol";
import {CloneNetwork} from "../../../src/lib/LibRainDeployClone.sol";
import {
    ExtendedNetworksRewritten,
    ExtendedNetworksUnreadable,
    ExtendedNetworksUnrecorded,
    LibRainDeployExtendedNetworks
} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {InvalidRecordRoot} from "../../../src/lib/LibRainDeploySnapshot.sol";

/// @title LibRainDeployExtendedNetworksTest
/// @notice The extended networks record: where it lives, what the writer writes, what the reader accepts, and the
/// append-only and exact-match refusals. Each test writes under its own fixture root.
contract LibRainDeployExtendedNetworksTest is Test {
    /// The release key every test records under.
    string constant SUITE = "per-network-clone@0_0_1";

    /// A fixture root of the test's own, emptied of any record an earlier run left.
    /// @param label The test's directory under `fixture-lib/extended-networks-lib`.
    /// @return The root.
    function freshRoot(string memory label) internal returns (string memory) {
        string memory root = string.concat("fixture-lib/extended-networks-lib/", label);
        (,, string memory path) = LibRainDeployExtendedNetworks.extendedNetworksPath(root, SUITE);
        if (vm.exists(path)) {
            vm.removeFile(path);
        }
        return root;
    }

    /// A network with the given fields.
    /// @param chainId The chain id.
    /// @param data The init data.
    /// @param deployedAddress The address.
    /// @return The network.
    function network(uint256 chainId, bytes memory data, address deployedAddress)
        internal
        pure
        returns (CloneNetwork memory)
    {
        return CloneNetwork({chainId: chainId, data: data, deployedAddress: deployedAddress});
    }

    /// Polygon then Base, at distinct data and addresses.
    /// @return The networks.
    function twoNetworks() internal pure returns (CloneNetwork[] memory) {
        CloneNetwork[] memory networks = new CloneNetwork[](2);
        networks[0] = network(137, hex"00aa", address(0x1111111111111111111111111111111111111111));
        networks[1] = network(8453, hex"", address(0xC4c4c4C4C4c4C4c4c4C4c4c4c4c4c4C4c4c4c4C4));
        return networks;
    }

    /// The first `n` of `networks`.
    /// @param networks The networks.
    /// @param n How many.
    /// @return The prefix.
    function prefix(CloneNetwork[] memory networks, uint256 n) internal pure returns (CloneNetwork[] memory) {
        CloneNetwork[] memory out = new CloneNetwork[](n);
        for (uint256 i = 0; i < n; i++) {
            out[i] = networks[i];
        }
        return out;
    }

    /// External wrapper for `writeExtendedNetworks`, under the Rain licence.
    /// @param root The record root.
    /// @param suite The release's suite key.
    /// @param declared The declared networks.
    function externalWrite(string memory root, string memory suite, CloneNetwork[] memory declared) external {
        LibRainDeployExtendedNetworks.writeExtendedNetworks(vm, root, suite, declared);
    }

    /// External wrapper for `recordedExtendedNetworks`.
    /// @param root The record root.
    /// @param suite The release's suite key.
    /// @return The recorded networks.
    function externalRecorded(string memory root, string memory suite) external view returns (CloneNetwork[] memory) {
        return LibRainDeployExtendedNetworks.recordedExtendedNetworks(vm, root, suite);
    }

    /// External wrapper for `checkExtendedNetworksRecorded`.
    /// @param root The record root.
    /// @param suite The release's suite key.
    /// @param declared The declared networks.
    function externalCheck(string memory root, string memory suite, CloneNetwork[] memory declared) external view {
        LibRainDeployExtendedNetworks.checkExtendedNetworksRecorded(vm, root, suite, declared);
    }

    /// External wrapper for `extendedNetworksPath`.
    /// @param root The record root.
    /// @param suite The release's suite key.
    /// @return Whether the key is tagged.
    /// @return The record's directory.
    /// @return The record's path.
    function externalPath(string memory root, string memory suite)
        external
        pure
        returns (bool, string memory, string memory)
    {
        return LibRainDeployExtendedNetworks.extendedNetworksPath(root, suite);
    }

    /// A tagged key's record is `<root>/extended/<tag>/<name>.sol`; an untagged key has none.
    function testExtendedNetworksPath() external pure {
        (bool tagged, string memory dir, string memory path) =
            LibRainDeployExtendedNetworks.extendedNetworksPath("src/generated", SUITE);
        assertTrue(tagged);
        assertEq(dir, "src/generated/extended/0_0_1");
        assertEq(path, "src/generated/extended/0_0_1/per-network-clone.sol");

        (tagged, dir, path) = LibRainDeployExtendedNetworks.extendedNetworksPath("src/generated", "a@b");
        assertTrue(tagged);
        assertEq(path, "src/generated/extended/b/a.sol");

        (tagged, dir, path) = LibRainDeployExtendedNetworks.extendedNetworksPath("src/generated", "per-network-clone");
        assertFalse(tagged);
        assertEq(dir, "");
        assertEq(path, "");
    }

    /// The root is held to the record root shape.
    function testExtendedNetworksPathRefusesAnInvalidRoot() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidRecordRoot.selector, "../src"));
        this.externalPath("../src", SUITE);
    }

    /// What is written is the licence header then the body, and reads back as the networks written, in order.
    function testWriteThenReadRoundTrips() external {
        string memory root = freshRoot("round-trip");
        CloneNetwork[] memory networks = twoNetworks();
        this.externalWrite(root, SUITE, networks);

        (,, string memory path) = LibRainDeployExtendedNetworks.extendedNetworksPath(root, SUITE);
        assertEq(
            vm.readFile(path),
            string.concat(
                LibCodeGen.filePrefix(RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT),
                LibRainDeployExtendedNetworks.extendedNetworksBody(vm, networks)
            )
        );
        assertEq(abi.encode(this.externalRecorded(root, SUITE)), abi.encode(networks));
        this.externalCheck(root, SUITE, networks);
    }

    /// The body names each network's chain id in its constants, address first, then its init data.
    function testExtendedNetworksBodyShape() external pure {
        CloneNetwork[] memory networks = new CloneNetwork[](1);
        networks[0] = network(137, hex"00aa", address(0x1111111111111111111111111111111111111111));
        assertEq(
            LibRainDeployExtendedNetworks.extendedNetworksBody(vm, networks),
            string.concat(
                "\n/// @dev The deterministic deploy address of the EIP-1167 clone on chain id\n/// 137, a network the",
                " release is declared on beyond its record.\naddress constant DEPLOYED_ADDRESS_137 =",
                " address(0x1111111111111111111111111111111111111111);\n\n/// @dev The init data the clone is",
                " broadcast with on chain id 137.\nbytes constant INIT_DATA_137 = hex\"00aa\";\n"
            )
        );
        assertEq(LibRainDeployExtendedNetworks.extendedNetworksBody(vm, new CloneNetwork[](0)), "");
    }

    /// The licence-taking writer declares the licence it is given.
    function testWriteDeclaresTheGivenLicence() external {
        string memory root = freshRoot("licence");
        CloneNetwork[] memory networks = twoNetworks();
        LibRainDeployExtendedNetworks.writeExtendedNetworks(vm, root, SUITE, networks, "MIT", "Copyright (c) Someone");
        (,, string memory path) = LibRainDeployExtendedNetworks.extendedNetworksPath(root, SUITE);
        assertEq(
            vm.readFile(path),
            string.concat(
                LibCodeGen.filePrefix("MIT", "Copyright (c) Someone"),
                LibRainDeployExtendedNetworks.extendedNetworksBody(vm, networks)
            )
        );
    }

    /// No record reads as no networks, and declaring none against it passes.
    function testNoRecordIsNoNetworks() external {
        string memory root = freshRoot("no-record");
        assertEq(this.externalRecorded(root, SUITE).length, 0);
        this.externalCheck(root, SUITE, new CloneNetwork[](0));
    }

    /// Declaring nothing writes nothing.
    function testWritingNothingWritesNoFile() external {
        string memory root = freshRoot("write-nothing");
        this.externalWrite(root, SUITE, new CloneNetwork[](0));
        (,, string memory path) = LibRainDeployExtendedNetworks.extendedNetworksPath(root, SUITE);
        assertFalse(vm.exists(path));
    }

    /// A network declared after those recorded is appended.
    function testWriteAppends() external {
        string memory root = freshRoot("append");
        CloneNetwork[] memory networks = twoNetworks();
        this.externalWrite(root, SUITE, prefix(networks, 1));
        assertEq(abi.encode(this.externalRecorded(root, SUITE)), abi.encode(prefix(networks, 1)));
        this.externalWrite(root, SUITE, networks);
        assertEq(abi.encode(this.externalRecorded(root, SUITE)), abi.encode(networks));
        this.externalWrite(root, SUITE, networks);
        assertEq(abi.encode(this.externalRecorded(root, SUITE)), abi.encode(networks));
    }

    /// Dropping, reordering or changing any field of a recorded network is refused at its index, and the record is
    /// left as it was.
    function testWriteRefusesARewrite() external {
        string memory root = freshRoot("rewrite");
        CloneNetwork[] memory networks = twoNetworks();
        this.externalWrite(root, SUITE, networks);

        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksRewritten.selector, SUITE, 0));
        this.externalWrite(root, SUITE, new CloneNetwork[](0));

        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksRewritten.selector, SUITE, 1));
        this.externalWrite(root, SUITE, prefix(networks, 1));

        CloneNetwork[] memory reordered = new CloneNetwork[](2);
        reordered[0] = networks[1];
        reordered[1] = networks[0];
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksRewritten.selector, SUITE, 0));
        this.externalWrite(root, SUITE, reordered);

        CloneNetwork[] memory changed = twoNetworks();
        changed[1].chainId = 8454;
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksRewritten.selector, SUITE, 1));
        this.externalWrite(root, SUITE, changed);

        changed = twoNetworks();
        changed[1].data = hex"01";
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksRewritten.selector, SUITE, 1));
        this.externalWrite(root, SUITE, changed);

        changed = twoNetworks();
        changed[1].deployedAddress = address(0xdead);
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksRewritten.selector, SUITE, 1));
        this.externalWrite(root, SUITE, changed);

        assertEq(abi.encode(this.externalRecorded(root, SUITE)), abi.encode(networks));
    }

    /// A declaration that is not exactly the record, in order, is refused.
    function testCheckRefusesAnythingButTheRecord() external {
        string memory root = freshRoot("check");
        CloneNetwork[] memory networks = twoNetworks();

        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnrecorded.selector, SUITE));
        this.externalCheck(root, SUITE, networks);

        this.externalWrite(root, SUITE, networks);

        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnrecorded.selector, SUITE));
        this.externalCheck(root, SUITE, prefix(networks, 1));

        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnrecorded.selector, SUITE));
        this.externalCheck(root, SUITE, new CloneNetwork[](0));

        CloneNetwork[] memory reordered = new CloneNetwork[](2);
        reordered[0] = networks[1];
        reordered[1] = networks[0];
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnrecorded.selector, SUITE));
        this.externalCheck(root, SUITE, reordered);

        CloneNetwork[] memory changed = twoNetworks();
        changed[0].chainId = 138;
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnrecorded.selector, SUITE));
        this.externalCheck(root, SUITE, changed);

        changed = twoNetworks();
        changed[0].data = hex"00ab";
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnrecorded.selector, SUITE));
        this.externalCheck(root, SUITE, changed);

        changed = twoNetworks();
        changed[0].deployedAddress = address(0xdead);
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnrecorded.selector, SUITE));
        this.externalCheck(root, SUITE, changed);
    }

    /// An untagged key has no record: declaring networks for it is refused by the check and by the writer, and
    /// declaring none passes both.
    function testUntaggedKeyHasNoRecord() external {
        string memory root = freshRoot("untagged");
        CloneNetwork[] memory networks = twoNetworks();
        assertEq(this.externalRecorded(root, "per-network-clone").length, 0);
        this.externalCheck(root, "per-network-clone", new CloneNetwork[](0));
        this.externalWrite(root, "per-network-clone", new CloneNetwork[](0));

        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnrecorded.selector, "per-network-clone"));
        this.externalCheck(root, "per-network-clone", networks);

        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnrecorded.selector, "per-network-clone"));
        this.externalWrite(root, "per-network-clone", networks);
    }

    /// Writes `contents` as the record and expects the read, the check and the writer all to refuse it as
    /// unreadable.
    /// @param label The test's fixture directory.
    /// @param contents The record's contents.
    function expectUnreadable(string memory label, string memory contents) internal {
        string memory root = freshRoot(label);
        (, string memory dir, string memory path) = LibRainDeployExtendedNetworks.extendedNetworksPath(root, SUITE);
        vm.createDir(dir, true);
        vm.writeFile(path, contents);
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnreadable.selector, path));
        this.externalRecorded(root, SUITE);
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnreadable.selector, path));
        this.externalCheck(root, SUITE, twoNetworks());
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnreadable.selector, path));
        this.externalWrite(root, SUITE, twoNetworks());
    }

    /// The record as the writer writes `twoNetworks()`.
    /// @return The record.
    function writtenRecord() internal pure returns (string memory) {
        return string.concat(
            LibCodeGen.filePrefix(RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT),
            LibRainDeployExtendedNetworks.extendedNetworksBody(vm, twoNetworks())
        );
    }

    /// The record as the writer writes `twoNetworks()`, with `from` replaced by `to`.
    /// @param from The text to replace.
    /// @param to Its replacement.
    /// @return The edited record.
    function editedRecord(string memory from, string memory to) internal pure returns (string memory) {
        return vm.replace(writtenRecord(), from, to);
    }

    /// A hand edit anywhere in the body, even one that leaves every value parseable, is unreadable.
    function testHandEditedBodyIsUnreadable() external {
        expectUnreadable("edited-comment", editedRecord("a network the", "a network  the"));
        expectUnreadable("edited-trailing", string.concat(writtenRecord(), "\n"));
        expectUnreadable(
            "edited-checksum",
            editedRecord("0xC4c4c4C4C4c4C4c4c4C4c4c4c4c4c4C4c4c4c4C4", "0xc4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4")
        );
        expectUnreadable("edited-chain-id", editedRecord("DEPLOYED_ADDRESS_137 =", "DEPLOYED_ADDRESS_0137 ="));
    }

    /// A record with no generated header, or two, is unreadable.
    function testHeaderlessRecordIsUnreadable() external {
        expectUnreadable("headerless", LibRainDeployExtendedNetworks.extendedNetworksBody(vm, twoNetworks()));
        expectUnreadable("two-headers", string.concat(writtenRecord(), LibRainDeployExtendedNetworks.HEADER_END));
    }

    /// An entry whose chain id, address or init data does not parse is refused as unreadable, not with the parse
    /// error.
    function testMalformedValuesAreUnreadable() external {
        expectUnreadable("bad-chain-id", editedRecord("DEPLOYED_ADDRESS_137 =", "DEPLOYED_ADDRESS_x137 ="));
        expectUnreadable(
            "bad-address",
            editedRecord("0x1111111111111111111111111111111111111111", "0x11111111111111111111111111111111111111zz")
        );
        expectUnreadable("bad-hex", editedRecord("hex\"00aa\"", "hex\"00zz\""));
    }

    /// An entry without its address wrapper, or with other than one hex literal, is unreadable.
    function testMisshapenEntriesAreUnreadable() external {
        expectUnreadable(
            "no-address-wrapper",
            editedRecord(
                "address(0x1111111111111111111111111111111111111111)", "0x1111111111111111111111111111111111111111"
            )
        );
        expectUnreadable("no-hex", editedRecord("hex\"00aa\"", "\"00aa\""));
        expectUnreadable("two-hex", editedRecord("hex\"00aa\"", "hex\"00aa\" hex\"\""));
    }
}
