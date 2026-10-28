// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, MechanismUnclaimed} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MOCK_CREATE2_FACTORY, MOCK_CREATE2_SALT, LibMockCreate2Mechanism} from "../../lib/LibMockCreate2Mechanism.sol";
import {GreedyFirstDeploy, GreedyLastDeploy, NoZoltuDeploy} from "../../concrete/MechanismOrderDeploys.sol";
import {TwoMechanismDeploy} from "../../concrete/TwoMechanismDeploy.sol";
import {TWO_MECHANISM_SALT} from "../../abstract/TwoMechanismDeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

/// @title RainDeploySuitesBaseMechanismsTest
/// @notice Every suite resolves to the first of `mechanisms()` claiming it, every record to the first not declining
/// it, and neither resolves to nothing.
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

    function testEachSuiteResolvesItsOwnMechanism() external view {
        assertEq(sDeploy.externalDeployedAddress(create2Suite(), 42161), networkAddress(42161));
        assertEq(sDeploy.externalDeployedAddress(create2Suite(), 137), networkAddress(137));
        assertEq(sDeploy.externalAddressChainIds(create2Suite()).length, 2);
        assertEq(sDeploy.externalDeployedAddress(saltSuite(), 42161), saltAddress());
        assertEq(sDeploy.externalRecordedAddress(saltSuite(), 42161), saltAddress());
        assertEq(sDeploy.externalAddressChainIds(saltSuite()).length, 0);
        DeploySuite memory zoltu = saltSuite();
        zoltu.mechanismData = "";
        assertEq(sDeploy.externalDeployedAddress(zoltu, 42161), LibRainDeploy.zoltuAddress(zoltu.creationCode));
    }

    function testEachSuiteDeploysAndLogsThroughItsOwnMechanism() external {
        address[] memory deployed = sDeploy.externalDeployLocally(vm, saltSuite());
        assertEq(deployed.length, 1);
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

    /// A mechanism claiming every suite with data takes the create2 suite only when listed before the create2
    /// mechanism; it then derives at the data's first word, the abi offset `0x20`.
    function testFirstClaimingMechanismWins() external {
        GreedyFirstDeploy first = new GreedyFirstDeploy();
        GreedyLastDeploy last = new GreedyLastDeploy();
        assertEq(
            first.externalDeployedAddress(create2Suite(), 42161),
            LibMockCreate2Mechanism.create2Address(
                MOCK_CREATE2_FACTORY, bytes32(uint256(0x20)), type(MockDeployable).creationCode
            )
        );
        assertEq(first.externalAddressChainIds(create2Suite()).length, 0);
        assertEq(last.externalDeployedAddress(create2Suite(), 42161), networkAddress(42161));
        assertEq(last.externalAddressChainIds(create2Suite()).length, 2);
        assertEq(first.externalDeployedAddress(saltSuite(), 137), saltAddress());
        assertEq(last.externalDeployedAddress(saltSuite(), 137), saltAddress());
    }

    function testUnclaimedSuiteIsRefused() external {
        DeploySuite memory unclaimed = saltSuite();
        unclaimed.mechanismData = hex"01";
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, "mock-salt"));
        sDeploy.externalDeployedAddress(unclaimed, 42161);

        NoZoltuDeploy noZoltu = new NoZoltuDeploy();
        DeploySuite memory zoltu = saltSuite();
        zoltu.mechanismData = "";
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, "mock-salt"));
        noZoltu.externalDeployedAddress(zoltu, 42161);
        assertEq(noZoltu.externalDeployedAddress(saltSuite(), 42161), saltAddress());
    }

    /// The salt mechanism, first, declines every record; the create2 mechanism takes one declaring `MECHANISM_DATA`
    /// and declines the rest; Zoltu takes the rest, and without it nothing does.
    function testRecordResolvesToTheFirstMechanismNotDecliningIt() external {
        //forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.removeDir(ROOT, true) {} catch {}
        string memory create2Path = sDeploy.externalWriteSuiteSnapshot(
            vm, ROOT, "0_0_1", "MockDeployable", "LicenseRef-DCL-1.0", "Copyright", create2Suite()
        );
        DeploySuite memory zoltu = saltSuite();
        zoltu.mechanismData = "";
        string memory zoltuPath = sDeploy.externalWriteSuiteSnapshot(
            vm, ROOT, "0_0_2", "MockDeployableV2", "LicenseRef-DCL-1.0", "Copyright", zoltu
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
        assertEq(zoltuExpression, "\"\"");
        assertEq(noZoltuExpression, "V0_0_1_MECHANISM_DATA");
    }
}
