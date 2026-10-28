// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IRegistryDelegatesV2} from "../../src/interface/IRegistryDelegatesV2.sol";
import {LibRegistryDelegatesApprove} from "../../src/lib/LibRegistryDelegatesApprove.sol";
import {LibConfigRegistryRegister} from "../../src/lib/LibConfigRegistryRegister.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRegistryAuthority} from "../../src/lib/LibRegistryAuthority.sol";

/// The local script harness both registries' wiring tests drive.
interface ILocalApproveRegistryDelegate {
    function baseForkVm() external view returns (Vm);
    function run() external returns (uint256[] memory);
    function runAsItself() external returns (uint256[] memory);
    function verify() external;
}

/// @title ApproveRegistryDelegateWiringTest
/// The script's wiring: which variables it reads, that the signer is the
/// script's `msg.sender`, that both entries default to every supported network
/// and to approving, and that it forks with the cheatcodes. Every network forks
/// as the local EVM.
///
/// ONE test function, because it writes process-wide environment variables and
/// forge runs test functions concurrently. Nothing else in the suite reads or
/// writes these names, and the unset cases run before each variable is first
/// set, since a set variable cannot be unset.
abstract contract ApproveRegistryDelegateWiringTest is Test {
    /// @return The registry's local script harness.
    function newScript() internal virtual returns (ILocalApproveRegistryDelegate);

    /// @return The script's variable prefix.
    function prefix() internal pure virtual returns (string memory);

    /// @return The pinned registry and its code hash.
    function pinned() internal pure virtual returns (address, bytes32);

    /// Deploys the pinned registry on the local EVM.
    function deployRegistry() internal virtual;

    /// @param suffix The variable's name after the prefix.
    /// @return The variable's full name.
    function e(string memory suffix) internal pure returns (string memory) {
        return string.concat(prefix(), "_", suffix);
    }

    function testWiring() external {
        ILocalApproveRegistryDelegate script = newScript();
        (address registryAddress, bytes32 registryCodehash) = pinned();
        assertEq(address(script.baseForkVm()), address(vm));
        // The no-op broadcast leaves the script signing, and the script is
        // deployed at the root authority, so it signs as it.
        address authority = LibRegistryAuthority.ROOT_AUTHORITY;
        assertEq(address(script), authority);
        address delegate = address(0x5AFE);
        string memory name = string.concat("rain.deploy.approve-test.", vm.toString(vm.randomUint()));
        bytes32 hashed = keccak256(bytes(name));
        IRegistryDelegatesV2 registry = IRegistryDelegatesV2(registryAddress);

        vm.setEnv(e("SCOPES"), name);
        vm.setEnv(e("ADDRESS"), vm.toString(delegate));

        vm.setEnv(e("ADDRESS"), "not-an-address");
        assertEnvAddressRefused(script, e("ADDRESS"));
        vm.setEnv(e("ADDRESS"), vm.toString(address(0)));
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV2.ZeroDelegate.selector));
        script.runAsItself();
        vm.setEnv(e("ADDRESS"), vm.toString(delegate));

        vm.setEnv(e("SCOPES"), "Not.Canonical");
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.runAsItself();
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.verify();
        vm.setEnv(e("SCOPES"), name);

        // The signer is the script's `msg.sender`: this test contract is not
        // the authority.
        vm.expectRevert(
            abi.encodeWithSelector(LibRegistryDelegatesApprove.SenderNotAuthority.selector, address(this), authority)
        );
        script.run();

        // Networks unset: every declared network, and the first has no
        // registry yet.
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRegistryDelegatesApprove.UnexpectedRegistryCodeHash.selector,
                registryAddress,
                registryCodehash,
                bytes32(0)
            )
        );
        script.runAsItself();
        deployRegistry();

        // Approved unset: the default approves, on every declared network:
        // the first sends and the rest, the same local EVM, skip.
        string[] memory supported = LibRainDeploy.supportedNetworks();
        uint256[] memory forkIds = script.runAsItself();
        assertEq(forkIds.length, supported.length);
        for (uint256 i = 0; i < forkIds.length; i++) {
            assertEq(forkIds[i], LibRainDeploy.declaredNetworkConfigs(supported)[i].chainId);
        }
        assertTrue(registry.approvedV4(authority, hashed, delegate));
        script.verify();

        // A run already in the target state sends nothing.
        vm.recordLogs();
        script.runAsItself();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].emitter != address(registry));
        }

        string memory network = supported[0];
        vm.setEnv(e("NETWORKS"), string.concat(network, ",nowhere"));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        script.runAsItself();
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        script.verify();
        vm.setEnv(e("NETWORKS"), network);

        // `false` revokes, on exactly the selected network.
        vm.setEnv(e("APPROVED"), "false");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRegistryDelegatesApprove.UnexpectedApproval.selector, network, authority, hashed, delegate, false
            )
        );
        script.verify();
        forkIds = script.runAsItself();
        assertEq(forkIds.length, 1);
        assertEq(forkIds[0], LibRainDeploy.declaredNetworkConfigs(supported)[0].chainId);
        assertFalse(registry.approvedV4(authority, hashed, delegate));
        script.verify();

        // `true` approves again.
        vm.setEnv(e("APPROVED"), "true");
        script.runAsItself();
        assertTrue(registry.approvedV4(authority, hashed, delegate));
        script.verify();
    }

    /// `run()` stops on forge's own refusal to parse `variable` as an address.
    /// Forge raises it as `CheatcodeError(string)`, and only the prefix naming
    /// the variable is pinned.
    /// @param script The script.
    /// @param variable The variable that does not parse.
    function assertEnvAddressRefused(ILocalApproveRegistryDelegate script, string memory variable) internal {
        try script.runAsItself() {
            revert("run() did not revert");
        } catch (bytes memory reason) {
            bytes memory expectedSelector = abi.encodeWithSignature("CheatcodeError(string)");
            assertGe(reason.length, expectedSelector.length);
            for (uint256 i = 0; i < expectedSelector.length; i++) {
                assertEq(reason[i], expectedSelector[i]);
            }
            bytes memory payload = new bytes(reason.length - 4);
            for (uint256 i = 0; i < payload.length; i++) {
                payload[i] = reason[i + 4];
            }
            bytes memory message = bytes(abi.decode(payload, (string)));
            bytes memory expected = bytes(string.concat("vm.envAddress: failed parsing $", variable));
            assertGe(message.length, expected.length);
            for (uint256 i = 0; i < expected.length; i++) {
                assertEq(message[i], expected[i]);
            }
        }
    }
}
