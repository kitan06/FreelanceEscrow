// SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {FreelanceEscrow} from "../src/FreelanceEscrow.sol";

contract FreelanceEscrowTest is Test {
    FreelanceEscrow escrow;

    address client = address(1);
    address freelancer = address(2);
    address arbitrator = address(3);

    function setUp() public {
        escrow = new FreelanceEscrow(arbitrator);

        vm.deal(client, 10 ether);
        vm.deal(freelancer, 1 ether);
        vm.deal(arbitrator, 1 ether);
    }

    function testCreateJob() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");
    }

    function testCompleteJobAndPayFreelancer() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        vm.prank(freelancer);

        escrow.markDelivered(0);

        vm.prank(client);

        escrow.approveJob(0);

        assertEq(freelancer.balance, 2 ether);
        assertEq(address(escrow).balance, 0);

        assertEq(escrow.jobCount(), 1);

        (
            address jobClient,
            address jobFreelancer,
            string memory description,
            uint256 amount,
            FreelanceEscrow.JobStatus status
        ) = escrow.jobs(0);

        assertEq(jobClient, client);
        assertEq(jobFreelancer, freelancer);
        assertEq(description, "Build a website");
        assertEq(amount, 1 ether);

        assertEq(uint256(status), uint256(FreelanceEscrow.JobStatus.Completed));
        assertEq(address(escrow).balance, 0 ether);
    }

    function testDisputeAndRefundClient() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        vm.prank(client);

        escrow.openDispute(0);

        vm.prank(arbitrator);

        escrow.resolveDispute(0, false);

        assertEq(client.balance, 10 ether);
        assertEq(address(escrow).balance, 0);
    }

    function testDisputeAndPayFreelancer() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        vm.prank(freelancer);

        escrow.markDelivered(0);

        vm.prank(client);

        escrow.openDispute(0);

        vm.prank(arbitrator);

        escrow.resolveDispute(0, true);

        assertEq(freelancer.balance, 2 ether);
        assertEq(address(escrow).balance, 0);
    }

    function testCannotDeliverNonexistentJob() public {
        vm.expectRevert("Job does not exist");
        escrow.markDelivered(999);
    }

    function testMilestonePayment() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        vm.prank(client);
        escrow.addMilestone(0, "Design homepage", 0.5 ether);

        vm.prank(freelancer);
        escrow.completeMilestone(0, 0);

        vm.prank(client);
        escrow.approveMilestone(0, 0);

        assertEq(freelancer.balance, 1.5 ether);
        assertEq(address(escrow).balance, 0.5 ether);
    }

    function testCannotCreateMilestonesAboveJobAmount() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        vm.prank(client);

        vm.expectRevert("Milestones exceed job amount");

        escrow.addMilestone(0, "Extra work", 1.1 ether);
    }

    function testOnlyClientCanAddMilestone() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        vm.prank(freelancer);

        vm.expectRevert("Only client can add");

        escrow.addMilestone(0, "Design homepage", 0.5 ether);
    }

    function testOnlyFreelancerCanCompleteMilestone() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        vm.prank(client);

        escrow.addMilestone(0, "Design homepage", 0.5 ether);

        vm.prank(client);

        vm.expectRevert("Only freelancer can complete");

        escrow.completeMilestone(0, 0);
    }

    function testOnlyClientCanApproveMilestone() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        vm.prank(client);

        escrow.addMilestone(0, "Design homepage", 0.5 ether);

        vm.prank(freelancer);

        escrow.completeMilestone(0, 0);

        vm.prank(freelancer);

        vm.expectRevert("Only client can approve");

        escrow.approveMilestone(0, 0);
    }

    function testCannotPayMilestoneTwice() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        vm.prank(client);

        escrow.addMilestone(0, "Design homepage", 0.5 ether);

        vm.prank(freelancer);

        escrow.completeMilestone(0, 0);

        // First payment
        vm.prank(client);

        escrow.approveMilestone(0, 0);

        // Try to pay the same milestone again
        vm.prank(client);

        vm.expectRevert("Milestone already paid");

        escrow.approveMilestone(0, 0);
    }

    function testClientCanCancelJob() public {
        vm.prank(client);

        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        uint256 jobId = escrow.jobCount() - 1;

        uint256 clientBalanceBefore = client.balance;

        vm.prank(client);
        escrow.cancelJob(jobId);

        assertEq(client.balance, clientBalanceBefore + 1 ether);

        (,,,, FreelanceEscrow.JobStatus status) = escrow.jobs(jobId);

        assertEq(uint256(status), uint256(FreelanceEscrow.JobStatus.Refunded));
    }

    function testOnlyClientCanCancelJob() public {
        escrow.createJob{value: 1 ether}(freelancer, "Build a website");

        uint256 jobId = escrow.jobCount() - 1;

        vm.prank(freelancer);

        vm.expectRevert("Only client can cancel");

        escrow.cancelJob(jobId);
    }
}
