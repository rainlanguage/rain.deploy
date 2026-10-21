// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {stdError} from "forge-std-1.17.0/src/StdError.sol";
import {Vm, VmSafe} from "forge-std-1.17.0/src/Vm.sol";
import {ICloneableFactoryV4} from "rain-factory-pr271-0477c05/src/interface/deprecated/ICloneableFactoryV4.sol";
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
    CloneInitializeReadsStorage,
    ExtendedNetworkAddressMismatch,
    ExtendedNetworkUnfrozen,
    ExtendedNetworksUnexpected,
    LibRainDeployMechanism,
    UnexpectedMechanismData,
    UnexpectedStoredDeployedAddress
} from "../../../src/lib/LibRainDeployMechanism.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {
    exampleCloneDependencies,
    exampleCloneFactory,
    exampleCloneImplementation
} from "../../abstract/ExampleCloneDeploys.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";
import {MockSaltShiftingCloneFactory} from "../../concrete/MockSaltShiftingCloneFactory.sol";
import {
    MockInitializeRefused,
    MockStorageReadingCloneable,
    SourceUse
} from "../../concrete/MockStorageReadingCloneable.sol";
import {MockStorageSource} from "../../concrete/MockStorageSource.sol";
import {MockStorageSourceFactory} from "../../concrete/MockStorageSourceFactory.sol";
import {MockStorageReadingCloneFactory} from "../../concrete/MockStorageReadingCloneFactory.sol";
import {upgradedPerNetworkClone} from "../../abstract/UpgradedPerNetworkCloneDeploys.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN,
    PER_NETWORK_CLONE_POLYGON_ADMIN,
    NoPerNetworkCloneAdmin,
    perNetworkClone,
    perNetworkCloneChainIds,
    perNetworkCloneInitData
} from "../../abstract/PerNetworkCloneDeploys.sol";

/// Per-network init data in which Arbitrum One and Base share Arbitrum One's admin and Polygon has
/// its own.
/// @param chainId The network's chain id.
/// @return The init data on that network.
function sharingInitData(uint256 chainId) pure returns (bytes memory) {
    return perNetworkCloneInitData(chainId == 8453 ? 42161 : chainId);
}

