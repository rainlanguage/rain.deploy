// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";

/// One network the Rain org deploys to, as everything generated from the roster
/// needs it. The roster is the single statement of the set: `foundry.toml`'s
/// `[rpc_endpoints]` and `[etherscan]` sections and `.env.example` are written
/// from it by `BuildScript`, so a network arrives everywhere by being added
/// here.
/// @param name The `[rpc_endpoints]` alias, the `[etherscan]` key, and the stem
/// of both the `<NAME>_RPC_URL` and `CI_DEPLOY_<NAME>_ETHERSCAN_API_KEY`
/// variables the generated entries interpolate.
/// @param chainId The chain id the bound endpoint reports. Generation cannot
/// settle this one — it is a claim about the world, checked by
/// `RainDeployVerifyChain` against `block.chainid` on a fork.
/// @param explorerUrl The explorer API `--verify` posts to, or empty for the
/// one Etherscan V2 resolves from `chainId`.
/// @param defaultRpcUrl The public endpoint `.env.example` binds for a local
/// run. CI binds its own, so this is a convenience rather than a contract.
struct SupportedNetwork {
    string name;
    uint256 chainId;
    string explorerUrl;
    string defaultRpcUrl;
}

/// One address a suite's deployment requires and the code that must be at it:
/// the depended-on snapshot's own published `DEPLOYED_ADDRESS` and
/// `RUNTIME_CODE`, written out by the declarer. Nothing here resolves an address
/// back to a suite that owns it — a dependency need not be a suite of the
/// declaring repo at all.
///
/// Here rather than on the declaration that carries it, because this is the
/// file that checks a declared pair against a chain. `RainDeploySuitesBase`
/// imports it and therefore re-exports it, which keeps that the one path every
/// declaration and every generated released lib names.
struct DeployDependency {
    /// The address that MUST already have code on a network before the suite
    /// declaring it is broadcast there.
    address deployedAddress;
    /// The runtime code that MUST be at `deployedAddress`:
    /// `RainDeployVerifyBase.deriveDeployment` etches exactly these bytes, so
    /// a derived code hash is a function of them, and
    /// `LibRainDeploy.deployToNetworks` holds the chain to them before it
    /// broadcasts.
    bytes runtimeCode;
}

