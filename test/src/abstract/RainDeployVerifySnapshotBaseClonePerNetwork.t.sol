// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    FrozenSnapshotAmbiguous,
    FrozenSnapshotNotReleased,
    FrozenSnapshotsOutnumberReleases,
    FrozenSnapshotUnreadable,
    RainDeployVerifySnapshotBase,
    StoredAddressMismatch
} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {CloneNetworks} from "../../../src/lib/LibRainDeployClone.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PER_NETWORK_CLONE_RECORD_ROOT,
    PerNetworkCloneDeploys,
    perNetworkCloneRelease
} from "../../abstract/PerNetworkCloneDeploys.sol";

/// @title RainDeployVerifySnapshotBaseClonePerNetworkTest
/// @notice The snapshot group over a per-network clone deploy repo: a frozen
/// per-network release and a per-network candidate, each at a different
/// address on each of two networks.
///
/// `testSnapshotInternallyConsistent` is inherited and runs over both, so each
/// network's clone is derived through the factory with that network's init
/// data and held to the address recorded for that network.
///
/// `RainDeployVerifySnapshotBase` and not `RainDeployVerifySnapshot`, for the
/// reason `RainDeployVerifySnapshotBaseCloneTest` gives.
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
    /// @return chainIds The chain id each address is for.
    /// @return addresses The addresses the record declares.
    function externalRecordedDeployedAddresses(string memory path, string memory record)
        external
        pure
        returns (uint256[] memory chainIds, address[] memory addresses)
    {
        return recordedDeployedAddresses(path, record);
    }

    /// The committed record's one file.
    /// @return paths The record's paths.
    function recordPaths() internal view returns (string[] memory paths) {
        paths = LibRainDeploySnapshot.frozenSnapshotPaths(vm, PER_NETWORK_CLONE_RECORD_ROOT);
        assertEq(paths.length, 1, "the fixture record holds one release");
    }

    /// The release really is at a different address on each network, and each
    /// is the address its declaration derives for that network: otherwise the
    /// inherited consistency test passing says nothing about pairing an address
    /// with its network.
    function testFrozenPerNetworkReleaseIsAtADifferentAddressPerNetwork() external pure {
        DeploySuite memory release = releasedSuites()[0];
        address[] memory addresses = LibRainDeployMechanism.deployedAddresses(release);
        assertEq(addresses.length, 2);
        assertNotEq(addresses[0], addresses[1]);
        assertEq(release.storedDeployedAddress, address(0));

        DeploySuite memory declared = LibRainDeployMechanism.cloneCandidate(perNetworkCloneRelease()).snapshot;
        assertEq(release.mechanismData, declared.mechanismData);
        assertEq(addresses[0], LibRainDeployMechanism.deployedAddress(release, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID));
        assertEq(addresses[1], LibRainDeployMechanism.deployedAddress(release, PER_NETWORK_CLONE_POLYGON_CHAIN_ID));
    }

    /// A recorded address that is not the one its network's init data derives
    /// is refused, naming that network's recorded and derived addresses. The
    /// SECOND network's is staled, so a check that compared only the first
    /// passes it.
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

    /// The committed per-network record is accounted for by the release
    /// declared from it.
    function testFrozenPerNetworkRecordIsReleased() external view {
        checkFrozenSnapshotsReleased(recordPaths(), releasedSuites());
    }

    /// The record without its release is refused: with no released suites at
    /// all, and with the candidate alone, which is the same clone at another
    /// salt and therefore at other addresses.
    function testFrozenPerNetworkRecordWithoutItsReleaseIsRefused() external {
        string[] memory paths = recordPaths();

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, paths[0]));
        this.externalCheckFrozenSnapshotsReleased(paths, new DeploySuite[](0));

        DeploySuite[] memory candidates = new DeploySuite[](1);
        candidates[0] = candidateSuites()[0].snapshot;
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, paths[0]));
        this.externalCheckFrozenSnapshotsReleased(paths, candidates);
    }

    /// A release that derives the record's addresses but labels them with each
    /// other's chain ids is NOT that record's release. Its addresses are the
    /// same list in the same order, and it is internally consistent — each
    /// entry's recorded address is what its init data derives — so only the
    /// chain id being part of the identity tells them apart: it is a release
    /// that would put the Arbitrum admin's clone on Polygon.
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

    /// Two copies of the per-network record against one release is a record
    /// outnumbering its declarations, and the refusal carries the record's
    /// whole address list in file order.
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

    /// A per-network record reads as each declaration's chain id and address
    /// in FILE order, whatever order the chain ids sort in, and a declaration
    /// in a block comment is not read.
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

    /// One chain id declared twice is refused: no compiler reads the file, and
    /// either copy is a value the generator did not write.
    function testPerNetworkRecordWithAChainIdTwiceIsAmbiguous() external {
        string memory record = string.concat(
            perNetworkLine(42161, address(0xbeef)),
            perNetworkLine(137, address(0xcafe)),
            perNetworkLine(42161, address(0xdead))
        );
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotAmbiguous.selector, "record.sol"));
        this.externalRecordedDeployedAddresses("record.sol", record);
    }

    /// `DEPLOYED_ADDRESS` beside any `DEPLOYED_ADDRESS_<chainId>` is refused,
    /// whichever comes first: two answers to where the release is.
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

    /// A record whose only per-network declaration is commented out declares
    /// nothing, and is unreadable rather than an empty list.
    function testPerNetworkRecordWithEveryDeclarationCommentedOutIsUnreadable() external {
        string memory record = string.concat("/*\n", perNetworkLine(137, address(0xcafe)), "*/\n");
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, "record.sol"));
        this.externalRecordedDeployedAddresses("record.sol", record);
    }
}
