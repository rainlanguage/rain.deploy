// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {IConfigRegistryV4} from "../../../src/interface/IConfigRegistryV4.sol";
import {IRegistryDelegatesV2} from "../../../src/interface/IRegistryDelegatesV2.sol";
import {LibConfigRegistryApprove} from "../../../src/lib/LibConfigRegistryApprove.sol";
import {LibRegistryDelegatesApprove} from "../../../src/lib/LibRegistryDelegatesApprove.sol";
import {LibRegistryDelegates} from "../../../src/lib/LibRegistryDelegates.sol";
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
    bytes32 internal constant OTHER_NAME = keccak256("c.d");

    /// `cast sig "multicall(bytes[])"`.
    bytes4 internal constant MULTICALL_SELECTOR = bytes4(0xac9650d8);

    function base() internal pure returns (SupportedNetwork memory) {
        string[] memory names = new string[](1);
        names[0] = LibRainDeploy.BASE;
        return LibRainDeploy.declaredNetworkConfigs(names)[0];
    }

    function deployRegistry() internal returns (IConfigRegistryV4) {
        vm.chainId(base().chainId);
        LibRainDeploy.etchZoltuFactory(vm);
        address registry = LibRainDeploy.deployZoltu(type(ConfigRegistry).creationCode);
        assertEq(registry, LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        return IConfigRegistryV4(registry);
    }

    function list(string memory first, string memory second) internal pure returns (string[] memory) {
        string[] memory names = new string[](2);
        names[0] = first;
        names[1] = second;
        return names;
    }

    function one(string memory only) internal pure returns (string[] memory) {
        string[] memory names = new string[](1);
        names[0] = only;
        return names;
    }

    function hashes(bytes32 first) internal pure returns (bytes32[] memory) {
        bytes32[] memory hashed = new bytes32[](1);
        hashed[0] = first;
        return hashed;
    }

    function hashes(bytes32 first, bytes32 second) internal pure returns (bytes32[] memory) {
        bytes32[] memory hashed = new bytes32[](2);
        hashed[0] = first;
        hashed[1] = second;
        return hashed;
    }

    /// The `multicall` calldata over `calls`, built from the selector rather
    /// than the library's encoding.
    function multicallData(bytes[] memory calls) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(MULTICALL_SELECTOR, calls);
    }

    function calls(bytes memory only) internal pure returns (bytes[] memory) {
        bytes[] memory batch = new bytes[](1);
        batch[0] = only;
        return batch;
    }

    function externalCheckInputs(string[] memory selected, address sender, string[] memory names, address delegate)
        external
        pure
        returns (bytes32[] memory, SupportedNetwork[] memory)
    {
        return LibRegistryDelegatesApprove.checkInputs(
            selected, LibRainDeploy.supportedNetworks(), sender, AUTHORITY, names, delegate
        );
    }

    function externalApproveOnSelectedChain(
        address authority,
        string[] memory names,
        bytes32[] memory hashed,
        address delegate,
        bool approve
    ) external returns (bool, string memory) {
        return LibRegistryDelegatesApprove.approveOnSelectedChain(
            LibConfigRegistryApprove.delegation(), vm, base(), authority, names, hashed, delegate, approve
        );
    }

    function externalCheckApprovalOnSelectedChain(bytes32[] memory hashed, address delegate, bool approve)
        external
        view
    {
        LibRegistryDelegatesApprove.checkApprovalOnSelectedChain(
            LibConfigRegistryApprove.delegation(), vm, base(), AUTHORITY, hashed, delegate, approve
        );
    }

    function externalApproveOnNetworks(
        Vm forkVm,
        string[] memory selected,
        address authority,
        string[] memory names,
        bool approve
    ) external returns (uint256[] memory, string memory) {
        return LibRegistryDelegatesApprove.approveOnNetworks(
            LibConfigRegistryApprove.delegation(),
            forkVm,
            selected,
            LibRainDeploy.supportedNetworks(),
            authority,
            authority,
            names,
            DELEGATE,
            approve
        );
    }

    function externalApproveOnForks(Vm forkVm, string[] memory selected, uint256[] memory forkIds) external {
        LibRegistryDelegatesApprove.approveOnForks(
            LibConfigRegistryApprove.delegation(),
            forkVm,
            selected,
            LibRainDeploy.supportedNetworks(),
            forkIds,
            AUTHORITY,
            AUTHORITY,
            one("a.b"),
            DELEGATE,
            true
        );
    }

    function externalCheckApprovalOnForks(Vm forkVm, string[] memory selected, uint256[] memory forkIds) external {
        LibRegistryDelegatesApprove.checkApprovalOnForks(
            LibConfigRegistryApprove.delegation(),
            forkVm,
            selected,
            LibRainDeploy.supportedNetworks(),
            forkIds,
            AUTHORITY,
            one("a.b"),
            DELEGATE,
            true
        );
    }

    function externalCheckApprovalOnNetworks(
        Vm forkVm,
        string[] memory selected,
        address authority,
        string[] memory names,
        bool approve
    ) external {
        LibRegistryDelegatesApprove.checkApprovalOnNetworks(
            LibConfigRegistryApprove.delegation(),
            forkVm,
            selected,
            LibRainDeploy.supportedNetworks(),
            authority,
            names,
            DELEGATE,
            approve
        );
    }

    /// The calldata of each scope is `approveV4` or `revokeV4`, selectors from
    /// `cast sig "approveV4(bytes32,address)"` and
    /// `cast sig "revokeV4(bytes32,address)"`, and the call sent is one
    /// `multicall` over it.
    function testApproveCalldataIsTheCallSent(bytes32 name, address delegate) external {
        vm.assume(delegate != address(0));
        bytes memory approveData = abi.encodePacked(bytes4(0xeb34d125), name, uint256(uint160(delegate)));
        bytes memory revokeData = abi.encodePacked(bytes4(0x8f02e4a5), name, uint256(uint160(delegate)));
        assertEq(LibRegistryDelegates.approveCalldata(name, delegate, true), approveData);
        assertEq(LibRegistryDelegates.approveCalldata(name, delegate, false), revokeData);

        deployRegistry();
        vm.expectCall(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, multicallData(calls(approveData)), 1);
        this.externalApproveOnSelectedChain(AUTHORITY, one("x"), hashes(name), delegate, true);
        vm.expectCall(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, multicallData(calls(revokeData)), 1);
        this.externalApproveOnSelectedChain(AUTHORITY, one("x"), hashes(name), delegate, false);
    }

    /// The input refusals, each made with every later input also invalid, so
    /// each is the first.
    function testCheckInputsRefusesInOrder(address sender) external {
        vm.assume(sender != AUTHORITY);
        string[] memory none = new string[](0);
        vm.expectRevert(
            abi.encodeWithSelector(LibRegistryDelegatesApprove.SenderNotAuthority.selector, sender, AUTHORITY)
        );
        this.externalCheckInputs(none, sender, none, address(0));
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV2.ZeroDelegate.selector));
        this.externalCheckInputs(none, AUTHORITY, none, address(0));
        vm.expectRevert(abi.encodeWithSelector(LibRegistryDelegatesApprove.NoScopes.selector));
        this.externalCheckInputs(none, AUTHORITY, none, DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalCheckInputs(none, AUTHORITY, list("a.b", "A"), DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckInputs(none, AUTHORITY, one("a.b"), DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalCheckInputs(list(LibRainDeploy.BASE, "nowhere"), AUTHORITY, one("a.b"), DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.DuplicateNetwork.selector, LibRainDeploy.BASE));
        this.externalCheckInputs(list(LibRainDeploy.BASE, LibRainDeploy.BASE), AUTHORITY, one("a.b"), DELEGATE);
    }

    /// Valid inputs return each name's hash and the selected networks, in
    /// order.
    function testCheckInputsReturns() external pure {
        string[] memory selected = list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        (bytes32[] memory hashed, SupportedNetwork[] memory networks) = LibRegistryDelegatesApprove.checkInputs(
            selected, LibRainDeploy.supportedNetworks(), AUTHORITY, AUTHORITY, list("c.d", "a.b"), DELEGATE
        );
        assertEq(hashed.length, 2);
        assertEq(hashed[0], OTHER_NAME);
        assertEq(hashed[1], NAME);
        assertEq(networks.length, 2);
        assertEq(networks[0].name, LibRainDeploy.ARBITRUM_ONE);
        assertEq(networks[1].name, LibRainDeploy.BASE);
    }

    /// The inputs record, field for field, for two of st0x's config names and
    /// a delegate of `0x…dEaD`. The hashes are `cast keccak` of each name.
    function testDescribeInputs() external pure {
        string memory head = string.concat(
            "Scope: st0x.vault-beacon.v1\n",
            "Scope hash (keccak256 of the scope): 0xbc3702bc4254d6adf9c8d9533435a31cdab2986e3ce12c603de052c6987573ba\n",
            "Scope: st0x.rbac.us.v1\n",
            "Scope hash (keccak256 of the scope): 0xb046f6b844b680f0dcfc7a139f126e7e13d58023f8d26c15e3229eb4fff8499f\n",
            "Authority (signer): ",
            vm.toString(AUTHORITY),
            "\nDelegate: 0x000000000000000000000000000000000000dEaD\n"
        );
        string memory registry =
            string.concat("\nRegistry: ", vm.toString(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS));
        string[] memory names = list("st0x.vault-beacon.v1", "st0x.rbac.us.v1");
        assertEq(
            LibRegistryDelegatesApprove.describeInputs(
                LibConfigRegistryApprove.delegation(), vm, names, AUTHORITY, address(0xdEaD), true
            ),
            string.concat(head, "Target: approved", registry)
        );
        assertEq(
            LibRegistryDelegatesApprove.describeInputs(
                LibConfigRegistryApprove.delegation(), vm, names, AUTHORITY, address(0xdEaD), false
            ),
            string.concat(head, "Target: revoked", registry)
        );
    }

    /// The network head, with the delegate's code size either way.
    function testDescribeNetwork() external pure {
        assertEq(
            LibRegistryDelegatesApprove.describeNetwork(vm, "base", 8453, 0),
            "Network: base\n  chain id: 8453\n  delegate code: none"
        );
        assertEq(
            LibRegistryDelegatesApprove.describeNetwork(vm, "base", 8453, 171),
            "Network: base\n  chain id: 8453\n  delegate code: 171 bytes"
        );
    }

    /// Every action a scope's line can name.
    function testDescribeScope() external pure {
        assertEq(LibRegistryDelegatesApprove.describeScope("a.b", false, true), "\n  a.b: not approved, APPROVE");
        assertEq(
            LibRegistryDelegatesApprove.describeScope("a.b", true, true), "\n  a.b: approved, SKIP: already approved"
        );
        assertEq(LibRegistryDelegatesApprove.describeScope("a.b", true, false), "\n  a.b: approved, REVOKE");
        assertEq(
            LibRegistryDelegatesApprove.describeScope("a.b", false, false),
            "\n  a.b: not approved, SKIP: already not approved"
        );
    }

    /// Unapproved delegates are approved for every scope in one transaction
    /// from the authority, emitting `Approved` per scope, and the record is the
    /// one logged.
    function testApproveApproves(address delegate) external {
        assumeNotPrecompile(delegate);
        assumeNotForgeAddress(delegate);
        vm.assume(delegate != address(0));
        IConfigRegistryV4 registry = deployRegistry();
        uint64 nonce = vm.getNonce(AUTHORITY);
        vm.expectEmit(address(registry));
        emit IRegistryDelegatesV2.Approved(AUTHORITY, NAME, delegate);
        vm.expectEmit(address(registry));
        emit IRegistryDelegatesV2.Approved(AUTHORITY, OTHER_NAME, delegate);
        (bool sent, string memory record) =
            this.externalApproveOnSelectedChain(AUTHORITY, list("a.b", "c.d"), hashes(NAME, OTHER_NAME), delegate, true);
        assertTrue(sent);
        assertEq(vm.getNonce(AUTHORITY), nonce + 1);
        assertTrue(registry.approvedV4(AUTHORITY, NAME, delegate));
        assertTrue(registry.approvedV4(AUTHORITY, OTHER_NAME, delegate));
        bytes[] memory batch = new bytes[](2);
        batch[0] = abi.encodePacked(bytes4(0xeb34d125), NAME, uint256(uint160(delegate)));
        batch[1] = abi.encodePacked(bytes4(0xeb34d125), OTHER_NAME, uint256(uint160(delegate)));
        assertEq(
            record,
            string.concat(
                LibRegistryDelegatesApprove.describeNetwork(vm, "base", base().chainId, delegate.code.length),
                "\n  a.b: not approved, APPROVE\n  c.d: not approved, APPROVE\n  Calldata: ",
                vm.toString(multicallData(batch))
            )
        );
        this.externalCheckApprovalOnSelectedChain(hashes(NAME, OTHER_NAME), delegate, true);
    }

    /// With one scope already approved, the one transaction carries only the
    /// other.
    function testApproveSendsOnlyTheScopesNotInTheTargetState() external {
        IConfigRegistryV4 registry = deployRegistry();
        vm.prank(AUTHORITY);
        registry.approveV4(NAME, DELEGATE);
        bytes memory otherData = abi.encodePacked(bytes4(0xeb34d125), OTHER_NAME, uint256(uint160(DELEGATE)));
        uint64 nonce = vm.getNonce(AUTHORITY);
        vm.expectCall(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS, multicallData(calls(otherData)), 1);
        (bool sent, string memory record) =
            this.externalApproveOnSelectedChain(AUTHORITY, list("a.b", "c.d"), hashes(NAME, OTHER_NAME), DELEGATE, true);
        assertTrue(sent);
        assertEq(vm.getNonce(AUTHORITY), nonce + 1);
        assertTrue(registry.approvedV4(AUTHORITY, OTHER_NAME, DELEGATE));
        assertEq(
            record,
            string.concat(
                LibRegistryDelegatesApprove.describeNetwork(vm, "base", base().chainId, 0),
                "\n  a.b: approved, SKIP: already approved\n  c.d: not approved, APPROVE\n  Calldata: ",
                vm.toString(multicallData(calls(otherData)))
            )
        );
    }

    /// An approved delegate is revoked: one transaction from the authority,
    /// emitting `Revoked`.
    function testRevokeRevokes() external {
        IConfigRegistryV4 registry = deployRegistry();
        vm.prank(AUTHORITY);
        registry.approveV4(NAME, DELEGATE);
        uint64 nonce = vm.getNonce(AUTHORITY);
        vm.expectEmit(address(registry));
        emit IRegistryDelegatesV2.Revoked(AUTHORITY, NAME, DELEGATE);
        (bool sent, string memory record) =
            this.externalApproveOnSelectedChain(AUTHORITY, one("a.b"), hashes(NAME), DELEGATE, false);
        assertTrue(sent);
        assertEq(vm.getNonce(AUTHORITY), nonce + 1);
        assertFalse(registry.approvedV4(AUTHORITY, NAME, DELEGATE));
        assertEq(
            record,
            string.concat(
                LibRegistryDelegatesApprove.describeNetwork(vm, "base", base().chainId, 0),
                "\n  a.b: approved, REVOKE\n  Calldata: ",
                vm.toString(
                    multicallData(calls(abi.encodePacked(bytes4(0x8f02e4a5), NAME, uint256(uint160(DELEGATE)))))
                )
            )
        );
        this.externalCheckApprovalOnSelectedChain(hashes(NAME), DELEGATE, false);
    }

    /// Every scope already in the target state, either way, sends nothing and
    /// logs no calldata.
    function testSkipsTargetState(bool approve) external {
        IConfigRegistryV4 registry = deployRegistry();
        if (approve) {
            vm.startPrank(AUTHORITY);
            registry.approveV4(NAME, DELEGATE);
            registry.approveV4(OTHER_NAME, DELEGATE);
            vm.stopPrank();
        }
        uint64 nonce = vm.getNonce(AUTHORITY);
        vm.recordLogs();
        (bool sent, string memory record) = this.externalApproveOnSelectedChain(
            AUTHORITY, list("a.b", "c.d"), hashes(NAME, OTHER_NAME), DELEGATE, approve
        );
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].emitter != address(registry));
        }
        assertFalse(sent);
        assertEq(vm.getNonce(AUTHORITY), nonce);
        assertEq(registry.approvedV4(AUTHORITY, NAME, DELEGATE), approve);
        assertEq(
            record,
            string.concat(
                LibRegistryDelegatesApprove.describeNetwork(vm, "base", base().chainId, 0),
                LibRegistryDelegatesApprove.describeScope("a.b", approve, approve),
                LibRegistryDelegatesApprove.describeScope("c.d", approve, approve)
            )
        );
    }

    /// The approval read is under the authority and name given: another
    /// authority's or another name's approval is not this one.
    function testApprovalIsPerAuthorityAndName(address other, bytes32 otherName) external {
        vm.assume(other != AUTHORITY && other != address(0));
        vm.assume(otherName != NAME);
        IConfigRegistryV4 registry = deployRegistry();
        vm.prank(other);
        registry.approveV4(NAME, DELEGATE);
        vm.prank(AUTHORITY);
        registry.approveV4(otherName, DELEGATE);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRegistryDelegatesApprove.UnexpectedApproval.selector, "base", AUTHORITY, NAME, DELEGATE, true
            )
        );
        this.externalCheckApprovalOnSelectedChain(hashes(NAME), DELEGATE, true);
        (bool sent,) = this.externalApproveOnSelectedChain(AUTHORITY, one("a.b"), hashes(NAME), DELEGATE, true);
        assertTrue(sent);
        assertTrue(registry.approvedV4(AUTHORITY, NAME, DELEGATE));
    }

    /// The confirmed check refuses the opposite state, naming the first scope
    /// in it, and checks every scope rather than the first alone.
    function testCheckApprovalRefusesTheOtherState(bool approve) external {
        IConfigRegistryV4 registry = deployRegistry();
        if (!approve) {
            vm.prank(AUTHORITY);
            registry.approveV4(NAME, DELEGATE);
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRegistryDelegatesApprove.UnexpectedApproval.selector, "base", AUTHORITY, NAME, DELEGATE, approve
            )
        );
        this.externalCheckApprovalOnSelectedChain(hashes(NAME, OTHER_NAME), DELEGATE, approve);

        vm.prank(AUTHORITY);
        if (approve) {
            registry.approveV4(NAME, DELEGATE);
        } else {
            registry.revokeV4(NAME, DELEGATE);
        }
        if (!approve) {
            vm.prank(AUTHORITY);
            registry.approveV4(OTHER_NAME, DELEGATE);
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRegistryDelegatesApprove.UnexpectedApproval.selector,
                "base",
                AUTHORITY,
                OTHER_NAME,
                DELEGATE,
                approve
            )
        );
        this.externalCheckApprovalOnSelectedChain(hashes(NAME, OTHER_NAME), DELEGATE, approve);
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
        this.externalApproveOnSelectedChain(AUTHORITY, one("a.b"), hashes(NAME), DELEGATE, true);
        vm.expectRevert(expected);
        this.externalCheckApprovalOnSelectedChain(hashes(NAME), DELEGATE, false);
    }

    /// The transaction and the confirmed check both refuse a chain without
    /// the pinned registry.
    function testWithoutRegistry() external {
        vm.chainId(base().chainId);
        bytes memory expected = abi.encodeWithSelector(
            LibRegistryDelegatesApprove.UnexpectedRegistryCodeHash.selector,
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
            bytes32(0)
        );
        vm.expectRevert(expected);
        this.externalApproveOnSelectedChain(AUTHORITY, one("a.b"), hashes(NAME), DELEGATE, true);
        vm.expectRevert(expected);
        this.externalCheckApprovalOnSelectedChain(hashes(NAME), DELEGATE, false);
    }

    /// On the local fork seam, `approveOnNetworks` approves every scope on
    /// every selected network in selection order and returns each fork and the
    /// inputs record; the confirmed check then passes, and a revoke run
    /// reverses it. The seam's broadcast is a no-op, so this contract signs and
    /// is the authority.
    function testApproveOnNetworks() external {
        IConfigRegistryV4 registry = deployRegistry();
        Vm forkVm = Vm(address(new LocalForkVm()));
        string[] memory selected = list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        string[] memory names = list("a.b", "c.d");
        SupportedNetwork[] memory networks = LibRainDeploy.declaredNetworkConfigs(selected);

        (uint256[] memory forkIds, string memory record) =
            this.externalApproveOnNetworks(forkVm, selected, address(this), names, true);
        assertEq(forkIds.length, 2);
        assertEq(forkIds[0], networks[0].chainId);
        assertEq(forkIds[1], networks[1].chainId);
        assertEq(block.chainid, networks[1].chainId);
        assertEq(
            record,
            LibRegistryDelegatesApprove.describeInputs(
                LibConfigRegistryApprove.delegation(), vm, names, address(this), DELEGATE, true
            )
        );
        assertTrue(registry.approvedV4(address(this), NAME, DELEGATE));
        assertTrue(registry.approvedV4(address(this), OTHER_NAME, DELEGATE));
        this.externalCheckApprovalOnNetworks(forkVm, selected, address(this), names, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRegistryDelegatesApprove.UnexpectedApproval.selector,
                LibRainDeploy.ARBITRUM_ONE,
                address(this),
                NAME,
                DELEGATE,
                false
            )
        );
        this.externalCheckApprovalOnNetworks(forkVm, selected, address(this), names, false);

        this.externalApproveOnNetworks(forkVm, selected, address(this), names, false);
        assertFalse(registry.approvedV4(address(this), NAME, DELEGATE));
        assertFalse(registry.approvedV4(address(this), OTHER_NAME, DELEGATE));
        this.externalCheckApprovalOnNetworks(forkVm, selected, address(this), names, false);
    }

    /// The fork loops refuse fork ids not paired one to one with the
    /// networks.
    function testForkLoopsRefuseUnpairedForks() external {
        Vm forkVm = Vm(address(new LocalForkVm()));
        string[] memory selected = list(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        uint256[] memory oneFork = new uint256[](1);
        uint256[] memory three = new uint256[](3);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 1));
        this.externalApproveOnForks(forkVm, selected, oneFork);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 3));
        this.externalApproveOnForks(forkVm, selected, three);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 1));
        this.externalCheckApprovalOnForks(forkVm, selected, oneFork);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 3));
        this.externalCheckApprovalOnForks(forkVm, selected, three);
    }

    /// The confirmed check refuses its inputs before anything is forked.
    function testCheckApprovalOnNetworksRefusesInputs() external {
        Vm forkVm = Vm(address(new LocalForkVm()));
        vm.expectRevert(abi.encodeWithSelector(LibRegistryDelegatesApprove.NoScopes.selector));
        this.externalCheckApprovalOnNetworks(forkVm, new string[](0), AUTHORITY, new string[](0), true);
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalCheckApprovalOnNetworks(forkVm, new string[](0), AUTHORITY, list("a.b", "A"), true);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckApprovalOnNetworks(forkVm, new string[](0), AUTHORITY, one("a.b"), true);
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        this.externalCheckApprovalOnNetworks(forkVm, list(LibRainDeploy.BASE, "nowhere"), AUTHORITY, one("a.b"), true);
    }
}
