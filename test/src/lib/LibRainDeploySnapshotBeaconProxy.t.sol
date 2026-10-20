// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeployDependency, DeployMechanism, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    FrozenSnapshotBeaconProxyMarkerAmbiguous,
    FrozenSnapshotBeaconProxyMechanismDataMissing,
    FrozenSnapshotUnreadable,
    LibRainDeploySnapshot
} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {BEACON_PROXY_ARTIFACT_PATH, BeaconProxyDeploy} from "../../../src/lib/LibRainDeployBeaconProxy.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {MockBeaconProxyFactory} from "../../concrete/MockBeaconProxyFactory.sol";
import {MockCloneableV2} from "../../concrete/MockCloneableV2.sol";
import {perNetworkCloneChainIds, perNetworkCloneInitData} from "../../abstract/PerNetworkCloneDeploys.sol";

/// @title LibRainDeploySnapshotBeaconProxyTest
/// @notice The beacon proxy record marker: what the writer emits, how `recordedMechanism` reads it,
/// and the released lib entries it produces.
contract LibRainDeploySnapshotBeaconProxyTest is Test {
    string constant ROOT = "fixture-lib/snapshot-beacon-proxy";

    string constant MARKER_LINE = "bool constant BEACON_PROXY = true;\n";

    string constant MECHANISM_DATA_LINE = "bytes constant MECHANISM_DATA = hex\"01\";\n";

    /// @param path The record.
    /// @return The mechanism it was cut with.
    function externalRecordedMechanism(string memory path) external view returns (DeployMechanism) {
        return LibRainDeploySnapshot.recordedMechanism(vm, path);
    }

    /// Writes `record` as the one file of a test's own directory.
    /// @param name The test's directory under `ROOT`.
    /// @param record The record's contents.
    /// @return The directory and the record file.
    function writeRecord(string memory name, string memory record) internal returns (string memory, string memory) {
        string memory dir = string.concat(ROOT, "/", name);
        string memory path = string.concat(dir, "/Record.sol");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(dir, true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, record);
        return (dir, path);
    }

    /// @param a The address.
    /// @return `address constant DEPLOYED_ADDRESS = address(<a>);`, newline-terminated.
    function everyNetworkLine(address a) internal pure returns (string memory) {
        return string.concat("address constant DEPLOYED_ADDRESS = address(", vm.toString(a), ");\n");
    }

    /// @param chainId The chain id.
    /// @param a The address.
    /// @return `address constant DEPLOYED_ADDRESS_<chainId> = address(<a>);`, newline-terminated.
    function perNetworkLine(uint256 chainId, address a) internal pure returns (string memory) {
        return string.concat(
            "address constant DEPLOYED_ADDRESS_", vm.toString(chainId), " = address(", vm.toString(a), ");\n"
        );
    }

    /// @param name The test's directory under `ROOT`.
    /// @param record The record's contents.
    /// @param selector The refusal expected, naming the file.
    function checkRefused(string memory name, string memory record, bytes4 selector) internal {
        (string memory dir, string memory path) = writeRecord(name, record);
        vm.expectRevert(abi.encodeWithSelector(selector, path));
        this.externalRecordedMechanism(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(dir, true);
    }

    /// @param name The test's directory under `ROOT`.
    /// @param record The record's contents.
    /// @param expected The mechanism expected.
    function checkRead(string memory name, string memory record, DeployMechanism expected) internal {
        (string memory dir, string memory path) = writeRecord(name, record);
        DeployMechanism read = this.externalRecordedMechanism(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(dir, true);
        assertEq(uint256(read), uint256(expected));
    }

    /// The marker beside `MECHANISM_DATA` reads as a beacon proxy, one-address or per-network by
    /// the address declarations, wherever it sits among the lines.
    function testTheMarkerReadsAsABeaconProxy() external {
        checkRead(
            "one",
            string.concat(MECHANISM_DATA_LINE, MARKER_LINE, everyNetworkLine(address(1))),
            DeployMechanism.BeaconProxy
        );
        checkRead(
            "one-marker-first",
            string.concat(MARKER_LINE, everyNetworkLine(address(1)), MECHANISM_DATA_LINE),
            DeployMechanism.BeaconProxy
        );
        checkRead(
            "per-network",
            string.concat(
                perNetworkLine(137, address(2)), MARKER_LINE, MECHANISM_DATA_LINE, perNetworkLine(42161, address(3))
            ),
            DeployMechanism.BeaconProxyPerNetwork
        );
    }

    /// The same records without the marker read as clones.
    function testNoMarkerReadsAsAClone() external {
        checkRead("clone", string.concat(MECHANISM_DATA_LINE, everyNetworkLine(address(1))), DeployMechanism.Clone);
        checkRead(
            "clone-per-network",
            string.concat(perNetworkLine(137, address(2)), MECHANISM_DATA_LINE, perNetworkLine(42161, address(3))),
            DeployMechanism.ClonePerNetwork
        );
    }

    /// A marker without `MECHANISM_DATA` is refused, one-address or per-network.
    function testTheMarkerWithoutMechanismDataIsRefused() external {
        checkRefused(
            "marker-no-data",
            string.concat(MARKER_LINE, everyNetworkLine(address(1))),
            FrozenSnapshotBeaconProxyMechanismDataMissing.selector
        );
        checkRefused(
            "marker-no-data-per-network",
            string.concat(perNetworkLine(137, address(2)), MARKER_LINE),
            FrozenSnapshotBeaconProxyMechanismDataMissing.selector
        );
    }

    /// Two markers are refused as ambiguous, with or without `MECHANISM_DATA`.
    function testTwoMarkersAreAmbiguous() external {
        checkRefused(
            "two-markers",
            string.concat(MARKER_LINE, MECHANISM_DATA_LINE, MARKER_LINE, everyNetworkLine(address(1))),
            FrozenSnapshotBeaconProxyMarkerAmbiguous.selector
        );
        checkRefused(
            "two-markers-no-data",
            string.concat(MARKER_LINE, MARKER_LINE, everyNetworkLine(address(1))),
            FrozenSnapshotBeaconProxyMarkerAmbiguous.selector
        );
    }

    /// A line naming `BEACON_PROXY` that is not exactly the marker is refused as unreadable, whether
    /// solc would read it as the marker, as another value, or not at all.
    function testAStrayMentionOfTheMarkerIsUnreadable() external {
        string[5] memory strays = [
            "bool constant BEACON_PROXY = false;\n",
            "bool constant BEACON_PROXY = true; \n",
            " bool constant BEACON_PROXY = true;\n",
            "// bool constant BEACON_PROXY = true;\n",
            "uint256 constant NOT_BEACON_PROXY = 1;\n"
        ];
        for (uint256 i = 0; i < strays.length; i++) {
            checkRefused(
                string.concat("stray-", vm.toString(i)),
                string.concat(MECHANISM_DATA_LINE, strays[i], everyNetworkLine(address(1))),
                FrozenSnapshotUnreadable.selector
            );
        }
    }

    /// Every mechanism's name is its enum member, and only the per-network ones record an address
    /// per network.
    function testMechanismNameAndPerNetworkKind() external pure {
        assertEq(LibRainDeploySnapshot.mechanismName(DeployMechanism.Clone), "DeployMechanism.Clone");
        assertEq(
            LibRainDeploySnapshot.mechanismName(DeployMechanism.ClonePerNetwork), "DeployMechanism.ClonePerNetwork"
        );
        assertEq(LibRainDeploySnapshot.mechanismName(DeployMechanism.BeaconProxy), "DeployMechanism.BeaconProxy");
        assertEq(
            LibRainDeploySnapshot.mechanismName(DeployMechanism.BeaconProxyPerNetwork),
            "DeployMechanism.BeaconProxyPerNetwork"
        );
        assertFalse(LibRainDeploySnapshot.isPerNetworkKind(DeployMechanism.Zoltu));
        assertFalse(LibRainDeploySnapshot.isPerNetworkKind(DeployMechanism.Clone));
        assertTrue(LibRainDeploySnapshot.isPerNetworkKind(DeployMechanism.ClonePerNetwork));
        assertFalse(LibRainDeploySnapshot.isPerNetworkKind(DeployMechanism.BeaconProxy));
        assertTrue(LibRainDeploySnapshot.isPerNetworkKind(DeployMechanism.BeaconProxyPerNetwork));
    }

    /// A beacon proxy candidate over a fresh factory and beacon, both declared as its dependencies.
    /// @param initDataPerNetwork Whether the init data is per network.
    /// @return The candidate's suite.
    function beaconProxySuite(bool initDataPerNetwork) internal returns (DeploySuite memory) {
        address factory = address(new MockBeaconProxyFactory());
        address beacon = address(new UpgradeableBeacon(address(new MockCloneableV2()), address(this)));
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({deployedAddress: factory, runtimeCode: factory.code});
        dependencies[1] = DeployDependency({deployedAddress: beacon, runtimeCode: beacon.code});
        return LibRainDeployMechanism.beaconProxyCandidate(
            BeaconProxyDeploy({
                suite: "beacon-proxy",
                factory: factory,
                beacon: beacon,
                data: initDataPerNetwork ? bytes("") : bytes(hex"deadbeef"),
                initDataPerNetwork: initDataPerNetwork,
                initData: initDataPerNetwork ? perNetworkCloneInitData : LibRainDeployClone.noInitDataPerNetwork,
                salt: bytes32(uint256(7)),
                dependencies: dependencies
            }),
            perNetworkCloneChainIds()
        )
        .snapshot;
    }

    /// Writes `suite`'s record under `ROOT/<tag>`, and returns what it reads back as.
    /// @param tag The record's tag directory.
    /// @param suite The suite.
    /// @return The record's path.
    function writeBeaconProxyRecord(string memory tag, DeploySuite memory suite) internal returns (string memory) {
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(string.concat(ROOT, "/", tag), true);
        return LibRainDeploySnapshot.writeSnapshot(vm, ROOT, tag, "BeaconProxyRecord", suite);
    }

    /// @param haystack The text.
    /// @param needle What to count.
    /// @return How many times `needle` occurs in `haystack`.
    function occurrences(string memory haystack, string memory needle) internal pure returns (uint256) {
        return vm.split(haystack, needle).length - 1;
    }

    /// A one-address beacon proxy's record carries the marker once, reads back as a beacon proxy,
    /// and is released as one, at its recorded address.
    function testTheWriterMarksAOneAddressBeaconProxyAndReleasesIt() external {
        DeploySuite memory suite = beaconProxySuite(false);
        string memory path = writeBeaconProxyRecord("0_0_1", suite);
        string memory record = vm.readFile(path);
        assertEq(occurrences(record, MARKER_LINE), 1);
        assertEq(uint256(this.externalRecordedMechanism(path)), uint256(DeployMechanism.BeaconProxy));
        assertTrue(
            vm.contains(
                record,
                "/// @dev The deterministic deploy address of the beacon proxy, through its\n/// factory's beacon-proxy open salt."
            )
        );
        assertTrue(
            vm.contains(
                record,
                "/// @dev The beacon proxy factory call this release was cut with: the\n/// `abi.encode`d `CloneTarget`"
            )
        );
        assertFalse(vm.contains(record, "EIP-1167"));
        assertFalse(vm.contains(record, "clone factory"));

        string memory imported = LibRainDeploySnapshot.releasedImport(vm, path);
        assertTrue(vm.contains(imported, "DEPLOYED_ADDRESS as BeaconProxyRecord_0_0_1_DEPLOYED_ADDRESS"));
        assertTrue(vm.contains(imported, "MECHANISM_DATA as BeaconProxyRecord_0_0_1_MECHANISM_DATA"));

        string memory entry = LibRainDeploySnapshot.releasedSuiteEntry(vm, 0, path, suite);
        assertTrue(vm.contains(entry, "storedDeployedAddress: BeaconProxyRecord_0_0_1_DEPLOYED_ADDRESS,\n"));
        assertTrue(vm.contains(entry, "mechanism: DeployMechanism.BeaconProxy,\n"));
        assertTrue(vm.contains(entry, "mechanismData: BeaconProxyRecord_0_0_1_MECHANISM_DATA\n"));
        assertTrue(vm.contains(entry, string.concat("artifactPath: \"", BEACON_PROXY_ARTIFACT_PATH, "\"")));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(string.concat(ROOT, "/0_0_1"), true);
    }

    /// A per-network beacon proxy's record carries the marker once, reads back as a per-network
    /// beacon proxy, and is released as one, with no stored address.
    function testTheWriterMarksAPerNetworkBeaconProxyAndReleasesIt() external {
        DeploySuite memory suite = beaconProxySuite(true);
        string memory path = writeBeaconProxyRecord("0_0_2", suite);
        string memory record = vm.readFile(path);
        assertEq(occurrences(record, MARKER_LINE), 1);
        assertEq(uint256(this.externalRecordedMechanism(path)), uint256(DeployMechanism.BeaconProxyPerNetwork));
        assertTrue(
            vm.contains(record, "/// @dev The deterministic deploy address of the beacon proxy on chain id\n/// 42161,")
        );
        assertTrue(
            vm.contains(record, "/// @dev The deterministic deploy address of the beacon proxy on chain id\n/// 137,")
        );
        assertTrue(
            vm.contains(
                record,
                "/// @dev The beacon proxy factory call this release was cut with: the\n/// `abi.encode`d `CloneNetworks`"
            )
        );
        assertFalse(vm.contains(record, "EIP-1167"));
        assertFalse(vm.contains(record, "clone factory"));

        string memory imported = LibRainDeploySnapshot.releasedImport(vm, path);
        assertFalse(vm.contains(imported, "DEPLOYED_ADDRESS as"));
        assertTrue(vm.contains(imported, "MECHANISM_DATA as BeaconProxyRecord_0_0_2_MECHANISM_DATA"));

        string memory entry = LibRainDeploySnapshot.releasedSuiteEntry(vm, 0, path, suite);
        assertTrue(vm.contains(entry, "storedDeployedAddress: address(0),\n"));
        assertTrue(vm.contains(entry, "mechanism: DeployMechanism.BeaconProxyPerNetwork,\n"));
        assertTrue(vm.contains(entry, "mechanismData: BeaconProxyRecord_0_0_2_MECHANISM_DATA\n"));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(string.concat(ROOT, "/0_0_2"), true);
    }
}
