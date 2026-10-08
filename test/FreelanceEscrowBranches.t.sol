// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FreelanceEscrow} from "../src/FreelanceEscrow.sol";

/// @dev No receive/fallback, so any ETH sent to it reverts.
contract EtherRejecter {}

contract FreelanceEscrowBranchTest is Test {
    FreelanceEscrow escrow;

    address client = address(1);
    address freelancer = address(2);
    address arbitrator = address(3);
    address stranger = address(4);
    address rejecter;

    function setUp() public {
        escrow = new FreelanceEscrow(arbitrator);
        rejecter = address(new EtherRejecter());

        vm.deal(client, 10 ether);
        vm.deal(freelancer, 1 ether);
        vm.deal(arbitrator, 1 ether);
        vm.deal(rejecter, 10 ether);
    }

    // =========================
    // HELPERS
    // =========================

    function _createJob(address _client, address _freelancer) internal returns (uint256 jobId) {
        vm.prank(_client);
        escrow.createJob{value: 1 ether}(_freelancer, "Build a website");
        jobId = escrow.jobCount() - 1;
    }

    function _status(uint256 jobId) internal view returns (FreelanceEscrow.JobStatus status) {
        (,,,, status) = escrow.jobs(jobId);
    }

    // =========================
    // CONSTRUCTOR
    // =========================

    function testConstructorRejectsZeroArbitrator() public {
        vm.expectRevert("Invalid arbitrator");
        new FreelanceEscrow(address(0));
    }

    // =========================
    // createJob
    // =========================

    function testCannotCreateJobWithZeroFreelancer() public {
        vm.prank(client);
        vm.expectRevert("Invalid freelancer");
        escrow.createJob{value: 1 ether}(address(0), "Build a website");
    }

    function testCannotCreateJobWithZeroPayment() public {
        vm.prank(client);
        vm.expectRevert("Payment must be greater than zero");
        escrow.createJob{value: 0}(freelancer, "Build a website");
    }

    // =========================
    // markDelivered
    // =========================

    function testOnlyFreelancerCanDeliver() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        vm.expectRevert("Only freelancer can deliver");
        escrow.markDelivered(id);
    }

    function testCannotDeliverTwice() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(freelancer);
        escrow.markDelivered(id);

        vm.prank(freelancer);
        vm.expectRevert("Job is not active");
        escrow.markDelivered(id);
    }

    // =========================
    // cancelJob
    // =========================

    function testCannotCancelDeliveredJob() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(freelancer);
        escrow.markDelivered(id);

        vm.prank(client);
        vm.expectRevert("Job cannot be cancelled");
        escrow.cancelJob(id);
    }

    function testCancelRefundFailureReverts() public {
        uint256 id = _createJob(rejecter, freelancer);

        vm.prank(rejecter);
        vm.expectRevert("Refund failed");
        escrow.cancelJob(id);
    }

    // =========================
    // approveJob
    // =========================

    function testOnlyClientCanApproveJob() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(freelancer);
        escrow.markDelivered(id);

        vm.prank(freelancer);
        vm.expectRevert("Only client can approve");
        escrow.approveJob(id);
    }

    function testCannotApproveUndeliveredJob() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        vm.expectRevert("Job not delivered");
        escrow.approveJob(id);
    }

    function testApproveJobPaymentFailureReverts() public {
        uint256 id = _createJob(client, rejecter);

        vm.prank(rejecter);
        escrow.markDelivered(id);

        vm.prank(client);
        vm.expectRevert("Payment failed");
        escrow.approveJob(id);
    }

    // =========================
    // openDispute
    // =========================

    function testFreelancerCanOpenDispute() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(freelancer);
        escrow.openDispute(id);

        assertEq(uint256(_status(id)), uint256(FreelanceEscrow.JobStatus.Disputed));
    }

    function testStrangerCannotOpenDispute() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(stranger);
        vm.expectRevert("Only parties can dispute");
        escrow.openDispute(id);
    }

    function testCannotDisputeTwice() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        escrow.openDispute(id);

        vm.prank(client);
        vm.expectRevert("Cannot dispute this job");
        escrow.openDispute(id);
    }

    // =========================
    // resolveDispute
    // =========================

    function testOnlyArbitratorCanResolve() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        escrow.openDispute(id);

        vm.prank(client);
        vm.expectRevert("Only arbitrator can resolve");
        escrow.resolveDispute(id, true);
    }

    function testCannotResolveUndisputedJob() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(arbitrator);
        vm.expectRevert("Job is not disputed");
        escrow.resolveDispute(id, true);
    }

    function testResolveDisputePayFreelancerFailureReverts() public {
        uint256 id = _createJob(client, rejecter);

        vm.prank(client);
        escrow.openDispute(id);

        vm.prank(arbitrator);
        vm.expectRevert("Payment failed");
        escrow.resolveDispute(id, true);
    }

    function testResolveDisputeRefundFailureReverts() public {
        uint256 id = _createJob(rejecter, freelancer);

        vm.prank(rejecter);
        escrow.openDispute(id);

        vm.prank(arbitrator);
        vm.expectRevert("Refund failed");
        escrow.resolveDispute(id, false);
    }

    // =========================
    // addMilestone
    // =========================

    function testCannotAddMilestoneAfterDelivery() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(freelancer);
        escrow.markDelivered(id);

        vm.prank(client);
        vm.expectRevert("Job already started");
        escrow.addMilestone(id, "Late milestone", 0.5 ether);
    }

    function testCannotAddZeroAmountMilestone() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        vm.expectRevert("Amount must be greater than zero");
        escrow.addMilestone(id, "Free work", 0);
    }

    function testMilestonesCanSumToExactJobAmountButNotOneWeiMore() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        escrow.addMilestone(id, "A", 0.5 ether);

        vm.prank(client);
        escrow.addMilestone(id, "B", 0.5 ether);

        assertEq(escrow.milestoneTotal(id), 1 ether);

        vm.prank(client);
        vm.expectRevert("Milestones exceed job amount");
        escrow.addMilestone(id, "C", 1);
    }

    // =========================
    // completeMilestone
    // =========================

    function testCannotCompleteNonexistentMilestone() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(freelancer);
        vm.expectRevert("Milestone does not exist");
        escrow.completeMilestone(id, 0);
    }

    function testCannotCompleteMilestoneTwice() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        escrow.addMilestone(id, "A", 0.5 ether);

        vm.prank(freelancer);
        escrow.completeMilestone(id, 0);

        vm.prank(freelancer);
        vm.expectRevert("Milestone already completed");
        escrow.completeMilestone(id, 0);
    }

    function testCannotCompleteMilestoneWhenJobNotActive() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        escrow.addMilestone(id, "A", 0.5 ether);

        vm.prank(client);
        escrow.cancelJob(id);

        vm.prank(freelancer);
        vm.expectRevert("Job not active");
        escrow.completeMilestone(id, 0);
    }

    // =========================
    // approveMilestone
    // =========================

    function testCannotApproveNonexistentMilestone() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        vm.expectRevert("Milestone does not exist");
        escrow.approveMilestone(id, 0);
    }

    function testCannotApproveMilestoneWhenJobNotActive() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        escrow.addMilestone(id, "A", 0.5 ether);

        vm.prank(freelancer);
        escrow.completeMilestone(id, 0);

        vm.prank(client);
        escrow.openDispute(id);

        vm.prank(client);
        vm.expectRevert("Job not active");
        escrow.approveMilestone(id, 0);
    }

    function testCannotApproveIncompleteMilestone() public {
        uint256 id = _createJob(client, freelancer);

        vm.prank(client);
        escrow.addMilestone(id, "A", 0.5 ether);

        vm.prank(client);
        vm.expectRevert("Milestone not completed");
        escrow.approveMilestone(id, 0);
    }

    function testApproveMilestonePaymentFailureReverts() public {
        uint256 id = _createJob(client, rejecter);

        vm.prank(client);
        escrow.addMilestone(id, "A", 0.5 ether);

        vm.prank(rejecter);
        escrow.completeMilestone(id, 0);

        vm.prank(client);
        vm.expectRevert("Payment failed");
        escrow.approveMilestone(id, 0);
    }

    function testJobCompletesOnlyAfterAllMilestonesPaid() public {
        uint256 id = _createJob(client, freelancer);

        vm.startPrank(client);
        escrow.addMilestone(id, "A", 0.4 ether);
        escrow.addMilestone(id, "B", 0.6 ether);
        vm.stopPrank();

        vm.startPrank(freelancer);
        escrow.completeMilestone(id, 0);
        escrow.completeMilestone(id, 1);
        vm.stopPrank();

        // First approval: only part of the job amount released -> job stays open
        vm.prank(client);
        escrow.approveMilestone(id, 0);
        assertEq(uint256(_status(id)), uint256(FreelanceEscrow.JobStatus.Created));

        // Second approval: full job amount released -> job completes
        vm.prank(client);
        escrow.approveMilestone(id, 1);
        assertEq(uint256(_status(id)), uint256(FreelanceEscrow.JobStatus.Completed));

        assertEq(freelancer.balance, 2 ether);
        assertEq(address(escrow).balance, 0);
    }
}
