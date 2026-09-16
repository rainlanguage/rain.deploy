// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Build, GeneratedContract} from "../../script/Build.sol";
import {DeployCandidate} from "../../src/abstract/RainDeploySuitesBase.sol";

/// Thrown when a harness left pointed at `Build`'s own lib directory is asked
/// to run the lib half of a build. That write lands on the committed libs the
/// rest of the suite compiles and reads, which forge runs in parallel with it.
error BuildHarnessWouldWriteTheCommittedLibs();

/// @title BuildHarness
/// @notice An external seam onto the two internal declarations `BuildTest`
/// compares, so a test can hold both at once, and onto `regenerateLibs()`
/// pointed somewhere nothing compiles, so a test can RUN it.
///
/// A harness rather than a change to `Build`: `generatedContracts()` is the
/// script's own declaration and has no caller outside it, and widening it to
/// `public` to be testable would put a second entry point on a script whose
/// whole surface is `run()` and `cutRelease()`.
contract BuildHarness is Build {
    /// The lib directory the hooks write into. Empty defers to `Build`'s own,
    /// which is what makes the default assertable and the write refusable.
    string internal sLibDir;

    /// @param libDirectory The directory `regenerateLibs` writes into, or empty
    /// for `Build`'s own.
    constructor(string memory libDirectory) {
        sLibDir = libDirectory;
    }

    /// @inheritdoc Build
    function libDir() internal view override returns (string memory) {
        return bytes(sLibDir).length > 0 ? sLibDir : super.libDir();
    }

    function externalLibDir() external view returns (string memory) {
        return libDir();
    }

    /// Runs the lib half of a build, into the fixture directory this harness
    /// was handed. The directory has to exist already, as it does for every
    /// writer `regenerateLibs` calls.
    function externalRegenerateLibs() external {
        if (bytes(sLibDir).length == 0) {
            revert BuildHarnessWouldWriteTheCommittedLibs();
        }
        regenerateLibs();
    }

    /// The generator's list.
    /// @return The generated contracts.
    function externalGeneratedContracts() external pure returns (GeneratedContract[] memory) {
        return generatedContracts();
    }

    /// The names a release cut from this script freezes.
    /// @return The snapshot contract names.
    function externalSnapshotContractNames() external pure returns (string[] memory) {
        return snapshotContractNames();
    }

    /// The deploy declaration's list, through the same guarded reader every
    /// other consumer of the declaration uses.
    /// @return The declared candidates.
    function externalCandidateSuites() external pure returns (DeployCandidate[] memory) {
        return checkedCandidateSuites();
    }
}
