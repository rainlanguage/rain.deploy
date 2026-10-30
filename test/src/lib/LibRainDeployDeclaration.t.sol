// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeployMechanismHandler,
    DeploySuite,
    DuplicateMechanism,
    MechanismUnclaimed
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism, ZOLTU_MECHANISM_ID} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {LibMockCreate2Mechanism, MOCK_CREATE2_MECHANISM_ID} from "../../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism, MOCK_SALT_MECHANISM_ID} from "../../lib/LibMockSaltMechanism.sol";

contract LibRainDeployDeclarationTest is Test {
    function suiteNamed(string memory name, string[] memory networks) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: name,
            creationCode: "",
            storedDeployedAddress: address(0),
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: "",
            dependencies: new DeployDependency[](0),
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            networks: networks,
            describedByMeta: ""
        });
    }

    function twoNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = "alpha";
        networks[1] = "beta";
        return networks;
    }

    function oneNetwork(string memory network) internal pure returns (string[] memory) {
        string[] memory networks = new string[](1);
        networks[0] = network;
        return networks;
    }

    function assertNetworks(string[] memory actual, string[] memory expected, string memory message) internal pure {
        assertEq(actual.length, expected.length, message);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(actual[i], expected[i], message);
        }
    }

    function threeMechanisms() internal pure returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
        LibMockSaltMechanism.extend(d);
        return d;
    }

    function testExtendSetsEveryRainNetwork() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.setNetworks(d, oneNetwork("stale"));
        LibRainDeployDeclaration.extend(d);
        assertNetworks(d.networks, LibRainDeploy.supportedNetworks(), "networks");
        assertNetworks(d.deployNetworks, LibRainDeploy.supportedNetworks(), "deployNetworks");
        d.networks[0] = "changed";
        assertEq(d.deployNetworks[0], LibRainDeploy.supportedNetworks()[0], "deployNetworks aliases d.networks");
        assertEq(d.released.length, 0);
        assertEq(d.candidates.length, 0);
        assertEq(d.mechanisms.length, 0);
    }

    function testSetNetworksGivesBothListsTheirOwnCopy() external pure {
        DeployDeclaration memory d;
        string[] memory networks = twoNetworks();
        LibRainDeployDeclaration.setNetworks(d, networks);
        assertNetworks(d.networks, twoNetworks(), "networks");
        assertNetworks(d.deployNetworks, twoNetworks(), "deployNetworks");
        assertNetworks(networks, twoNetworks(), "caller's list");

        networks[0] = "caller";
        assertEq(d.networks[0], "alpha", "networks aliases the caller's list");
        assertEq(d.deployNetworks[0], "alpha", "deployNetworks aliases the caller's list");

        d.networks[1] = "networks";
        assertEq(d.deployNetworks[1], "beta", "deployNetworks aliases networks");
        d.deployNetworks[0] = "deployNetworks";
        assertEq(d.networks[0], "alpha", "networks aliases deployNetworks");
        assertEq(networks[1], "beta", "caller's list aliases networks");
    }

    function testSetDeployNetworksSetsOnlyAnOwnCopyOfDeployNetworks() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.setNetworks(d, twoNetworks());
        string[] memory deployNetworks = oneNetwork("beta");
        LibRainDeployDeclaration.setDeployNetworks(d, deployNetworks);
        assertNetworks(d.networks, twoNetworks(), "networks");
        assertNetworks(d.deployNetworks, oneNetwork("beta"), "deployNetworks");
        assertNetworks(deployNetworks, oneNetwork("beta"), "caller's list");
        assertEq(d.released.length, 0);
        assertEq(d.candidates.length, 0);
        assertEq(d.mechanisms.length, 0);
        assertEq(d.dispatchWorkflow, "");

        deployNetworks[0] = "caller";
        assertEq(d.deployNetworks[0], "beta", "deployNetworks aliases the caller's list");
    }

    function testNarrowingThroughSetNetworksLeavesNoStaleDeployNetworks() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployDeclaration.setNetworks(d, oneNetwork(LibRainDeploy.BASE));
        assertNetworks(d.networks, oneNetwork(LibRainDeploy.BASE), "networks");
        assertNetworks(d.deployNetworks, oneNetwork(LibRainDeploy.BASE), "deployNetworks");
        assertEq(d.dispatchWorkflow, LibRainDeployDeclaration.DISPATCH_WORKFLOW);
    }

    function testAddReleasedFillsUnsetNetworksWithAFreshCopy() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.setNetworks(d, twoNetworks());
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = suiteNamed("a", new string[](0));
        LibRainDeployDeclaration.addReleased(d, suites);

        assertEq(d.released.length, 1);
        assertNetworks(d.released[0].networks, twoNetworks(), "filled");
        assertEq(suites[0].networks.length, 0, "caller's suite filled");
        d.released[0].networks[0] = "mutated";
        assertEq(d.networks[0], "alpha", "fill aliases d.networks");
    }

    function testAddReleasedKeepsExplicitNetworks() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.setNetworks(d, twoNetworks());
        string[] memory own = oneNetwork("gamma");
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = suiteNamed("a", own);
        LibRainDeployDeclaration.addReleased(d, suites);

        assertNetworks(d.released[0].networks, oneNetwork("gamma"), "explicit");
        own[0] = "delta";
        assertEq(d.released[0].networks[0], "gamma", "explicit array aliased");
        assertNetworks(d.networks, twoNetworks(), "d.networks");
    }

    function testAddReleasedAppendsInOrder() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.setNetworks(d, twoNetworks());
        DeploySuite[] memory first = new DeploySuite[](1);
        first[0] = suiteNamed("a", new string[](0));
        LibRainDeployDeclaration.addReleased(d, first);
        DeploySuite[] memory second = new DeploySuite[](2);
        second[0] = suiteNamed("b", new string[](0));
        second[1] = suiteNamed("c", oneNetwork("gamma"));
        LibRainDeployDeclaration.addReleased(d, second);

        assertEq(d.released.length, 3);
        assertEq(d.released[0].suite, "a");
        assertEq(d.released[1].suite, "b");
        assertEq(d.released[2].suite, "c");
        assertEq(d.candidates.length, 0, "candidates touched");
    }

    function testAddReleasedFillsFromTheCurrentNetworks() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployDeclaration.setNetworks(d, oneNetwork("narrowed"));
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = suiteNamed("a", new string[](0));
        LibRainDeployDeclaration.addReleased(d, suites);
        assertNetworks(d.released[0].networks, oneNetwork("narrowed"), "narrowed");
    }

    function testAddCandidatesFillsUnsetNetworksWithAFreshCopy() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.setNetworks(d, twoNetworks());
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({snapshot: suiteNamed("a", new string[](0)), unanchorableReason: ""});
        string[] memory own = oneNetwork("gamma");
        candidates[1] = DeployCandidate({snapshot: suiteNamed("b", own), unanchorableReason: "why"});
        LibRainDeployDeclaration.addCandidates(d, candidates);

        assertEq(d.candidates.length, 2);
        assertEq(d.candidates[0].snapshot.suite, "a");
        assertEq(d.candidates[1].snapshot.suite, "b");
        assertEq(d.candidates[1].unanchorableReason, "why");
        assertNetworks(d.candidates[0].snapshot.networks, twoNetworks(), "filled");
        assertEq(candidates[0].snapshot.networks.length, 0, "caller's candidate filled");
        d.candidates[0].snapshot.networks[0] = "mutated";
        assertEq(d.networks[0], "alpha", "fill aliases d.networks");

        own[0] = "delta";
        assertEq(d.candidates[1].snapshot.networks[0], "gamma", "explicit array aliased");
        assertEq(d.released.length, 0, "released touched");
    }

    function testAddCandidatesAppendsInOrder() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.setNetworks(d, twoNetworks());
        DeployCandidate[] memory first = new DeployCandidate[](1);
        first[0] = DeployCandidate({snapshot: suiteNamed("a", new string[](0)), unanchorableReason: ""});
        LibRainDeployDeclaration.addCandidates(d, first);
        DeployCandidate[] memory second = new DeployCandidate[](1);
        second[0] = DeployCandidate({snapshot: suiteNamed("b", new string[](0)), unanchorableReason: ""});
        LibRainDeployDeclaration.addCandidates(d, second);

        assertEq(d.candidates.length, 2);
        assertEq(d.candidates[0].snapshot.suite, "a");
        assertEq(d.candidates[1].snapshot.suite, "b");
    }

    function testZoltuExtendAppendsTheZoltuHandler() external pure {
        DeployDeclaration memory d;
        LibMockSaltMechanism.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        assertEq(d.mechanisms.length, 2);
        assertEq(d.mechanisms[0].id, MOCK_SALT_MECHANISM_ID);
        assertEq(d.mechanisms[1].id, ZOLTU_MECHANISM_ID);
        assertEq(d.networks.length, 0, "networks touched");
    }

    function externalAddCreate2ToThreeMechanisms() external pure {
        DeployDeclaration memory d = threeMechanisms();
        LibRainDeployDeclaration.addMechanism(d, LibMockCreate2Mechanism.handler());
    }

    function externalMechanismByIdInThreeMechanisms(bytes32 id) external pure returns (bytes32) {
        return LibRainDeployDeclaration.mechanismById(threeMechanisms(), id, "subject").id;
    }

    function externalMechanismByIdInEmptyDeclaration(bytes32 id) external pure returns (bytes32) {
        DeployDeclaration memory d;
        return LibRainDeployDeclaration.mechanismById(d, id, "subject").id;
    }

    function externalMechanismByIdWithRepeatedSalt(bytes32 id) external pure returns (bytes32) {
        DeployDeclaration memory d;
        d.mechanisms = new DeployMechanismHandler[](3);
        d.mechanisms[0] = LibRainDeployZoltuMechanism.handler();
        d.mechanisms[1] = LibMockSaltMechanism.handler();
        d.mechanisms[2] = LibMockSaltMechanism.handler();
        return LibRainDeployDeclaration.mechanismById(d, id, "subject").id;
    }

    function testAddMechanismRefusesARepeatedId() external {
        vm.expectRevert(abi.encodeWithSelector(DuplicateMechanism.selector, MOCK_CREATE2_MECHANISM_ID));
        this.externalAddCreate2ToThreeMechanisms();
    }

    function testMechanismByIdFindsEachIdInAnyOrder() external pure {
        DeployDeclaration memory d = threeMechanisms();
        bytes32[3] memory ids = [ZOLTU_MECHANISM_ID, MOCK_CREATE2_MECHANISM_ID, MOCK_SALT_MECHANISM_ID];
        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(LibRainDeployDeclaration.mechanismById(d, ids[i], "subject").id, ids[i]);
        }

        DeployMechanismHandler[] memory reversed = new DeployMechanismHandler[](3);
        reversed[0] = d.mechanisms[2];
        reversed[1] = d.mechanisms[1];
        reversed[2] = d.mechanisms[0];
        d.mechanisms = reversed;
        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(LibRainDeployDeclaration.mechanismById(d, ids[i], "subject").id, ids[i]);
        }
    }

    function testMechanismByIdRefusesAnUnclaimedId() external {
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, "subject"));
        this.externalMechanismByIdInThreeMechanisms(keccak256("unclaimed"));
    }

    function testMechanismByIdRefusesAnEmptyDeclaration() external {
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, "subject"));
        this.externalMechanismByIdInEmptyDeclaration(ZOLTU_MECHANISM_ID);
    }

    function testMechanismByIdRefusesARepeatedIdEvenWhenTheRequestedIdIsUnique() external {
        vm.expectRevert(abi.encodeWithSelector(DuplicateMechanism.selector, MOCK_SALT_MECHANISM_ID));
        this.externalMechanismByIdWithRepeatedSalt(ZOLTU_MECHANISM_ID);
    }
}
