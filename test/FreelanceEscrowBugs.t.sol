// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FreelanceEscrow} from "../src/FreelanceEscrow.sol";

/// @notice Proof-of-concept tests. They PASS on the current contract because they
/// assert the buggy behaviour. After you fix the contract, flip the assertions
/// (or delete these tests).
contract FreelanceEscrowBugsTest is Test {
    FreelanceEscrow escrow;

    address client = address(1);
    address freelancer = address(2);
    address arbitrator = address(3);
    address client2 = address(5);

    function setUp() public {
        escrow = new FreelanceEscrow(arbitrator);

        vm.deal(client, 10 ether);
        vm.deal(client2, 10 ether);
    }

    /// Bug 1: milestones are paid out of the job's escrow, but cancelJob (and
    /// approveJob / resolveDispute) still pay out the FULL job.amount. The
    /// difference is taken from other jobs' funds, so the contract becomes insolvent.
    function testBug_CancelAfterMilestonePaidDrainsOtherJobs() public {
        // Job 0: client, 1 ether. Job 1: client2, 1 ether.
        vm.prank(client);
        escrow.createJob{value: 1 ether}(freelancer, "Job 0");
        vm.prank(client2);
        escrow.createJob{value: 1 ether}(freelancer, "Job 1");

        // Two milestones so that paying one does not flip the job to Completed.
        vm.startPrank(client);
        escrow.addMilestone(0, "A", 0.5 ether);
        escrow.addMilestone(0, "B", 0.5 ether);
        vm.stopPrank();

        vm.prank(freelancer);
        escrow.completeMilestone(0, 0);

        vm.prank(client);
        escrow.approveMilestone(0, 0); // freelancer receives 0.5 ether

        // Client now cancels and is refunded the FULL 1 ether.
        vm.prank(client);
        escrow.cancelJob(0);

        // Escrow holds 0.5 ether, but job 1 is owed 1 ether.
        assertEq(address(escrow).balance, 0.5 ether);

        vm.prank(client2);
        vm.expectRevert("Refund failed");
        escrow.cancelJob(1);
    }

    /// Bug 2: when every EXISTING milestone is paid the job becomes Completed, even
    /// if the milestones sum to less than job.amount. The remainder is stuck forever.
    function testBug_RemainderStrandedWhenMilestonesSumBelowJobAmount() public {
        vm.prank(client);
        escrow.createJob{value: 1 ether}(freelancer, "Job 0");

        vm.prank(client);
        escrow.addMilestone(0, "A", 0.5 ether);

        vm.prank(freelancer);
        escrow.completeMilestone(0, 0);

        vm.prank(client);
        escrow.approveMilestone(0, 0);

        (,,,, FreelanceEscrow.JobStatus status) = escrow.jobs(0);
        assertEq(uint256(status), uint256(FreelanceEscrow.JobStatus.Completed));
        assertEq(address(escrow).balance, 0.5 ether);

        // No function can release the remaining 0.5 ether.
        vm.prank(client);
        vm.expectRevert("Job cannot be cancelled");
        escrow.cancelJob(0);

        vm.prank(client);
        vm.expectRevert("Job not delivered");
        escrow.approveJob(0);

        vm.prank(client);
        vm.expectRevert("Cannot dispute this job");
        escrow.openDispute(0);
    }
}