/// @title LibRainDeployMechanismTest Tests for `LibRainDeployMechanism`.
contract LibRainDeployMechanismTest is Test {
    /// A salt with bytes set across the whole word, so a derivation that truncated it or used only
    /// its low bytes would be caught.
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

    /// The suite key MUST NOT move the address.
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

    /// `cloneCandidate` MUST derive every field of the candidate from the clone, and MUST carry the
    /// standard unanchorable reason.
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

        assertNotEq(bytes(candidate.unanchorableReason).length, 0);
    }

    /// The recorded code hash MUST be the hash of the recorded runtime code, and the recorded
    /// address MUST be where the recorded creation code lands.
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

    /// External wrapper for `LibRainDeployMechanism.deployStepData` on Arbitrum One.
    /// @param suite The suite whose step data is wanted.
    /// @return The suite's step data on Arbitrum One.
    function externalDeployStepData(DeploySuite memory suite) external pure returns (bytes memory) {
        return LibRainDeployMechanism.deployStepData(suite, 42161);
    }

    /// External wrapper for `LibRainDeployMechanism.deployStep` on a local Arbitrum One fork.
    /// @param suite The suite whose step is run.
    /// @return The address the suite's step reports, on a local fork.
    function externalDeployStep(DeploySuite memory suite) external returns (address) {
        return LibRainDeployMechanism.deployStep(
            suite
        )(Vm(address(new LocalForkVm())), LibRainDeploy.ARBITRUM_ONE, address(this), this.externalDeployStepData(suite));
    }

    /// @param networks The networks to broadcast to.
    /// @param suite The suite to broadcast.
    /// @return The fork each network was deployed on.
    function externalDeployAndBroadcast(string[] memory networks, DeploySuite memory suite)
        external
        returns (uint256[] memory)
    {
        (, uint256[] memory forkIds) = LibRainDeployMechanism.deployAndBroadcast(vm, networks, 1, suite, suite);
        return forkIds;
    }

    /// The example clone over its declared factory and implementation, as a suite.
    /// @return The clone suite.
    function exampleCloneSuite() internal view returns (DeploySuite memory) {
        return LibRainDeployMechanism.cloneCandidate(
            declaredClone("example", exampleCloneFactory(), exampleCloneImplementation(), exampleCloneDependencies()),
            new uint256[](0)
        )
        .snapshot;
    }

    /// `MockDeployable` as a Zoltu suite.
    /// @param suite The suite key.
    /// @return The suite.
    function zoltuMockDeployableSuite(string memory suite) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: suite,
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
    }

    /// A clone suite deploys locally to the address its mechanism derives, and what lands there is
    /// the proxy.
    function testCloneSuiteDeploysLocallyToItsDerivedAddress() external {
        DeploySuite memory suite = exampleCloneSuite();
        address deployed = this.externalDeployLocally(suite);
        assertEq(deployed, suite.storedDeployedAddress);
        assertEq(deployed, this.externalDeployedAddress(suite));
        assertEq(deployed.code, suite.storedRuntimeCode);
    }

    /// A clone's factory and implementation are what its address and code are functions of, so a
    /// suite that does not declare either is refused before an address is derived from it — by the
    /// address derivation and the local deploy alike.
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

    /// A Zoltu suite has no mechanism data.
    function testZoltuSuiteCarryingMechanismDataIsRefused() external {
        DeploySuite memory suite = zoltuMockDeployableSuite("zoltu-with-data");
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
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        this.externalDeployStepData(suite);
    }

    /// Each mechanism's step deploys its suite to the suite's derived address.
    function testDeployStepDeploysEachMechanismToItsDerivedAddress() external {
        DeploySuite memory zoltu = zoltuMockDeployableSuite("zoltu");
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = this.externalDeployStep(zoltu);
        assertEq(deployed, zoltu.storedDeployedAddress);
        assertEq(deployed.code, zoltu.storedRuntimeCode);

        DeploySuite memory clone = exampleCloneSuite();
        for (uint256 i = 0; i < clone.dependencies.length; i++) {
            vm.etch(clone.dependencies[i].deployedAddress, clone.dependencies[i].runtimeCode);
        }
        deployed = this.externalDeployStep(clone);
        assertEq(deployed, clone.storedDeployedAddress);
        assertEq(deployed.code, clone.storedRuntimeCode);
    }

    /// A factory whose clone lands somewhere other than the address the formula derives is refused,
    /// naming both.
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

    /// A real factory whose clone lands, and initializes its own storage, somewhere other than the address the
    /// formula derives is refused as a derivation mismatch, not as a foreign storage read.
    function testRealFactoryLandingOffTheFormulaIsADerivationMismatch() external {
        DeploySuite memory suite = exampleCloneSuite();
        assertEq(suite.dependencies[0].deployedAddress, exampleCloneFactory());
        suite.dependencies[0].runtimeCode = type(MockSaltShiftingCloneFactory).runtimeCode;
        CloneTarget memory shifted = LibRainDeployMechanism.cloneTarget(suite);
        shifted.salt ^= bytes32(uint256(1));
        address elsewhere = LibRainDeployClone.cloneDeployedAddress(shifted);
        vm.expectRevert(
            abi.encodeWithSelector(
                CloneDerivationMismatch.selector, suite.suite, suite.storedDeployedAddress, elsewhere
            )
        );
        this.externalDeployLocally(suite);
    }

    /// A clone suite's creation code MUST be the EIP-1167 proxy over its own implementation.
    function testCloneCreationCodeThatIsNotTheProxyIsRefused() external {
        DeploySuite memory suite = exampleCloneSuite();
        suite.creationCode = type(MockCloneable).creationCode;
        vm.expectRevert(abi.encodeWithSelector(CloneCreationCodeMismatch.selector, suite.suite));
        this.externalDeployLocally(suite);

        suite.creationCode = LibRainDeployClone.cloneCreationCode(exampleCloneFactory());
        vm.expectRevert(abi.encodeWithSelector(CloneCreationCodeMismatch.selector, suite.suite));
        this.externalDeployLocally(suite);
    }

    /// The per-network example clone at `TEST_SALT`, with `data` beside its per-network init data,
    /// as a candidate for `chainIds`.
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

    /// The example one-data clone, with `initDataPerNetwork` set on it, as a candidate for
    /// `chainIds`.
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

    /// The example per-network clone — Arbitrum One's admin, then Polygon's — as a suite.
    /// @return The per-network clone suite.
    function perNetworkSuite() internal view returns (DeploySuite memory) {
        return LibRainDeployMechanism.cloneCandidate(
            perNetworkClone("per-network", TEST_SALT), perNetworkCloneChainIds()
        )
        .snapshot;
    }

    /// The address the example factory clones the example implementation to with the given init
    /// data at `TEST_SALT`, derived from a `CloneTarget` built here rather than through the
    /// per-network code under test.
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

    /// A per-network declaration becomes a `ClonePerNetwork` candidate whose `CloneNetworks`
    /// carries each network's chain id, init data and the address that data derives, with no
    /// `storedDeployedAddress`.
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

    /// A suite at one address on every network has no per-address chain ids.
    function testAddressChainIdsIsEmptyForAOneAddressSuite() external view {
        assertEq(this.externalAddressChainIds(exampleCloneSuite()).length, 0);
        assertEq(this.externalAddressChainIds(zoltuMockDeployableSuite("zoltu")).length, 0);
    }

    /// A declaration with one init data for every network AND init data per network is refused
    /// naming its suite.
    function testCloneCandidateRefusesDataBesidePerNetworkData() external {
        vm.expectRevert(abi.encodeWithSelector(CloneDataAmbiguous.selector, "per-network"));
        this.externalPerNetworkCloneCandidate(TEST_DATA, perNetworkCloneChainIds());

        vm.expectRevert(abi.encodeWithSelector(CloneDataAmbiguous.selector, "per-network"));
        this.externalPerNetworkCloneCandidate(hex"00", perNetworkCloneChainIds());
    }

    /// A per-network suite that also carries a `storedDeployedAddress` is refused by every reader
    /// of its addresses and by the broadcast before any network is forked.
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

    /// A per-network suite naming no network is refused.
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

    /// A per-network suite naming a chain id twice is refused naming it.
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

    /// A per-network suite's address on a network it has no entry for is refused naming that chain
    /// id, never defaulted to another network's.
    function testPerNetworkAddressOnAnUndeclaredNetworkIsRefused() external {
        DeploySuite memory suite = perNetworkSuite();
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.CloneNetworkUndeclared.selector, 8453));
        this.externalDeployedAddressOn(suite, 8453);
    }

    /// A per-network suite deploys locally to each network's derived address, each clone
    /// initialized with that network's admin.
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

    /// @param suite The suite to deploy locally under `block.chainid`.
    function externalDeployLocallyOnChain(DeploySuite memory suite) external {
        LibRainDeployMechanism.deployLocallyOnChain(vm, suite);
    }

    function testPerNetworkSuiteDeploysLocallyOnChainOnlyThatNetworksClone() external {
        DeploySuite memory suite = perNetworkSuite();
        bytes memory mechanismData = suite.mechanismData;
        address arbitrumAddress = exampleCloneAddress(abi.encode(PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN));
        address polygonAddress = exampleCloneAddress(abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN));
        vm.chainId(137);
        LibRainDeployMechanism.deployLocallyOnChain(vm, suite);
        assertEq(suite.mechanismData, mechanismData);
        assertEq(polygonAddress.code, suite.storedRuntimeCode);
        assertEq(MockCloneable(polygonAddress).sInitData(), abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN));
        assertEq(arbitrumAddress.code.length, 0);
    }

    function testPerNetworkSuiteDeployLocallyOnAnUndeclaredChainIsRefused() external {
        DeploySuite memory suite = perNetworkSuite();
        vm.chainId(8453);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.CloneNetworkUndeclared.selector, 8453));
        this.externalDeployLocallyOnChain(suite);
    }

    /// Networks sharing init data share an address, and that clone is deployed once without skipping a later network's own clone.
    function testPerNetworkSuiteSharingDataDeploysTheSharedCloneOnce() external {
        CloneDeploy memory clone = perNetworkClone("per-network", TEST_SALT);
        clone.initData = sharingInitData;
        uint256[] memory chainIds = new uint256[](3);
        chainIds[0] = 42161;
        chainIds[1] = 8453;
        chainIds[2] = 137;
        bytes memory shared = sharingInitData(42161);
        bytes memory other = sharingInitData(137);
        DeploySuite memory suite = LibRainDeployMechanism.cloneCandidate(clone, chainIds).snapshot;

        address[] memory deployed = this.externalDeployLocallyEvery(suite);
        assertEq(deployed.length, 3);
        assertEq(deployed[0], exampleCloneAddress(shared));
        assertEq(deployed[1], deployed[0]);
        assertEq(deployed[2], exampleCloneAddress(other));
        assertEq(deployed[0].code, suite.storedRuntimeCode);
        assertEq(deployed[2].code, suite.storedRuntimeCode);
        assertEq(MockCloneable(deployed[0]).sInitData(), shared);
        assertEq(MockCloneable(deployed[2]).sInitData(), other);
    }

    /// A per-network candidate has exactly one entry per given chain id, in the given order, with
    /// `initData`'s answer for that chain id.
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

    /// A chain id `initData` reverts on reverts the candidate with that revert, wherever in the
    /// list it is.
    function testPerNetworkCloneCandidateSurfacesAnInitDataRevert() external {
        uint256[] memory chainIds = new uint256[](3);
        chainIds[0] = 42161;
        chainIds[1] = 8453;
        chainIds[2] = 137;
        vm.expectRevert(abi.encodeWithSelector(NoPerNetworkCloneAdmin.selector, uint256(8453)));
        this.externalPerNetworkCloneCandidate("", chainIds);
    }

    /// A per-network candidate built for no chain id names no network, and its readers refuse it.
    function testPerNetworkCloneCandidateForNoChainIdIsRefusedByItsReaders() external {
        DeploySuite memory suite = this.externalPerNetworkCloneCandidate("", new uint256[](0)).snapshot;
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.NoCloneNetworks.selector));
        this.externalDeployedAddresses(suite);
    }

    /// A one-data clone never reads its `initData`, whatever the chain ids.
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

    /// A one-data clone's `noInitDataPerNetwork`, read because the declaration set
    /// `initDataPerNetwork`, refuses naming the chain id it was asked for.
    function testNoInitDataPerNetworkRefusesWhenRead() external {
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 42161;
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.NoInitDataPerNetwork.selector, uint256(42161)));
        this.externalOneDataCloneMarkedPerNetworkCandidate(chainIds);
    }

    /// External wrapper for `LibRainDeployMechanism.withUnrecordedNetworks`.
    /// @param suite The suite.
    /// @param candidate The candidate.
    /// @return The suite with the candidate's networks it lacks.
    function externalWithUnrecordedNetworks(DeploySuite memory suite, DeploySuite memory candidate)
        external
        pure
        returns (DeploySuite memory)
    {
        return LibRainDeployMechanism.withUnrecordedNetworks(
            suite, candidate, LibRainDeployMechanism.addressChainIds(candidate)
        );
    }

    /// The per-network example clone at `salt` as a candidate for `chainIds`.
    /// @param salt The salt.
    /// @param chainIds The chain ids to build it for.
    /// @return The candidate's suite.
    function perNetworkSuiteAt(bytes32 salt, uint256[] memory chainIds) internal view returns (DeploySuite memory) {
        return LibRainDeployMechanism.cloneCandidate(perNetworkClone("per-network", salt), chainIds).snapshot;
    }

    /// One chain id.
    /// @param chainId The chain id.
    /// @return It, alone.
    function onlyChainId(uint256 chainId) internal pure returns (uint256[] memory) {
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = chainId;
        return chainIds;
    }

    /// A release recorded on Arbitrum One only, with an Arbitrum One admin the declaration no
    /// longer names, at a salt the candidate does not use.
    function testUnrecordedNetworkTakesTheCandidatesDataUnderTheReleasesSalt() external view {
        bytes32 releaseSalt = bytes32(uint256(5));
        DeploySuite memory release = perNetworkSuiteAt(releaseSalt, onlyChainId(42161));
        CloneNetworks memory recorded = abi.decode(release.mechanismData, (CloneNetworks));
        bytes memory recordedData = abi.encode(address(0xc3c3c3c3c3c3c3c3c3C3C3c3C3C3C3c3C3C3c3c3));
        recorded.networks[0].data = recordedData;
        recorded.networks[0].deployedAddress = LibRainDeployClone.cloneDeployedAddress(
            CloneTarget({
                factory: exampleCloneFactory(),
                implementation: exampleCloneImplementation(),
                data: recordedData,
                salt: releaseSalt
            })
        );
        release.mechanismData = abi.encode(recorded);

        DeploySuite memory candidate = perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds());
        DeploySuite memory extended = this.externalWithUnrecordedNetworks(release, candidate);

        CloneNetworks memory expected = CloneNetworks({
            factory: exampleCloneFactory(),
            implementation: exampleCloneImplementation(),
            salt: releaseSalt,
            networks: new CloneNetwork[](2)
        });
        expected.networks[0] = recorded.networks[0];
        bytes memory polygonData = abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN);
        expected.networks[1] = CloneNetwork({
            chainId: 137,
            data: polygonData,
            deployedAddress: LibRainDeployClone.cloneDeployedAddress(
                CloneTarget({
                    factory: exampleCloneFactory(),
                    implementation: exampleCloneImplementation(),
                    data: polygonData,
                    salt: releaseSalt
                })
            )
        });
        assertEq(extended.mechanismData, abi.encode(expected));
        assertNotEq(
            expected.networks[1].deployedAddress,
            abi.decode(candidate.mechanismData, (CloneNetworks)).networks[1].deployedAddress,
            "the release's salt must put Polygon somewhere the candidate's does not"
        );

        assertEq(extended.suite, release.suite);
        assertEq(extended.creationCode, release.creationCode);
        assertEq(extended.storedDeployedAddress, address(0));
        assertEq(extended.storedBytecodeHash, release.storedBytecodeHash);
        assertEq(extended.storedRuntimeCode, release.storedRuntimeCode);
        assertEq(extended.artifactPath, release.artifactPath);
        assertEq(abi.encode(extended.dependencies), abi.encode(release.dependencies));
        assertEq(uint256(extended.mechanism), uint256(DeployMechanism.ClonePerNetwork));
        assertEq(this.externalDeployedAddressOn(extended, 42161), recorded.networks[0].deployedAddress);
        assertEq(this.externalDeployedAddressOn(extended, 137), expected.networks[1].deployedAddress);
    }

    /// Recorded entries keep their order and come first.
    function testUnrecordedNetworksFollowTheRecordedOnesInTheCandidatesOrder() external view {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(137));
        uint256[] memory candidateChainIds = new uint256[](3);
        candidateChainIds[0] = 8453;
        candidateChainIds[1] = 137;
        candidateChainIds[2] = 42161;
        DeploySuite memory candidate =
        LibRainDeployMechanism.cloneCandidate(
            CloneDeploy({
                suite: "per-network",
                factory: exampleCloneFactory(),
                implementation: exampleCloneImplementation(),
                data: "",
                initDataPerNetwork: true,
                initData: sharingInitData,
                salt: TEST_SALT,
                dependencies: exampleCloneDependencies()
            }),
            candidateChainIds
        )
        .snapshot;

        CloneNetworks memory extended =
            abi.decode(this.externalWithUnrecordedNetworks(release, candidate).mechanismData, (CloneNetworks));
        assertEq(extended.networks.length, 3);
        assertEq(extended.networks[0].chainId, 137);
        assertEq(extended.networks[1].chainId, 8453);
        assertEq(extended.networks[2].chainId, 42161);
        assertEq(extended.networks[1].data, abi.encode(PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN));
        assertEq(extended.networks[2].data, abi.encode(PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN));
    }

    /// A release recording every network the candidate has comes back with the same mechanism data.
    function testFullyRecordedReleaseIsUnchanged() external view {
        DeploySuite memory release = perNetworkSuiteAt(bytes32(uint256(5)), perNetworkCloneChainIds());
        DeploySuite memory candidate = perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds());
        assertEq(this.externalWithUnrecordedNetworks(release, candidate).mechanismData, release.mechanismData);
    }

    /// Nothing is added unless both the suite and the candidate are per network.
    function testOnlyAPerNetworkSuiteTakesAPerNetworkCandidatesNetworks() external view {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(137));
        DeploySuite memory perNetwork = perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds());
        DeploySuite memory oneData = exampleCloneSuite();

        assertEq(this.externalWithUnrecordedNetworks(release, oneData).mechanismData, release.mechanismData);
        assertEq(this.externalWithUnrecordedNetworks(oneData, perNetwork).mechanismData, oneData.mechanismData);
        assertEq(
            uint256(this.externalWithUnrecordedNetworks(oneData, perNetwork).mechanism), uint256(DeployMechanism.Clone)
        );
    }

    /// A per-network suite the readers refuse is refused here too, before anything is added to it.
    function testUnrecordedNetworksRefuseAPerNetworkSuiteCarryingAStoredAddress() external {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(137));
        release.storedDeployedAddress = address(0xdead);
        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedStoredDeployedAddress.selector, release.suite, address(0xdead))
        );
        this.externalWithUnrecordedNetworks(release, perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds()));
    }

    /// `unverifiableSourceNotice` names the address and every network in order, formatting the address once.
    function testUnverifiableSourceNoticeNamesTheAddressAndEachNetwork() external pure {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
        assertEq(
            LibRainDeployMechanism.unverifiableSourceNotice(vm, networks, 0x1234567890AbcdEF1234567890aBcdef12345678),
            "no verify command: the Zoltu entry carries a factory proxy artifact path; verify the source at 0x1234567890AbcdEF1234567890aBcdef12345678 by hand on base arbitrum"
        );
    }

    /// A release under another implementation than its candidate's takes an unrecorded network at the candidate's init
    /// data under its own implementation.
    function testUnrecordedNetworkUnderAnotherImplementationTakesTheCandidatesData() external view {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        DeploySuite memory candidate =
        LibRainDeployMechanism.cloneCandidate(upgradedPerNetworkClone(), perNetworkCloneChainIds()).snapshot;

        CloneNetworks memory extended =
            abi.decode(this.externalWithUnrecordedNetworks(release, candidate).mechanismData, (CloneNetworks));
        assertEq(extended.implementation, exampleCloneImplementation());
        assertEq(extended.networks.length, 2);
        assertEq(extended.networks[1].chainId, 137);
        assertEq(extended.networks[1].data, perNetworkCloneInitData(137));
    }

    /// A release under another implementation that records every network its candidate has is unchanged.
    function testFullyRecordedReleaseUnderAnotherImplementationIsUnchanged() external view {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds());
        DeploySuite memory candidate =
        LibRainDeployMechanism.cloneCandidate(upgradedPerNetworkClone(), perNetworkCloneChainIds()).snapshot;
        assertEq(this.externalWithUnrecordedNetworks(release, candidate).mechanismData, release.mechanismData);
    }

    /// External wrapper for `LibRainDeployMechanism.withUnrecordedNetworks` over given chain ids in play.
    /// @param suite The suite.
    /// @param candidate The candidate.
    /// @param chainIds The chain ids in play.
    /// @return The suite with the candidate's networks in play it lacks.
    function externalWithUnrecordedNetworksIn(
        DeploySuite memory suite,
        DeploySuite memory candidate,
        uint256[] memory chainIds
    ) external pure returns (DeploySuite memory) {
        return LibRainDeployMechanism.withUnrecordedNetworks(suite, candidate, chainIds);
    }

    /// A candidate network not in play is not added, so a release under another implementation is not refused for
    /// it, and one under the candidate's own does not take it.
    function testUnrecordedNetworkNotInPlayIsNotAdded() external view {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        DeploySuite memory upgraded =
        LibRainDeployMechanism.cloneCandidate(upgradedPerNetworkClone(), perNetworkCloneChainIds()).snapshot;
        assertEq(
            this.externalWithUnrecordedNetworksIn(release, upgraded, onlyChainId(42161)).mechanismData,
            release.mechanismData
        );
        assertEq(
            this.externalWithUnrecordedNetworksIn(release, upgraded, new uint256[](0)).mechanismData,
            release.mechanismData
        );
        DeploySuite memory candidate = perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds());
        assertEq(
            this.externalWithUnrecordedNetworksIn(release, candidate, onlyChainId(42161)).mechanismData,
            release.mechanismData
        );
        CloneNetworks memory polygon = abi.decode(
            this.externalWithUnrecordedNetworksIn(release, candidate, onlyChainId(137)).mechanismData, (CloneNetworks)
        );
        assertEq(polygon.networks.length, 2);
        assertEq(polygon.networks[1].chainId, 137);
    }

    /// External wrapper for `LibRainDeployMechanism.withExtendedNetworks`.
    /// @param suite The release.
    /// @param extended The networks it was extended to.
    /// @return The release with them.
    function externalWithExtendedNetworks(DeploySuite memory suite, CloneNetwork[] memory extended)
        external
        pure
        returns (DeploySuite memory)
    {
        return LibRainDeployMechanism.withExtendedNetworks(suite, extended);
    }

    /// External wrapper for `LibRainDeployMechanism.checkNetworkFrozen`.
    /// @param frozen The release with its extended networks.
    /// @param chainId The network's chain id.
    /// @param where The address checked on it.
    function externalCheckNetworkFrozen(DeploySuite memory frozen, uint256 chainId, address where) external pure {
        LibRainDeployMechanism.checkNetworkFrozen(frozen, "net", chainId, where);
    }

    /// Polygon at the given init data, at the address it derives under the example clone at `TEST_SALT`.
    /// @param data The init data.
    /// @return The entry.
    function polygonAt(bytes memory data) internal pure returns (CloneNetwork[] memory) {
        CloneNetwork[] memory networks = new CloneNetwork[](1);
        networks[0] = CloneNetwork({chainId: 137, data: data, deployedAddress: exampleCloneAddress(data)});
        return networks;
    }

    /// An extended network is appended after the recorded ones exactly as declared, and the rest of the suite is
    /// kept.
    function testExtendedNetworkIsAppendedAsDeclared() external view {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        bytes memory data = abi.encode(address(0xc3c3c3c3c3c3c3c3c3C3C3c3C3C3C3c3C3C3c3c3));
        CloneNetwork[] memory extension = polygonAt(data);
        DeploySuite memory extended = this.externalWithExtendedNetworks(release, extension);

        CloneNetworks memory expected = abi.decode(release.mechanismData, (CloneNetworks));
        CloneNetwork memory recorded = expected.networks[0];
        expected.networks = new CloneNetwork[](2);
        expected.networks[0] = recorded;
        expected.networks[1] = extension[0];
        assertEq(extended.mechanismData, abi.encode(expected));
        assertEq(extended.suite, release.suite);
        assertEq(extended.creationCode, release.creationCode);
        assertEq(extended.storedDeployedAddress, release.storedDeployedAddress);
        assertEq(extended.storedBytecodeHash, release.storedBytecodeHash);
        assertEq(extended.storedRuntimeCode, release.storedRuntimeCode);
        assertEq(extended.artifactPath, release.artifactPath);
        assertEq(abi.encode(extended.dependencies), abi.encode(release.dependencies));
        assertEq(uint256(extended.mechanism), uint256(DeployMechanism.ClonePerNetwork));
    }

    /// No extended network leaves any suite as it is.
    function testNoExtendedNetworkLeavesTheSuiteUnchanged() external view {
        DeploySuite memory oneData = exampleCloneSuite();
        assertEq(abi.encode(this.externalWithExtendedNetworks(oneData, new CloneNetwork[](0))), abi.encode(oneData));
    }

    /// Extended networks on a suite that is not per network are refused.
    function testExtendedNetworksOnAOneDataCloneAreRefused() external {
        DeploySuite memory oneData = exampleCloneSuite();
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnexpected.selector, oneData.suite));
        this.externalWithExtendedNetworks(oneData, polygonAt(TEST_DATA));
    }

    /// Extended networks on a Zoltu suite are refused.
    function testExtendedNetworksOnAZoltuSuiteAreRefused() external {
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnexpected.selector, "zoltu"));
        this.externalWithExtendedNetworks(zoltuMockDeployableSuite("zoltu"), polygonAt(TEST_DATA));
    }

    /// An extended network at an address its init data does not derive is refused, naming both.
    function testExtendedNetworkAtAnotherAddressIsRefused() external {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        CloneNetwork[] memory extension = polygonAt(TEST_DATA);
        address derived = extension[0].deployedAddress;
        extension[0].deployedAddress = address(0xdead);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkAddressMismatch.selector, release.suite, uint256(137), derived, address(0xdead)
            )
        );
        this.externalWithExtendedNetworks(release, extension);
    }

    /// A second extended network at an address its init data does not derive is refused though the first is
    /// correct, and both are appended once it is corrected.
    function testSecondExtendedNetworkAtAnotherAddressIsRefused() external {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        bytes memory baseData = abi.encode(address(0xb4b4B4B4b4b4B4B4b4b4B4B4b4b4b4b4B4B4B4B4));
        CloneNetwork[] memory extension = new CloneNetwork[](2);
        extension[0] = polygonAt(TEST_DATA)[0];
        extension[1] = CloneNetwork({chainId: 8453, data: baseData, deployedAddress: address(0xdead)});
        address derived = exampleCloneAddress(baseData);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkAddressMismatch.selector, release.suite, uint256(8453), derived, address(0xdead)
            )
        );
        this.externalWithExtendedNetworks(release, extension);

        extension[1].deployedAddress = derived;
        CloneNetworks memory extended =
            abi.decode(this.externalWithExtendedNetworks(release, extension).mechanismData, (CloneNetworks));
        assertEq(extended.networks.length, 3);
        assertEq(extended.networks[1].chainId, 137);
        assertEq(extended.networks[2].chainId, 8453);
        assertEq(extended.networks[2].deployedAddress, derived);
    }

    /// A network declared twice as extended is refused as a duplicate.
    function testExtendedNetworkDeclaredTwiceIsRefused() external {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        CloneNetwork[] memory extension = new CloneNetwork[](2);
        extension[0] = polygonAt(TEST_DATA)[0];
        extension[1] = polygonAt(TEST_DATA)[0];
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.DuplicateCloneNetwork.selector, uint256(137)));
        this.externalWithExtendedNetworks(release, extension);
    }

    /// A release under another implementation than its candidate's, whose extended networks cover every network
    /// the candidate has, takes nothing from the candidate.
    function testExtendedReleaseUnderAnotherImplementationTakesNothingFromTheCandidate() external view {
        DeploySuite memory release = this.externalWithExtendedNetworks(
            perNetworkSuiteAt(TEST_SALT, onlyChainId(42161)), polygonAt(perNetworkCloneInitData(137))
        );
        DeploySuite memory candidate =
        LibRainDeployMechanism.cloneCandidate(upgradedPerNetworkClone(), perNetworkCloneChainIds()).snapshot;
        assertNotEq(
            abi.decode(candidate.mechanismData, (CloneNetworks)).implementation,
            abi.decode(release.mechanismData, (CloneNetworks)).implementation
        );
        assertEq(this.externalWithUnrecordedNetworks(release, candidate).mechanismData, release.mechanismData);
    }

    /// An extended network the release already records is refused as a duplicate.
    function testExtendedNetworkTheReleaseRecordsIsRefused() external {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds());
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.DuplicateCloneNetwork.selector, uint256(137)));
        this.externalWithExtendedNetworks(release, polygonAt(TEST_DATA));
    }

    /// An extended network the release already records is refused as a duplicate even at an address its init data
    /// does not derive.
    function testExtendedNetworkTheReleaseRecordsAtAnotherAddressIsRefusedAsADuplicate() external {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        CloneNetwork[] memory extension = new CloneNetwork[](1);
        extension[0] = CloneNetwork({chainId: 42161, data: TEST_DATA, deployedAddress: address(0xdead)});
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.DuplicateCloneNetwork.selector, uint256(42161)));
        this.externalWithExtendedNetworks(release, extension);
    }

    /// An extended network keeps its own init data when the candidate's for that network differs.
    function testExtendedNetworkIsNotTakenFromTheCandidate() external view {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        DeploySuite memory candidate = perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds());
        DeploySuite memory extended = this.externalWithExtendedNetworks(release, polygonAt(TEST_DATA));
        CloneNetworks memory onNetworks =
            abi.decode(this.externalWithUnrecordedNetworks(extended, candidate).mechanismData, (CloneNetworks));
        assertEq(onNetworks.networks.length, 2);
        assertEq(onNetworks.networks[1].data, TEST_DATA);
        assertEq(onNetworks.networks[1].deployedAddress, exampleCloneAddress(TEST_DATA));
        assertNotEq(TEST_DATA, abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN));
    }

    /// A per-network suite is refused on a network it has no entry for, and passes on each it has.
    function testNetworkFrozenOnlyWhereThePerNetworkSuiteHasAnEntry() external {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        DeploySuite memory extended = this.externalWithExtendedNetworks(release, polygonAt(TEST_DATA));
        this.externalCheckNetworkFrozen(extended, 42161, address(1));
        this.externalCheckNetworkFrozen(extended, 137, address(1));
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworkUnfrozen.selector, release.suite, "net", address(2)));
        this.externalCheckNetworkFrozen(extended, 8453, address(2));
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworkUnfrozen.selector, release.suite, "net", address(3)));
        this.externalCheckNetworkFrozen(release, 137, address(3));
    }

    /// A suite that is not per network is frozen on every network.
    function testOneDataSuiteIsFrozenEverywhere() external view {
        this.externalCheckNetworkFrozen(exampleCloneSuite(), 8453, address(1));
    }

    /// External wrapper for `LibRainDeployMechanism.checkNetworksFrozen`.
    /// @param frozen The release with its extended networks.
    /// @param onNetworks The release as it would be broadcast.
    /// @param networks The networks to broadcast to.
    function externalCheckNetworksFrozen(
        DeploySuite memory frozen,
        DeploySuite memory onNetworks,
        string[] memory networks
    ) external pure {
        LibRainDeployMechanism.checkNetworksFrozen(frozen, onNetworks, networks);
    }

    /// Two network names.
    /// @param first The first.
    /// @param second The second.
    /// @return Both, in order.
    function twoNetworks(string memory first, string memory second) internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = first;
        networks[1] = second;
        return networks;
    }

    /// A release recording Arbitrum One alone is refused a broadcast to Polygon until Polygon is declared, naming
    /// Polygon and the address it would be broadcast at, and passes once it is.
    function testBroadcastToAnUndeclaredNetworkIsRefused() external {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        DeploySuite memory onNetworks =
            this.externalWithUnrecordedNetworks(release, perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds()));
        address polygonAddress = abi.decode(onNetworks.mechanismData, (CloneNetworks)).networks[1].deployedAddress;
        string[] memory networks = twoNetworks(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON);

        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector, release.suite, LibRainDeploy.POLYGON, polygonAddress
            )
        );
        this.externalCheckNetworksFrozen(release, onNetworks, networks);

        this.externalCheckNetworksFrozen(
            this.externalWithExtendedNetworks(release, polygonAt(TEST_DATA)), onNetworks, networks
        );
    }

    /// Recorded networks need no declaration, and a network the broadcast release has no entry for is left to the
    /// broadcast to refuse.
    function testBroadcastToRecordedNetworksIsNotChecked() external view {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        DeploySuite memory onNetworks =
            this.externalWithUnrecordedNetworks(release, perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds()));
        this.externalCheckNetworksFrozen(
            release, onNetworks, twoNetworks(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE)
        );
        DeploySuite memory full = perNetworkSuiteAt(TEST_SALT, perNetworkCloneChainIds());
        this.externalCheckNetworksFrozen(full, full, twoNetworks(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON));
    }

    /// The broadcast release's first entry is checked like every other: a release recording Arbitrum One alone is
    /// refused a broadcast whose only entry is Polygon, naming Polygon and the address it would be broadcast at.
    function testBroadcastReleasesFirstEntryIsChecked() external {
        DeploySuite memory release = perNetworkSuiteAt(TEST_SALT, onlyChainId(42161));
        DeploySuite memory onNetworks = perNetworkSuiteAt(TEST_SALT, onlyChainId(137));
        address polygonAddress = abi.decode(onNetworks.mechanismData, (CloneNetworks)).networks[0].deployedAddress;
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.POLYGON;

        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector, release.suite, LibRainDeploy.POLYGON, polygonAddress
            )
        );
        this.externalCheckNetworksFrozen(release, onNetworks, networks);
    }

    /// External wrapper for `LibRainDeployMechanism.withMechanismData`.
    /// @param suite The suite.
    /// @param mechanismData The mechanism data it takes.
    /// @return The suite with that mechanism data.
    function externalWithMechanismData(DeploySuite memory suite, bytes memory mechanismData)
        external
        pure
        returns (DeploySuite memory)
    {
        return LibRainDeployMechanism.withMechanismData(suite, mechanismData);
    }

    /// Replacing a suite's mechanism data keeps every other field, its stored address among them.
    function testWithMechanismDataKeepsEveryOtherField() external view {
        DeploySuite memory suite = zoltuMockDeployableSuite("zoltu");
        assertNotEq(suite.storedDeployedAddress, address(0));
        DeploySuite memory replaced = this.externalWithMechanismData(suite, hex"beef");
        suite.mechanismData = hex"beef";
        assertEq(abi.encode(replaced), abi.encode(suite));
    }

    /// A suite that is not per network is never checked.
    function testBroadcastOfAOneDataSuiteIsNotChecked() external view {
        DeploySuite memory oneData = exampleCloneSuite();
        this.externalCheckNetworksFrozen(
            perNetworkSuiteAt(TEST_SALT, onlyChainId(42161)),
            oneData,
            twoNetworks(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON)
        );
    }

    /// A clone over a fresh factory and `MockStorageReadingCloneable`, initialized against a fresh source.
    /// @param use How `initialize` treats the source.
    /// @return The suite.
    /// @return The source `initialize` treats as `use` says.
    function storageClone(SourceUse use) internal returns (DeploySuite memory, address) {
        address source = address(new MockStorageSource());
        return (storageCloneOver(address(new MockCloneFactory()), source, use), source);
    }

    /// A clone over a given factory and `MockStorageReadingCloneable`, initialized against a given source.
    /// @param factory The clone factory.
    /// @param source The account `initialize` treats as `use` says.
    /// @param use How `initialize` treats the source.
    /// @return The suite.
    function storageCloneOver(address factory, address source, SourceUse use) internal returns (DeploySuite memory) {
        MockStorageReadingCloneable implementation = new MockStorageReadingCloneable();
        DeployDependency[] memory dependencies = new DeployDependency[](3);
        dependencies[0] = DeployDependency({deployedAddress: factory, runtimeCode: factory.code});
        dependencies[1] =
            DeployDependency({deployedAddress: address(implementation), runtimeCode: address(implementation).code});
        dependencies[2] = DeployDependency({deployedAddress: source, runtimeCode: source.code});
        CloneDeploy memory clone = declaredClone("storage-clone", factory, address(implementation), dependencies);
        clone.data = abi.encode(source, use);
        return LibRainDeployMechanism.cloneCandidate(clone, new uint256[](0)).snapshot;
    }

    /// A factory whose clone lands off the formula and whose call reads another account's storage is refused as a
    /// derivation mismatch: where the clone landed is checked before what the call read.
    function testCloneFactoryLandingOffTheFormulaAndReadingStorageIsADerivationMismatch() external {
        address source = address(new MockStorageSource());
        DeploySuite memory suite = storageCloneOver(address(new MockSaltShiftingCloneFactory()), source, SourceUse.Read);
        CloneTarget memory shifted = LibRainDeployMechanism.cloneTarget(suite);
        shifted.salt ^= bytes32(uint256(1));
        address elsewhere = LibRainDeployClone.cloneDeployedAddress(shifted);
        assertNotEq(elsewhere, suite.storedDeployedAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                CloneDerivationMismatch.selector, suite.suite, suite.storedDeployedAddress, elsewhere
            )
        );
        this.externalDeployLocally(suite);
    }

    /// An `initialize` that reads an account a pre-existing dependency creates for it is refused naming that
    /// account: only the clone and what it creates are empty on chain too.
    function testCloneInitializeReadingAnAccountADependencyCreatesIsRefused() external {
        address sourceFactory = address(new MockStorageSourceFactory());
        DeploySuite memory suite =
            storageCloneOver(address(new MockCloneFactory()), sourceFactory, SourceUse.ReadFactoryChild);
        address child = vm.computeCreateAddress(sourceFactory, vm.getNonce(sourceFactory));
        vm.expectRevert(
            abi.encodeWithSelector(CloneInitializeReadsStorage.selector, suite.suite, child, bytes32(uint256(1)))
        );
        this.externalDeployLocally(suite);
    }

    /// An `initialize` that reads another account's storage is refused naming the account and slot, whether the
    /// read would have reverted it or not.
    function testCloneInitializeReadingAnotherAccountsStorageIsRefused() external {
        (DeploySuite memory suite, address source) = storageClone(SourceUse.ReadRequired);
        vm.expectRevert(
            abi.encodeWithSelector(CloneInitializeReadsStorage.selector, suite.suite, source, bytes32(uint256(1)))
        );
        this.externalDeployLocally(suite);

        (suite, source) = storageClone(SourceUse.Read);
        vm.expectRevert(
            abi.encodeWithSelector(CloneInitializeReadsStorage.selector, suite.suite, source, bytes32(uint256(1)))
        );
        this.externalDeployLocally(suite);
    }

    /// An account no `Create` access names has no creator, reported as zero, even when an access of another kind
    /// names it.
    function testCreatorInOfAnAccountNothingCreatedIsAbsentAndZero() external pure {
        Vm.AccountAccess[] memory accesses = new Vm.AccountAccess[](2);
        accesses[0].kind = VmSafe.AccountAccessKind.Create;
        accesses[0].account = address(0xA1);
        accesses[0].accessor = address(0xC1);
        accesses[1].kind = VmSafe.AccountAccessKind.Call;
        accesses[1].account = address(0xA2);
        accesses[1].accessor = address(0xC2);
        (bool created, address creator) = LibRainDeployMechanism.creatorIn(address(0xA2), accesses);
        assertFalse(created);
        assertEq(creator, address(0));
        (created, creator) = LibRainDeployMechanism.creatorIn(address(0xA1), accesses);
        assertTrue(created);
        assertEq(creator, address(0xC1));
    }

    /// A `Create` access in a synthetic recording.
    /// @param account The account created.
    /// @param accessor Its creator.
    /// @return The access.
    function createAccess(address account, address accessor) internal pure returns (Vm.AccountAccess memory) {
        Vm.AccountAccess memory access;
        access.kind = VmSafe.AccountAccessKind.Create;
        access.account = account;
        access.accessor = accessor;
        return access;
    }

    /// The clone is under itself in an empty recording, and a chain of creators as long as the recording reaches it:
    /// the walk takes one step more than the recording has accesses.
    function testCreatedUnderWalksAsManyStepsAsTheRecordHasAccesses() external pure {
        address clone = address(0xC10);
        assertTrue(LibRainDeployMechanism.createdUnder(clone, clone, new Vm.AccountAccess[](0)));

        Vm.AccountAccess[] memory accesses = new Vm.AccountAccess[](1);
        accesses[0] = createAccess(address(0xA1), clone);
        assertTrue(LibRainDeployMechanism.createdUnder(address(0xA1), clone, accesses));

        accesses = new Vm.AccountAccess[](2);
        accesses[0] = createAccess(address(0xA1), clone);
        accesses[1] = createAccess(address(0xA2), address(0xA1));
        assertTrue(LibRainDeployMechanism.createdUnder(address(0xA2), clone, accesses));
        assertFalse(LibRainDeployMechanism.createdUnder(address(0xA3), clone, accesses));
    }

    /// A cycle of creators that never reaches the clone is not under it, and the walk ends.
    function testCreatedUnderACycleIsNotTheClones() external pure {
        Vm.AccountAccess[] memory accesses = new Vm.AccountAccess[](2);
        accesses[0] = createAccess(address(0xA1), address(0xA2));
        accesses[1] = createAccess(address(0xA2), address(0xA1));
        assertFalse(LibRainDeployMechanism.createdUnder(address(0xA1), address(0xC10), accesses));
    }

    /// An `initialize` that reads the storage of an account it creates, or of one such an account creates, deploys,
    /// while a read of an account that predates the call is still refused.
    function testCloneInitializeReadingAnAccountItCreatesDeploys() external {
        (DeploySuite memory suite, address source) = storageClone(SourceUse.ReadChild);
        assertEq(this.externalDeployLocally(suite), suite.storedDeployedAddress);

        (suite, source) = storageClone(SourceUse.ReadGrandchild);
        assertEq(this.externalDeployLocally(suite), suite.storedDeployedAddress);

        (suite, source) = storageClone(SourceUse.Read);
        vm.expectRevert(
            abi.encodeWithSelector(CloneInitializeReadsStorage.selector, suite.suite, source, bytes32(uint256(1)))
        );
        this.externalDeployLocally(suite);
    }

    /// A read of another account's storage is refused when that account wrote a slot first in the same call.
    function testCloneInitializeReadingAfterAWriteIsRefused() external {
        (DeploySuite memory suite, address source) = storageClone(SourceUse.WriteThenRead);
        vm.expectRevert(
            abi.encodeWithSelector(CloneInitializeReadsStorage.selector, suite.suite, source, bytes32(uint256(1)))
        );
        this.externalDeployLocally(suite);
    }

    /// A factory's read of its own storage is refused: the factory predates the call.
    function testCloneFactoryReadingItsOwnStorageIsRefused() external {
        MockStorageReadingCloneFactory factory = new MockStorageReadingCloneFactory();
        MockCloneable implementation = new MockCloneable();
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({deployedAddress: address(factory), runtimeCode: address(factory).code});
        dependencies[1] =
            DeployDependency({deployedAddress: address(implementation), runtimeCode: address(implementation).code});
        CloneDeploy memory clone =
            declaredClone("storage-factory", address(factory), address(implementation), dependencies);
        DeploySuite memory suite = LibRainDeployMechanism.cloneCandidate(clone, new uint256[](0)).snapshot;
        vm.expectRevert(
            abi.encodeWithSelector(CloneInitializeReadsStorage.selector, suite.suite, address(factory), bytes32(0))
        );
        this.externalDeployLocally(suite);
    }

    /// An `initialize` that writes another account's storage without reading it deploys.
    function testCloneInitializeWritingAnotherAccountsStorageDeploys() external {
        (DeploySuite memory suite, address source) = storageClone(SourceUse.Write);
        assertEq(this.externalDeployLocally(suite), suite.storedDeployedAddress);
        assertEq(MockStorageSource(source).sValue(), 1);
    }

    /// An `initialize` that reverts without reading another account's storage reverts the local deploy with its own
    /// revert.
    function testCloneInitializeRevertIsBubbled() external {
        (DeploySuite memory suite,) = storageClone(SourceUse.Refuse);
        vm.expectRevert(abi.encodeWithSelector(MockInitializeRefused.selector));
        this.externalDeployLocally(suite);
    }

    /// @param mechanism A mechanism byte, which may lie outside the enum.
    function externalDeployStepOf(uint8 mechanism) external pure {
        DeploySuite memory suite;
        // `mechanism` is the eighth field of `DeploySuite`.
        assembly ("memory-safe") {
            mstore(add(suite, 0xe0), mechanism)
        }
        LibRainDeployMechanism.deployStep(suite);
    }

    /// A suite whose mechanism lies outside the enum panics on reading it, before any step is chosen.
    function testDeployStepPanicsOnAMechanismOutsideTheEnum(uint8 mechanism) external {
        mechanism = uint8(bound(mechanism, uint256(type(DeployMechanism).max) + 1, type(uint8).max));
        vm.expectRevert(stdError.enumConversionError);
        this.externalDeployStepOf(mechanism);
    }

    /// `deployStep` and `LibRainDeploySnapshot.mechanismName` hold one table entry per member, five in all.
    function testDeployMechanismHasFiveMembers() external pure {
        assertEq(uint256(type(DeployMechanism).max), 4);
    }
}
