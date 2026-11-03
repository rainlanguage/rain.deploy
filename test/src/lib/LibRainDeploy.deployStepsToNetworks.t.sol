// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    DeployDependency,
    DeployStepRow,
    LibRainDeploy,
    NetworkDeploys,
    SupportedNetwork
} from "../../../src/lib/LibRainDeploy.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title LibRainDeployDeployStepsToNetworksTest
/// @notice Every row of a batch deploys in order on each network's one fork.
contract LibRainDeployDeployStepsToNetworksTest is Test {
    /// Thrown when a step the batch must not reach is reached.
    error DeployStepWasReached();

    /// The local fork Vm the batch forks with.
    LocalForkVm internal sForkVm;

    /// The address each step call etched, in call order.
    address[] internal sStepTargets;

    /// The deployer's nonce on the selected fork as each step call began, in call order.
    uint256[] internal sStepNonces;

    /// Deploys the local fork Vm.
    function setUp() external {
        sForkVm = new LocalForkVm();
    }

    /// A step that reverts if reached.
    /// @return Never returns.
    function unreachableDeployStep(Vm, string memory, address, bytes memory) internal pure returns (address) {
        revert DeployStepWasReached();
    }

    /// Records the step data's address, then etches `hex"00"` there and reports it.
    /// @param stepData The address to etch, encoded.
    /// @return The etched address.
    function recordingEtchingDeployStep(Vm, string memory, address, bytes memory stepData) internal returns (address) {
        address target = abi.decode(stepData, (address));
        sStepTargets.push(target);
        vm.etch(target, hex"00");
        return target;
    }

    /// Records the deployer's nonce on the selected fork, then deploys through the Zoltu step.
    /// @param stepVm The Vm the batch passes.
    /// @param network The network being deployed to.
    /// @param deployer The address to broadcast as.
    /// @param creationCode The step data.
    /// @return The address the Zoltu factory deployed to.
    function nonceRecordingZoltuDeployStep(
        Vm stepVm,
        string memory network,
        address deployer,
        bytes memory creationCode
    ) internal returns (address) {
        sStepNonces.push(stepVm.getNonce(deployer));
        return LibRainDeploy.zoltuDeployStep(stepVm, network, deployer, creationCode);
    }

    /// The named networks' catalogue entries.
    /// @param first The first network.
    /// @param second The second network.
    /// @return Their catalogue entries.
    function twoNetworks(string memory first, string memory second) internal pure returns (SupportedNetwork[] memory) {
        string[] memory names = new string[](2);
        names[0] = first;
        names[1] = second;
        return LibRainDeploy.declaredNetworkConfigs(names);
    }

    /// A one-network row etching at `target` and expecting `code` there.
    /// @param target The expected address.
    /// @param code The code the row expects at `target`.
    /// @return The row.
    function etchingRow(address target, bytes memory code) internal pure returns (DeployStepRow memory) {
        return DeployStepRow({
            deploys: LibRainDeploy.everyNetwork(1, abi.encode(target), target, target),
            expectedCodeHash: keccak256(code)
        });
    }

    /// Rows deploying `MockDeployable` through Zoltu, each at its own address by appending the row index to the
    /// creation code.
    /// @param networksLength How many networks.
    /// @param length How many rows.
    /// @return The rows.
    function mockDeployableRows(uint256 networksLength, uint256 length) internal pure returns (DeployStepRow[] memory) {
        DeployStepRow[] memory rows = new DeployStepRow[](length);
        for (uint256 r = 0; r < length; r++) {
            bytes memory creationCode = abi.encodePacked(type(MockDeployable).creationCode, r);
            address target = LibRainDeploy.zoltuAddress(creationCode);
            rows[r] = DeployStepRow({
                deploys: LibRainDeploy.everyNetwork(networksLength, creationCode, target, target),
                expectedCodeHash: keccak256(type(MockDeployable).runtimeCode)
            });
        }
        return rows;
    }

    /// External wrapper for `LibRainDeploy.deployStepsToNetworks` over the local fork Vm on Arbitrum One.
    /// @param rows The rows.
    /// @return The fork of each network.
    function externalLocalEtchingSteps(DeployStepRow[] memory rows) external returns (uint256[] memory) {
        string[] memory names = new string[](1);
        names[0] = LibRainDeploy.ARBITRUM_ONE;
        return LibRainDeploy.deployStepsToNetworks(
            Vm(address(sForkVm)),
            LibRainDeploy.declaredNetworkConfigs(names),
            address(this),
            recordingEtchingDeployStep,
            rows,
            new DeployDependency[](0)
        );
    }

    /// External wrapper for `LibRainDeploy.deployStepsToNetworks` through the step that cannot run.
    /// @param networks The networks.
    /// @param rows The rows.
    /// @return The fork of each network.
    function externalUnreachableSteps(SupportedNetwork[] memory networks, DeployStepRow[] memory rows)
        external
        returns (uint256[] memory)
    {
        return LibRainDeploy.deployStepsToNetworks(
            vm, networks, address(this), unreachableDeployStep, rows, new DeployDependency[](0)
        );
    }

    /// Under broadcast, each row MUST be sent at the nonce the row before it left, on one fork per network.
    function testRowsBroadcastAtAdvancingNoncesOnOneForkPerNetwork() external {
        SupportedNetwork[] memory networks = twoNetworks(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        address deployer = makeAddr("deployStepsToNetworks deployer");
        DeployStepRow[] memory rows = mockDeployableRows(networks.length, 3);

        uint256[] memory forkIds = LibRainDeploy.deployStepsToNetworks(
            vm, networks, deployer, nonceRecordingZoltuDeployStep, rows, new DeployDependency[](0)
        );

        assertEq(sStepNonces.length, networks.length * rows.length);
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 firstNonce = sStepNonces[i * rows.length];
            for (uint256 r = 1; r < rows.length; r++) {
                assertEq(sStepNonces[i * rows.length + r], firstNonce + r, "row broadcast at a stale nonce");
            }
            vm.selectFork(forkIds[i]);
            assertEq(block.chainid, networks[i].chainId);
            assertEq(vm.getNonce(deployer), firstNonce + rows.length);
            for (uint256 r = 0; r < rows.length; r++) {
                assertEq(rows[r].deploys.expectedAddresses[i].codehash, rows[r].expectedCodeHash);
            }
        }
        (bool forkedMore,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", networks.length));
        assertFalse(forkedMore, "the batch forked more than once per network");
    }

    /// A row whose expected address already holds code MUST be skipped and checked against its own code hash, while
    /// the rows either side of it still deploy in order.
    function testRowHoldingCodeIsSkippedAndTheOthersDeploy() external {
        address first = address(0xabc);
        address second = address(0xdef);
        address third = address(0x123);
        vm.etch(second, hex"01");
        DeployStepRow[] memory rows = new DeployStepRow[](3);
        rows[0] = etchingRow(first, hex"00");
        rows[1] = etchingRow(second, hex"01");
        rows[2] = etchingRow(third, hex"00");

        this.externalLocalEtchingSteps(rows);

        assertEq(sStepTargets.length, 2);
        assertEq(sStepTargets[0], first);
        assertEq(sStepTargets[1], third);
        assertEq(first.code, hex"00");
        assertEq(second.code, hex"01");
        assertEq(third.code, hex"00");
    }

    /// A skipped row holding other code than its own code hash MUST be refused, naming that row's hash.
    function testSkippedRowHoldingOtherCodeIsRefused() external {
        address first = address(0xabc);
        address second = address(0xdef);
        vm.etch(second, hex"01");
        DeployStepRow[] memory rows = new DeployStepRow[](2);
        rows[0] = etchingRow(first, hex"00");
        rows[1] = etchingRow(second, hex"02");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                second,
                keccak256(hex"02"),
                keccak256(hex"01")
            )
        );
        this.externalLocalEtchingSteps(rows);
    }

    /// A later row's unpaired lists or mismatched derived address MUST be refused before any network is forked.
    function testLaterRowRefusedBeforeForking() external {
        SupportedNetwork[] memory networks = twoNetworks(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON);
        DeployStepRow[] memory rows = new DeployStepRow[](2);
        rows[0] = DeployStepRow({
            deploys: LibRainDeploy.everyNetwork(2, hex"", address(0xabc), address(0xabc)), expectedCodeHash: bytes32(0)
        });

        rows[1] = DeployStepRow({
            deploys: NetworkDeploys({
                deployStepData: new bytes[](2), expectedAddresses: new address[](1), derivedAddresses: new address[](2)
            }),
            expectedCodeHash: bytes32(0)
        });
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployStepNetworksMismatch.selector, 2, 2, 1, 2));
        this.externalUnreachableSteps(networks, rows);

        rows[1] = DeployStepRow({
            deploys: LibRainDeploy.everyNetwork(2, hex"", address(0xdef), address(0xbad)), expectedCodeHash: bytes32(0)
        });
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, address(0xdef), address(0xbad))
        );
        this.externalUnreachableSteps(networks, rows);

        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        assertFalse(forked, "the batch forked a network before refusing a later row");
    }
}
