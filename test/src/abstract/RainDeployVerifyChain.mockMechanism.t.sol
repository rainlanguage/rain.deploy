// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm, VmSafe} from "forge-std-1.17.0/src/Vm.sol";
import {DeployCandidate, DeployDeclaration, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibMockNetworkRecord, MockNetworkDeploy} from "../../lib/LibMockNetworkRecord.sol";
import {MockCreate2DeploySuites} from "../../abstract/MockCreate2DeploySuites.sol";
import {
    LibMockCreate2Mechanism,
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_MECHANISM_ID,
    MOCK_CREATE2_SALT,
    MockCreate2NetworkUnfrozen
} from "../../lib/LibMockCreate2Mechanism.sol";
import {IMockMechanismProbe, MOCK_MECHANISM_PROBE} from "../../lib/LibMockMechanismProbe.sol";
import {LibMockSaltMechanism, MOCK_SALT_MECHANISM_ID} from "../../lib/LibMockSaltMechanism.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title RainDeployVerifyChainMockMechanismTest
/// @notice The chain group derives, freezes and checks on chain through a non-Zoltu mechanism handler.
contract RainDeployVerifyChainMockMechanismTest is MockCreate2DeploySuites, RainDeployVerifyChain {
    LocalForkVm internal sForkVm;
    /// The config the salt mechanism declares; empty unless a test sets it.
    bytes internal sMockConfig;

    function setUp() external {
        sForkVm = new LocalForkVm();
    }

    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        LibRainDeployDeclaration.setNetworks(d, networks);
        LibMockCreate2Mechanism.extend(d);
        LibMockSaltMechanism.extend(d);
        d.mechanisms[d.mechanisms.length - 1].config = sMockConfig;
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({snapshot: mockCandidate(), unanchorableReason: ""});
        LibRainDeployDeclaration.addCandidates(d, candidates);
        return d;
    }

    function networkAddress(uint256 chainId) internal pure returns (address) {
        bytes32 salt = keccak256(abi.encode(MOCK_CREATE2_SALT, abi.encode(chainId)));
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), MOCK_CREATE2_FACTORY, salt, keccak256(type(MockDeployable).creationCode)
                        )
                    )
                )
            )
        );
    }

    function etchLive(uint256 chainId) internal {
        vm.etch(networkAddress(chainId), type(MockDeployable).runtimeCode);
        vm.makePersistent(networkAddress(chainId));
    }

    function networkConfigs(string memory a, string memory b) internal pure returns (string[] memory) {
        string[] memory names = new string[](2);
        names[0] = a;
        names[1] = b;
        return names;
    }

    function checkOn(string memory a, string memory b, DeploySuite memory suite) external {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = suite;
        checkAllOn(networkConfigs(a, b), suites);
    }

    function checkAllOn(string[] memory names, DeploySuite[] memory suites) internal {
        checkDeployedOnNetworks(
            declaration(), Vm(address(sForkVm)), LibRainDeploy.declaredNetworkConfigs(names), suites
        );
    }

    function externalCheckAllOn(string[] memory names, DeploySuite[] memory suites) external {
        checkAllOn(names, suites);
    }

    function testChecksEachNetworkAtItsOwnAddress() external {
        etchLive(42161);
        etchLive(137);
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON, mockRelease());
    }

    function testRefusesANetworkWhoseOwnAddressIsEmpty() external {
        etchLive(42161);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, networkAddress(137)
            )
        );
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON, mockRelease());
    }

    /// A network the candidate adds but the release does not record is refused as unfrozen, whether or not its
    /// address is live.
    function testRefusesAnUnrecordedCandidateNetworkAsUnfrozen() external {
        etchLive(42161);
        etchLive(8453);
        DeploySuite memory release = mockRelease();
        vm.expectRevert(
            abi.encodeWithSelector(
                MockCreate2NetworkUnfrozen.selector, release.suite, LibRainDeploy.BASE, networkAddress(8453)
            )
        );
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE, release);
    }

    function writeBaseRecord(string memory root, string memory suite) internal {
        //forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.removeDir(root, true) {} catch {}
        MockNetworkDeploy[] memory extended = new MockNetworkDeploy[](1);
        extended[0] =
            MockNetworkDeploy({chainId: 8453, data: abi.encode(uint256(8453)), deployedAddress: networkAddress(8453)});
        LibMockNetworkRecord.write(vm, root, suite, extended);
        this.setMockRecordRoot(root);
    }

    function testChecksARecordedExtendedNetworkAtItsDeclaredAddress() external {
        string memory root = "test/generated-snapshot/mock-create2-verify-chain-extended";
        writeBaseRecord(root, mockRelease().suite);
        etchLive(42161);
        etchLive(8453);
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE, mockRelease());
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);
    }

    function arbitrumOnlySuite() internal view returns (DeploySuite memory) {
        MockNetworkDeploy[] memory networks = new MockNetworkDeploy[](1);
        networks[0] = mockNetwork(42161);
        return mockSuite("arbitrum-only@0_0_1", networks);
    }

    function checkOnChainCall(DeploySuite memory suite, string memory network, uint256 chainId)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(
            IMockMechanismProbe.checkOnChain,
            (MOCK_CREATE2_MECHANISM_ID, suite.suite, network, chainId, networkAddress(chainId))
        );
    }

    /// `checkOnChain` runs once for each suite on each network that suite is required on, and on no other.
    function testCheckOnChainRunsOncePerRequiredNetwork() external {
        etchLive(42161);
        etchLive(137);
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = mockRelease();
        suites[1] = arbitrumOnlySuite();
        string[] memory names = new string[](3);
        names[0] = LibRainDeploy.ARBITRUM_ONE;
        names[1] = LibRainDeploy.POLYGON;
        names[2] = LibRainDeploy.ETHEREUM;

        vm.expectCall(MOCK_MECHANISM_PROBE, checkOnChainCall(suites[0], LibRainDeploy.ARBITRUM_ONE, 42161), 1);
        vm.expectCall(MOCK_MECHANISM_PROBE, checkOnChainCall(suites[0], LibRainDeploy.POLYGON, 137), 1);
        vm.expectCall(MOCK_MECHANISM_PROBE, checkOnChainCall(suites[0], LibRainDeploy.ETHEREUM, 1), 0);
        vm.expectCall(MOCK_MECHANISM_PROBE, checkOnChainCall(suites[1], LibRainDeploy.ARBITRUM_ONE, 42161), 1);
        vm.expectCall(MOCK_MECHANISM_PROBE, checkOnChainCall(suites[1], LibRainDeploy.POLYGON, 137), 0);
        vm.expectCall(MOCK_MECHANISM_PROBE, checkOnChainCall(suites[1], LibRainDeploy.ETHEREUM, 1), 0);
        this.externalCheckAllOn(names, suites);
    }

    function testCheckOnChainRefusalStopsTheCheck() external {
        etchLive(42161);
        etchLive(137);
        DeploySuite memory release = mockRelease();
        vm.mockCallRevert(
            MOCK_MECHANISM_PROBE, checkOnChainCall(release, LibRainDeploy.POLYGON, 137), abi.encode("refused")
        );
        vm.expectRevert(abi.encode("refused"));
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON, release);
    }

    function testAddRecordedNetworksRunsOncePerSuite() external {
        etchLive(42161);
        etchLive(137);
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = mockRelease();
        suites[1] = arbitrumOnlySuite();

        vm.expectCall(
            MOCK_MECHANISM_PROBE,
            abi.encodeCall(IMockMechanismProbe.addRecordedNetworks, (MOCK_CREATE2_MECHANISM_ID, suites[0].suite)),
            1
        );
        vm.expectCall(
            MOCK_MECHANISM_PROBE,
            abi.encodeCall(IMockMechanismProbe.addRecordedNetworks, (MOCK_CREATE2_MECHANISM_ID, suites[1].suite)),
            1
        );
        this.externalCheckAllOn(networkConfigs(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON), suites);
    }

    /// The recorded network and the candidate's network are added to the copies the check reads, never to the
    /// suites the caller holds.
    function testCheckLeavesTheCallersSuitesUnchanged() external {
        string memory root = "test/generated-snapshot/mock-create2-verify-chain-unchanged";
        writeBaseRecord(root, mockRelease().suite);
        etchLive(42161);
        etchLive(8453);
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = mockRelease();
        bytes32 before = keccak256(abi.encode(suites));

        DeploySuite memory recorded = mockRelease();
        addRecordedNetworks(declaration(), recorded);
        assertNotEq(keccak256(abi.encode(recorded)), keccak256(abi.encode(suites[0])), "nothing to add");

        checkAllOn(networkConfigs(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE), suites);

        assertEq(keccak256(abi.encode(suites)), before);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);
    }

    function setMockConfig(bytes memory config) external {
        sMockConfig = config;
    }

    function checkNetworkCall(bytes32 mechanismId, string memory network, uint256 chainId)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(IMockMechanismProbe.checkNetwork, (mechanismId, network, chainId, chainId));
    }

    function expectCheckNetwork(string memory network, uint256 chainId, uint64 count) internal {
        vm.expectCall(MOCK_MECHANISM_PROBE, checkNetworkCall(MOCK_CREATE2_MECHANISM_ID, network, chainId), count);
        vm.expectCall(MOCK_MECHANISM_PROBE, checkNetworkCall(MOCK_SALT_MECHANISM_ID, network, chainId), count);
    }

    /// `checkNetwork` runs once per mechanism on each checked network's fork, including a network no suite requires.
    function testCheckNetworkRunsOncePerMechanismOnEachCheckedNetwork() external {
        etchLive(42161);
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = arbitrumOnlySuite();

        expectCheckNetwork(LibRainDeploy.ARBITRUM_ONE, 42161, 1);
        expectCheckNetwork(LibRainDeploy.POLYGON, 137, 1);
        vm.expectCall(MOCK_MECHANISM_PROBE, checkOnChainCall(suites[0], LibRainDeploy.POLYGON, 137), 0);
        this.externalCheckAllOn(networkConfigs(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON), suites);
    }

    function chainIdList(uint256 a, uint256 b) internal pure returns (uint256[] memory) {
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = a;
        chainIds[1] = b;
        return chainIds;
    }

    function checkNetworksAnyCall(bytes32 mechanismId) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IMockMechanismProbe.checkNetworks.selector, mechanismId);
    }

    function returnNetworks(bytes memory checkNetworksCall, uint256[] memory chainIds) internal {
        vm.mockCall(MOCK_MECHANISM_PROBE, checkNetworksCall, abi.encode(chainIds));
    }

    function createForkCall(string memory network) internal pure returns (bytes memory) {
        return abi.encodeCall(LocalForkVm.createFork, (network));
    }

    /// @return Each `createFork` call to the fork Vm among `accesses`, in the order made.
    function createForkCalls(Vm.AccountAccess[] memory accesses) internal view returns (bytes[] memory) {
        bytes[] memory calls = new bytes[](accesses.length);
        uint256 count = 0;
        for (uint256 i = 0; i < accesses.length; i++) {
            bytes memory data = accesses[i].data;
            if (
                accesses[i].account == address(sForkVm) && accesses[i].kind == VmSafe.AccountAccessKind.Call
                    && data.length >= 4 && bytes4(data) == LocalForkVm.createFork.selector
            ) {
                calls[count++] = data;
            }
        }
        bytes[] memory made = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            made[i] = calls[i];
        }
        return made;
    }

    /// The suite is live everywhere it is required, so the only refusal there is to make is `checkNetworks`'.
    function testACheckNetworksRefusalStopsTheGroupBeforeAnyFork() external {
        etchLive(42161);
        etchLive(137);
        vm.mockCallRevert(MOCK_MECHANISM_PROBE, checkNetworksAnyCall(MOCK_SALT_MECHANISM_ID), abi.encode("refused"));
        vm.expectCall(address(sForkVm), abi.encodeWithSelector(LocalForkVm.createFork.selector), 0);
        vm.expectCall(MOCK_MECHANISM_PROBE, abi.encodeWithSelector(IMockMechanismProbe.addRecordedNetworks.selector), 0);
        vm.expectRevert(abi.encode("refused"));
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON, mockRelease());
    }

    /// Each mechanism is answered only for the exact networks checked; the returns overlap, out of `networks` order.
    function testNoSuitesForksOnlyTheReturnedNetworksInNetworksOrder() external {
        string[] memory names = new string[](4);
        names[0] = LibRainDeploy.ARBITRUM_ONE;
        names[1] = LibRainDeploy.POLYGON;
        names[2] = LibRainDeploy.ETHEREUM;
        names[3] = LibRainDeploy.BASE;
        uint256[] memory checked = LibRainDeploy.networkChainIds(LibRainDeploy.declaredNetworkConfigs(names));
        uint256[] memory onlyBase = new uint256[](1);
        onlyBase[0] = 8453;
        returnNetworks(
            abi.encodeCall(IMockMechanismProbe.checkNetworks, (MOCK_CREATE2_MECHANISM_ID, checked)), onlyBase
        );
        returnNetworks(
            abi.encodeCall(IMockMechanismProbe.checkNetworks, (MOCK_SALT_MECHANISM_ID, checked)),
            chainIdList(8453, 42161)
        );
        expectCheckNetwork(LibRainDeploy.ARBITRUM_ONE, 42161, 1);
        expectCheckNetwork(LibRainDeploy.POLYGON, 137, 0);
        expectCheckNetwork(LibRainDeploy.ETHEREUM, 1, 0);
        expectCheckNetwork(LibRainDeploy.BASE, 8453, 1);

        vm.startStateDiffRecording();
        this.externalCheckAllOn(names, new DeploySuite[](0));
        bytes[] memory forked = createForkCalls(vm.stopAndReturnStateDiff());

        bytes[] memory expected = new bytes[](2);
        expected[0] = createForkCall(LibRainDeploy.ARBITRUM_ONE);
        expected[1] = createForkCall(LibRainDeploy.BASE);
        assertEq(forked, expected);
    }

    /// A mechanism's config alone forks nothing.
    function testNoSuitesForksNothingWhenNoMechanismReturnsANetwork() external {
        this.setMockConfig(hex"01");
        vm.expectCall(address(sForkVm), abi.encodeWithSelector(LocalForkVm.createFork.selector), 0);
        vm.expectCall(address(sForkVm), abi.encodeWithSelector(LocalForkVm.selectFork.selector), 0);
        vm.expectCall(MOCK_MECHANISM_PROBE, abi.encodeWithSelector(IMockMechanismProbe.checkNetwork.selector), 0);
        this.externalCheckAllOn(networkConfigs(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON), new DeploySuite[](0));
    }

    /// The suite is required on Arbitrum only and a mechanism returns only Polygon, yet every network is forked.
    function testWithSuitesForksEveryNetworkInNetworksOrder() external {
        etchLive(42161);
        uint256[] memory onlyPolygon = new uint256[](1);
        onlyPolygon[0] = 137;
        returnNetworks(checkNetworksAnyCall(MOCK_SALT_MECHANISM_ID), onlyPolygon);
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = arbitrumOnlySuite();
        string[] memory names = new string[](3);
        names[0] = LibRainDeploy.ARBITRUM_ONE;
        names[1] = LibRainDeploy.POLYGON;
        names[2] = LibRainDeploy.ETHEREUM;

        vm.startStateDiffRecording();
        this.externalCheckAllOn(names, suites);
        bytes[] memory forked = createForkCalls(vm.stopAndReturnStateDiff());

        bytes[] memory expected = new bytes[](3);
        expected[0] = createForkCall(LibRainDeploy.ARBITRUM_ONE);
        expected[1] = createForkCall(LibRainDeploy.POLYGON);
        expected[2] = createForkCall(LibRainDeploy.ETHEREUM);
        assertEq(forked, expected);
    }

    /// A hook reads its mechanism's config through the declaration the caller passes it.
    function testCheckNetworkReadsItsConfigThroughTheDeclaration() external {
        this.setMockConfig(hex"c0ffee");
        returnNetworks(checkNetworksAnyCall(MOCK_SALT_MECHANISM_ID), chainIdList(42161, 137));
        vm.expectCall(
            MOCK_MECHANISM_PROBE,
            abi.encodeCall(IMockMechanismProbe.declaredConfig, (MOCK_SALT_MECHANISM_ID, hex"c0ffee")),
            2
        );
        this.externalCheckAllOn(networkConfigs(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON), new DeploySuite[](0));
    }
}
