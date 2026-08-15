// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {UnknownDeploymentSuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleDeploy} from "../../concrete/ExampleDeploy.sol";
import {ExampleDeploySingleNetwork} from "../../concrete/ExampleDeploySingleNetwork.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

/// @title RainDeployBroadcastTest
/// @notice The broadcast entry point, driven exactly as the `Manual sol
/// artifacts` workflow drives it — through `DEPLOYMENT_SUITE` and
/// `DEPLOYMENT_KEY` env vars.
///
/// Both halves of `run()` are driven here: the selection, through the cases
/// that fail before `deployAndBroadcast` is reached, and the broadcast itself,
/// on a fork.
///
/// The broadcast half costs no key custody and no money. `vm.startBroadcast`
/// under `forge test` executes the deploy against the fork and records a
/// transaction it never sends, so the whole of it is a test key that has never
/// held anything and the same RPC alias every other fork test in this repo
/// forks — which is what the sibling `LibRainDeployTest` drives this same
/// library through this same path on. Without it, the org's only broadcast
/// entry point, inherited by every downstream deploy repo, asserts nothing
/// about what it would deploy or where.
contract RainDeployBroadcastTest is Test {
    /// Chain id of Arbitrum One, which is what `deployNetworks()` being honoured
    /// looks like from inside a completed run.
    ///
    /// The literal rather than a second fork of the same alias to compare
    /// against: an `arbitrum` RPC alias misconfigured onto some other chain
    /// would agree with itself and quietly assert nothing, while a fact of the
    /// world fails loudly.
    uint256 constant ARBITRUM_ONE_CHAIN_ID = 42161;

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
    /// had written. Sequenced inside one test the values cannot interleave, and
    /// every `vm.setEnv` in this repo is one of the four below — with every
    /// write to `DEPLOYMENT_SUITE` after the only read that needs it absent, so
    /// there is no write left for another test to observe.
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
    ///
    /// ## And then the suite it names, actually broadcast
    ///
    /// The two legs above decide WHAT would be deployed. They say nothing about
    /// the nine lines that carry that decision to a chain, and those nine lines
    /// are the entire body of `script/Deploy.sol`. A third leg runs `run()` all
    /// the way through on a fork, so that the selected suite's fields, and the
    /// target set they go to, are observed rather than assumed.
    ///
    /// Here rather than in a test of its own for the reason the first two are
    /// here: this leg has to SET `DEPLOYMENT_SUITE`, and a second test doing
    /// that is a second test racing the first over one process-global variable.
    function testRunSelectsTheSuiteFromTheEnvBeforeTheKeyNeverDefaultsAndBroadcastsIt() external {
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

        // ## Then the suite it names, actually broadcast
        //
        // A fixture that names ONE network, so that where the broadcast went is
        // observable at all. `sDeploy` takes the default target set, and a suite
        // deployed to all five chains and a suite deployed to the one chain the
        // repo asked for are indistinguishable from a fixture that asks for all
        // five.
        ExampleDeploySingleNetwork single = new ExampleDeploySingleNetwork();

        // Derived here from the same source the declaration derives them from,
        // not pinned as literals: both are a function of the compiler settings,
        // so a pinned copy would be a second thing to keep in step with
        // `foundry.toml` and would fail as a stale constant rather than as the
        // wiring defect this leg is about.
        address expectedAddress = LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode);
        bytes32 expectedCodeHash = keccak256(type(MockDeployableV2).runtimeCode);

        vm.setEnv("DEPLOYMENT_SUITE", "second-address-candidate");
        // Parseable, unlike the value above, because this leg has to get PAST
        // the key. `vm.rememberKey` takes it and the deploy is broadcast as the
        // address it derives; the key itself is a test constant that has never
        // transacted anywhere.
        vm.setEnv("DEPLOYMENT_KEY", "0xa11ce");

        single.run();

        // The suite `DEPLOYMENT_SUITE` NAMED is the suite on chain: at the
        // address its own creation code derives, holding the code hash that
        // creation code produces.
        //
        // This is what says the SELECTED entry reached `deployAndBroadcast`
        // rather than some other entry of the registry, and it says it because
        // of which entry it is. `MockDeployableV2` is a mock that exists on no
        // supported chain, so this address has code only because this run put
        // it there. The other address the declaration carries is
        // `AddressRegistry`, which this repo really has deployed, so a `run()`
        // that ignored the selection and broadcast that instead would take the
        // already-deployed skip branch and SUCCEED — leaving this assertion the
        // only thing between the two outcomes.
        assertGt(expectedAddress.code.length, 0);
        assertEq(expectedAddress.codehash, expectedCodeHash);

        // The OVERRIDE is what was broadcast to, rather than
        // `LibRainDeploy.supportedNetworks()` reached past it.
        //
        // `deployToNetworks` forks each network in turn and never restores, so a
        // completed run leaves the LAST network of `deployNetworks()` selected:
        // arbitrum for this fixture's single-element override, polygon for the
        // default. That is the whole of the difference an assertion can see, and
        // an override `run()` ignored is a repo that asked for one chain getting
        // a suite on five — with a revert partway through leaving a dispatch
        // half done.
        //
        // `testDeployNetworksDefaultsToSupportedNetworks` asserts the default
        // VALUE of that function; nothing until here asserted that `run()` is
        // what consults it.
        assertEq(block.chainid, ARBITRUM_ONE_CHAIN_ID);
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
