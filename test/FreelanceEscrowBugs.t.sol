// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FreelanceEscrow} from "../src/FreelanceEscrow.sol";

/// @notice Regression tests for two accounting bugs that used to exist:
/// 1. cancel / approve / resolve paid the full job amount even after milestones
///    had already been paid, draining other jobs' funds.
/// 2. Paying every existing milestone completed the job even when they summed to
///    less than the job amount, which stranded the remainder.
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

    function _status(uint256 jobId) internal view returns (FreelanceEscrow.JobStatus status) {
        (,,,, status) = escrow.jobs(jobId);
    }

    /// Job 0 has two 0.5 ether milestones, the first one is paid.
    function _jobWithOneMilestonePaid() internal {
        vm.prank(client);
        escrow.createJob{value: 1 ether}(freelancer, "Job 0");

        vm.startPrank(client);
        escrow.addMilestone(0, "A", 0.5 ether);
        escrow.addMilestone(0, "B", 0.5 ether);
        vm.stopPrank();

        vm.prank(freelancer);
        escrow.completeMilestone(0, 0);

        vm.prank(client);
        escrow.approveMilestone(0, 0);
    }

    function testCancelAfterMilestoneRefundsOnlyRemainder() public {
        _jobWithOneMilestonePaid();

        // Another client's job is also sitting in escrow.
        vm.prank(client2);
        escrow.createJob{value: 1 ether}(freelancer, "Job 1");

        vm.prank(client);
        escrow.cancelJob(0);

        // Client gets back only the unpaid 0.5 ether, not the full 1 ether.
        assertEq(client.balance, 9.5 ether);
        assertEq(freelancer.balance, 0.5 ether);

        // Job 1's funds are untouched, so its client can still cancel.
        assertEq(address(escrow).balance, 1 ether);

        vm.prank(client2);
        escrow.cancelJob(1);

        assertEq(client2.balance, 10 ether);
        assertEq(address(escrow).balance, 0);
    }

    function testApproveJobAfterMilestonePaysOnlyRemainder() public {
        _jobWithOneMilestonePaid();

        vm.prank(freelancer);
        escrow.markDelivered(0);

        vm.prank(client);
        escrow.approveJob(0);

        // 0.5 via milestone + 0.5 remainder = exactly the job amount.
        assertEq(freelancer.balance, 1 ether);
        assertEq(address(escrow).balance, 0);
        assertEq(uint256(_status(0)), uint256(FreelanceEscrow.JobStatus.Completed));
    }

    function testResolveDisputeAfterMilestonePaysOnlyRemainder() public {
        _jobWithOneMilestonePaid();

        vm.prank(client);
        escrow.openDispute(0);

        vm.prank(arbitrator);
        escrow.resolveDispute(0, true);

        assertEq(freelancer.balance, 1 ether);
        assertEq(address(escrow).balance, 0);
    }

    function testResolveDisputeRefundAfterMilestoneRefundsOnlyRemainder() public {
        _jobWithOneMilestonePaid();

        vm.prank(client);
        escrow.openDispute(0);

        vm.prank(arbitrator);
        escrow.resolveDispute(0, false);

        assertEq(freelancer.balance, 0.5 ether);
        assertEq(client.balance, 9.5 ether);
        assertEq(address(escrow).balance, 0);
    }

    function testRemainderNotStrandedWhenMilestonesBelowJobAmount() public {
        vm.prank(client);
        escrow.createJob{value: 1 ether}(freelancer, "Job 0");

        vm.prank(client);
        escrow.addMilestone(0, "A", 0.5 ether);

        vm.prank(freelancer);
        escrow.completeMilestone(0, 0);

        vm.prank(client);
        escrow.approveMilestone(0, 0);

        // Job stays open because only half of the amount has been released.
        assertEq(uint256(_status(0)), uint256(FreelanceEscrow.JobStatus.Created));
        assertEq(address(escrow).balance, 0.5 ether);

        // The remainder can still be released normally.
        vm.prank(freelancer);
        escrow.markDelivered(0);

        vm.prank(client);
        escrow.approveJob(0);

        assertEq(freelancer.balance, 1 ether);
        assertEq(address(escrow).balance, 0);
    }
}
