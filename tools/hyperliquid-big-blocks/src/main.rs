// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

//! Signs and submits Hyperliquid's `evmUserModify` L1 action for the
//! `DEPLOYMENT_KEY` signer, setting `usingBigBlocks` to exactly what
//! `USING_BIG_BLOCKS` says. Run by the `Manual big blocks` workflow; a thin
//! caller of the official Hyperliquid Rust SDK and nothing more.
//!
//! The SDK owns the signing on purpose. An L1 action is signed by
//! msgpack-encoding the action with its nonce and vault flag, keccak-hashing
//! that, and EIP-712-signing a "phantom agent" over the digest — and a
//! hand-rolled encoding that differs by one byte still produces a VALID
//! signature, just one that recovers some other address, so the failure mode
//! is an action attributed to an address nobody controls rather than an
//! error. The exchange refusing that unknown address is the only thing that
//! makes the mistake visible, which is not a property to lean on.
//!
//! The exchange's answer is parsed by the SDK into `ExchangeResponseStatus`,
//! whose serde tag is the response's `"status"` field: the `Ok` variant IS
//! `"status": "ok"`, anything else is a refusal and a nonzero exit. The full
//! parsed response is printed either way, because there is no info-endpoint
//! query that reads `usingBigBlocks` back — the printed response is the
//! record, and the flag's observable afterwards is which blocks the
//! deployer's transactions land in.

use std::env;
use std::process::ExitCode;

use alloy::signers::local::PrivateKeySigner;
use hyperliquid_rust_sdk::{BaseUrl, ExchangeClient, ExchangeResponseStatus};

/// Strict parse of the `USING_BIG_BLOCKS` env value: exactly `true` or
/// `false`, nothing else. The flag is persistent per address on HyperCore and
/// this binary's whole job is to set it, so a value that is not literally one
/// of the two states — an empty string, a `1`, a `True` from some other
/// tooling's bool rendering — is refused rather than guessed at.
fn parse_using_big_blocks(raw: &str) -> Result<bool, String> {
    match raw {
        "true" => Ok(true),
        "false" => Ok(false),
        other => Err(format!(
            "USING_BIG_BLOCKS must be exactly 'true' or 'false', got '{other}'."
        )),
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    let using_big_blocks = match env::var("USING_BIG_BLOCKS") {
        Ok(raw) => match parse_using_big_blocks(&raw) {
            Ok(flag) => flag,
            Err(message) => {
                eprintln!("::error::{message}");
                return ExitCode::FAILURE;
            }
        },
        Err(_) => {
            eprintln!("::error::USING_BIG_BLOCKS is not set.");
            return ExitCode::FAILURE;
        }
    };

    // Trimmed because a key that arrived via `read -rs` or a file can carry a
    // trailing newline; parsed with the error DISCARDED, because a signer
    // parse error is the one error type that could quote its input back.
    let wallet: PrivateKeySigner = match env::var("DEPLOYMENT_KEY") {
        Ok(raw) => match raw.trim().parse() {
            Ok(wallet) => wallet,
            Err(_) => {
                eprintln!("::error::DEPLOYMENT_KEY did not parse as a private key.");
                return ExitCode::FAILURE;
            }
        },
        Err(_) => {
            eprintln!("::error::DEPLOYMENT_KEY is not set.");
            return ExitCode::FAILURE;
        }
    };
    println!(
        "Submitting evmUserModify {{ usingBigBlocks: {using_big_blocks} }} for {} to mainnet.",
        wallet.address()
    );

    let exchange_client =
        match ExchangeClient::new(None, wallet, Some(BaseUrl::Mainnet), None, None).await {
            Ok(client) => client,
            Err(error) => {
                eprintln!("::error::Failed to construct the exchange client: {error}");
                return ExitCode::FAILURE;
            }
        };

    let response = match exchange_client
        .enable_big_blocks(using_big_blocks, None)
        .await
    {
        Ok(response) => response,
        Err(error) => {
            eprintln!("::error::The exchange request failed: {error}");
            return ExitCode::FAILURE;
        }
    };
    println!("Exchange response: {response:?}");
    match response {
        ExchangeResponseStatus::Ok(_) => {
            println!("The exchange accepted the action: usingBigBlocks is now {using_big_blocks}.");
            ExitCode::SUCCESS
        }
        ExchangeResponseStatus::Err(refusal) => {
            eprintln!("::error::The exchange refused the action: {refusal}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod test {
    use hyperliquid_rust_sdk::{Actions, EvmUserModify};

    use super::parse_using_big_blocks;

    #[test]
    fn parses_exactly_true() {
        assert_eq!(parse_using_big_blocks("true"), Ok(true));
    }

    #[test]
    fn parses_exactly_false() {
        assert_eq!(parse_using_big_blocks("false"), Ok(false));
    }

    #[test]
    fn refuses_everything_else() {
        for raw in [
            "", " true", "true ", "TRUE", "True", "FALSE", "1", "0", "yes", "no",
        ] {
            assert!(parse_using_big_blocks(raw).is_err(), "accepted '{raw}'");
        }
    }

    /// Pins the SDK's wire encoding of the action to the shape the Hyperliquid
    /// docs give for it, `{"type": "evmUserModify", "usingBigBlocks": <flag>}`
    /// — hand-written here from the docs, not read back from the SDK — so a
    /// pin bump that renames a field or the tag fails this test instead of
    /// being refused (or misattributed) live.
    #[test]
    fn action_serializes_to_the_documented_wire_shape() {
        for (flag, expected) in [
            (true, r#"{"type":"evmUserModify","usingBigBlocks":true}"#),
            (false, r#"{"type":"evmUserModify","usingBigBlocks":false}"#),
        ] {
            let action = Actions::EvmUserModify(EvmUserModify {
                using_big_blocks: flag,
            });
            assert_eq!(serde_json::to_string(&action).unwrap(), expected);
        }
    }
}
