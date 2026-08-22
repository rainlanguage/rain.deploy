// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.2/src/Vm.sol";
import {console2} from "forge-std-1.16.2/src/console2.sol";

import {LibRainDeploy} from "./LibRainDeploy.sol";

/// @title LibHyperCore
/// @notice Moves HYPE from an address on HyperEVM to the SAME address on
/// HyperCore, so that a deployer which already holds HYPE for gas can make
/// itself a HyperCore user without an external bridge.
///
/// ## Why a deploy repo has this at all
///
/// Deploying anything sizeable to HyperEVM needs big blocks, and big blocks are
/// opted into with a `{"type": "evmUserModify", "usingBigBlocks": true}` action
/// signed by the deployer. HyperCore only accepts that action from an address
/// that is ALREADY a HyperCore user, and an address becomes one by holding a
/// Core asset. So a freshly funded EVM deployer — which holds HYPE, because it
/// pays gas in it — cannot opt in, and the usual answer is to bridge something
/// in from somewhere else.
///
/// It does not have to be. HYPE is the native gas token on HyperEVM rather than
/// an ERC20, and value sent to the system contract on the EVM side arrives on
/// Core for the sender. The deployer therefore credits ITSELF out of the
/// balance it already has, and the whole prerequisite collapses into one
/// value transfer with no third party in it.
///
/// ## The mechanism
///
/// `HYPE_SYSTEM_ADDRESS` is a payable contract whose `receive()` emits
/// `Received(address indexed user, uint256 amount)` and does nothing else.
/// HyperCore watches that log and credits `user` — which is `msg.sender` of the
/// EVM call — with `amount`, converted into Core's wei decimals. Nothing is
/// called, nothing is approved and no calldata is sent: a bare value transfer
/// is the entire interface, which is why an EOA can do this as readily as a
/// contract.
///
/// The direction is one way. This sends EVM -> Core; the return leg is a Core
/// action and has nothing to do with this library.
library LibHyperCore {
    /// Thrown when the selected chain is not HyperEVM.
    ///
    /// This is the guard that matters most here and it is checked first, before
    /// anything else is read. `HYPE_SYSTEM_ADDRESS` is a system contract on
    /// HyperEVM and an ordinary, almost certainly empty, address everywhere
    /// else — nobody holds its key, and no chain but HyperEVM is watching it.
    /// Value sent to it on any other chain is not refused, it is simply gone,
    /// and gone at an address that looks deliberate enough that the mistake is
    /// easy to make twice.
    ///
    /// A chain id rather than an RPC alias, because the alias is not the fact.
    /// `HYPEREVM_RPC_URL` is bound at run time by rainix's rpc-preflight to
    /// whichever candidate endpoint is reachable, so the alias says which
    /// endpoint answered and the chain id says what it answered as.
    /// @param expected `HYPEREVM_CHAIN_ID`.
    /// @param actual The chain id of the selected fork.
    error UnexpectedChainId(uint256 expected, uint256 actual);

    /// Thrown when the code at `HYPE_SYSTEM_ADDRESS` is not the code this
    /// library was written against.
    ///
    /// The chain id says the endpoint answered as HyperEVM. This says the
    /// contract that will receive the value is the one whose `receive()` emits
    /// the log Core credits from. Both, because a fork of HyperEVM reports
    /// HyperEVM's chain id while holding whatever state its operator put there,
    /// and because a system contract that has been replaced is a mechanism that
    /// may have changed under a library that would otherwise carry on sending
    /// real value into it.
    ///
    /// Also the zero hash, which is what an address with no code at all
    /// reports, so a chain that merely does not have this contract fails here
    /// rather than accepting the transfer into a hole.
    /// @param expected `HYPE_SYSTEM_CODEHASH`.
    /// @param actual The code hash actually at `HYPE_SYSTEM_ADDRESS`.
    error SystemContractChanged(bytes32 expected, bytes32 actual);

    /// Thrown when the amount to credit is zero.
    ///
    /// A zero transfer emits `Received(user, 0)` and credits nothing, so it
    /// spends gas to leave the deployer exactly as much of a non-user as it was
    /// — while reporting success, which is the shape of failure this whole
    /// script exists to avoid.
    error ZeroCredit();

    /// Thrown when the amount would lose value to Core's coarser wei decimals.
    ///
    /// Core carries HYPE in `HYPE_CORE_DECIMALS` wei decimals and the EVM
    /// carries it in `HYPE_EVM_DECIMALS`, so a credit is the EVM amount divided
    /// by `HYPE_EVM_WEI_PER_CORE_WEI` and the remainder is BURNED rather than
    /// credited or returned.
    ///
    /// Refused rather than rounded, because the sharp end of it is not the
    /// dust. An amount smaller than one Core wei has no non-remainder part at
    /// all: every bit of it is burned, nothing whatsoever reaches Core, the
    /// deployer does not become a HyperCore user, and the transfer succeeds. A
    /// caller that meant to send that amount wants to hear about it, and one
    /// that meant to send more has a typo worth catching.
    /// @param amount The amount that was asked for.
    /// @param evmWeiPerCoreWei `HYPE_EVM_WEI_PER_CORE_WEI`, which `amount` has
    /// to be a whole multiple of.
    error CreditNotRound(uint256 amount, uint256 evmWeiPerCoreWei);

    /// Thrown when the account cannot cover the credit and the gas to send it.
    ///
    /// Strictly greater than, not at least: gas on HyperEVM is paid in HYPE out
    /// of this same balance, so an account holding exactly `amount` cannot send
    /// `amount`. How much more it needs is the gas price at the time, which is
    /// not knowable here, but zero more is knowably not enough.
    /// @param account The account that would send the credit.
    /// @param balance Its HYPE balance on HyperEVM.
    /// @param amount The amount asked for.
    error InsufficientBalance(address account, uint256 balance, uint256 amount);

    /// Thrown when the value transfer to the system contract reverts.
    ///
    /// Not reachable through the guards above: the pinned bytecode reverts only
    /// on a call carrying calldata, this one carries none, and the balance
    /// guard has already funded it. It is here because an unchecked low-level
    /// call is a defect on its own terms, and because loosening either pin
    /// would make it reachable — and because without it a failed transfer would
    /// be reported as `UnexpectedSystemBalance`, which is the wrong diagnosis
    /// for it.
    /// @param account The account the credit was sent from.
    /// @param amount The amount sent.
    /// @param returnData The revert data from the system contract.
    error CreditFailed(address account, uint256 amount, bytes returnData);

    /// Thrown when the system contract's balance did not rise by exactly the
    /// amount sent. A successful call that did not move the value is not a
    /// credit, and Core reads the transfer rather than the return status.
    ///
    /// The one assertion after the transfer, and the SYSTEM side of it rather
    /// than the sender's, because only one of the two can ever be reached. A
    /// direct value transfer moves both balances or neither, so the only input
    /// that reaches either is one where they are the same balance — `account`
    /// being the system contract itself, which sends to itself and moves
    /// nothing. Whichever check is written first is the one that fires, and the
    /// other is unreachable by construction. This is the side that says what
    /// Core reads.
    /// @param expected The balance before, plus the amount.
    /// @param actual The balance after.
    error UnexpectedSystemBalance(uint256 expected, uint256 actual);

    /// HyperEVM's chain id. The only chain any of this means anything on.
    uint256 constant HYPEREVM_CHAIN_ID = 999;

    /// The HyperEVM system contract for native HYPE. Value sent here is
    /// credited to the sender's HyperCore account.
    ///
    /// HYPE is a special case among the assets that cross this boundary,
    /// because on the EVM side it is the native gas token rather than an ERC20.
    /// Spot tokens each get their own system address derived from their token
    /// index and move by `transfer`; HYPE moves as transaction value into this
    /// one.
    address constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;

    /// Runtime bytecode of the HYPE system contract, for `vm.etch`.
    ///
    /// It is a `receive()` and nothing else: any call carrying calldata
    /// reverts, and a call carrying none emits
    /// `Received(address indexed user, uint256 amount)` with `user` the caller
    /// and `amount` the value. That is the whole contract, which is why pinning
    /// it is cheap and why the pin is worth having.
    bytes constant HYPE_SYSTEM_BYTECODE =
        hex"608060405236603f5760405134815233907f88a5966d370b9919b20f3e2c13ff65706f196a4e32cc2c12bf57088f885258749060200160405180910390a2005b600080fdfea2646970667358221220ca425db50898ac19f9e4676e86e8ebed9853baa048942f6306fe8a86b8d4abb964736f6c63430008090033";

    /// Code hash of `HYPE_SYSTEM_BYTECODE`, checked against the live contract
    /// before any value is sent.
    bytes32 constant HYPE_SYSTEM_CODEHASH = 0xf79e9de95af9d7ada36fd11ff7da9308976f47f441a8acea9dcfaa8ab703baf2;

    /// Wei decimals HYPE has on HyperEVM, where it is the native gas token.
    uint256 constant HYPE_EVM_DECIMALS = 18;

    /// Wei decimals HYPE has on HyperCore.
    uint256 constant HYPE_CORE_DECIMALS = 8;

    /// EVM wei in one Core wei of HYPE. A credit is the EVM amount divided by
    /// this, and the remainder is burned, so an amount below it credits nothing
    /// at all.
    uint256 constant HYPE_EVM_WEI_PER_CORE_WEI = 10 ** (HYPE_EVM_DECIMALS - HYPE_CORE_DECIMALS);

    /// Etches the HYPE system contract's runtime code at its address, so that
    /// the transfer can be exercised somewhere that is not HyperEVM.
    ///
    /// For tests. The chain guard is not etchable, so a test that wants past it
    /// pairs this with `vm.chainId(HYPEREVM_CHAIN_ID)`, and what it then drives
    /// is the real contract's real bytecode rather than a mock that agrees with
    /// whatever this library expects.
    /// @param vm The Vm instance to etch with.
    function etchHypeSystemContract(Vm vm) internal {
        vm.etch(HYPE_SYSTEM_ADDRESS, HYPE_SYSTEM_BYTECODE);
    }

    /// Sends `amount` HYPE from `account` to the system contract on the
    /// SELECTED chain, crediting `account`'s HyperCore account.
    ///
    /// Every guard runs before the broadcast, in the order where, what, who:
    /// the chain and the contract that will receive the value, then the amount,
    /// then the funds to send it. The first two are the ones that decide
    /// whether the value is recoverable at all, so they are the ones that go
    /// first.
    ///
    /// Takes the account rather than its key. The caller's own
    /// `vm.rememberKey` is what turns a key into an address, and an address
    /// here means a caller cannot hand the amount and the key to each other by
    /// mistake — they are not the same type, so it does not compile.
    /// @param vm The Vm instance to broadcast with.
    /// @param account The account to send from, and therefore the HyperCore
    /// account credited.
    /// @param amount The amount of HYPE to send, in EVM wei.
    function creditCore(Vm vm, address account, uint256 amount) internal {
        if (block.chainid != HYPEREVM_CHAIN_ID) {
            revert UnexpectedChainId(HYPEREVM_CHAIN_ID, block.chainid);
        }
        if (HYPE_SYSTEM_ADDRESS.codehash != HYPE_SYSTEM_CODEHASH) {
            revert SystemContractChanged(HYPE_SYSTEM_CODEHASH, HYPE_SYSTEM_ADDRESS.codehash);
        }
        if (amount == 0) {
            revert ZeroCredit();
        }
        if (amount % HYPE_EVM_WEI_PER_CORE_WEI != 0) {
            revert CreditNotRound(amount, HYPE_EVM_WEI_PER_CORE_WEI);
        }
        if (account.balance <= amount) {
            revert InsufficientBalance(account, account.balance, amount);
        }

        uint256 systemBalanceBefore = HYPE_SYSTEM_ADDRESS.balance;

        console2.log("Crediting HyperCore account:", account);
        console2.log(" - HYPE system contract:", HYPE_SYSTEM_ADDRESS);
        console2.log(" - EVM wei sent:", amount);
        console2.log(" - Core wei credited:", amount / HYPE_EVM_WEI_PER_CORE_WEI);

        vm.broadcast(account);
        // A bare value transfer with no calldata is the entire interface, so
        // there is no function to call and no interface to call it through.
        // Excluded at the site rather than repo-wide so a low-level call added
        // anywhere else is still reported.
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory returnData) = HYPE_SYSTEM_ADDRESS.call{value: amount}("");
        if (!success) {
            revert CreditFailed(account, amount, returnData);
        }

        if (HYPE_SYSTEM_ADDRESS.balance != systemBalanceBefore + amount) {
            revert UnexpectedSystemBalance(systemBalanceBefore + amount, HYPE_SYSTEM_ADDRESS.balance);
        }
    }

    /// `creditCore` against the `hyperevm` RPC alias.
    ///
    /// The fork is taken here rather than left to a `--rpc-url` on the command
    /// line, which is how `LibRainDeploy` reaches a network too: the alias is
    /// the repo's own declaration of what HyperEVM is, and a script that
    /// depended on a flag would send wherever the flag pointed. The chain guard
    /// in `creditCore` is then a real check rather than a formality — it is
    /// what says the alias resolved to HyperEVM and not to whatever else was
    /// reachable.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param account The account to send from, and therefore the HyperCore
    /// account credited.
    /// @param amount The amount of HYPE to send, in EVM wei.
    function creditCoreOnHyperEvm(Vm vm, address account, uint256 amount) internal {
        // createSelectFork returns a fork id that is not needed here; bind and
        // reference it so the unused-return lint stays satisfied.
        uint256 forkId = vm.createSelectFork(LibRainDeploy.HYPEREVM);
        (forkId);
        creditCore(vm, account, amount);
    }
}
