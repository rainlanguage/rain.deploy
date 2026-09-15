// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

//! The binary's whole interface: the environment it reads, what it refuses
//! before signing anything, what it announces about the action it is about to
//! submit, and which exchange that action is addressed to.
//!
//! Every run here is pointed at an HTTP proxy on loopback that no exchange is
//! behind, so a signed `evmUserModify` can never leave the machine: the two
//! outcomes are a connection refused by a dead port, and a `CONNECT` line read
//! off a listener the test owns. The proxy is what makes the destination
//! observable at all — the request itself is TLS, so the hostname in `CONNECT`
//! is the only part of it a test can read, and it is the part that says
//! mainnet rather than testnet.

use std::io::{BufRead, BufReader};
use std::net::TcpListener;
use std::process::{Command, Output, Stdio};
use std::sync::mpsc;
use std::time::Duration;

/// A well formed secp256k1 private key, and the address it derives to —
/// derived independently of this crate, with `cast wallet address`.
const KEY: &str = "0x1111111111111111111111111111111111111111111111111111111111111111";
const ADDRESS: &str = "0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A";

/// Port 1 on loopback: nothing listens there, so a request through it is
/// refused locally rather than reaching the exchange.
const DEAD_PROXY: &str = "http://127.0.0.1:1";

/// The binary takes its whole input from the environment, so the test's own
/// environment is cleared out of the way and a proxy is forced in every form
/// the HTTP client honours.
fn command(proxy: &str) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_hyperliquid-big-blocks"));
    command.env_remove("USING_BIG_BLOCKS");
    command.env_remove("DEPLOYMENT_KEY");
    command.env_remove("NO_PROXY");
    command.env_remove("no_proxy");
    for variable in [
        "HTTP_PROXY",
        "http_proxy",
        "HTTPS_PROXY",
        "https_proxy",
        "ALL_PROXY",
        "all_proxy",
    ] {
        command.env(variable, proxy);
    }
    command
}

fn run(flag: Option<&str>, key: Option<&str>) -> Output {
    let mut command = command(DEAD_PROXY);
    if let Some(flag) = flag {
        command.env("USING_BIG_BLOCKS", flag);
    }
    if let Some(key) = key {
        command.env("DEPLOYMENT_KEY", key);
    }
    command.output().unwrap()
}

/// A refusal is a workflow error annotation on stderr, nothing on stdout, and
/// a nonzero exit — the flag is persistent per address, so a run that cannot
/// tell exactly which state was asked for submits nothing at all.
fn assert_refused(output: &Output, expected: &str) {
    assert_eq!(String::from_utf8_lossy(&output.stdout), "");
    assert_eq!(String::from_utf8_lossy(&output.stderr), expected);
    assert_eq!(output.status.code(), Some(1));
}

#[test]
fn an_unset_flag_is_refused() {
    assert_refused(
        &run(None, Some(KEY)),
        "::error::USING_BIG_BLOCKS is not set.\n",
    );
}

/// The flag is validated before the key is even read, so the run that is
/// missing both is refused for the flag: the key is the secret and the flag is
/// the instruction, and an instruction nobody stated is the first thing wrong.
#[test]
fn the_flag_is_checked_before_the_key() {
    assert_refused(&run(None, None), "::error::USING_BIG_BLOCKS is not set.\n");
    assert_refused(
        &run(Some("maybe"), None),
        "::error::USING_BIG_BLOCKS must be exactly 'true' or 'false', got 'maybe'.\n",
    );
}

/// Anything that is not literally `true` or `false` is refused with the value
/// quoted back, including the renderings other tooling produces for a bool.
#[test]
fn a_flag_that_is_not_exactly_true_or_false_is_refused() {
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
        assert_refused(
            &run(Some(raw), Some(KEY)),
            &format!("::error::USING_BIG_BLOCKS must be exactly 'true' or 'false', got '{raw}'.\n"),
        );
    }
}

#[test]
fn an_unset_key_is_refused() {
    for flag in ["true", "false"] {
        assert_refused(
            &run(Some(flag), None),
            "::error::DEPLOYMENT_KEY is not set.\n",
        );
    }
}

/// A key that does not parse is refused with a fixed message that never echoes
/// what it was given: the input here is a private key, and a run log is not a
/// place to put one, not even a malformed one.
#[test]
fn a_key_that_does_not_parse_is_refused_without_echoing_it() {
    for raw in [
        "0xzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",
        "0x01",
        "hunter2",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
    ] {
        let output = run(Some("true"), Some(raw));
        assert_refused(
            &output,
            "::error::DEPLOYMENT_KEY did not parse as a private key.\n",
        );
        assert!(
            !String::from_utf8_lossy(&output.stderr).contains(raw.trim_start_matches("0x")),
            "the offending key material was echoed: {raw}"
        );
    }
}

/// The key is trimmed before parsing, because the documented way to supply it
/// is `read -rs`, which leaves a trailing newline on it. What is announced
/// before the submit is the flag exactly as given and the address the key
/// derives to — the address, never the key.
#[test]
fn a_key_with_surrounding_whitespace_is_accepted_and_the_action_is_announced() {
    for flag in ["true", "false"] {
        let output = run(Some(flag), Some(&format!("\n  {KEY}  \n")));
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            format!(
                "Submitting evmUserModify {{ usingBigBlocks: {flag} }} for {ADDRESS} to mainnet.\n"
            )
        );
        // The exchange is unreachable here, which is reported as an error
        // annotation and a nonzero exit — never a panic, whose exit code and
        // backtrace would say nothing about what the run did or did not
        // submit.
        assert!(
            String::from_utf8_lossy(&output.stderr)
                .starts_with("::error::Failed to construct the exchange client:"),
            "unexpected stderr: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(output.status.code(), Some(1));
    }
}

/// The action is addressed to Hyperliquid's mainnet API and nothing else. The
/// flag is persistent per address on HyperCore and there is no query that
/// reads it back, so a run that quietly toggled the testnet copy of the
/// deployer would look exactly like a run that worked.
#[test]
fn the_action_is_addressed_to_the_mainnet_api() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let (sender, receiver) = mpsc::channel();
    std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(60)))
            .unwrap();
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).unwrap();
        let _ = sender.send(line);
    });

    let mut child = command(&format!("http://127.0.0.1:{port}"))
        .env("USING_BIG_BLOCKS", "true")
        .env("DEPLOYMENT_KEY", KEY)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap();
    let line = receiver.recv_timeout(Duration::from_secs(120));
    let _ = child.kill();
    let _ = child.wait();

    assert_eq!(
        line.expect("the binary made no request through the proxy"),
        "CONNECT api.hyperliquid.xyz:443 HTTP/1.1\r\n"
    );
}
