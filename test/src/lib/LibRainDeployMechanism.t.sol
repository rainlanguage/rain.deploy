// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {DeployCandidate, DeployMechanism, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    CLONE_ARTIFACT_PATH,
    CLONE_UNANCHORABLE_REASON,
    CloneDeploy,
    CloneNetwork,
    CloneNetworks,
    CloneTarget,
    LibRainDeployClone
} from "../../../src/lib/LibRainDeployClone.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    CloneCreationCodeMismatch,
    CloneDataAmbiguous,
    CloneDerivationMismatch,
    LibRainDeployMechanism,
    UnexpectedMechanismData,
    UnexpectedStoredDeployedAddress
} from "../../../src/lib/LibRainDeployMechanism.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {
    exampleCloneDependencies,
    exampleCloneFactory,
    exampleCloneImplementation
} from "../../abstract/ExampleCloneDeploys.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN,
    PER_NETWORK_CLONE_POLYGON_ADMIN,
    NoPerNetworkCloneAdmin,
    perNetworkClone,
    perNetworkCloneChainIds,
    perNetworkCloneInitData
} from "../../abstract/PerNetworkCloneDeploys.sol";

/// Per-network init data in which Arbitrum One and Base share Arbitrum One's
/// admin and Polygon has its own.
/// @param chainId The network's chain id.
/// @return The init data on that network.
function sharingInitData(uint256 chainId) pure returns (bytes memory) {
    return perNetworkCloneInitData(chainId == 8453 ? 42161 : chainId);
}

