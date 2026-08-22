// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";

import {LibHyperCore} from "../src/lib/LibHyperCore.sol";

/// @title CreditHyperCore
/// @notice Makes the deployer a HyperCore user, by sending it some of its own
/// HYPE.
///
/// Deploying anything sizeable to HyperEVM needs big blocks, which are opted
/// into with an `evmUserModify` action that HyperCore accepts only from an
/// address that is already a HyperCore user. An address becomes one by holding
/// a Core asset, and HYPE sent to the system contract from HyperEVM arrives on
/// Core for the same address — so the deployer, which holds HYPE already
/// because it pays gas in it, credits itself. `LibHyperCore` carries the
/// mechanism and every guard; see there for what each one is for.
///
/// This is a sibling of `script/Deploy.sol` rather than a part of it. It moves
/// the deployer's own funds instead of deploying anything, it touches exactly
/// one network where the deploy touches all of them, and it is run ONCE per
/// deployer address for the lifetime of that address — a second run is more
/// money for no further effect, because a HyperCore user does not stop being
/// one.
///
/// ## Running it
///
/// The canonical entry is the `Manual credit hypercore` workflow
/// (`.github/workflows/manual-credit-hypercore.yaml`): `workflow_dispatch`
/// only, gated to repo admins by its first step, the amount as a typed input
/// under its own name, and a dry run on every dispatch with the broadcast
/// behind a separate input that defaults to off.
///
/// Not `Manual sol artifacts`. That workflow exports `DEPLOYMENT_SUITE`,
/// `DEPLOYMENT_NETWORK` and `DEPLOYMENT_KEY` and nothing else, so the amount
/// has no way through it, and an amount squeezed into one of those names would
/// be a real-money argument travelling under a name that means something else.
///
/// The fallback, for when the workflow itself is what is broken, is by hand:
///
/// ```sh
/// read -rs DEPLOYMENT_KEY && export DEPLOYMENT_KEY
/// HYPERCORE_CREDIT_WEI=10000000000000000 \
///   forge script script/CreditHyperCore.sol:CreditHyperCore --legacy
/// ```
///
/// The key is read rather than written into the command: a
/// `DEPLOYMENT_KEY=0x...` prefix leaves a private key in the shell's history
/// file, where it outlives both the run and the terminal.
///
/// Without `--broadcast` that is a dry run against a fork of HyperEVM, which
/// executes every guard and the transfer itself and sends nothing. Do that
/// first: it is the same code path, so anything it refuses is something the
/// real run would have refused after paying for it. `--legacy` because
/// HyperEVM's RPC rejects the fee-history ranges EIP-1559 estimation asks for,
/// which is the same reason the deploy workflow carries a `legacy` input. No
/// `--rpc-url`: the fork comes from the `hyperevm` alias in `foundry.toml`.
///
/// ## The amount
///
/// `HYPERCORE_CREDIT_WEI` is EVM wei — 18 decimals, the units the deployer's
/// gas balance is in — and it is required rather than defaulted. A default
/// would be an amount of real money nobody typed, and how much a deployer
/// should hold on Core is a decision about that deployer rather than a fact
/// about this mechanism. It has to be a whole number of Core wei; `10 ** 10`
/// EVM wei is one of them, and `LibHyperCore.CreditNotRound` says why anything
/// else is refused.
///
/// ## Why the body is three lines and no test drives it
///
/// Everything with behaviour is in `LibHyperCore` and is covered there, without
/// an env var in sight. What is left here is two reads by name, and driving
/// them from a test would mean writing `DEPLOYMENT_KEY` — a process-wide
/// variable that `rainix-sol-test` exports onto the job and that
/// `RainDeployBroadcastTest` already sequences its own writes of. Forge runs
/// test contracts concurrently, so a second writer of that name is a race
/// against a suite that is currently green, which is a worse trade than this
/// buys.
///
/// So the body is written to make its own mistake impossible rather than
/// caught. Both env reads are `uint256`, and a key and an amount transposed
/// between them would send a private key's worth of HYPE — so the key is turned
/// into an `address` on its own line first, and the call takes that address.
/// The two arguments no longer have the same type, and the transposition that
/// no test is watching for does not compile.
contract CreditHyperCore is Script {
    /// Credits the `DEPLOYMENT_KEY` deployer's HyperCore account with
    /// `HYPERCORE_CREDIT_WEI` of its own HYPE.
    function run() external {
        address deployer = vm.rememberKey(vm.envUint("DEPLOYMENT_KEY"));
        uint256 amount = vm.envUint("HYPERCORE_CREDIT_WEI");
        LibHyperCore.creditCoreOnHyperEvm(vm, deployer, amount);
    }
}