/// @title LibRainDeploy
/// Library for deploying contracts via the Zoltu factory across all the networks
/// currently supported by Rain by default. The Rain contracts can be deployed
/// permissionlessly to other networks by end users, using the same patterns
/// here, but the Rain organization only (re)deploys contracts periodically to
/// networks that have specific adoption and use cases.
library LibRainDeploy {
    /// Thrown when deployment via Zoltu factory fails. This could be either an
    /// explicit revert that manifests as non success, or a silent failure that
    /// results in the deployed address being empty somehow. `deployedAddress`
    /// is zero whenever `success` is false: a failed call leaves revert data in
    /// the output buffer rather than an address, so it is never read there.
    error DeployFailed(bool success, address deployedAddress);

    /// Thrown when a dependency is missing on a network before deployment.
    error MissingDependency(string network, address dependency);

    /// Thrown when an address does not match the address the deploy expects.
    /// Raised at two distinct points, and nothing is deployed at the first of
    /// them: before any fork, when the address the creation code derives is not
    /// the expected one, and after broadcasting, when the address deployed to
    /// is not the expected one.
    /// @param expected The `expectedAddress` the caller passed to
    /// `deployToNetworks` or `deployAndBroadcast`, at both sites.
    /// @param actual The address the creation code derives, before any fork, or
    /// the address actually deployed to, after broadcasting.
    error UnexpectedDeployedAddress(address expected, address actual);

    /// Thrown when the deployed code hash does not match the expected code hash.
    error UnexpectedDeployedCodeHash(bytes32 expected, bytes32 actual);

    /// Thrown when a dependency's code hash does not match the expected value.
    ///
    /// Raised for the Zoltu factory against `ZOLTU_FACTORY_CODEHASH`, and for
    /// every DECLARED dependency against the hash of the `runtimeCode` its
    /// declaration carries. The declared half is not decoration: a derivation
    /// etches it to run the constructor, so the code hash a suite records — and
    /// a release freezes — is a function of what the declaration SAYS is at
    /// that address. Nothing else ever compares that claim to a chain, so
    /// without this the first thing to disagree is the deployed contract's own
    /// code hash, after the gas.
    /// @param network The network name, as configured in `[rpc_endpoints]`.
    /// @param dependency The address checked.
    /// @param expectedCodeHash The hash of the code that must be at it.
    /// @param actualCodeHash The hash of the code actually at it on this
    /// network.
    error DependencyChanged(string network, address dependency, bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// Thrown when no networks are provided for deployment.
    error NoNetworks();

    /// Thrown when a fork id list does not pair up with its network names. The
    /// name is what a failure reports and the id is what it reads, so an
    /// unpaired list reports one network's result under another's name.
    /// @param networksLength How many networks were named.
    /// @param forkIdsLength How many fork ids were given.
    error ForkIdsLengthMismatch(uint256 networksLength, uint256 forkIdsLength);

    /// Thrown when a declared network name has no entry in
    /// `supportedNetworkConfigs()`. The catalogue is where a network's chain
    /// id, explorer and default endpoint come from, so a name it says nothing
    /// about is a name the generated config cannot state anything for — and
    /// emitting the name alone is an `[etherscan]` entry with no `chain`,
    /// which takes `--verify` down for every other entry in the section.
    ///
    /// This is the refusal that replaces comparing two hand-maintained lists:
    /// a declaration naming a network this package does not support is red on
    /// the build that generates from it rather than on an assertion somebody
    /// had to think of.
    /// @param network The declared name with no catalogue entry.
    error NetworkNotInCatalogue(string network);

    /// Thrown when attempting to find the deploy block of a contract that has
    /// no code at the current block.
    error NotDeployed(address target);

    /// Thrown when a code hash check is handed the zero code hash. An account
    /// with no code answers `codehash` zero, so a zero expectation is met by
    /// the ABSENCE of a contract and missed at every block one exists. A true
    /// from it is indistinguishable at the call site from a real match.
    error NoExpectedCodeHash(address target);

    /// Thrown when the target already has code at the start block, meaning
    /// the deploy may have happened before the search range.
    error DeployedBeforeStartBlock(address target, uint256 startBlock);

    /// Thrown when a deployed contract holds an address other than the one the
    /// deployment expects, on a network.
    error UnexpectedResolvedAddress(string network, address target, uint256 index, address expected, address actual);

    /// Thrown when the read calls and expected addresses of a post-deploy check
    /// do not pair up.
    error ResolvedAddressesLengthMismatch(uint256 readCallsLength, uint256 expectedAddressesLength);

    /// Thrown when a post-deploy check is given no reads. A check with nothing
    /// to read passes on every network having asserted nothing, which is
    /// indistinguishable from every read checking out.
    error NoResolvedAddressReads(address target);

    /// Thrown when a post-deploy read reverts, or answers with something that is
    /// not a single address-sized word.
    error ResolvedAddressReadFailed(string network, address target, uint256 index, bytes returnData);

    /// Zoltu factory is the same on every network.
    address constant ZOLTU_FACTORY = 0x7A0D94F55792C434d74a40883C6ed8545E406D12;

    /// Expected codehash of the Zoltu factory contract.
    bytes32 constant ZOLTU_FACTORY_CODEHASH = 0x5acaad953250bec20933f7c72a25bb03bfa54767ebd3a750396276512c46a79c;

    /// Runtime bytecode of the Zoltu factory, for use with `vm.etch`.
    bytes constant ZOLTU_FACTORY_BYTECODE = hex"60003681823780368234f58015156014578182fd5b80825250506014600cf3";

    /// Config name for Arbitrum One network.
    string constant ARBITRUM_ONE = "arbitrum";

    /// Config name for Base network.
    string constant BASE = "base";

    /// Config name for BNB Smart Chain (chain id 56). The Zoltu factory is
    /// deployed there with the canonical runtime, so deterministic deploys
    /// land at the same addresses as on every other supported network.
    string constant BSC = "bsc";

    /// Config name for Base Sepolia testnet.
    string constant BASE_SEPOLIA = "base_sepolia";

    /// Config name for Ethereum mainnet.
    string constant ETHEREUM = "ethereum";

    /// Config name for Flare network.
    string constant FLARE = "flare";

    /// Config name for HyperEVM network.
    string constant HYPEREVM = "hyperevm";

    /// Config name for Polygon network.
    string constant POLYGON = "polygon";

    /// Config name for Robinhood Chain (chain id 4663), an Arbitrum Orbit L2
    /// settling to Ethereum. The Zoltu factory is deployed there with the
    /// canonical runtime, so deterministic deploys land at the same addresses
    /// as on every other supported network.
    string constant ROBINHOOD = "robinhood";

    /// Checks whether a block is the first block where a contract with the
    /// expected code hash exists. True when the target has the expected code
    /// hash at `blockNumber` and does NOT have it at `blockNumber - 1`. At
    /// block 0, only the first condition is checked. The fork is restored to
    /// its original block number after checking.
    ///
    /// "First" is only true of a target whose code hash is MONOTONE: once it
    /// equals `expectedCodeHash` at some block it equals it at every later
    /// block. This reads two adjacent blocks and nothing else, so on a target
    /// that held `expectedCodeHash`, lost it and holds it again — a pre-Cancun
    /// `SELFDESTRUCT` followed by a `CREATE2` redeploy of the same code at the
    /// same address, say — it answers true at EVERY block where the hash
    /// reappears, not only the earliest. Monotonicity is the caller's to know:
    /// two blocks cannot show it.
    /// @param vm The Vm instance for fork manipulation.
    /// @param target The contract address to check.
    /// @param expectedCodeHash The code hash to look for. MUST NOT be zero;
    /// `NoExpectedCodeHash` says why.
    /// @param blockNumber The block number to check.
    /// @return True if the contract first appears at this block.
    function isStartBlock(Vm vm, address target, bytes32 expectedCodeHash, uint256 blockNumber)
        internal
        returns (bool)
    {
        if (expectedCodeHash == bytes32(0)) {
            revert NoExpectedCodeHash(target);
        }

        uint256 originalBlock = block.number;
        vm.rollFork(blockNumber);
        bool isStart = target.codehash == expectedCodeHash;
        if (isStart && blockNumber > 0) {
            vm.rollFork(blockNumber - 1);
            isStart = target.codehash != expectedCodeHash;
        }
        vm.rollFork(originalBlock);
        return isStart;
    }

    /// Finds the block number at which a contract was first deployed by binary
    /// searching the fork history. Requires an active fork with archive access
    /// back to `startBlock`. The fork is restored to its original block
    /// number before returning. The target's code hash is verified against the
    /// expected value before searching.
    ///
    /// The search REQUIRES the target's code hash to be monotone over
    /// `[startBlock, block.number]`, in the sense `isStartBlock` describes.
    /// Against a target that held `expectedCodeHash`, lost it and holds it
    /// again, the search converges on one of those appearances with no way to
    /// say which, and the result is meaningless as the subgraph start block it
    /// is typically used as.
    ///
    /// That is the caller's precondition because nothing here can check it, and
    /// `isStartBlock` least of all. `high` is only ever a block where the code
    /// hash matches: it starts at the current block, checked above, and
    /// otherwise takes a `mid` the loop has just read as matching. `low` is
    /// either `startBlock`, checked above as NOT matching, or one past a `mid`
    /// the loop has just read as not matching. It cannot still be `startBlock`
    /// when the loop ends, because that needs `high` down at `startBlock` and
    /// `high` is only ever a matching block, so where they meet the hash
    /// matches and did not match at the block before — `isStartBlock`'s exact
    /// condition, satisfied by construction and satisfied on a non-monotone
    /// history just the same. Running it on the result would read two more
    /// archive blocks to agree with itself.
    /// @param vm The Vm instance for fork manipulation.
    /// @param target The contract address to search for.
    /// @param expectedCodeHash The expected code hash of the target contract.
    /// @param startBlock The earliest block to search from. The target MUST
    /// NOT have the expected code hash at this block.
    /// @return The first block number where `target` has the expected code
    /// hash.
    function findDeployBlock(Vm vm, address target, bytes32 expectedCodeHash, uint256 startBlock)
        internal
        returns (uint256)
    {
        if (target.code.length == 0) {
            revert NotDeployed(target);
        }
        if (target.codehash != expectedCodeHash) {
            revert UnexpectedDeployedCodeHash(expectedCodeHash, target.codehash);
        }

        uint256 originalBlock = block.number;

        // Verify the target does not already have the expected code at
        // startBlock. If it does, the deploy happened before our search
        // range and the result would be meaningless.
        vm.rollFork(startBlock);
        if (target.codehash == expectedCodeHash) {
            vm.rollFork(originalBlock);
            revert DeployedBeforeStartBlock(target, startBlock);
        }

        uint256 low = startBlock;
        uint256 high = originalBlock;

        while (low < high) {
            uint256 mid = (low + high) / 2;
            vm.rollFork(mid);
            if (target.codehash == expectedCodeHash) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        vm.rollFork(originalBlock);
        return low;
    }

    /// Etches the Zoltu factory bytecode into the factory address. Useful for
    /// networks where the factory is not yet deployed.
    /// @param vm The Vm instance to use for etching.
    function etchZoltuFactory(Vm vm) internal {
        vm.etch(ZOLTU_FACTORY, ZOLTU_FACTORY_BYTECODE);
    }

    /// Derives the address the Zoltu factory deploys the given creation code
    /// to. The factory is CREATE2 over its calldata with a zero salt, so the
    /// address is a pure function of the creation code and is identical on
    /// every network.
    /// @param creationCode The creation code to derive the address for.
    /// @return The address the creation code deploys to.
    function zoltuAddress(bytes memory creationCode) internal pure returns (address) {
        return address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), ZOLTU_FACTORY, bytes32(0), keccak256(creationCode))))
            )
        );
    }

    /// Deploys the given creation code via the Zoltu factory.
    /// Handles the return data and errors appropriately.
    /// @param creationCode The creation code to deploy.
    /// @return The address of the deployed contract.
    function deployZoltu(bytes memory creationCode) internal returns (address) {
        address zoltuFactory = ZOLTU_FACTORY;
        address deployedAddress;
        bool success;
        assembly ("memory-safe") {
            // Zero scratch space so mload(0) reads a clean 32-byte word.
            mstore(0, 0)
            // The Zoltu factory returns a raw 20-byte address (not ABI-encoded).
            // Writing 20 bytes at offset 12 (= 32 - 20) right-aligns the address
            // in scratch space so that mload(0) produces a correctly padded value.
            success := call(gas(), zoltuFactory, 0, add(creationCode, 0x20), mload(creationCode), 12, 20)
            // The EVM copies revert data into the output region too, so only a
            // successful call leaves an address there. A failed call leaves
            // `deployedAddress` zero rather than reporting revert bytes as an
            // address.
            if success { deployedAddress := mload(0) }
        }
        if (!success || deployedAddress == address(0) || deployedAddress.code.length == 0) {
            console2.log("Zoltu deployment failed. Success:", success, "Deployed Address:", deployedAddress);
            console2.log("Code length at Deployed Address:", deployedAddress.code.length);
            console2.log("Codehash at Deployed Address:");
            console2.logBytes32(deployedAddress.codehash);
            revert DeployFailed(success, deployedAddress);
        }
        return deployedAddress;
    }

    /// Creates a fork for every network, returning their ids in list order.
    /// Nothing is selected here: the caller selects each in turn.
    ///
    /// Creating them all BEFORE the first one is selected is the whole point.
    /// Foundry captures the account set of the pre-fork EVM when the first fork
    /// is selected, and seeds every fork CREATED after that capture with it, so
    /// any address the calling script touched beforehand is carried onto the
    /// second and later networks as the empty account the default 31337 EVM has
    /// for it. A `dep.code.length` read added to a deploy script for logging is
    /// enough. Forks created before the capture read their chain, which is why
    /// the first network was always right and every one after it was wrong.
    ///
    /// Closed here rather than by a rule about what a deploy script may read,
    /// because the trap is invisible from where a consumer sits: the read is
    /// ordinary, the failure names a real address on a network that really has
    /// it, and nothing connects the two.
    /// @param vm The Vm instance to fork with.
    /// @param networks The network names to fork, as `[rpc_endpoints]` aliases.
    /// @return The fork id of each network, positionally paired.
    function createForks(Vm vm, string[] memory networks) internal returns (uint256[] memory) {
        uint256[] memory forkIds = new uint256[](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            forkIds[i] = vm.createFork(networks[i]);
        }
        return forkIds;
    }

    /// Every network Rain deployments support, with everything the generated
    /// config states about each.
    ///
    /// The CATALOGUE: what is true of a network, not which networks a repo
    /// deals with. That second question is
    /// `RainDeploySuitesBase.supportedNetworks()`, the one hook on the
    /// declaration both sides read, and this is what its names select from —
    /// `declaredNetworkConfigs` is the selection, `LibRainDeployConfig` writes
    /// the config sections from it, and `RainDeployVerifyChain` forks it. So
    /// the config cannot disagree with the declaration without `Git is clean`
    /// failing the tree that says so, and there is nothing left for a test to
    /// compare.
    ///
    /// Deriving the catalogue from the config instead would be the same facts
    /// spelled once as well, and wrong: a repo that deleted an alias would
    /// deploy to and verify fewer chains, green, because the thing that would
    /// notice reads the same file.
    /// @return The supported networks.
    function supportedNetworkConfigs() internal pure returns (SupportedNetwork[] memory) {
        SupportedNetwork[] memory networks = new SupportedNetwork[](9);
        networks[0] = SupportedNetwork({
            name: ARBITRUM_ONE, chainId: 42161, explorerUrl: "", defaultRpcUrl: "https://arb1.arbitrum.io/rpc"
        });
        networks[1] =
            SupportedNetwork({name: BASE, chainId: 8453, explorerUrl: "", defaultRpcUrl: "https://mainnet.base.org"});
        networks[2] = SupportedNetwork({
            name: BASE_SEPOLIA, chainId: 84532, explorerUrl: "", defaultRpcUrl: "https://sepolia.base.org"
        });
        networks[3] = SupportedNetwork({
            name: BSC, chainId: 56, explorerUrl: "", defaultRpcUrl: "https://bsc-dataseed.binance.org"
        });
        networks[4] = SupportedNetwork({
            name: ETHEREUM, chainId: 1, explorerUrl: "", defaultRpcUrl: "https://eth-pokt.nodies.app"
        });
        networks[5] = SupportedNetwork({
            name: FLARE, chainId: 14, explorerUrl: "", defaultRpcUrl: "https://flare-api.flare.network/ext/C/rpc"
        });
        networks[6] = SupportedNetwork({
            name: HYPEREVM, chainId: 999, explorerUrl: "", defaultRpcUrl: "https://rpc.hyperliquid.xyz/evm"
        });
        networks[7] = SupportedNetwork({
            name: POLYGON, chainId: 137, explorerUrl: "", defaultRpcUrl: "https://polygon-bor-rpc.publicnode.com"
        });
        // Robinhood Chain is not indexed by Etherscan V2, so `--verify` is
        // pointed at its Blockscout explorer, which speaks the Etherscan API
        // and ignores the key. Blockscout sits behind a browser challenge that
        // has rejected non-browser clients, so if `--verify` fails on this
        // network after a broadcast, verify afterwards through Sourcify (which
        // supports 4663 and which Blockscout imports):
        // `forge verify-contract --verifier sourcify --chain 4663 ...`.
        networks[8] = SupportedNetwork({
            name: ROBINHOOD,
            chainId: 4663,
            explorerUrl: "https://robinhoodchain.blockscout.com/api",
            defaultRpcUrl: "https://rpc.mainnet.chain.robinhood.com"
        });
        return networks;
    }

    /// The names of the networks currently supported by Rain deployments, in
    /// catalogue order.
    /// @return The list of supported network names.
    function supportedNetworks() internal pure returns (string[] memory) {
        SupportedNetwork[] memory configs = supportedNetworkConfigs();
        string[] memory networks = new string[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            networks[i] = configs[i].name;
        }
        return networks;
    }

    /// The catalogue entries a declaration names, in the order it names them.
    ///
    /// Everything generated or forked per network goes through here, so a
    /// declaration that narrows `supportedNetworks()` narrows the config, the
    /// chain id checks and the deploy together, from one answer. The names a
    /// repo declares are the selection and the catalogue is the facts, so there
    /// are never two statements of either to drift apart.
    ///
    /// A name the catalogue says nothing about is refused rather than skipped:
    /// skipping it would generate config for fewer networks than the repo
    /// deploys to and verifies on, which is the silent green the whole
    /// mechanism exists to remove.
    /// @param networks The declared network names.
    /// @return The catalogue entry for each, in declaration order.
    function declaredNetworkConfigs(string[] memory networks) internal pure returns (SupportedNetwork[] memory) {
        SupportedNetwork[] memory catalogue = supportedNetworkConfigs();
        SupportedNetwork[] memory declared = new SupportedNetwork[](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < catalogue.length; j++) {
                if (keccak256(bytes(networks[i])) == keccak256(bytes(catalogue[j].name))) {
                    declared[i] = catalogue[j];
                    found = true;
                    break;
                }
            }
            if (!found) {
                revert NetworkNotInCatalogue(networks[i]);
            }
        }
        return declared;
    }

    /// The read-set refusals every resolved-address check makes before it reads
    /// anything, so they are reportable without an RPC round trip.
    ///
    /// An empty read set is REFUSED: a check with nothing to read returns having
    /// asserted nothing, which no caller can tell from every read checking out.
    /// Checked AFTER pairing, because the empty pair is the one mispairing that
    /// pairing cannot see — zero against zero says nothing.
    /// @param target The deployed contract the reads are aimed at, for the
    /// refusal to name.
    /// @param readCalls The calldata for each read.
    /// @param expectedAddresses The address each read MUST answer with,
    /// positionally paired with `readCalls`.
    function checkResolvedAddressReads(address target, bytes[] memory readCalls, address[] memory expectedAddresses)
        private
        pure
    {
        if (readCalls.length != expectedAddresses.length) {
            revert ResolvedAddressesLengthMismatch(readCalls.length, expectedAddresses.length);
        }
        if (readCalls.length == 0) {
            revert NoResolvedAddressReads(target);
        }
    }

    /// Asserts that an already-deployed contract holds the addresses the
    /// deployment expects, on whichever network is currently selected.
    ///
    /// This runs AFTER the deploy, deliberately. What it checks is state the
    /// deployed contract has already settled — a value it resolved once, in its
    /// constructor, and stored — so nothing it reads can move underneath it. The
    /// same check run BEFORE a deploy would be worth nothing: it would read a
    /// source that can change between the check and the constructor that
    /// consumes it.
    ///
    /// It is deliberately source-agnostic. It says the deployed contract holds
    /// the expected address, not where that address came from, because the
    /// address registry is only one way a deployment acquires one, and because
    /// re-reading the registry here would assert a value that can move rather
    /// than the value this deployment actually took.
    ///
    /// Only the consumer knows where it stored what it resolved, so the consumer
    /// supplies the reads. Each entry in `readCalls` is static-called against
    /// `target` and MUST answer with exactly one address.
    /// @param network The network name, for the error only.
    /// @param target The deployed contract to read.
    /// @param readCalls The calldata for each read, e.g.
    /// `abi.encodeCall(IOwnable.owner, ())`.
    /// @param expectedAddresses The address each read MUST answer with,
    /// positionally paired with `readCalls`.
    function checkResolvedAddresses(
        string memory network,
        address target,
        bytes[] memory readCalls,
        address[] memory expectedAddresses
    ) internal view {
        checkResolvedAddressReads(target, readCalls, expectedAddresses);
        for (uint256 i = 0; i < readCalls.length; i++) {
            // The consumer supplies the reads, so the call is low level by
            // construction: there is no interface here to call through. Excluded
            // at the site rather than repo-wide so a low-level call added
            // anywhere else is still reported.
            // slither-disable-next-line low-level-calls
            (bool success, bytes memory returnData) = target.staticcall(readCalls[i]);
            // A read that reverts, answers nothing (no code at `target`), or
            // answers something that is not one word cannot be compared, and is
            // never a pass.
            if (!success || returnData.length != 0x20) {
                revert ResolvedAddressReadFailed(network, target, i, returnData);
            }
            // Decoded as a word and range checked here rather than decoded as an
            // address, because `abi.decode(_, (address))` reverts with no data
            // of its own when the word's upper 96 bits are dirty. A read that
            // answers with a word that is not an address is exactly the case
            // `ResolvedAddressReadFailed` is for, so it is reported as that
            // rather than as a bare revert nothing can diagnose.
            uint256 word = abi.decode(returnData, (uint256));
            if (word > type(uint160).max) {
                revert ResolvedAddressReadFailed(network, target, i, returnData);
            }
            // Casting to `uint160` is safe because the range check directly
            // above rejects every word with dirty upper 96 bits, so the low 160
            // bits are the whole of the word and the cast keeps every one.
            // Excluded at the site rather than repo-wide so an unchecked cast
            // added anywhere else is still reported.
            // forge-lint: disable-next-line(unsafe-typecast)
            address actual = address(uint160(word));
            if (actual != expectedAddresses[i]) {
                revert UnexpectedResolvedAddress(network, target, i, expectedAddresses[i], actual);
            }
        }
    }

    /// SIMULATION verification: runs `checkResolvedAddresses` on forks that
    /// ALREADY EXIST, which `deployToNetworks` returns the ids for.
    ///
    /// A deploy script broadcasts nothing itself — it simulates on each fork and
    /// records transactions, and forge submits them only once the script has
    /// returned. So during the script the deployment exists on the deploy's own
    /// forks and nowhere else, and this is the only way a first-time deploy can
    /// be verified in the run that deploys it. Once the transactions confirm,
    /// `checkResolvedAddressesOnNetworks` is the stage to use.
    ///
    /// An empty network set, an unpaired fork id list and an empty read set are
    /// all REFUSED before any fork is selected.
    /// @param vm The Vm instance to select forks with.
    /// @param networks The list of network names to check, naming the fork ids
    /// positionally. The name is what a failure reports.
    /// @param forkIds The fork to check each network on, positionally paired
    /// with `networks`.
    /// @param target The deployed contract to read on each network.
    /// @param readCalls The calldata for each read.
    /// @param expectedAddresses The address each read MUST answer with,
    /// positionally paired with `readCalls`.
    function checkResolvedAddressesOnForks(
        Vm vm,
        string[] memory networks,
        uint256[] memory forkIds,
        address target,
        bytes[] memory readCalls,
        address[] memory expectedAddresses
    ) internal {
        if (networks.length == 0) {
            revert NoNetworks();
        }
        if (forkIds.length != networks.length) {
            revert ForkIdsLengthMismatch(networks.length, forkIds.length);
        }
        checkResolvedAddressReads(target, readCalls, expectedAddresses);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            console2.log("Checking resolved addresses on network:", networks[i]);
            checkResolvedAddresses(networks[i], target, readCalls, expectedAddresses);
        }
    }

    /// CONFIRMED-DEPLOYMENT verification: runs `checkResolvedAddresses` on a
    /// FRESH fork of every network, a run of its own once the deploy's
    /// transactions have been mined. A network holding something other than
    /// expected is a burned deterministic address, found while nothing points
    /// at it yet.
    ///
    /// It CANNOT verify a deploy made earlier in the same script. Nothing is
    /// mined when `deployAndBroadcast` returns, so a fresh fork has no code at
    /// the address, every read answers nothing, and `ResolvedAddressReadFailed`
    /// takes the run down before forge submits what it collected. Same-script
    /// verification is `checkResolvedAddressesOnForks`, on the ids the deploy
    /// hands back.
    ///
    /// An empty network set and an empty read set are both REFUSED before
    /// anything is forked.
    /// @param vm The Vm instance to use for forking.
    /// @param networks The list of network names to check.
    /// @param target The deployed contract to read on each network.
    /// @param readCalls The calldata for each read.
    /// @param expectedAddresses The address each read MUST answer with,
    /// positionally paired with `readCalls`.
    function checkResolvedAddressesOnNetworks(
        Vm vm,
        string[] memory networks,
        address target,
        bytes[] memory readCalls,
        address[] memory expectedAddresses
    ) internal {
        if (networks.length == 0) {
            revert NoNetworks();
        }
        // Repeated here rather than left to the fork loop, so a mispaired or
        // empty read set is reported without an RPC round trip.
        checkResolvedAddressReads(target, readCalls, expectedAddresses);
        checkResolvedAddressesOnForks(vm, networks, createForks(vm, networks), target, readCalls, expectedAddresses);
    }

    /// What the ZOLTU mechanism needs on a network before it can deploy there:
    /// the factory, holding the code this library pins for it.
    ///
    /// Split out from the declared dependencies because it belongs to the
    /// mechanism and not to the declaration. `deployStepToNetworks` serves every
    /// mechanism, and a clone broadcast run through a loop that demanded the
    /// Zoltu factory would refuse a network over a contract it never calls —
    /// while the declared dependencies have to hold whichever mechanism puts the
    /// code there. So the loop checks the list and each step checks its own
    /// factory.
    /// @param network The network being checked, for the refusal to name.
    function checkZoltuFactory(string memory network) internal view {
        console2.log(" - Zoltu Factory:", ZOLTU_FACTORY);
        if (ZOLTU_FACTORY.code.length == 0) {
            revert MissingDependency(network, ZOLTU_FACTORY);
        }
        if (ZOLTU_FACTORY.codehash != ZOLTU_FACTORY_CODEHASH) {
            revert DependencyChanged(network, ZOLTU_FACTORY, ZOLTU_FACTORY_CODEHASH, ZOLTU_FACTORY.codehash);
        }
    }

    /// Every DECLARED dependency that MUST already be on a network before the
    /// suite declaring it is broadcast there, with the code its declaration
    /// carries.
    ///
    /// Each dependency's presence is checked before its code hash, and not
    /// folded into one comparison. An account with no code answers `codehash`
    /// zero, which is a value no declaration can produce — `keccak256` of the
    /// empty string is not zero — so the hash check alone would report every
    /// absent dependency as a changed one.
    /// @param network The network being checked, for the refusal to name.
    /// @param dependencies The declared dependencies.
    function checkDeclaredDependencies(string memory network, DeployDependency[] memory dependencies) internal view {
        for (uint256 j = 0; j < dependencies.length; j++) {
            address dependency = dependencies[j].deployedAddress;
            console2.log(" - Dependency:", dependency);
            if (dependency.code.length == 0) {
                revert MissingDependency(network, dependency);
            }
            bytes32 expectedDependencyCodeHash = keccak256(dependencies[j].runtimeCode);
            if (dependency.codehash != expectedDependencyCodeHash) {
                revert DependencyChanged(network, dependency, expectedDependencyCodeHash, dependency.codehash);
            }
        }
    }

    /// The ZOLTU mechanism as a `deployStepToNetworks` step: the one thing a
    /// Zoltu deploy does that a clone deploy does not.
    ///
    /// Everything around it — the network list, the forks, the skip, the
    /// address and code hash assertions — is the loop's, and the loop is shared.
    /// This is the step, and the step is the whole of the difference: Zoltu's
    /// `CREATE2` over the creation code at a zero salt, versus a clone factory's
    /// `cloneDeterministicOpenSalt`.
    ///
    /// Its own factory check lives here rather than in the loop, because it is
    /// this mechanism's requirement: a clone broadcast has no business reading
    /// the Zoltu factory at all, and would be refused a network over it.
    ///
    /// `vm.startBroadcast` / `vm.stopBroadcast` are the step's too, so that the
    /// broadcast window is exactly the one call that puts code on chain. The
    /// factory read above it is a plain read, taken before the window opens.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The network being deployed to, for a refusal to name.
    /// @param deployer The deployer address to broadcast as.
    /// @param creationCode The step data: the creation code to deploy.
    /// @return The address the Zoltu factory deployed to.
    function zoltuDeployStep(Vm vm, string memory network, address deployer, bytes memory creationCode)
        internal
        returns (address)
    {
        checkZoltuFactory(network);

        console2.log(" - Deploying via Zoltu");
        vm.startBroadcast(deployer);
        address zoltuDeployedAddress = deployZoltu(creationCode);
        vm.stopBroadcast();
        return zoltuDeployedAddress;
    }

    /// Puts ONE deployment at ONE expected address on EVERY network, by whatever
    /// mechanism `deployStep` is.
    ///
    /// The one loop, for every mechanism. Rain deploys to all networks on every
    /// dispatch because deploying is idempotent, and that — the list, the forks
    /// created before any is selected, the skip where the address already has
    /// code, and the address and code hash assertions against what the
    /// declaration says — is identical whether the bytes arrive through the
    /// Zoltu factory or through a clone factory's `cloneDeterministicOpenSalt`.
    /// The only variable is the step that puts the code there, so that is the
    /// parameter. A second copy of this loop with one call swapped would be two
    /// copies to keep in step, and the one that fell behind is the one whose
    /// deploys stop being checked.
    ///
    /// `deployStep` is an internal function POINTER rather than a virtual on an
    /// abstract, so the mechanism is chosen where the deploy is described —
    /// `deployToNetworks` passes `zoltuDeployStep`, `LibRainDeployClone`'s
    /// `cloneToNetworks` passes its clone step — and the loop stays a library
    /// function that a test can drive directly on a fork.
    ///
    /// For each network it forks once. Where `expectedAddress` has no code it
    /// verifies every declared dependency has code AND that each one's code
    /// hash is the hash of the `runtimeCode` its declaration carries, then runs
    /// `deployStep` on that same fork — which checks whatever its OWN mechanism
    /// needs there before broadcasting. Where code already exists at
    /// `expectedAddress`, that verification is skipped along with the deploy, so
    /// a rerun proves nothing about the factory or the dependencies on an
    /// already-deployed network. Checking and deploying on a single fork reads
    /// each dependency exactly once, so a transient RPC inconsistency on a
    /// redundant second read cannot report an already-deployed dependency as
    /// missing and abort an otherwise-valid deploy. Each network is handled
    /// independently: the deploy is idempotent (an existing contract is
    /// skipped), so a failure on one network leaves the others intact and the
    /// script can simply be re-run.
    ///
    /// The forks themselves are all created up front, before any is selected —
    /// `createForks` says why it has to be that way round. Endpoint reachability
    /// is therefore the one thing that IS all-network: an alias that cannot be
    /// forked stops the run before anything is broadcast, rather than partway
    /// through it.
    ///
    /// `expectedAddress` MUST be the address `deployStep` will actually deploy
    /// to. Nothing here can check that — only the mechanism knows its own
    /// derivation — so each mechanism's entry point checks it BEFORE any fork
    /// and `UnexpectedDeployedAddress` is what both of them raise.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployer The deployer address.
    /// @param deployStep The mechanism that puts code at `expectedAddress` on
    /// the selected fork, and that checks whatever IT needs on the network
    /// first. Handed the network name so its own refusals can name it.
    /// @param deployStepData Whatever the step needs: the creation code for
    /// Zoltu, the encoded clone for a clone factory. Opaque here on purpose —
    /// the loop asserts about the ADDRESS and the CODE, not about the recipe.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The expected deterministic address, which MUST be
    /// the address `deployStep` deploys to.
    /// @param expectedCodeHash The expected code hash of the deployed contract.
    /// @param dependencies The addresses that must already have code on a
    /// network before this contract can be broadcast there, each paired with
    /// the runtime code that must be at it. The declared pair and not the
    /// address alone, because a derivation etches the code to run this
    /// contract's constructor: an address that merely has SOMETHING at it
    /// satisfies no constructor that calls it, and the derived code hash this
    /// broadcast carries was computed against the declared bytes.
    /// @return deployedAddress The deployed contract address.
    /// @return forkIds The fork each network was deployed on, positionally
    /// paired with `networks`. Handed back rather than dropped because the
    /// deployment exists ONLY on them until forge submits what this recorded,
    /// so they are what `checkResolvedAddressesOnForks` verifies a first-time
    /// deploy on.
    function deployStepToNetworks(
        Vm vm,
        string[] memory networks,
        address deployer,
        function(Vm, string memory, address, bytes memory) internal returns (address) deployStep,
        bytes memory deployStepData,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        DeployDependency[] memory dependencies
    ) internal returns (address deployedAddress, uint256[] memory forkIds) {
        if (networks.length == 0) {
            revert NoNetworks();
        }
        forkIds = createForks(vm, networks);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            console2.log("Deploying to network:", networks[i]);
            console2.log("Block number:", block.number);

            if (expectedAddress.code.length == 0) {
                checkDeclaredDependencies(networks[i], dependencies);

                address stepDeployedAddress = deployStep(vm, networks[i], deployer, deployStepData);
                if (stepDeployedAddress != expectedAddress) {
                    revert UnexpectedDeployedAddress(expectedAddress, stepDeployedAddress);
                }
            } else {
                // Already deployed on this network. The deploy is idempotent, so
                // skip it without checking the mechanism's factory or the
                // dependencies: an already-deployed network needs neither
                // present to remain deployed, which keeps a rerun a clean no-op
                // here.
                console2.log(" - Code already exists at expected address, skipping deployment");
            }
            console2.log(" - Final Address:", expectedAddress);
            console2.log(" - Verifying code hash");
            if (expectedCodeHash != expectedAddress.codehash) {
                revert UnexpectedDeployedCodeHash(expectedCodeHash, expectedAddress.codehash);
            }

            console2.log("manual verification command:");
            console2.log(
                string.concat(
                    "forge verify-contract --chain ", networks[i], " ", vm.toString(expectedAddress), " ", contractPath
                )
            );
        }

        return (expectedAddress, forkIds);
    }

    /// Deploys the given creation code to each network via the Zoltu factory:
    /// `deployStepToNetworks` with `zoltuDeployStep` as the mechanism.
    ///
    /// `expectedAddress` MUST be the address the Zoltu factory derives for
    /// `creationCode`, which is checked HERE, before any network is forked, so
    /// an expected address that disagrees with the creation code fails loudly
    /// rather than matching some other contract already deployed there and
    /// skipping every network. It is checked here rather than in the loop
    /// because the derivation is the mechanism's: the loop cannot predict where
    /// a step it was handed will deploy to.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployer The deployer address.
    /// @param creationCode The creation code to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The expected deterministic address, which MUST be
    /// the address the Zoltu factory derives for `creationCode`.
    /// @param expectedCodeHash The expected code hash of the deployed contract.
    /// @param dependencies The addresses that must already have code on a
    /// network before this contract can be broadcast there, each paired with
    /// the runtime code that must be at it.
    /// @return deployedAddress The deployed contract address.
    /// @return forkIds The fork each network was deployed on, as
    /// `deployStepToNetworks` hands them back.
    function deployToNetworks(
        Vm vm,
        string[] memory networks,
        address deployer,
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        DeployDependency[] memory dependencies
    ) internal returns (address deployedAddress, uint256[] memory forkIds) {
        if (networks.length == 0) {
            revert NoNetworks();
        }
        // The Zoltu factory deploys the given creation code to a single
        // deterministic address on every network, so an expected address that
        // disagrees with the creation code can never hold that code. Checked
        // up front, before any fork, because otherwise a network that already
        // has some other contract at the expected address takes the skip
        // branch and reports success without ever deploying.
        address derivedAddress = zoltuAddress(creationCode);
        if (derivedAddress != expectedAddress) {
            revert UnexpectedDeployedAddress(expectedAddress, derivedAddress);
        }
        return deployStepToNetworks(
            vm,
            networks,
            deployer,
            zoltuDeployStep,
            creationCode,
            contractPath,
            expectedAddress,
            expectedCodeHash,
            dependencies
        );
    }

    /// Deploys the given creation code via the Zoltu factory to the given
    /// networks, broadcasting the deployment transaction using the given private
    /// key.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployerPrivateKey The private key to use for broadcasting.
    /// @param creationCode The creation code to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The expected deterministic address, which MUST be
    /// the address the Zoltu factory derives for `creationCode`.
    /// @param expectedCodeHash The expected code hash of the deployed contract.
    /// @param dependencies The dependencies to check, each an address and the
    /// runtime code that must be at it.
    /// @return deployedAddress The address of the deployed contract.
    /// @return forkIds The fork each network was deployed on, as
    /// `deployToNetworks` returns them.
    function deployAndBroadcast(
        Vm vm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        DeployDependency[] memory dependencies
    ) internal returns (address deployedAddress, uint256[] memory forkIds) {
        if (networks.length == 0) {
            revert NoNetworks();
        }
        return deployToNetworks(
            vm,
            networks,
            rememberDeployer(vm, deployerPrivateKey),
            creationCode,
            contractPath,
            expectedAddress,
            expectedCodeHash,
            dependencies
        );
    }

    /// Takes the deploy key up as a wallet and reports the address it derives.
    ///
    /// REMEMBERED rather than merely derived: `vm.startBroadcast(deployer)` signs
    /// as an address forge has a key for, and an address derived without
    /// remembering is one it cannot sign for. Shared by every mechanism's
    /// `…AndBroadcast` so there is one spelling of the key handling — the key is
    /// the one thing a dispatch cannot see the effect of until a chain rejects
    /// the transactions for gas.
    /// @param vm The Vm instance to remember the key with.
    /// @param deployerPrivateKey The private key to broadcast as.
    /// @return deployer The address the key derives.
    function rememberDeployer(Vm vm, uint256 deployerPrivateKey) internal returns (address deployer) {
        deployer = vm.rememberKey(deployerPrivateKey);
        console2.log("Deploying from address:", deployer);
    }
}
