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
//! whose serde tag is the response's `"status"` field. A `"status": "err"` is
//! a refusal and a nonzero exit, and a `"status": "ok"` is a success only when
//! it carries the empty default envelope: Hyperliquid answers `"status": "ok"`
//! with a per-action error nested under `data.statuses` for the actions that
//! have per-action outcomes, so the envelope tag on its own does not say the
//! action applied. The full parsed response is printed either way, because
//! there is no info-endpoint query that reads `usingBigBlocks` back — the
//! printed response is the record, and the flag's observable afterwards is
//! which blocks the deployer's transactions land in.

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

/// The `response.type` of the empty envelope, which is what the exchange
/// answered the live `evmUserModify` run on record with:
/// `Ok(ExchangeResponse { response_type: "default", data: None })`.
const EMPTY_ENVELOPE_RESPONSE_TYPE: &str = "default";

/// Whether the exchange's answer establishes that the action applied, which is
/// narrower than its `"status"` tag. `"status": "ok"` carrying a `data` payload
/// is the shape Hyperliquid reports per-action outcomes in, including
/// `{"error": ...}` entries under `statuses`, so an answer that is not the
/// empty envelope is refused rather than read as a success: the flag has no
/// info-endpoint read-back, which leaves the exit code as the only thing an
/// automated caller can act on.
fn classify_response(response: &ExchangeResponseStatus) -> Result<(), String> {
    match response {
        ExchangeResponseStatus::Ok(envelope)
            if envelope.response_type == EMPTY_ENVELOPE_RESPONSE_TYPE
                && envelope.data.is_none() =>
        {
            Ok(())
        }
        ExchangeResponseStatus::Ok(envelope) => Err(format!(
            "The exchange answered 'status: ok' with {envelope:?}, which is not the empty envelope that says the action applied."
        )),
        ExchangeResponseStatus::Err(refusal) => {
            Err(format!("The exchange refused the action: {refusal}"))
        }
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
    match classify_response(&response) {
        Ok(()) => {
            println!("The exchange accepted the action: usingBigBlocks is now {using_big_blocks}.");
            ExitCode::SUCCESS
        }
        Err(message) => {
            eprintln!("::error::{message}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod test {
    use hyperliquid_rust_sdk::{Actions, EvmUserModify, ExchangeResponseStatus};

    use super::{classify_response, parse_using_big_blocks};

    /// Classification is driven from the exchange's wire bytes rather than a
    /// hand-built value, so the serde tagging the design leans on is exercised
    /// along with the arm that reads it.
    fn classify(wire: &str) -> Result<(), String> {
        classify_response(&serde_json::from_str::<ExchangeResponseStatus>(wire).unwrap())
    }

    #[test]
    fn parses_exactly_true() {
        assert_eq!(parse_using_big_blocks("true"), Ok(true));
    }

    #[test]
    fn parses_exactly_false() {
        assert_eq!(parse_using_big_blocks("false"), Ok(false));
    }

    /// The refusal names the variable and quotes the offending value back,
    /// because that value is the one thing a run log cannot reconstruct:
    /// `True` from some other tooling's bool rendering and nothing set at all
    /// are different fixes.
    #[test]
    fn refuses_everything_else() {
        for raw in [
            "",
            " ",
            " true",
            "true ",
            "TRUE",
            "True",
            "FALSE",
            "1",
            "0",
            "yes",
            "no",
            "true false",
        ] {
            assert_eq!(
                parse_using_big_blocks(raw),
                Err(format!(
                    "USING_BIG_BLOCKS must be exactly 'true' or 'false', got '{raw}'."
                )),
                "accepted '{raw}'"
            );
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

    /// The one shape that exits zero, taken from the only live `evmUserModify`
    /// run on record — GitHub Actions run 32570754934, which logged
    /// `Ok(ExchangeResponse { response_type: "default", data: None })` — and
    /// written back here as the wire bytes that parse to it, with `data` both
    /// absent and explicitly null because the exchange may render either.
    #[test]
    fn the_empty_envelope_the_live_run_observed_is_accepted() {
        for wire in [
            r#"{"status":"ok","response":{"type":"default"}}"#,
            r#"{"status":"ok","response":{"type":"default","data":null}}"#,
        ] {
            assert_eq!(classify(wire), Ok(()), "refused {wire}");
        }
    }

    /// `"status": "ok"` with a per-action error nested under `data.statuses` —
    /// Hyperliquid's shape for actions that report per-action outcomes — is a
    /// refusal, not a success. The envelope tag is `ok` in both this and the
    /// accepted case, so the payload is the only thing that separates them.
    #[test]
    fn an_ok_envelope_carrying_a_nested_error_is_refused() {
        assert_eq!(
            classify(
                r#"{"status":"ok","response":{"type":"order","data":{"statuses":[{"error":"User or API Wallet does not exist."}]}}}"#
            ),
            Err(
                "The exchange answered 'status: ok' with ExchangeResponse { response_type: \"order\", data: Some(ExchangeDataStatuses { statuses: [Error(\"User or API Wallet does not exist.\")] }) }, which is not the empty envelope that says the action applied."
                    .to_string()
            )
        );
    }

    /// A payload whose nested statuses all succeeded is refused too: this
    /// binary submits one action whose documented answer carries no payload at
    /// all, so a payload means the answer is to something other than what was
    /// asked, and the flag has no read-back query to settle it with.
    #[test]
    fn an_ok_envelope_carrying_any_payload_is_refused() {
        assert_eq!(
            classify(r#"{"status":"ok","response":{"type":"default","data":{"statuses":[]}}}"#),
            Err(
                "The exchange answered 'status: ok' with ExchangeResponse { response_type: \"default\", data: Some(ExchangeDataStatuses { statuses: [] }) }, which is not the empty envelope that says the action applied."
                    .to_string()
            )
        );
    }

    /// An envelope tagged `ok` but typed as something other than the empty
    /// envelope is refused on the type alone, with no payload involved.
    #[test]
    fn an_ok_envelope_of_another_type_is_refused() {
        assert_eq!(
            classify(r#"{"status":"ok","response":{"type":"evmUserModify"}}"#),
            Err(
                "The exchange answered 'status: ok' with ExchangeResponse { response_type: \"evmUserModify\", data: None }, which is not the empty envelope that says the action applied."
                    .to_string()
            )
        );
    }

    /// A refusal carries the exchange's own message through to the annotation:
    /// the run log holds the parsed response, but the annotation is what a
    /// dispatcher sees without opening the log.
    #[test]
    fn a_refusal_is_reported_with_the_exchange_message() {
        assert_eq!(
            classify(r#"{"status":"err","response":"Must deposit before performing actions."}"#),
            Err(
                "The exchange refused the action: Must deposit before performing actions."
                    .to_string()
            )
        );
    }
}
