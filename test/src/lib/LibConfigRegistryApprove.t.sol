// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {IConfigRegistryV2} from "../../../src/interface/IConfigRegistryV2.sol";
import {IRegistryDelegatesV1} from "../../../src/interface/IRegistryDelegatesV1.sol";
import {LibConfigRegistry} from "../../../src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryApprove} from "../../../src/lib/LibConfigRegistryApprove.sol";
import {LibConfigRegistryDeploy} from "../../../src/lib/LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister} from "../../../src/lib/LibConfigRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// @title LibConfigRegistryApproveTest
/// Every guard `LibConfigRegistryApprove` makes before an approval or
/// revocation, and the transaction itself, on the local chain: the real
/// `ConfigRegistry` deployed through the Zoltu factory at the pinned address,
/// with the chain id set to the network's, and the fork loops through a
/// `LocalForkVm`.
contract LibConfigRegistryApproveTest is Test {
    address internal constant AUTHORITY = address(0xA11CE);
    address internal constant DELEGATE = address(0x5AFE);
    bytes32 internal constant NAME = keccak256("a.b");

    function base() internal pure returns (SupportedNetwork memory) {
        string[] memory names = new string[](1);
        names[0] = LibRainDeploy.BASE;
        return LibRainDeploy.declaredNetworkConfigs(names)[0];
    }

    function deployRegistry() internal returns (IConfigRegistryV2) {
        vm.chainId(base().chainId);
        LibRainDeploy.etchZoltuFactory(vm);
        address registry = LibRainDeploy.deployZoltu(type(ConfigRegistry).creationCode);
        assertEq(registry, LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        return IConfigRegistryV2(registry);
    }

    function list(string memory first, string memory second) internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = first;
        networks[1] = second;
        return networks;
    }

    function externalCheckInputs(
        string[] memory selected,
        address sender,
        string memory name,
        address delegate,
        bool approve
    ) external pure returns (bytes32, SupportedNetwork[] memory, string memory) {
        return LibConfigRegistryApprove.checkInputs(
            vm, selected, LibRainDeploy.supportedNetworks(), sender, AUTHORITY, name, delegate, approve
        );
    }

    function externalApproveOnSelectedChain(address authority, bytes32 name, address delegate, bool approve)
        external
        returns (bool, string memory)
    {
        return LibConfigRegistryApprove.approveOnSelectedChain(vm, base(), authority, name, delegate, approve);
    }

    function externalCheckApprovalOnSelectedChain(bytes32 name, address delegate, bool approve) external view {
        LibConfigRegistryApprove.checkApprovalOnSelectedChain(vm, base(), AUTHORITY, name, delegate, approve);
    }

    function externalApproveOnNetworks(Vm forkVm, string[] memory selected, address authority, bool approve)
        external
        returns (uint256[] memory, string memory)
    {
        return LibConfigRegistryApprove.approveOnNetworks(
            forkVm, selected, LibRainDeploy.supportedNetworks(), authority, authority, "a.b", DELEGATE, approve
        );
    }

    function externalApproveOnForks(Vm forkVm, string[] memory selected, uint256[] memory forkIds) external {
        LibConfigRegistryApprove.approveOnForks(
            forkVm, selected, LibRainDeploy.supportedNetworks(), forkIds, AUTHORITY, AUTHORITY, "a.b", DELEGATE, true
        );
    }

    function externalCheckApprovalOnForks(Vm forkVm, string[] memory selected, uint256[] memory forkIds) external {
        LibConfigRegistryApprove.checkApprovalOnForks(
            forkVm, selected, LibRainDeploy.supportedNetworks(), forkIds, AUTHORITY, "a.b", DELEGATE, true
        );
    }

    function externalCheckApprovalOnNetworks(
        Vm forkVm,
        string[] memory selected,
        address authority,
        string memory name,
        bool approve
    ) external {
        LibConfigRegistryApprove.checkApprovalOnNetworks(
            forkVm, selected, LibRainDeploy.supportedNetworks(), authority, name, DELEGATE, approve
        );
    }

    /// The calldata is `approveV2` or `revokeV2`, selectors from
    /// `cast sig "approveV2(bytes32,address)"` and
    /// `cast sig "revokeV2(bytes32,address)"`, and it is the call sent.
    function testApproveCalldataIsTheCallSent(bytes32 name, address delegate) external {
        vm.assume(delegate != address(0));
        bytes memory approveData = abi.encodePacked(bytes4(0xfc7dfd2e), name, uint256(uint160(delegate)));
        bytes memory revokeData = abi.encodePacked(bytes4(0x2026c9f1), name, uint256(uint160(delegate)));
        assertEq(LibConfigRegistryApprove.approveCalldata(name, delegate, true), approveData);
        assertEq(LibConfigRegistryApprove.approveCalldata(name, delegate, false), revokeData);

        deployRegistry();
        vm.expectCall(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, approveData, 1);
        this.externalApproveOnSelectedChain(AUTHORITY, name, delegate, true);
        vm.expectCall(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, revokeData, 1);
        this.externalApproveOnSelectedChain(AUTHORITY, name, delegate, false);
    }

    /// The input refusals, each made with every later input also invalid, so
    /// each is the first.
    function testCheckInputsRefusesInOrder(address sender) external {
        vm.assume(sender != AUTHORITY);
        string[] memory none = new string[](0);
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryApprove.SenderNotAuthority.selector, sender, AUTHORITY));
        this.externalCheckInputs(none, sender, "A", address(0), true);
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV1.ZeroDelegate.selector));
        this.externalCheckInputs(none, AUTHORITY, "A", address(0), false);
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalCheckInputs(none, AUTHORITY, "A", DELEGATE, true);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckInputs(none, AUTHORITY, "a.b", DELEGATE, true);
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalCheckInputs(list(LibRainDeploy.BASE, "nowhere"), AUTHORITY, "a.b", DELEGATE, true);
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.DuplicateNetwork.selector, LibRainDeploy.BASE));
        this.externalCheckInputs(list(LibRainDeploy.BASE, LibRainDeploy.BASE), AUTHORITY, "a.b", DELEGATE, true);
    }

    /// Valid inputs return the name's hash, the selected networks in order and
    /// the inputs record.
    function testCheckInputsReturns(bool approve) external pure {
        string[] memory selected = list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        (bytes32 hashed, SupportedNetwork[] memory networks, string memory record) = LibConfigRegistryApprove.checkInputs(
            vm, selected, LibRainDeploy.supportedNetworks(), AUTHORITY, AUTHORITY, "a.b", DELEGATE, approve
        );
        assertEq(hashed, NAME);
        assertEq(networks.length, 2);
        assertEq(networks[0].name, LibRainDeploy.ARBITRUM_ONE);
        assertEq(networks[1].name, LibRainDeploy.BASE);
        assertEq(record, LibConfigRegistryApprove.describeInputs(vm, "a.b", AUTHORITY, DELEGATE, approve));
    }

    /// The inputs record, field for field, for st0x's token-owner Safe name
    /// and a delegate of `0x…dEaD`. The hash and calldata are
    /// `cast keccak st0x.token-owner-safe` and
    /// `cast calldata "approveV2(bytes32,address)" <hash> 0x…dEaD`, and
    /// `revokeV2` likewise.
    function testDescribeInputs() external pure {
        string memory head = string.concat(
            "Name: st0x.token-owner-safe\n",
            "Name hash (keccak256 of the name): 0xba1ec70c388d07ed204e3cfdcbdc2564f9aa2e5b310aeae3767c61a68306cfc8\n",
            "Authority (signer): ",
            vm.toString(AUTHORITY),
            "\nDelegate: 0x000000000000000000000000000000000000dEaD\n"
        );
        string memory registry =
            string.concat("\nRegistry: ", vm.toString(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS));
        string memory args =
            "ba1ec70c388d07ed204e3cfdcbdc2564f9aa2e5b310aeae3767c61a68306cfc8000000000000000000000000000000000000000000000000000000000000dead";
        assertEq(
            LibConfigRegistryApprove.describeInputs(vm, "st0x.token-owner-safe", AUTHORITY, address(0xdEaD), true),
            string.concat(head, "Target: approved", registry, "\nCalldata: 0xfc7dfd2e", args)
        );
        assertEq(
            LibConfigRegistryApprove.describeInputs(vm, "st0x.token-owner-safe", AUTHORITY, address(0xdEaD), false),
            string.concat(head, "Target: revoked", registry, "\nCalldata: 0x2026c9f1", args)
        );
    }

    /// Every action, and the delegate's code size either way.
    function testDescribeNetwork() external pure {
        string memory prefix = "Network: base\n  chain id: 8453\n  delegate code: ";
        assertEq(
            LibConfigRegistryApprove.describeNetwork(vm, "base", 8453, 0, false, true),
            string.concat(prefix, "none\n  current: not approved\n  APPROVE")
        );
        assertEq(
            LibConfigRegistryApprove.describeNetwork(vm, "base", 8453, 171, true, true),
            string.concat(prefix, "171 bytes\n  current: approved\n  SKIP: already approved")
        );
        assertEq(
            LibConfigRegistryApprove.describeNetwork(vm, "base", 8453, 1, true, false),
            string.concat(prefix, "1 bytes\n  current: approved\n  REVOKE")
        );
        assertEq(
            LibConfigRegistryApprove.describeNetwork(vm, "base", 8453, 0, false, false),
            string.concat(prefix, "none\n  current: not approved\n  SKIP: already not approved")
        );
    }

    /// An unapproved delegate is approved: one transaction from the authority,
    /// emitting `Approved`, and the record is the one logged.
    function testApproveApproves(address delegate) external {
        assumeNotPrecompile(delegate);
        assumeNotForgeAddress(delegate);
        vm.assume(delegate != address(0));
        IConfigRegistryV2 registry = deployRegistry();
        uint64 nonce = vm.getNonce(AUTHORITY);
        vm.expectEmit(address(registry));
        emit IRegistryDelegatesV1.Approved(AUTHORITY, NAME, delegate);
        (bool sent, string memory record) = this.externalApproveOnSelectedChain(AUTHORITY, NAME, delegate, true);
        assertTrue(sent);
        assertEq(vm.getNonce(AUTHORITY), nonce + 1);
        assertTrue(registry.approvedV2(AUTHORITY, NAME, delegate));
        assertEq(
            record,
            LibConfigRegistryApprove.describeNetwork(vm, "base", base().chainId, delegate.code.length, false, true)
        );
        this.externalCheckApprovalOnSelectedChain(NAME, delegate, true);
    }

    /// An approved delegate is revoked: one transaction from the authority,
    /// emitting `Revoked`.
    function testRevokeRevokes() external {
        IConfigRegistryV2 registry = deployRegistry();
        vm.prank(AUTHORITY);
        registry.approveV2(NAME, DELEGATE);
        uint64 nonce = vm.getNonce(AUTHORITY);
        vm.expectEmit(address(registry));
        emit IRegistryDelegatesV1.Revoked(AUTHORITY, NAME, DELEGATE);
        (bool sent, string memory record) = this.externalApproveOnSelectedChain(AUTHORITY, NAME, DELEGATE, false);
        assertTrue(sent);
        assertEq(vm.getNonce(AUTHORITY), nonce + 1);
        assertFalse(registry.approvedV2(AUTHORITY, NAME, DELEGATE));
        assertEq(record, LibConfigRegistryApprove.describeNetwork(vm, "base", base().chainId, 0, true, false));
        this.externalCheckApprovalOnSelectedChain(NAME, DELEGATE, false);
    }

    /// Already in the target state, either way, sends nothing.
    function testSkipsTargetState(bool approve) external {
        IConfigRegistryV2 registry = deployRegistry();
        if (approve) {
            vm.prank(AUTHORITY);
            registry.approveV2(NAME, DELEGATE);
        }
        uint64 nonce = vm.getNonce(AUTHORITY);
        vm.recordLogs();
        (bool sent, string memory record) = this.externalApproveOnSelectedChain(AUTHORITY, NAME, DELEGATE, approve);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].emitter != address(registry));
        }
        assertFalse(sent);
        assertEq(vm.getNonce(AUTHORITY), nonce);
        assertEq(registry.approvedV2(AUTHORITY, NAME, DELEGATE), approve);
        assertEq(record, LibConfigRegistryApprove.describeNetwork(vm, "base", base().chainId, 0, approve, approve));
    }

    /// The approval read is under the authority and name given: another
    /// authority's or another name's approval is not this one.
    function testApprovalIsPerAuthorityAndName(address other, bytes32 otherName) external {
        vm.assume(other != AUTHORITY && other != address(0));
        vm.assume(otherName != NAME);
        IConfigRegistryV2 registry = deployRegistry();
        vm.prank(other);
        registry.approveV2(NAME, DELEGATE);
        vm.prank(AUTHORITY);
        registry.approveV2(otherName, DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryApprove.UnexpectedApproval.selector, "base", AUTHORITY, NAME, DELEGATE, true
            )
        );
        this.externalCheckApprovalOnSelectedChain(NAME, DELEGATE, true);
        (bool sent,) = this.externalApproveOnSelectedChain(AUTHORITY, NAME, DELEGATE, true);
        assertTrue(sent);
        assertTrue(registry.approvedV2(AUTHORITY, NAME, DELEGATE));
    }

    /// The confirmed check refuses the opposite state, naming it.
    function testCheckApprovalRefusesTheOtherState(bool approve) external {
        IConfigRegistryV2 registry = deployRegistry();
        if (!approve) {
            vm.prank(AUTHORITY);
            registry.approveV2(NAME, DELEGATE);
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryApprove.UnexpectedApproval.selector, "base", AUTHORITY, NAME, DELEGATE, approve
            )
        );
        this.externalCheckApprovalOnSelectedChain(NAME, DELEGATE, approve);
    }

    /// The transaction and the confirmed check both refuse a chain other than
    /// the network's.
    function testWrongChain(uint64 chainId) external {
        vm.assume(chainId != base().chainId);
        deployRegistry();
        vm.chainId(chainId);
        bytes memory expected = abi.encodeWithSelector(
            LibConfigRegistryRegister.UnexpectedChainId.selector, "base", base().chainId, chainId
        );
        vm.expectRevert(expected);
        this.externalApproveOnSelectedChain(AUTHORITY, NAME, DELEGATE, true);
        vm.expectRevert(expected);
        this.externalCheckApprovalOnSelectedChain(NAME, DELEGATE, false);
    }

    /// The transaction and the confirmed check both refuse a chain without
    /// the pinned registry.
    function testWithoutRegistry() external {
        vm.chainId(base().chainId);
        bytes memory expected = abi.encodeWithSelector(
            LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
            bytes32(0)
        );
        vm.expectRevert(expected);
        this.externalApproveOnSelectedChain(AUTHORITY, NAME, DELEGATE, true);
        vm.expectRevert(expected);
        this.externalCheckApprovalOnSelectedChain(NAME, DELEGATE, false);
    }

    /// On the local fork seam, `approveOnNetworks` approves on every selected
    /// network in selection order and returns each fork and the inputs
    /// record; the confirmed check then passes, and a revoke run reverses it.
    /// The seam's broadcast is a no-op, so this contract signs and is the
    /// authority.
    function testApproveOnNetworks() external {
        IConfigRegistryV2 registry = deployRegistry();
        Vm forkVm = Vm(address(new LocalForkVm()));
        string[] memory selected = list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        SupportedNetwork[] memory networks = LibRainDeploy.declaredNetworkConfigs(selected);

        (uint256[] memory forkIds, string memory record) =
            this.externalApproveOnNetworks(forkVm, selected, address(this), true);
        assertEq(forkIds.length, 2);
        assertEq(forkIds[0], networks[0].chainId);
        assertEq(forkIds[1], networks[1].chainId);
        assertEq(block.chainid, networks[1].chainId);
        assertEq(record, LibConfigRegistryApprove.describeInputs(vm, "a.b", address(this), DELEGATE, true));
        assertTrue(registry.approvedV2(address(this), NAME, DELEGATE));
        this.externalCheckApprovalOnNetworks(forkVm, selected, address(this), "a.b", true);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryApprove.UnexpectedApproval.selector,
                LibRainDeploy.ARBITRUM_ONE,
                address(this),
                NAME,
                DELEGATE,
                false
            )
        );
        this.externalCheckApprovalOnNetworks(forkVm, selected, address(this), "a.b", false);

        this.externalApproveOnNetworks(forkVm, selected, address(this), false);
        assertFalse(registry.approvedV2(address(this), NAME, DELEGATE));
        this.externalCheckApprovalOnNetworks(forkVm, selected, address(this), "a.b", false);
    }

    /// The fork loops refuse fork ids not paired one to one with the
    /// networks.
    function testForkLoopsRefuseUnpairedForks() external {
        Vm forkVm = Vm(address(new LocalForkVm()));
        string[] memory selected = list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        uint256[] memory one = new uint256[](1);
        uint256[] memory three = new uint256[](3);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 1));
        this.externalApproveOnForks(forkVm, selected, one);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 3));
        this.externalApproveOnForks(forkVm, selected, three);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 1));
        this.externalCheckApprovalOnForks(forkVm, selected, one);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 3));
        this.externalCheckApprovalOnForks(forkVm, selected, three);
    }

    /// The confirmed check refuses its inputs before anything is forked.
    function testCheckApprovalOnNetworksRefusesInputs() external {
        Vm forkVm = Vm(address(new LocalForkVm()));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalCheckApprovalOnNetworks(forkVm, new string[](0), AUTHORITY, "A", true);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckApprovalOnNetworks(forkVm, new string[](0), AUTHORITY, "a.b", true);
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalCheckApprovalOnNetworks(forkVm, list(LibRainDeploy.BASE, "nowhere"), AUTHORITY, "a.b", true);
    }
}
