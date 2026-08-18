// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.2/src/Vm.sol";
import {console2} from "forge-std-1.16.2/src/console2.sol";

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
    error DependencyChanged(string network, address dependency, bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// Thrown when no networks are provided for deployment.
    error NoNetworks();

    /// Thrown when attempting to find the deploy block of a contract that has
    /// no code at the current block.
    error NotDeployed(address target);

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

    /// Config name for Base Sepolia testnet.
    string constant BASE_SEPOLIA = "base_sepolia";

    /// Config name for Flare network.
    string constant FLARE = "flare";

    /// Config name for Polygon network.
    string constant POLYGON = "polygon";

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
    /// @param expectedCodeHash The code hash to look for.
    /// @param blockNumber The block number to check.
    /// @return True if the contract first appears at this block.
    function isStartBlock(Vm vm, address target, bytes32 expectedCodeHash, uint256 blockNumber)
        internal
        returns (bool)
    {
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

    /// Returns the list of networks currently supported by Rain deployments.
    /// @return The list of supported network names.
    function supportedNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](5);
        networks[0] = ARBITRUM_ONE;
        networks[1] = BASE;
        networks[2] = BASE_SEPOLIA;
        networks[3] = FLARE;
        networks[4] = POLYGON;
        return networks;
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
    ///
    /// An empty read set is REFUSED. A check with nothing to read returns having
    /// asserted nothing, which is indistinguishable from every read checking
    /// out, and it is what a consumer that built its read list from a source
    /// that came back empty hands in — right before it migrates onto the
    /// deployment this was supposed to verify.
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
        if (readCalls.length != expectedAddresses.length) {
            revert ResolvedAddressesLengthMismatch(readCalls.length, expectedAddresses.length);
        }
        // After the pairing check, not before it: an unpaired call is a
        // mispairing whichever side is empty, and reporting the empty pair as a
        // mismatch of zero against zero would say nothing. The empty pair is the
        // one case pairing cannot see, so it is its own error.
        if (readCalls.length == 0) {
            revert NoResolvedAddressReads(target);
        }
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

    /// Runs `checkResolvedAddresses` on every network, so a deployment verifies
    /// itself across the whole target set here rather than in every consumer's
    /// deploy script.
    ///
    /// Run this after `deployAndBroadcast` and before anything depends on the
    /// deployment. A network where the deployed contract holds something other
    /// than expected is a burned deterministic address, found while nothing
    /// points at it yet — which is the whole reason to verify before migrating
    /// onto a deployment rather than trusting it.
    ///
    /// An empty network set and an empty read set are both REFUSED, before
    /// anything is forked. Either one makes this return success across every
    /// network having read nothing at all.
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
        // Checked before any fork so a mispaired call fails immediately rather
        // than after an RPC round trip.
        if (readCalls.length != expectedAddresses.length) {
            revert ResolvedAddressesLengthMismatch(readCalls.length, expectedAddresses.length);
        }
        // Same reason: an empty read set is reported without an RPC round trip,
        // so it cannot be masked by an outage on the first network.
        if (readCalls.length == 0) {
            revert NoResolvedAddressReads(target);
        }
        for (uint256 i = 0; i < networks.length; i++) {
            // createSelectFork returns a fork id that is not needed here; bind
            // and reference it so the unused-return lint stays satisfied.
            uint256 forkId = vm.createSelectFork(networks[i]);
            (forkId);
            console2.log("Checking resolved addresses on network:", networks[i]);
            checkResolvedAddresses(networks[i], target, readCalls, expectedAddresses);
        }
    }

    /// Deploys the given creation code to each network via the Zoltu factory.
    /// `expectedAddress` MUST be the address the Zoltu factory derives for
    /// `creationCode`, which is checked before any network is forked, so an
    /// expected address that disagrees with the creation code fails loudly
    /// rather than matching some other contract already deployed there and
    /// skipping every network.
    /// For each network it forks once, verifies the Zoltu factory and every
    /// dependency have code (the factory codehash must also match), then
    /// broadcasts the deploy on that same fork. If code already exists at
    /// `expectedAddress`, deployment is skipped for that network. Checking and
    /// deploying on a single fork reads each dependency exactly once, so a
    /// transient RPC inconsistency on a redundant second read cannot report an
    /// already-deployed dependency as missing and abort an otherwise-valid
    /// deploy. Each network is handled independently: the Zoltu deploy is
    /// idempotent (an existing contract is skipped), so a failure on one network
    /// leaves the others intact and the script can simply be re-run, which is why
    /// no separate all-network pre-flight is needed.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployer The deployer address.
    /// @param creationCode The creation code to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The expected deterministic address, which MUST be
    /// the address the Zoltu factory derives for `creationCode`.
    /// @param expectedCodeHash The expected code hash of the deployed contract.
    /// @param dependencies The addresses that must have code on each network.
    /// @return The deployed contract address.
    function deployToNetworks(
        Vm vm,
        string[] memory networks,
        address deployer,
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        address[] memory dependencies
    ) internal returns (address) {
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
        address deployedAddress;
        for (uint256 i = 0; i < networks.length; i++) {
            // createSelectFork returns a fork id that is not needed here; bind
            // and reference it so the unused-return lint stays satisfied.
            uint256 forkId = vm.createSelectFork(networks[i]);
            (forkId);
            console2.log("Deploying to network:", networks[i]);
            console2.log("Block number:", block.number);

            if (expectedAddress.code.length == 0) {
                // Nothing is deployed here yet, so the Zoltu factory and every
                // dependency must be present before broadcasting the deploy.
                console2.log(" - Zoltu Factory:", ZOLTU_FACTORY);
                if (ZOLTU_FACTORY.code.length == 0) {
                    revert MissingDependency(networks[i], ZOLTU_FACTORY);
                }
                if (ZOLTU_FACTORY.codehash != ZOLTU_FACTORY_CODEHASH) {
                    revert DependencyChanged(networks[i], ZOLTU_FACTORY, ZOLTU_FACTORY_CODEHASH, ZOLTU_FACTORY.codehash);
                }
                for (uint256 j = 0; j < dependencies.length; j++) {
                    console2.log(" - Dependency:", dependencies[j]);
                    if (dependencies[j].code.length == 0) {
                        revert MissingDependency(networks[i], dependencies[j]);
                    }
                }

                console2.log(" - Deploying via Zoltu");
                vm.startBroadcast(deployer);
                deployedAddress = deployZoltu(creationCode);
                vm.stopBroadcast();
                if (deployedAddress != expectedAddress) {
                    revert UnexpectedDeployedAddress(expectedAddress, deployedAddress);
                }
            } else {
                // Already deployed on this network. The Zoltu deploy is
                // idempotent, so skip it without checking dependencies: an
                // already-deployed network needs neither the Zoltu factory nor
                // its dependencies present to remain deployed, which keeps a
                // rerun a clean no-op here.
                console2.log(" - Code already exists at expected address, skipping deployment");
                deployedAddress = expectedAddress;
            }
            console2.log(" - Final Address:", deployedAddress);
            console2.log(" - Verifying code hash");
            if (expectedCodeHash != deployedAddress.codehash) {
                revert UnexpectedDeployedCodeHash(expectedCodeHash, deployedAddress.codehash);
            }

            console2.log("manual verification command:");
            console2.log(
                string.concat(
                    "forge verify-contract --chain ", networks[i], " ", vm.toString(deployedAddress), " ", contractPath
                )
            );
        }

        return deployedAddress;
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
    /// @param dependencies The dependency addresses to check.
    /// @return The address of the deployed contract.
    function deployAndBroadcast(
        Vm vm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        address[] memory dependencies
    ) internal returns (address) {
        if (networks.length == 0) {
            revert NoNetworks();
        }
        address deployer = vm.rememberKey(deployerPrivateKey);

        console2.log("Deploying from address:", deployer);

        return deployToNetworks(
            vm, networks, deployer, creationCode, contractPath, expectedAddress, expectedCodeHash, dependencies
        );
    }
}
