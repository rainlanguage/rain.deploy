// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExampleDeployScript} from "../abstract/ExampleDeployScript.sol";

/// @title ExampleDeployNarrowNetworks
/// A repo that deploys to FEWER networks than Rain supports at all, which is
/// what a declaration's `networks` is for — `st0x.deploy` broadcasts to
/// five of the nine, so every release of it would otherwise be held to four
/// networks it never reaches.
///
/// Narrowing the DECLARATION rather than `deployNetworks()`, which is the
/// difference `ExampleDeploySingleNetwork` is the other half of: that one
/// narrows a single dispatch and leaves the repo's set alone, while this one is
/// the repo's set and so is what the verification groups follow too.
///
/// BASE rather than any other alias, deliberately. It is neither the FIRST nor
/// the LAST network `supportedNetworks()` lists, and the deploy and the matrix
/// both leave the last network they walked selected — so a reader that ignored
/// this declaration and took the library's nine would end up on polygon, and one
/// that read the library's first entry would be on arbitrum. Neither reads as
/// base.
contract ExampleDeployNarrowNetworks is ExampleDeployScript {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        d.networks = new string[](1);
        d.networks[0] = LibRainDeploy.BASE;
        d.deployNetworks = LibRainDeployDeclaration.everyNetwork(d);
        LibRainDeployZoltuMechanism.extend(d);
        addExample(d);
        return d;
    }
}
