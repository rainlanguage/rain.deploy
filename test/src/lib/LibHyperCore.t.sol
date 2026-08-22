// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.16.2/src/Test.sol";

import {LibHyperCore} from "../../../src/lib/LibHyperCore.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";

/// @title LibHyperCoreTest
/// @notice The EVM -> Core credit, driven both against the system contract's
/// own bytecode on a local chain and against the live contract on a HyperEVM
/// fork.
///
/// None of it costs anything. `vm.broadcast` under `forge test` executes the
/// transfer against the selected state and records a transaction it never
/// sends, and every account it moves value between is either dealt into
/// existence here or the system contract itself — the same way
/// `RainDeployBroadcastTest` drives the deploy broadcast.
///
/// The local legs `vm.etch` the REAL runtime bytecode rather than a mock, which
/// is the point of pinning it: what they drive is the contract that will
/// receive the money, so the log they observe is the log HyperCore credits
/// from, and a mock that agreed with this library instead would assert nothing
/// about either.
contract LibHyperCoreTest is Test {
    /// The event topic HyperCore credits from. Spelled as a signature the
    /// compiler hashes, not as a hash copied out of the deployed bytecode:
    /// agreeing with the bytes on chain is what the pinned code hash is for,
    /// and a topic transcribed by hand would agree with the transcription.
    bytes32 constant RECEIVED_TOPIC = keccak256("Received(address,uint256)");

    /// A round, non-zero, comfortably affordable credit for the legs that are
    /// about something other than the amount. One hundredth of a HYPE.
    uint256 constant VALID_CREDIT = 1e16;

    /// The account legs that do not fuzz it send from.
    address constant ACCOUNT = address(uint160(uint256(keccak256("hypercore credit account"))));

    /// `creditCore` reached through a call, so `vm.expectRevert` has an
    /// external call to attach to.
    /// @param account The account to credit.
    /// @param amount The amount in EVM wei.
    function externalCreditCore(address account, uint256 amount) external {
        LibHyperCore.creditCore(vm, account, amount);
    }

    /// `creditCoreOnHyperEvm` reached through a call, for the same reason.
    /// @param account The account to credit.
    /// @param amount The amount in EVM wei.
    function externalCreditCoreOnHyperEvm(address account, uint256 amount) external {
        LibHyperCore.creditCoreOnHyperEvm(vm, account, amount);
    }

    /// An account that can be dealt to and broadcast from without colliding
    /// with the transfer's own counterparties or with forge's own addresses.
    /// @param account The fuzzed account.
    function assumeCreditableAccount(address account) internal pure {
        assumeNotPrecompile(account);
        assumeNotForgeAddress(account);
        // The sender and the recipient are the two balances every assertion
        // here is about, so an account that is also the recipient would make
        // both sides of the transfer one number.
        vm.assume(account != LibHyperCore.HYPE_SYSTEM_ADDRESS);
        vm.assume(account != address(0));
    }

    /// Puts the selected state where a credit is expected to WORK: HyperEVM's
    /// chain id, the real system contract at the system address, and an account
    /// that can pay.
    /// @param account The account to fund.
    /// @param amount The amount it is about to send.
    function arrangeCreditableChain(address account, uint256 amount) internal {
        vm.chainId(LibHyperCore.HYPEREVM_CHAIN_ID);
        LibHyperCore.etchHypeSystemContract(vm);
        vm.deal(account, amount + 1);
    }

    /// PROPERTY: the pinned code hash is the hash of the pinned bytecode.
    ///
    /// Two constants describing one contract, and the guard reads only the
    /// hash while `etchHypeSystemContract` writes only the bytes — so a hash
    /// that did not belong to those bytes would make every local leg here
    /// exercise a contract the guard would refuse on chain, and the suite would
    /// not notice.
    function testHypeSystemBytecodeHashesToThePinnedCodehash() external pure {
        assertEq(keccak256(LibHyperCore.HYPE_SYSTEM_BYTECODE), LibHyperCore.HYPE_SYSTEM_CODEHASH);
    }

    /// PROPERTY: one Core wei is `10 ** 10` EVM wei, which is the gap between
    /// HYPE's 18 wei decimals on the EVM and its 8 on Core.
    ///
    /// The constant is what the round-amount guard divides the world into, and
    /// it is derived from two other constants rather than written down, so this
    /// pins the derivation against the number it has to produce.
    function testOneCoreWeiIsTheDecimalGap() external pure {
        assertEq(LibHyperCore.HYPE_EVM_WEI_PER_CORE_WEI, 1e10);
        assertEq(LibHyperCore.HYPE_EVM_DECIMALS - LibHyperCore.HYPE_CORE_DECIMALS, 10);
    }

    /// PROPERTY: a credit is REFUSED on every chain but HyperEVM, and nothing
    /// moves when it is refused.
    ///
    /// The system address is a system contract on HyperEVM and an ordinary
    /// address everywhere else. Value sent to it on another chain is not
    /// refused by anything, it is simply unrecoverable, so this is the guard
    /// the whole script is arranged around.
    ///
    /// Everything else is arranged to SUCCEED — the real bytecode is etched at
    /// the system address, the amount is round and non-zero, the account can
    /// pay — so the chain id is the only thing left that can be refusing it.
    /// Without that the same revert would arrive from a chain that simply had
    /// no system contract on it, which is a different check.
    function testCreditRefusesEveryChainButHyperEvm(uint64 chainId, address account, uint256 amount) external {
        assumeCreditableAccount(account);
        vm.assume(chainId != LibHyperCore.HYPEREVM_CHAIN_ID);
        vm.assume(chainId != 0);
        amount = bound(amount, 1, 1e14) * LibHyperCore.HYPE_EVM_WEI_PER_CORE_WEI;

        arrangeCreditableChain(account, amount);
        vm.chainId(chainId);

        uint256 systemBalanceBefore = LibHyperCore.HYPE_SYSTEM_ADDRESS.balance;
        uint256 accountBalanceBefore = account.balance;

        vm.expectRevert(
            abi.encodeWithSelector(LibHyperCore.UnexpectedChainId.selector, LibHyperCore.HYPEREVM_CHAIN_ID, chainId)
        );
        this.externalCreditCore(account, amount);

        assertEq(LibHyperCore.HYPE_SYSTEM_ADDRESS.balance, systemBalanceBefore);
        assertEq(account.balance, accountBalanceBefore);
    }

    /// PROPERTY: a credit is REFUSED unless the system address holds the exact
    /// contract this library was written against.
    ///
    /// Both ways it can fail: no code at all, which is a chain reporting
    /// HyperEVM's id without HyperEVM's state, and other code, which is a
    /// system contract that has been replaced under a library still sending
    /// real value into it. Neither is distinguishable from the real thing by
    /// chain id alone, which is why there are two guards and not one.
    function testCreditRefusesASystemContractThatIsNotTheOne(bytes memory code, address account) external {
        assumeCreditableAccount(account);
        vm.chainId(LibHyperCore.HYPEREVM_CHAIN_ID);
        vm.deal(account, VALID_CREDIT + 1);

        bytes32 absent = LibHyperCore.HYPE_SYSTEM_ADDRESS.codehash;
        assertNotEq(absent, LibHyperCore.HYPE_SYSTEM_CODEHASH);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibHyperCore.SystemContractChanged.selector, LibHyperCore.HYPE_SYSTEM_CODEHASH, absent
            )
        );
        this.externalCreditCore(account, VALID_CREDIT);

        vm.assume(code.length > 0);
        vm.assume(keccak256(code) != LibHyperCore.HYPE_SYSTEM_CODEHASH);
        vm.etch(LibHyperCore.HYPE_SYSTEM_ADDRESS, code);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibHyperCore.SystemContractChanged.selector, LibHyperCore.HYPE_SYSTEM_CODEHASH, keccak256(code)
            )
        );
        this.externalCreditCore(account, VALID_CREDIT);
    }

    /// PROPERTY: a zero credit is REFUSED.
    ///
    /// Zero is a whole number of Core wei, so the round-amount guard lets it
    /// through, and the transfer itself would succeed — emitting
    /// `Received(user, 0)`, crediting nothing, and leaving the deployer exactly
    /// as unable to opt into big blocks as it was, with the run reporting
    /// success.
    function testCreditRefusesZero(address account) external {
        assumeCreditableAccount(account);
        arrangeCreditableChain(account, 0);

        vm.expectRevert(abi.encodeWithSelector(LibHyperCore.ZeroCredit.selector));
        this.externalCreditCore(account, 0);
    }

    /// PROPERTY: an amount that is not a whole number of Core wei is REFUSED.
    ///
    /// Core carries HYPE in 8 wei decimals against the EVM's 18, so the low ten
    /// digits of an EVM amount are burned rather than credited. Rounding them
    /// away silently is the wrong answer for the same reason the zero case is:
    /// the caller asked for an amount, and some of it would not arrive.
    function testCreditRefusesAnAmountThatIsNotAWholeCoreWei(uint256 amount, address account) external {
        assumeCreditableAccount(account);
        amount = bound(amount, 1, type(uint128).max);
        vm.assume(amount % LibHyperCore.HYPE_EVM_WEI_PER_CORE_WEI != 0);

        arrangeCreditableChain(account, amount);

        vm.expectRevert(
            abi.encodeWithSelector(LibHyperCore.CreditNotRound.selector, amount, LibHyperCore.HYPE_EVM_WEI_PER_CORE_WEI)
        );
        this.externalCreditCore(account, amount);
    }

    /// PROPERTY: an amount below ONE Core wei is REFUSED — the case the
    /// round-amount guard is really there for.
    ///
    /// Everything under `10 ** 10` EVM wei is remainder, so all of it is burned
    /// and NOTHING arrives on Core. The transfer succeeds, the HYPE is gone,
    /// and the address is still not a HyperCore user. Covered by the fuzz above
    /// as a subset, and separately here because it is the outcome that made the
    /// guard worth having.
    function testCreditRefusesAnAmountBelowOneCoreWei(uint256 amount, address account) external {
        assumeCreditableAccount(account);
        amount = bound(amount, 1, LibHyperCore.HYPE_EVM_WEI_PER_CORE_WEI - 1);

        arrangeCreditableChain(account, amount);

        vm.expectRevert(
            abi.encodeWithSelector(LibHyperCore.CreditNotRound.selector, amount, LibHyperCore.HYPE_EVM_WEI_PER_CORE_WEI)
        );
        this.externalCreditCore(account, amount);
    }

    /// PROPERTY: an account that cannot cover the credit AND leave something
    /// for gas is REFUSED.
    ///
    /// Exactly the amount is the boundary and it is refused: gas on HyperEVM is
    /// paid in HYPE out of this same balance, so an account holding precisely
    /// what it is sending cannot send it. One wei more is the smallest balance
    /// this can accept, and the happy path below sends from exactly that.
    function testCreditRefusesAnAccountThatCannotAlsoPayGas(address account, uint256 amount, uint256 shortfall)
        external
    {
        assumeCreditableAccount(account);
        amount = bound(amount, 1, 1e14) * LibHyperCore.HYPE_EVM_WEI_PER_CORE_WEI;
        shortfall = bound(shortfall, 0, amount);

        vm.chainId(LibHyperCore.HYPEREVM_CHAIN_ID);
        LibHyperCore.etchHypeSystemContract(vm);
        vm.deal(account, amount - shortfall);

        vm.expectRevert(
            abi.encodeWithSelector(LibHyperCore.InsufficientBalance.selector, account, amount - shortfall, amount)
        );
        this.externalCreditCore(account, amount);
    }

    /// PROPERTY: a credit moves the amount from the account to the system
    /// contract and emits the log HyperCore credits THAT ACCOUNT from.
    ///
    /// The balances say the value moved. They do not say WHOSE Core account it
    /// lands in, and that is the part with no undo: Core credits the `user`
    /// topic of the `Received` log, which is the EVM `msg.sender`, so a
    /// transfer that arrived by way of anything other than the account itself
    /// would fund a Core account nobody has the key to.
    ///
    /// So the log is read back and matched whole — emitter, topic, user and
    /// amount — against the account that was asked for. It is emitted by the
    /// system contract's own etched bytecode, so what is being observed is the
    /// real log and not this test's idea of one.
    function testCreditSendsTheAmountAndCreditsTheSendingAccount(address account, uint256 amount) external {
        assumeCreditableAccount(account);
        amount = bound(amount, 1, 1e14) * LibHyperCore.HYPE_EVM_WEI_PER_CORE_WEI;

        arrangeCreditableChain(account, amount);
        uint256 systemBalanceBefore = LibHyperCore.HYPE_SYSTEM_ADDRESS.balance;

        vm.recordLogs();
        this.externalCreditCore(account, amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(LibHyperCore.HYPE_SYSTEM_ADDRESS.balance, systemBalanceBefore + amount);
        // Dealt `amount + 1`, so exactly the one wei that could not be sent is
        // what is left. Gas is not deducted from the balance in this
        // simulation, which is why the library bounds the sender's side rather
        // than fixing it.
        assertEq(account.balance, 1);

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, LibHyperCore.HYPE_SYSTEM_ADDRESS);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], RECEIVED_TOPIC);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(account))));
        assertEq(abi.decode(logs[0].data, (uint256)), amount);
    }

    /// PROPERTY: a credit that moved nothing is REFUSED, rather than reported
    /// as a credit.
    ///
    /// Sending from the system contract to the system contract is the only
    /// input that gets past every guard and still moves no value — a direct
    /// transfer moves both balances or neither, so the two are the same balance
    /// only when they are the same account. It is worth refusing on its own
    /// terms, because a run that credited the system contract's own Core
    /// account and said it had worked is the silent success this library is
    /// arranged against.
    ///
    /// It is also the ONLY input that reaches the assertion after the transfer,
    /// which is why there is one of those and not two: whichever side is
    /// checked first is the side that fires here, and the other side would be
    /// unreachable by construction and killed by no mutation.
    function testCreditThatMovesNothingIsRefused() external {
        arrangeCreditableChain(LibHyperCore.HYPE_SYSTEM_ADDRESS, VALID_CREDIT);
        uint256 systemBalanceBefore = LibHyperCore.HYPE_SYSTEM_ADDRESS.balance;

        vm.expectRevert(
            abi.encodeWithSelector(
                LibHyperCore.UnexpectedSystemBalance.selector, systemBalanceBefore + VALID_CREDIT, systemBalanceBefore
            )
        );
        this.externalCreditCore(LibHyperCore.HYPE_SYSTEM_ADDRESS, VALID_CREDIT);
    }

    /// PROPERTY: the `hyperevm` alias resolves to HyperEVM, and the contract
    /// live at the system address there is the one both constants describe.
    ///
    /// This is the test that goes red if Hyperliquid ever replaces the system
    /// contract. That is the intended outcome rather than a nuisance: the
    /// mechanism this library sends real value into would have changed, and the
    /// guard refusing the transfer on chain would be the first anyone heard of
    /// it otherwise.
    function testTheLiveSystemContractIsWhatIsPinned() external {
        vm.createSelectFork(LibRainDeploy.HYPEREVM);

        assertEq(block.chainid, LibHyperCore.HYPEREVM_CHAIN_ID);
        assertEq(LibHyperCore.HYPE_SYSTEM_ADDRESS.code, LibHyperCore.HYPE_SYSTEM_BYTECODE);
        assertEq(LibHyperCore.HYPE_SYSTEM_ADDRESS.codehash, LibHyperCore.HYPE_SYSTEM_CODEHASH);
    }

    /// PROPERTY: the credit works against the LIVE system contract, on a fork
    /// of the chain it will really run on.
    ///
    /// The local legs prove the mechanism against etched bytecode. This proves
    /// the etched bytecode is not the reason they pass — same assertions, same
    /// library, real chain state underneath.
    ///
    /// One account and one amount, where the local legs fuzz both. A fuzzed
    /// body that forks takes a fresh fork per run and reads every account it
    /// touches over the wire, which is a few hundred round trips to say what
    /// the local legs already say across the whole input space. What is being
    /// asked here is only whether the real contract behaves as its pinned
    /// bytecode does, and one credit answers that.
    function testCreditOnAHyperEvmFork() external {
        vm.createSelectFork(LibRainDeploy.HYPEREVM);
        vm.deal(ACCOUNT, VALID_CREDIT + 1);
        uint256 systemBalanceBefore = LibHyperCore.HYPE_SYSTEM_ADDRESS.balance;

        vm.recordLogs();
        this.externalCreditCore(ACCOUNT, VALID_CREDIT);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(LibHyperCore.HYPE_SYSTEM_ADDRESS.balance, systemBalanceBefore + VALID_CREDIT);
        assertEq(ACCOUNT.balance, 1);

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, LibHyperCore.HYPE_SYSTEM_ADDRESS);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], RECEIVED_TOPIC);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(ACCOUNT))));
        assertEq(abi.decode(logs[0].data, (uint256)), VALID_CREDIT);
    }

    /// PROPERTY: `creditCoreOnHyperEvm` takes the fork itself, from the
    /// `hyperevm` alias, and everything after it runs against that chain.
    ///
    /// The script's whole body is this one call, so the fork it takes is what
    /// decides where the money goes; a version that forked nothing would send
    /// on whatever chain the caller happened to be on.
    ///
    /// Observed through an UNFUNDED account. Without the fork the chain id is
    /// the test EVM's and the chain guard refuses first, so an
    /// `InsufficientBalance` — the guard that comes after both the chain id and
    /// the live code hash — is only reachable by having actually arrived on
    /// HyperEVM with the real system contract in front of it.
    ///
    /// Not fuzzed, for the reason the leg above is not.
    function testCreditOnHyperEvmForksTheAliasBeforeItsGuards() external {
        assertNotEq(block.chainid, LibHyperCore.HYPEREVM_CHAIN_ID);
        assertEq(ACCOUNT.balance, 0);

        vm.expectRevert(abi.encodeWithSelector(LibHyperCore.InsufficientBalance.selector, ACCOUNT, 0, VALID_CREDIT));
        this.externalCreditCoreOnHyperEvm(ACCOUNT, VALID_CREDIT);
    }
}
