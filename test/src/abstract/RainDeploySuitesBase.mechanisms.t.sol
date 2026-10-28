// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    DeployDeclaration,
    DeployMechanismHandler,
    DeploySuite,
    DuplicateMechanism,
    MechanismUnclaimed
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism, ZOLTU_MECHANISM_ID} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_MECHANISM_ID,
    MOCK_CREATE2_SALT,
    LibMockCreate2Mechanism
} from "../../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism, MOCK_SALT_MECHANISM_ID} from "../../lib/LibMockSaltMechanism.sol";
import {NoZoltuDeploy} from "../../concrete/NoZoltuDeploy.sol";
import {ReversedMechanismsDeploy} from "../../concrete/ReversedMechanismsDeploy.sol";
import {ReversedSuitesDeploy} from "../../concrete/ReversedSuitesDeploy.sol";
import {TwoMechanismDeploy} from "../../concrete/TwoMechanismDeploy.sol";
import {ExternalDeploySuites} from "../../abstract/ExternalDeploySuites.sol";
import {TWO_MECHANISM_SALT} from "../../abstract/TwoMechanismDeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

/// @title RainDeploySuitesBaseMechanismsTest
/// @notice Every suite and every record resolves to the one mechanism whose id it carries, whatever the order of
/// mechanisms or suites, and to nothing when no or two mechanisms carry that id.
contract RainDeploySuitesBaseMechanismsTest is Test {
    event MockCreate2Verification(string[] networks, string suite, address[] deployed);
    event MockSaltVerification(string suite, address deployed);

    string constant ROOT = "test/generated-snapshot/two-mechanisms";

    TwoMechanismDeploy internal sDeploy;

    function setUp() external {
        sDeploy = new TwoMechanismDeploy();
    }

    function create2Suite() internal view returns (DeploySuite memory) {
        return sDeploy.externalSuiteByName("mock-create-two");
    }

    function saltSuite() internal view returns (DeploySuite memory) {
        return sDeploy.externalSuiteByName("mock-salt");
    }

    function zoltuSuite() internal view returns (DeploySuite memory) {
        DeploySuite memory zoltu = saltSuite();
        zoltu.mechanismData = LibRainDeployZoltuMechanism.mechanismData();
        return zoltu;
    }

    function networkAddress(uint256 chainId) internal pure returns (address) {
        return LibMockCreate2Mechanism.create2Address(
            MOCK_CREATE2_FACTORY,
            LibMockCreate2Mechanism.networkSalt(MOCK_CREATE2_SALT, abi.encode(chainId)),
            type(MockDeployable).creationCode
        );
    }

    function saltAddress() internal pure returns (address) {
        return LibMockCreate2Mechanism.create2Address(
            MOCK_CREATE2_FACTORY, TWO_MECHANISM_SALT, type(MockDeployableV2).creationCode
        );
    }

    /// Looks `id` up in a hand-built list: Zoltu, salt, then salt again when `duplicate`, else create2.
    function lookup(bool duplicate, bytes32 id) external pure returns (bytes32) {
        DeployMechanismHandler[] memory handlers = new DeployMechanismHandler[](3);
        handlers[0] = LibRainDeployZoltuMechanism.handler();
        handlers[1] = LibMockSaltMechanism.handler();
        handlers[2] = duplicate ? LibMockSaltMechanism.handler() : LibMockCreate2Mechanism.handler();
        DeployDeclaration memory d;
        d.mechanisms = handlers;
        return LibRainDeployDeclaration.mechanismById(d, id, "subject").id;
    }

    function extendSaltTwice() external pure {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        LibMockSaltMechanism.extend(d);
        LibMockSaltMechanism.extend(d);
    }

    /// Every dispatched fact of a suite in `deploy`, keyed by the suite's id and addresses on two chains.
    function dispatched(ExternalDeploySuites deploy, DeploySuite memory suite) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                deploy.externalMechanismOf(suite),
                deploy.externalDeployedAddress(suite, 42161),
                deploy.externalDeployedAddress(suite, 137),
                deploy.externalRecordedAddress(suite, 42161),
                deploy.externalRecordedAddress(suite, 137),
                deploy.externalDeployStepData(suite, 137)
            )
        );
    }

    function testEachSuiteResolvesItsOwnMechanismById() external view {
        assertEq(sDeploy.externalMechanismOf(create2Suite()), MOCK_CREATE2_MECHANISM_ID);
        assertEq(sDeploy.externalMechanismOf(saltSuite()), MOCK_SALT_MECHANISM_ID);
        assertEq(sDeploy.externalMechanismOf(zoltuSuite()), ZOLTU_MECHANISM_ID);
        assertEq(sDeploy.externalDeployedAddress(create2Suite(), 42161), networkAddress(42161));
        assertEq(sDeploy.externalDeployedAddress(create2Suite(), 137), networkAddress(137));
        assertEq(sDeploy.externalDeployedAddress(saltSuite(), 42161), saltAddress());
        assertEq(sDeploy.externalRecordedAddress(saltSuite(), 42161), saltAddress());
        assertEq(
            sDeploy.externalDeployedAddress(zoltuSuite(), 42161), LibRainDeploy.zoltuAddress(zoltuSuite().creationCode)
        );
    }

    function testEachSuiteDeploysAndLogsThroughItsOwnMechanism() external {
        address[] memory deployed = sDeploy.externalDeployLocally(vm, saltSuite());
        assertEq(deployed.length, saltSuite().networks.length);
        assertEq(deployed[0], saltAddress());
        assertEq(deployed[0].code, type(MockDeployableV2).runtimeCode);
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        vm.expectEmit(address(sDeploy));
        emit MockSaltVerification("mock-salt", deployed[0]);
        sDeploy.externalLogVerification(vm, networks, saltSuite(), deployed);
        address[] memory create2Deployed = new address[](1);
        create2Deployed[0] = networkAddress(42161);
        vm.expectEmit(address(sDeploy));
        emit MockCreate2Verification(networks, "mock-create-two", create2Deployed);
        sDeploy.externalLogVerification(vm, networks, create2Suite(), create2Deployed);
    }

    /// The salt suite's 64-byte data is longer than one word, the shape of create2 data, and create2 is listed
    /// before salt; the id alone picks salt.
    function testOverlappingDataResolvesById() external {
        ReversedMechanismsDeploy reversed = new ReversedMechanismsDeploy();
        assertEq(saltSuite().mechanismData.length, 0x40);
        bytes32[] memory ids = reversed.externalMechanismIds();
        assertEq(ids[1], MOCK_CREATE2_MECHANISM_ID);
        assertEq(ids[2], MOCK_SALT_MECHANISM_ID);
        assertEq(reversed.externalMechanismOf(saltSuite()), MOCK_SALT_MECHANISM_ID);
        assertEq(reversed.externalDeployedAddress(saltSuite(), 137), saltAddress());
    }

    function testDispatchIsInvariantUnderMechanismOrder() external {
        ReversedMechanismsDeploy reversed = new ReversedMechanismsDeploy();
        bytes32[] memory forward = sDeploy.externalMechanismIds();
        bytes32[] memory backward = reversed.externalMechanismIds();
        assertEq(forward.length, 3);
        assertEq(backward.length, 3);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(forward[i], backward[2 - i]);
        }
        assertEq(dispatched(sDeploy, create2Suite()), dispatched(reversed, create2Suite()));
        assertEq(dispatched(sDeploy, saltSuite()), dispatched(reversed, saltSuite()));
        assertEq(dispatched(sDeploy, zoltuSuite()), dispatched(reversed, zoltuSuite()));
    }

    function testDispatchIsInvariantUnderSuiteOrder() external {
        ReversedSuitesDeploy reversed = new ReversedSuitesDeploy();
        assertEq(reversed.externalCandidates()[0].snapshot.suite, "mock-salt");
        assertEq(sDeploy.externalCandidates()[0].snapshot.suite, "mock-create-two");
        DeploySuite memory create2 = reversed.externalSuiteByName("mock-create-two");
        DeploySuite memory salt = reversed.externalSuiteByName("mock-salt");
        assertEq(keccak256(abi.encode(create2)), keccak256(abi.encode(create2Suite())));
        assertEq(keccak256(abi.encode(salt)), keccak256(abi.encode(saltSuite())));
        assertEq(dispatched(sDeploy, create2Suite()), dispatched(reversed, create2));
        assertEq(dispatched(sDeploy, saltSuite()), dispatched(reversed, salt));
    }

    function testTwoNonZoltuMechanismsInOneDeclaration() external {
        NoZoltuDeploy noZoltu = new NoZoltuDeploy();
        assertEq(noZoltu.externalMechanismIds().length, 2);
        assertEq(noZoltu.externalMechanismOf(create2Suite()), MOCK_CREATE2_MECHANISM_ID);
        assertEq(noZoltu.externalMechanismOf(saltSuite()), MOCK_SALT_MECHANISM_ID);
        assertEq(noZoltu.externalDeployedAddress(create2Suite(), 137), networkAddress(137));
        assertEq(noZoltu.externalDeployedAddress(saltSuite(), 137), saltAddress());
        address[] memory salt = noZoltu.externalDeployLocally(vm, saltSuite());
        address[] memory create2 = noZoltu.externalDeployLocally(vm, create2Suite());
        assertEq(salt[0].code, type(MockDeployableV2).runtimeCode);
        assertEq(create2.length, 2);
        assertEq(create2[0], networkAddress(42161));
        assertEq(create2[1], networkAddress(137));
        assertEq(create2[1].code, type(MockDeployable).runtimeCode);
    }

    function testDuplicateMechanismIsRefusedByAddMechanism() external {
        vm.expectRevert(abi.encodeWithSelector(DuplicateMechanism.selector, MOCK_SALT_MECHANISM_ID));
        this.extendSaltTwice();
    }

    /// A hand-built list holding one id twice refuses every lookup, of that id or another.
    function testDuplicateMechanismIsRefusedByLookup() external {
        vm.expectRevert(abi.encodeWithSelector(DuplicateMechanism.selector, MOCK_SALT_MECHANISM_ID));
        this.lookup(true, ZOLTU_MECHANISM_ID);
        vm.expectRevert(abi.encodeWithSelector(DuplicateMechanism.selector, MOCK_SALT_MECHANISM_ID));
        this.lookup(true, MOCK_SALT_MECHANISM_ID);
        assertEq(this.lookup(false, MOCK_SALT_MECHANISM_ID), MOCK_SALT_MECHANISM_ID);
        assertEq(this.lookup(false, MOCK_CREATE2_MECHANISM_ID), MOCK_CREATE2_MECHANISM_ID);
        assertEq(this.lookup(false, ZOLTU_MECHANISM_ID), ZOLTU_MECHANISM_ID);
    }

    /// @param id An id no declared mechanism carries.
    /// @param payload Data following the id.
    function testUnknownIdIsUnclaimed(bytes32 id, bytes memory payload) external {
        vm.assume(id != ZOLTU_MECHANISM_ID && id != MOCK_CREATE2_MECHANISM_ID && id != MOCK_SALT_MECHANISM_ID);
        DeploySuite memory unclaimed = saltSuite();
        unclaimed.mechanismData = bytes.concat(id, payload);
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, "mock-salt"));
        sDeploy.externalDeployedAddress(unclaimed, 42161);
    }

    /// @param data Mechanism data shorter than an id.
    function testDataShorterThanAnIdIsUnclaimed(bytes memory data) external {
        vm.assume(data.length < 0x20);
        DeploySuite memory unclaimed = saltSuite();
        unclaimed.mechanismData = data;
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, "mock-salt"));
        sDeploy.externalDeployedAddress(unclaimed, 42161);
    }

    function testZoltuIdIsUnclaimedWithoutZoltu() external {
        NoZoltuDeploy noZoltu = new NoZoltuDeploy();
        DeploySuite memory suite = zoltuSuite();
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, "mock-salt"));
        noZoltu.externalDeployedAddress(suite, 42161);
    }

    /// A record declaring `MECHANISM_DATA` resolves by its leading word; one without resolves to Zoltu, and without
    /// Zoltu to nothing.
    function testRecordResolvesByItsMechanismId() external {
        //forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.removeDir(ROOT, true) {} catch {}
        string memory create2Path = sDeploy.externalWriteSuiteSnapshot(
            vm, ROOT, "0_0_1", "MockDeployable", "LicenseRef-DCL-1.0", "Copyright", create2Suite()
        );
        string memory zoltuPath = sDeploy.externalWriteSuiteSnapshot(
            vm, ROOT, "0_0_2", "MockDeployableV2", "LicenseRef-DCL-1.0", "Copyright", zoltuSuite()
        );
        string memory create2Expression = sDeploy.externalReleasedMechanismData(vm, create2Path, "V0_0_1");
        string memory zoltuExpression = sDeploy.externalReleasedMechanismData(vm, zoltuPath, "V0_0_2");
        NoZoltuDeploy noZoltu = new NoZoltuDeploy();
        string memory noZoltuExpression = noZoltu.externalReleasedMechanismData(vm, create2Path, "V0_0_1");
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, zoltuPath));
        noZoltu.externalReleasedMechanismData(vm, zoltuPath, "V0_0_2");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(ROOT, true);

        assertEq(create2Expression, "V0_0_1_MECHANISM_DATA");
        assertEq(zoltuExpression, "LibRainDeployZoltuMechanism.mechanismData()");
        assertEq(noZoltuExpression, "V0_0_1_MECHANISM_DATA");
    }
}
