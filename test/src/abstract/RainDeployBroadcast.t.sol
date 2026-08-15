// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {CandidateSourceMismatch, UnknownDeploymentSuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleDeploy} from "../../concrete/ExampleDeploy.sol";
import {SourceMismatchDeploy} from "../../concrete/SourceMismatchDeploy.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

/// @title RainDeployBroadcastTest
/// @notice The broadcast entry point, driven exactly as the `Manual sol
/// artifacts` workflow drives it — through `DEPLOYMENT_SUITE` and
/// `DEPLOYMENT_KEY` env vars.
///
/// Nothing here broadcasts. Every case is one that fails before
/// `deployAndBroadcast` is reached, which is the half of `run()` that can be
/// tested without a key, an RPC and real money — and, not coincidentally, the
/// half that decides WHAT would be deployed.
contract RainDeployBroadcastTest is Test {
    ExampleDeploy internal sDeploy;

    /// A deploy repo's whole script: the fixture declaration plus
    /// `RainDeployBroadcast`.
    function setUp() external {
        sDeploy = new ExampleDeploy();
    }

    /// The suite comes from `DEPLOYMENT_SUITE`, an unset one is no suite rather
    /// than a default, and both answers are reached before `DEPLOYMENT_KEY` is
    /// read.
    ///
    /// ONE test for both values, because `vm.setEnv` writes the forge PROCESS'
    /// environment. It is scoped to neither a test nor a contract, nothing
    /// unsets or restores it, and forge runs tests concurrently — so two tests
    /// holding two values for one variable is two tests racing over one
    /// variable, and this contract was exactly that until it was seen losing
    /// the race: the unset case resolved the `address-registry` the other test
    /// had written. Sequenced inside one test the two values cannot interleave,
    /// and every `vm.setEnv` in this repo is now one of the two below — with
    /// the write to `DEPLOYMENT_SUITE` after the only read that needs it
    /// absent, so there is no write left for another test to observe.
    ///
    /// ## Unset first, and genuinely unset
    ///
    /// `vm.setEnv("DEPLOYMENT_SUITE", "")` would set a variable that is PRESENT
    /// and empty, which never reaches `vm.envOr`'s default — so it would pass
    /// just as happily if that default became a real suite key, and a deploy
    /// that picks something when told nothing is how the wrong contract reaches
    /// a chain. Only an absent variable exercises the default, and absent is a
    /// state no cheatcode restores, so this half runs before anything sets it.
    ///
    /// That the reported key is empty rather than a suite is what says there is
    /// no default; `RainDeploySuitesBaseTest.testEmptySuiteIsUnknown` is what
    /// says an empty key is unknown.
    ///
    /// ## Then a suite nobody declared
    ///
    /// A mistyped suite MUST fail naming every valid suite. The reported key is
    /// the value of THAT variable under THAT name, which is what a set value
    /// distinct from the default proves and an unset one cannot.
    ///
    /// ## Both before the key
    ///
    /// `DEPLOYMENT_KEY` is set to something `vm.envUint` cannot parse, and that
    /// unreadability is what makes the ordering observable: a suite failure
    /// while the key is garbage is the outcome that says the key had not been
    /// read yet, and a mistyped suite that failed on the key instead would send
    /// the deployer after the wrong thing entirely.
    ///
    /// Set rather than absent, because absence is not this test's to give.
    /// `rainix-sol-test` exports `DEPLOYMENT_KEY` from the org's deploy secret
    /// onto the job that runs this suite, so a test that assumed it unset
    /// asserted the ordering only in a bare shell — and a key that PARSES makes
    /// both orderings produce the same revert, so it would assert nothing about
    /// ordering in the one place the suite actually runs.
    function testRunSelectsTheSuiteFromTheEnvBeforeTheKeyAndNeverDefaults() external {
        // `DEPLOYMENT_SUITE` has to be ABSENT and no cheatcode makes it so, so
        // the precondition is asserted: a value set outside this test reports
        // itself by name here rather than as a surprising revert payload.
        assertFalse(vm.envExists("DEPLOYMENT_SUITE"));
        // `DEPLOYMENT_KEY` is asserted about by nothing, because this test SETS
        // it. It only has to be unparseable, and a value it writes is a value
        // no CI job's secret can change.
        vm.setEnv("DEPLOYMENT_KEY", "not a private key");

        vm.expectRevert(
            abi.encodeWithSelector(
                UnknownDeploymentSuite.selector,
                "",
                "address-registry-0-0-1, second-address, address-registry-candidate, second-address-candidate"
            )
        );
        sDeploy.run();

        vm.setEnv("DEPLOYMENT_SUITE", "address-registry");

        vm.expectRevert(
            abi.encodeWithSelector(
                UnknownDeploymentSuite.selector,
                "address-registry",
                "address-registry-0-0-1, second-address, address-registry-candidate, second-address-candidate"
            )
        );
        sDeploy.run();
    }

    /// The broadcast MUST refuse a candidate that is not the contract this repo
    /// compiles, and refuse it BEFORE anything else happens.
    ///
    /// This is the whole reason the anchor is on the declaration rather than on
    /// the verification abstract. `RainDeployBroadcast` cannot reach anything on
    /// `RainDeployVerifySnapshot`, which inherits `Test`, so an anchor defined
    /// there is an anchor the deploy does not run — and the only other guard
    /// before the `CREATE2` goes out compares the recorded address against the
    /// recorded creation code, both of which come out of the same generated
    /// file. That catches a stale PIN and cannot catch a snapshot of the wrong
    /// CONTRACT, so without this the bytes reaching five chains are whatever the
    /// generated file happens to hold. `CREATE2` at a zero salt makes that
    /// permanent: the wrong bytes take the wrong bytes' own address, on every
    /// chain the dispatch reached, and the dispatch is `workflow_dispatch` on a
    /// ref with no required-green gate — so "CI was red" is a signal a human may
    /// not have read.
    ///
    /// ## Before the suite, and therefore before the key
    ///
    /// This declaration names no suite anything sets `DEPLOYMENT_SUITE` to, so
    /// selection is a revert waiting to happen whatever that variable holds —
    /// asserted here rather than assumed. The revert that actually arrives from
    /// `run()` is the anchor's instead, which is what says the anchor ran first;
    /// an anchor placed after the selection would produce the other one. The key
    /// is read after the suite, which
    /// `testRunSelectsTheSuiteFromTheEnvBeforeTheKeyAndNeverDefaults` pins, so
    /// before the suite is before the key.
    ///
    /// Nothing here writes an env var. Both values are process-wide and forge
    /// runs tests concurrently, so a second writer is a race, and this test does
    /// not need one: the ordering is observable from a declaration that cannot
    /// resolve any key at all.
    ///
    /// ## Discriminating
    ///
    /// That same env test is the passing case — `ExampleDeploy.run()` reaches
    /// suite selection and fails there, which it can only do by getting past an
    /// anchor that had nothing to say about a declaration whose candidates are
    /// its source.
    function testRunRefusesToBroadcastACandidateThatIsNotItsSource() external {
        SourceMismatchDeploy mismatch = new SourceMismatchDeploy();

        string memory requested = vm.envOr("DEPLOYMENT_SUITE", string(""));
        vm.expectRevert(
            abi.encodeWithSelector(
                UnknownDeploymentSuite.selector, requested, "anchored-candidate, mismatched-candidate"
            )
        );
        mismatch.externalSuiteByName(requested);

        vm.expectRevert(
            abi.encodeWithSelector(
                CandidateSourceMismatch.selector,
                "mismatched-candidate",
                keccak256(type(MockDeployableV2).creationCode),
                keccak256(type(MockDeployable).creationCode)
            )
        );
        mismatch.run();
    }

    /// The default target set MUST be every supported network, so a
    /// deterministic deployment reaches one address on every chain from one
    /// dispatch and no repo restates the list.
    function testDeployNetworksDefaultsToSupportedNetworks() external view {
        string[] memory networks = sDeploy.externalDeployNetworks();
        string[] memory supported = LibRainDeploy.supportedNetworks();

        assertEq(networks.length, supported.length);
        for (uint256 i = 0; i < supported.length; i++) {
            assertEq(networks[i], supported[i]);
        }
    }

    /// The suite a key selects MUST be the one that would be broadcast — the
    /// creation code, the artifact path and the recorded pins all come from the
    /// same registry entry the verification contracts check.
    ///
    /// The recorded address and code hash are passed to `deployAndBroadcast`
    /// rather than derived at broadcast time on purpose:
    /// `LibRainDeploy.deployToNetworks` compares the recorded address against
    /// the creation code before it forks anything, and a derived value would
    /// make that comparison derived-against-derived.
    function testSelectedSuiteCarriesTheRecordedPins() external view {
        assertEq(
            sDeploy.externalSuiteByName("address-registry-0-0-1").storedDeployedAddress,
            LibRainDeploy.zoltuAddress(sDeploy.externalSuiteByName("address-registry-0-0-1").creationCode)
        );
        assertEq(
            sDeploy.externalSuiteByName("address-registry-0-0-1").artifactPath,
            "src/concrete/AddressRegistry.sol:AddressRegistry"
        );
    }
}
