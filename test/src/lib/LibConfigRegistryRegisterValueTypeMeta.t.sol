// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {IConfigRegistryV5} from "../../../src/interface/IConfigRegistryV5.sol";
import {LibConfigRegistry} from "../../../src/lib/LibConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "../../../src/lib/LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister, ConfigBinding} from "../../../src/lib/LibConfigRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {VALUE_TYPE_HASH, configBinding} from "../../lib/ConfigTestBinding.sol";
import {rainMeta} from "../../lib/RainMeta.sol";

/// @title LibConfigRegistryRegisterValueTypeMetaTest
/// @notice `LibConfigRegistryRegister` refuses an empty value type before any
/// network, binds and checks the binding's own type, and sends the binding's
/// meta.
contract LibConfigRegistryRegisterValueTypeMetaTest is Test {
    address internal constant AUTHORITY = address(0xA11CE);
    bytes32 internal constant META_TOPIC = keccak256("MetaV1_2(address,bytes32,bytes)");

    function base() internal pure returns (SupportedNetwork memory) {
        string[] memory names = new string[](1);
        names[0] = LibRainDeploy.BASE;
        return LibRainDeploy.declaredNetworkConfigs(names)[0];
    }

    function deployRegistry() internal returns (IConfigRegistryV5) {
        vm.chainId(base().chainId);
        LibRainDeploy.etchZoltuFactory(vm);
        return IConfigRegistryV5(LibRainDeploy.deployZoltu(type(ConfigRegistry).creationCode));
    }

    function binding(string memory name, string memory valueType, bytes memory value, bytes memory meta)
        internal
        pure
        returns (ConfigBinding memory)
    {
        return ConfigBinding({name: name, valueType: valueType, value: value, meta: meta});
    }

    function externalRegisterOnNetworks(string[] memory selected, ConfigBinding memory b)
        external
        returns (uint256[] memory, string memory)
    {
        return LibConfigRegistryRegister.registerOnNetworks(
            vm, selected, LibRainDeploy.supportedNetworks(), AUTHORITY, AUTHORITY, b
        );
    }

    function externalRegisterOnSelectedChain(bytes32 name, ConfigBinding memory b)
        external
        returns (bool, string memory)
    {
        return LibConfigRegistryRegister.registerOnSelectedChain(vm, base(), AUTHORITY, AUTHORITY, name, b);
    }

    function externalCheckRegisteredOnSelectedChain(bytes32 name, ConfigBinding memory b)
        external
        view
        returns (uint256)
    {
        return LibConfigRegistryRegister.checkRegisteredOnSelectedChain(vm, base(), AUTHORITY, name, b);
    }

    function countMeta(Vm.Log[] memory entries, address registry, bytes memory expected)
        internal
        pure
        returns (uint256)
    {
        uint256 metas = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == registry && entries[i].topics[0] == META_TOPIC) {
                metas++;
                assertEq(entries[i].data, expected);
            }
        }
        return metas;
    }

    /// An empty value type is refused after the name and value and before the
    /// networks.
    function testRegisterOnNetworksRefusesEmptyValueTypeInOrder() external {
        bytes32 hashed = keccak256("a.b");
        string[] memory none = new string[](0);
        string[] memory nowhere = new string[](1);
        nowhere[0] = "nowhere";

        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalName.selector, "A"));
        this.externalRegisterOnNetworks(none, binding("A", "", "", ""));

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValue.selector, hashed));
        this.externalRegisterOnNetworks(none, binding("a.b", "", "", ""));

        bytes memory bare = abi.encodePacked(address(0xdEaD));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalValue.selector, bare));
        this.externalRegisterOnNetworks(none, binding("a.b", "", bare, ""));

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValueType.selector, hashed));
        this.externalRegisterOnNetworks(none, binding("a.b", "", abi.encode(address(1)), ""));

        vm.expectRevert(abi.encodeWithSelector(IConfigRegistryV5.EmptyValueType.selector, hashed));
        this.externalRegisterOnNetworks(nowhere, binding("a.b", "", abi.encode(address(1)), hex"01"));

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalRegisterOnNetworks(none, binding("a.b", "x", abi.encode(address(1)), ""));
    }

    /// The bind is made as the binding's type, whatever it is.
    function testRegisterBindsTheBindingsType(bytes32 name, string memory valueType, bytes memory value) external {
        vm.assume(bytes(valueType).length > 0 && value.length > 0);
        IConfigRegistryV5 registry = deployRegistry();
        vm.warp(1);
        vm.recordLogs();
        (bool broadcast,) = this.externalRegisterOnSelectedChain(name, binding("", valueType, value, ""));
        assertTrue(broadcast);
        (bytes memory bound,, bytes32 boundTypeHash) = registry.getV5(AUTHORITY, name);
        assertEq(bound, value);
        assertEq(boundTypeHash, keccak256(bytes(valueType)));
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(countMeta(entries, address(registry), ""), 0);
    }

    /// The confirmed check refuses the bound value when it was bound as
    /// another type.
    function testCheckRegisteredOnSelectedChainRefusesOtherType(bytes32 name, bytes memory value) external {
        vm.assume(value.length > 0);
        IConfigRegistryV5 registry = deployRegistry();
        vm.warp(1);
        vm.prank(AUTHORITY);
        registry.registerV5(AUTHORITY, name, "uint256", value, "");
        vm.warp(2);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector, AUTHORITY, name, VALUE_TYPE_HASH, keccak256("uint256")
            )
        );
        this.externalCheckRegisteredOnSelectedChain(name, configBinding("", value));
        assertEq(this.externalCheckRegisteredOnSelectedChain(name, binding("", "uint256", value, "")), 1);
    }

    /// The calldata for a Safe or another signer binds as the binding's type
    /// and carries its meta.
    function testRegisterCalldataCarriesTypeAndMeta(
        bytes32 name,
        string memory valueType,
        bytes memory value,
        bytes memory meta
    ) external {
        vm.assume(bytes(valueType).length > 0 && value.length > 0);
        if (meta.length > 0) meta = rainMeta(meta);
        IConfigRegistryV5 registry = deployRegistry();
        vm.warp(1);
        bytes memory data =
            LibConfigRegistryRegister.registerCalldata(AUTHORITY, name, binding("", valueType, value, meta));
        vm.recordLogs();
        vm.prank(AUTHORITY);
        (bool success,) = address(registry).call(data);
        assertTrue(success);
        assertEq(
            countMeta(
                vm.getRecordedLogs(),
                address(registry),
                abi.encode(AUTHORITY, keccak256(abi.encode(AUTHORITY, name)), meta)
            ),
            meta.length > 0 ? 1 : 0
        );
        (bytes memory bound,, bytes32 boundTypeHash) = registry.getV5(AUTHORITY, name);
        assertEq(bound, value);
        assertEq(boundTypeHash, keccak256(bytes(valueType)));
    }

    /// The inputs record names the type, its hash and the meta, and its
    /// calldata is `cast calldata "registerV5(address,bytes32,string,bytes,bytes)"
    /// <authority> <hash> uint256 <value> 0xff0a89c674ee7874`.
    function testDescribeInputsNamesTypeAndMeta() external pure {
        assertEq(
            LibConfigRegistryRegister.describeInputs(
                vm,
                binding("st0x.token-owner-safe", "uint256", abi.encode(uint256(0xdead)), hex"ff0a89c674ee7874"),
                address(0xB0B),
                AUTHORITY
            ),
            string.concat(
                "Name: st0x.token-owner-safe\n",
                "Name hash (keccak256 of the name): 0xba1ec70c388d07ed204e3cfdcbdc2564f9aa2e5b310aeae3767c61a68306cfc8\n",
                "Value type: uint256\n",
                "Value type hash (keccak256 of the value type): ",
                vm.toString(keccak256("uint256")),
                "\nValue: 0x000000000000000000000000000000000000000000000000000000000000dead\n",
                "Meta: 0xff0a89c674ee7874\n",
                "Authority: ",
                vm.toString(AUTHORITY),
                "\nSender: ",
                vm.toString(address(0xB0B)),
                "\nRegistry: ",
                vm.toString(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS),
                "\nCalldata: 0x41f0fc94",
                "00000000000000000000000000000000000000000000000000000000000a11ce",
                "ba1ec70c388d07ed204e3cfdcbdc2564f9aa2e5b310aeae3767c61a68306cfc8",
                "00000000000000000000000000000000000000000000000000000000000000a0",
                "00000000000000000000000000000000000000000000000000000000000000e0",
                "0000000000000000000000000000000000000000000000000000000000000120",
                "0000000000000000000000000000000000000000000000000000000000000007",
                "75696e7432353600000000000000000000000000000000000000000000000000",
                "0000000000000000000000000000000000000000000000000000000000000020",
                "000000000000000000000000000000000000000000000000000000000000dead",
                "0000000000000000000000000000000000000000000000000000000000000008",
                "ff0a89c674ee7874000000000000000000000000000000000000000000000000"
            )
        );
    }
}