/// @title LibRainDeployMechanismTest
/// Tests for `LibRainDeployMechanism`.
contract LibRainDeployMechanismTest is Test {
    /// A salt with bytes set across the whole word, so a derivation that
    /// truncated it or used only its low bytes would be caught.
    bytes32 constant TEST_SALT = 0x1122334455667788990011223344556677889900112233445566778899001122;

    /// Init data that is neither empty nor a single word.
    bytes constant TEST_DATA = hex"deadbeefcafe0102030405060708090a0b0c0d0e0f";

    /// A clone declaration over the given factory and implementation.
    /// @param suite The suite key.
    /// @param factory The factory to clone through.
    /// @param implementation The implementation to clone.
    /// @param dependencies The dependencies declared beside the clone.
    /// @return The clone declaration.
    function declaredClone(
        string memory suite,
        address factory,
        address implementation,
        DeployDependency[] memory dependencies
    ) internal pure returns (CloneDeploy memory) {
        return CloneDeploy({
            suite: suite,
            factory: factory,
            implementation: implementation,
            data: TEST_DATA,
            initDataPerNetwork: false,
            initData: LibRainDeployClone.noInitDataPerNetwork,
            salt: TEST_SALT,
            dependencies: dependencies
        });
    }

    /// The target a clone declaration deploys.
    /// @param clone The clone declaration.
    /// @return The target.
    function targetOf(CloneDeploy memory clone) internal pure returns (CloneTarget memory) {
        return
            CloneTarget({
                factory: clone.factory, implementation: clone.implementation, data: clone.data, salt: clone.salt
            });
    }

    /// The suite key MUST NOT move the address. It names the clone in the
    /// declaration; it is not part of what gets deployed, and a derivation that
    /// hashed it in would make a rename a redeploy to a new address.
    function testCloneAddressIgnoresTheSuiteKey() external view {
        DeployCandidate memory named = LibRainDeployMechanism.cloneCandidate(
            declaredClone(
                "local-clone", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies()
            ),
            new uint256[](0)
        );
        DeployCandidate memory renamed = LibRainDeployMechanism.cloneCandidate(
            declaredClone(
                "renamed-clone", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies()
            ),
            new uint256[](0)
        );
        assertEq(renamed.snapshot.storedDeployedAddress, named.snapshot.storedDeployedAddress);
        assertEq(renamed.snapshot.mechanismData, named.snapshot.mechanismData);
    }

    /// `cloneCandidate` MUST derive every field of the candidate from the clone,
    /// and MUST carry the standard unanchorable reason. Each field asserted
    /// against its own derivation, because the point of the builder is that a
    /// consumer no longer writes these by hand.
    function testCloneCandidateDerivesEveryField() external view {
        CloneDeploy memory clone = declaredClone(
            "local-clone", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies()
        );
        CloneTarget memory target = targetOf(clone);
        DeployCandidate memory candidate = LibRainDeployMechanism.cloneCandidate(clone, new uint256[](0));

        assertEq(candidate.snapshot.suite, clone.suite);
        assertEq(candidate.snapshot.creationCode, LibRainDeployClone.cloneCreationCode(clone.implementation));
        assertEq(candidate.snapshot.storedDeployedAddress, LibRainDeployClone.cloneDeployedAddress(target));
        assertEq(candidate.snapshot.storedBytecodeHash, LibRainDeployClone.cloneDeployedCodehash(clone.implementation));
        assertEq(candidate.snapshot.storedRuntimeCode, LibRainDeployClone.cloneRuntimeCode(clone.implementation));
        assertEq(candidate.snapshot.artifactPath, CLONE_ARTIFACT_PATH);
        assertEq(uint256(candidate.snapshot.mechanism), uint256(DeployMechanism.Clone));
        assertEq(candidate.snapshot.mechanismData, abi.encode(target));
        assertEq(candidate.snapshot.dependencies.length, clone.dependencies.length);
        for (uint256 i = 0; i < clone.dependencies.length; i++) {
            assertEq(candidate.snapshot.dependencies[i].deployedAddress, clone.dependencies[i].deployedAddress);
            assertEq(candidate.snapshot.dependencies[i].runtimeCode, clone.dependencies[i].runtimeCode);
        }
        assertEq(candidate.unanchorableReason, CLONE_UNANCHORABLE_REASON);

        // The reason has to be NON-empty: an empty one is what says a candidate
        // IS anchorable, which would send the source anchor looking for an
        // artifact that cannot exist.
        assertNotEq(bytes(candidate.unanchorableReason).length, 0);
    }

    /// The recorded code hash MUST be the hash of the recorded runtime code, and
    /// the recorded address MUST be where the recorded creation code lands. The
    /// candidate's internal consistency, which the verification abstracts assume.
    function testCloneCandidateIsInternallyConsistent() external {
        MockCloneFactory factory = new MockCloneFactory();
        MockCloneable implementation = new MockCloneable();
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({deployedAddress: address(factory), runtimeCode: address(factory).code});
        dependencies[1] =
            DeployDependency({deployedAddress: address(implementation), runtimeCode: address(implementation).code});
        CloneDeploy memory clone = declaredClone("local-clone", address(factory), address(implementation), dependencies);
        DeployCandidate memory candidate = LibRainDeployMechanism.cloneCandidate(clone, new uint256[](0));

        assertEq(candidate.snapshot.storedBytecodeHash, keccak256(candidate.snapshot.storedRuntimeCode));
        address deployed = factory.cloneDeterministicOpenSalt(clone.implementation, clone.data, clone.salt);
        assertEq(deployed, candidate.snapshot.storedDeployedAddress);
        assertEq(deployed.codehash, candidate.snapshot.storedBytecodeHash);
    }

    /// @param suite The suite whose address is wanted.
    /// @return The address the suite's mechanism derives.
    function externalDeployedAddress(DeploySuite memory suite) external pure returns (address) {
        return LibRainDeployMechanism.deployedAddresses(suite)[0];
    }

    /// @param suite The suite to deploy locally.
    /// @return The address the suite was deployed to.
    function externalDeployLocally(DeploySuite memory suite) external returns (address) {
        return LibRainDeployMechanism.deployLocally(vm, suite)[0];
    }

    /// @param networks The networks to broadcast to.
    /// @param suite The suite to broadcast.
    /// @return forkIds The fork each network was deployed on.
    function externalDeployAndBroadcast(string[] memory networks, DeploySuite memory suite)
        external
        returns (uint256[] memory forkIds)
    {
        (, forkIds) = LibRainDeployMechanism.deployAndBroadcast(vm, networks, 1, suite);
    }

    /// The example clone over its declared factory and implementation, as a
    /// suite.
    /// @return The clone suite.
    function exampleCloneSuite() internal view returns (DeploySuite memory) {
        return LibRainDeployMechanism.cloneCandidate(
            declaredClone("example", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies()),
            new uint256[](0)
        )
        .snapshot;
    }

    /// A clone suite deploys locally to the address its mechanism derives, and
    /// what lands there is the proxy. The positive half every refusal below is
    /// measured against.
    function testCloneSuiteDeploysLocallyToItsDerivedAddress() external {
        DeploySuite memory suite = exampleCloneSuite();
        address deployed = this.externalDeployLocally(suite);
        assertEq(deployed, suite.storedDeployedAddress);
        assertEq(deployed, this.externalDeployedAddress(suite));
        assertEq(deployed.code, suite.storedRuntimeCode);
    }

    /// A clone's factory and implementation are what its address and code are
    /// functions of, so a suite that does not declare either is refused before
    /// an address is derived from it — by the address derivation and the local
    /// deploy alike.
    function testCloneSuiteMissingADeclaredDependencyIsRefused() external {
        DeploySuite memory suite = exampleCloneSuite();
        DeployDependency[] memory declared = suite.dependencies;

        suite.dependencies = new DeployDependency[](1);
        suite.dependencies[0] = declared[1];
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, declared[0].deployedAddress)
        );
        this.externalDeployedAddress(suite);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, declared[0].deployedAddress)
        );
        this.externalDeployLocally(suite);

        suite.dependencies[0] = declared[0];
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, declared[1].deployedAddress)
        );
        this.externalDeployedAddress(suite);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, declared[1].deployedAddress)
        );
        this.externalDeployLocally(suite);
    }

    /// A Zoltu suite has no mechanism data. One that carries some is a suite
    /// declared as one mechanism and filled in as another, so every dispatch
    /// refuses it rather than deploying the creation code and ignoring the
    /// rest — the broadcast before any network is forked.
    function testZoltuSuiteCarryingMechanismDataIsRefused() external {
        DeploySuite memory suite = DeploySuite({
            suite: "zoltu-with-data",
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
        assertEq(this.externalDeployedAddress(suite), suite.storedDeployedAddress);

        suite.mechanismData = hex"00";
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        this.externalDeployedAddress(suite);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        this.externalDeployLocally(suite);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        this.externalDeployAndBroadcast(networks, suite);
    }

    /// A factory whose clone lands somewhere other than the address the formula
    /// derives is refused, naming both: a release recorded at the formula's
    /// address would otherwise be a release of a clone that is not there.
    function testCloneFactoryLandingOffTheFormulaIsRefused() external {
        DeploySuite memory suite = exampleCloneSuite();
        address elsewhere = address(uint160(suite.storedDeployedAddress) + 1);
        vm.mockCall(
            exampleCloneFactory(),
            abi.encodeWithSelector(ICloneableFactoryV4.cloneDeterministicOpenSalt.selector),
            abi.encode(elsewhere)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                CloneDerivationMismatch.selector, suite.suite, suite.storedDeployedAddress, elsewhere
            )
        );
        this.externalDeployLocally(suite);
    }

    /// A clone suite's creation code MUST be the EIP-1167 proxy over its own
    /// implementation: it is what the record states the clone was made from,
    /// and the factory never reads it, so nothing else would catch a suite
    /// carrying the creation code of something else.
    function testCloneCreationCodeThatIsNotTheProxyIsRefused() external {
        DeploySuite memory suite = exampleCloneSuite();
        suite.creationCode = type(MockCloneable).creationCode;
        vm.expectRevert(abi.encodeWithSelector(CloneCreationCodeMismatch.selector, suite.suite));
        this.externalDeployLocally(suite);

        // The proxy over a DIFFERENT implementation is still not this clone's.
        suite.creationCode = LibRainDeployClone.cloneCreationCode(exampleCloneFactory());
        vm.expectRevert(abi.encodeWithSelector(CloneCreationCodeMismatch.selector, suite.suite));
        this.externalDeployLocally(suite);
    }

    /// The per-network example clone at `TEST_SALT`, with `data` beside its
    /// per-network init data, as a candidate for `chainIds`. A `CloneDeploy`
    /// carries an internal function, so it is built here rather than passed in.
    /// @param data The one-for-every-network data to declare beside it.
    /// @param chainIds The chain ids to build it for.
    /// @return The candidate.
    function externalPerNetworkCloneCandidate(bytes memory data, uint256[] memory chainIds)
        external
        view
        returns (DeployCandidate memory)
    {
        CloneDeploy memory clone = perNetworkClone("per-network", TEST_SALT);
        clone.data = data;
        return LibRainDeployMechanism.cloneCandidate(clone, chainIds);
    }

    /// The example one-data clone, with `initDataPerNetwork` set on it, as a
    /// candidate for `chainIds`.
    /// @param chainIds The chain ids to build it for.
    /// @return The candidate.
    function externalOneDataCloneMarkedPerNetworkCandidate(uint256[] memory chainIds)
        external
        view
        returns (DeployCandidate memory)
    {
        CloneDeploy memory clone = declaredClone(
            "example", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies()
        );
        clone.data = "";
        clone.initDataPerNetwork = true;
        return LibRainDeployMechanism.cloneCandidate(clone, chainIds);
    }

    /// @param suite The suite.
    /// @param chainId The network's chain id.
    /// @return The suite's derived address on that network.
    function externalDeployedAddressOn(DeploySuite memory suite, uint256 chainId) external pure returns (address) {
        return LibRainDeployMechanism.deployedAddress(suite, chainId);
    }

    /// @param suite The suite.
    /// @return Every address the suite's mechanism derives.
    function externalDeployedAddresses(DeploySuite memory suite) external pure returns (address[] memory) {
        return LibRainDeployMechanism.deployedAddresses(suite);
    }

    /// @param suite The suite.
    /// @return Every address the suite records.
    function externalRecordedAddresses(DeploySuite memory suite) external pure returns (address[] memory) {
        return LibRainDeployMechanism.recordedAddresses(suite);
    }

    /// @param suite The suite.
    /// @return The chain id each of the suite's addresses is for.
    function externalAddressChainIds(DeploySuite memory suite) external pure returns (uint256[] memory) {
        return LibRainDeployMechanism.addressChainIds(suite);
    }

    /// @param suite The suite to deploy locally.
    /// @return Every address the suite was deployed to.
    function externalDeployLocallyEvery(DeploySuite memory suite) external returns (address[] memory) {
        return LibRainDeployMechanism.deployLocally(vm, suite);
    }

    /// The example per-network clone — Arbitrum One's admin, then Polygon's —
    /// as a suite.
    /// @return The per-network clone suite.
    function perNetworkSuite() internal view returns (DeploySuite memory) {
        return LibRainDeployMechanism.cloneCandidate(
            perNetworkClone("per-network", TEST_SALT), perNetworkCloneChainIds()
        )
        .snapshot;
    }

    /// The address the example factory clones the example implementation to
    /// with the given init data at `TEST_SALT`, derived from a `CloneTarget`
    /// built here rather than through the per-network code under test.
    /// @param data The init data.
    /// @return The clone address.
    function exampleCloneAddress(bytes memory data) internal pure returns (address) {
        return LibRainDeployClone.cloneDeployedAddress(
            CloneTarget({
                factory: exampleCloneFactory(),
                implementation: exampleCloneImplementation(),
                data: data,
                salt: TEST_SALT
            })
        );
    }

    /// A per-network declaration becomes a `ClonePerNetwork` candidate whose
    /// `CloneNetworks` carries each network's chain id, init data and the
    /// address that data derives, with no `storedDeployedAddress`; every reader
    /// of its addresses answers in the declaration's network order, and
    /// `deployedAddress` answers each chain id with that network's address.
    function testPerNetworkCloneCandidateDerivesEveryField() external view {
        CloneDeploy memory clone = perNetworkClone("per-network", TEST_SALT);
        DeployCandidate memory candidate = this.externalPerNetworkCloneCandidate("", perNetworkCloneChainIds());
        DeploySuite memory suite = candidate.snapshot;

        bytes memory arbitrumData = abi.encode(PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN);
        bytes memory polygonData = abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN);
        address arbitrumAddress = exampleCloneAddress(arbitrumData);
        address polygonAddress = exampleCloneAddress(polygonData);
        assertNotEq(arbitrumAddress, polygonAddress, "the two admins must derive apart");

        CloneNetworks memory expected = CloneNetworks({
            factory: exampleCloneFactory(),
            implementation: exampleCloneImplementation(),
            salt: TEST_SALT,
            networks: new CloneNetwork[](2)
        });
        expected.networks[0] = CloneNetwork({chainId: 42161, data: arbitrumData, deployedAddress: arbitrumAddress});
        expected.networks[1] = CloneNetwork({chainId: 137, data: polygonData, deployedAddress: polygonAddress});

        assertEq(suite.suite, clone.suite);
        assertEq(uint256(suite.mechanism), uint256(DeployMechanism.ClonePerNetwork));
        assertEq(suite.mechanismData, abi.encode(expected));
        assertEq(suite.storedDeployedAddress, address(0));
        assertEq(suite.creationCode, LibRainDeployClone.cloneCreationCode(clone.implementation));
        assertEq(suite.storedBytecodeHash, LibRainDeployClone.cloneDeployedCodehash(clone.implementation));
        assertEq(suite.storedRuntimeCode, LibRainDeployClone.cloneRuntimeCode(clone.implementation));
        assertEq(suite.artifactPath, CLONE_ARTIFACT_PATH);
        assertEq(abi.encode(suite.dependencies), abi.encode(clone.dependencies));
        assertEq(candidate.unanchorableReason, CLONE_UNANCHORABLE_REASON);

        address[] memory addresses = new address[](2);
        addresses[0] = arbitrumAddress;
        addresses[1] = polygonAddress;
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 42161;
        chainIds[1] = 137;
        assertEq(this.externalDeployedAddresses(suite), addresses);
        assertEq(this.externalRecordedAddresses(suite), addresses);
        assertEq(this.externalAddressChainIds(suite), chainIds);
        assertEq(this.externalDeployedAddressOn(suite, 42161), arbitrumAddress);
        assertEq(this.externalDeployedAddressOn(suite, 137), polygonAddress);
    }

    /// A suite at one address on every network has no per-address chain ids:
    /// Zoltu and `Clone` alike.
    function testAddressChainIdsIsEmptyForAOneAddressSuite() external view {
        assertEq(this.externalAddressChainIds(exampleCloneSuite()).length, 0);
        DeploySuite memory zoltu = DeploySuite({
            suite: "zoltu",
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
        assertEq(this.externalAddressChainIds(zoltu).length, 0);
    }

    /// A declaration with one init data for every network AND init data per
    /// network is refused naming its suite: either could be meant, and each
    /// puts the clone somewhere else. A single byte is enough to refuse.
    function testCloneCandidateRefusesDataBesidePerNetworkData() external {
        vm.expectRevert(abi.encodeWithSelector(CloneDataAmbiguous.selector, "per-network"));
        this.externalPerNetworkCloneCandidate(TEST_DATA, perNetworkCloneChainIds());

        vm.expectRevert(abi.encodeWithSelector(CloneDataAmbiguous.selector, "per-network"));
        this.externalPerNetworkCloneCandidate(hex"00", perNetworkCloneChainIds());
    }

    /// A per-network suite that also carries a `storedDeployedAddress` is
    /// refused by every reader of its addresses and by the broadcast before
    /// any network is forked: an address beside the per-network record is a
    /// second record nobody reads.
    function testPerNetworkSuiteCarryingAStoredAddressIsRefused() external {
        DeploySuite memory suite = perNetworkSuite();
        suite.storedDeployedAddress = address(1);
        bytes memory refusal = abi.encodeWithSelector(UnexpectedStoredDeployedAddress.selector, suite.suite, address(1));
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(refusal);
        this.externalDeployedAddresses(suite);
        vm.expectRevert(refusal);
        this.externalRecordedAddresses(suite);
        vm.expectRevert(refusal);
        this.externalAddressChainIds(suite);
        vm.expectRevert(refusal);
        this.externalDeployedAddressOn(suite, 42161);
        vm.expectRevert(refusal);
        this.externalDeployLocallyEvery(suite);
        vm.expectRevert(refusal);
        this.externalDeployAndBroadcast(networks, suite);
    }

    /// A per-network suite naming no network is refused: it says where the
    /// clone is on no network at all.
    function testPerNetworkSuiteWithNoNetworksIsRefused() external {
        DeploySuite memory suite = perNetworkSuite();
        suite.mechanismData = abi.encode(
            CloneNetworks({
                factory: exampleCloneFactory(),
                implementation: exampleCloneImplementation(),
                salt: TEST_SALT,
                networks: new CloneNetwork[](0)
            })
        );
        bytes memory refusal = abi.encodeWithSelector(LibRainDeployClone.NoCloneNetworks.selector);

        vm.expectRevert(refusal);
        this.externalDeployedAddresses(suite);
        vm.expectRevert(refusal);
        this.externalRecordedAddresses(suite);
        vm.expectRevert(refusal);
        this.externalDeployedAddressOn(suite, 42161);
        vm.expectRevert(refusal);
        this.externalDeployLocallyEvery(suite);
    }

    /// A per-network suite naming a chain id twice is refused naming it: two
    /// entries for one network are two answers to where the clone is there.
    function testPerNetworkSuiteNamingAChainTwiceIsRefused() external {
        DeploySuite memory suite = perNetworkSuite();
        CloneNetworks memory clones = abi.decode(suite.mechanismData, (CloneNetworks));
        clones.networks[1].chainId = 42161;
        suite.mechanismData = abi.encode(clones);
        bytes memory refusal = abi.encodeWithSelector(LibRainDeployClone.DuplicateCloneNetwork.selector, 42161);

        vm.expectRevert(refusal);
        this.externalDeployedAddresses(suite);
        vm.expectRevert(refusal);
        this.externalDeployedAddressOn(suite, 137);
        vm.expectRevert(refusal);
        this.externalDeployLocallyEvery(suite);
    }

    /// A per-network suite's address on a network it has no entry for is
    /// refused naming that chain id, never defaulted to another network's.
    function testPerNetworkAddressOnAnUndeclaredNetworkIsRefused() external {
        DeploySuite memory suite = perNetworkSuite();
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.CloneNetworkUndeclared.selector, 8453));
        this.externalDeployedAddressOn(suite, 8453);
    }

    /// A per-network suite deploys locally to each network's derived address,
    /// each clone initialized with that network's admin.
    function testPerNetworkSuiteDeploysLocallyToEachNetworksAddress() external {
        DeploySuite memory suite = perNetworkSuite();
        address[] memory deployed = this.externalDeployLocallyEvery(suite);
        assertEq(deployed, this.externalDeployedAddresses(suite));
        assertEq(deployed.length, 2);
        assertEq(deployed[0].code, suite.storedRuntimeCode);
        assertEq(deployed[1].code, suite.storedRuntimeCode);
        assertEq(MockCloneable(deployed[0]).sInitData(), abi.encode(PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN));
        assertEq(MockCloneable(deployed[1]).sInitData(), abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN));
    }

    /// Networks sharing init data share an address, and that clone is deployed
    /// once: re-cloning it would leave the first clone's initialized storage
    /// for the second `initialize` to refuse. The sharing entries are the
    /// first and the THIRD, so a check of only the entry before is not enough.
    function testPerNetworkSuiteSharingDataDeploysTheSharedCloneOnce() external {
        CloneDeploy memory clone = perNetworkClone("per-network", TEST_SALT);
        clone.initData = sharingInitData;
        uint256[] memory chainIds = new uint256[](3);
        chainIds[0] = 42161;
        chainIds[1] = 137;
        chainIds[2] = 8453;
        bytes memory shared = sharingInitData(42161);
        bytes memory other = sharingInitData(137);
        DeploySuite memory suite = LibRainDeployMechanism.cloneCandidate(clone, chainIds).snapshot;

        address[] memory deployed = this.externalDeployLocallyEvery(suite);
        assertEq(deployed.length, 3);
        assertEq(deployed[0], exampleCloneAddress(shared));
        assertEq(deployed[1], exampleCloneAddress(other));
        assertEq(deployed[2], deployed[0]);
        assertEq(MockCloneable(deployed[0]).sInitData(), shared);
        assertEq(MockCloneable(deployed[1]).sInitData(), other);
    }

    /// A per-network candidate has exactly one entry per given chain id, in
    /// the given order, with `initData`'s answer for that chain id.
    function testPerNetworkCloneCandidateIsBuiltForExactlyTheGivenChainIdsInOrder() external view {
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 137;
        chainIds[1] = 42161;
        CloneNetworks memory clones =
            abi.decode(this.externalPerNetworkCloneCandidate("", chainIds).snapshot.mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, 2);
        assertEq(clones.networks[0].chainId, 137);
        assertEq(clones.networks[0].data, abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN));
        assertEq(clones.networks[0].deployedAddress, exampleCloneAddress(abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN)));
        assertEq(clones.networks[1].chainId, 42161);
        assertEq(clones.networks[1].data, abi.encode(PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN));
        assertEq(
            clones.networks[1].deployedAddress, exampleCloneAddress(abi.encode(PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN))
        );

        chainIds = new uint256[](1);
        chainIds[0] = 137;
        clones = abi.decode(this.externalPerNetworkCloneCandidate("", chainIds).snapshot.mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, 1);
        assertEq(clones.networks[0].chainId, 137);
    }

    /// A chain id `initData` reverts on reverts the candidate with that revert,
    /// wherever in the list it is.
    function testPerNetworkCloneCandidateSurfacesAnInitDataRevert() external {
        uint256[] memory chainIds = new uint256[](3);
        chainIds[0] = 42161;
        chainIds[1] = 8453;
        chainIds[2] = 137;
        vm.expectRevert(abi.encodeWithSelector(NoPerNetworkCloneAdmin.selector, uint256(8453)));
        this.externalPerNetworkCloneCandidate("", chainIds);
    }

    /// A per-network candidate built for no chain id names no network, and its
    /// readers refuse it.
    function testPerNetworkCloneCandidateForNoChainIdIsRefusedByItsReaders() external {
        DeploySuite memory suite = this.externalPerNetworkCloneCandidate("", new uint256[](0)).snapshot;
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.NoCloneNetworks.selector));
        this.externalDeployedAddresses(suite);
    }

    /// A one-data clone never reads its `initData`, whatever the chain ids: a
    /// reverting function and chain ids it reverts on leave it a `Clone`
    /// candidate.
    function testOneDataCloneNeverReadsInitData() external view {
        CloneDeploy memory clone =
            declaredClone("example", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies());
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 8453;
        DeployCandidate memory candidate = LibRainDeployMechanism.cloneCandidate(clone, chainIds);
        assertEq(uint256(candidate.snapshot.mechanism), uint256(DeployMechanism.Clone));
        assertEq(candidate.snapshot.mechanismData, abi.encode(targetOf(clone)));

        clone.initData = perNetworkCloneInitData;
        candidate = LibRainDeployMechanism.cloneCandidate(clone, chainIds);
        assertEq(uint256(candidate.snapshot.mechanism), uint256(DeployMechanism.Clone));
        assertEq(candidate.snapshot.mechanismData, abi.encode(targetOf(clone)));
    }

    /// A one-data clone's `noInitDataPerNetwork`, read because the declaration
    /// set `initDataPerNetwork`, refuses naming the chain id it was asked for.
    function testNoInitDataPerNetworkRefusesWhenRead() external {
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 42161;
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.NoInitDataPerNetwork.selector, uint256(42161)));
        this.externalOneDataCloneMarkedPerNetworkCandidate(chainIds);
    }
}
