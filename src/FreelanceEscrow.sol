// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract FreelanceEscrow is ReentrancyGuard {
    address public arbitrator;

    constructor(address _arbitrator) {
        require(_arbitrator != address(0), "Invalid arbitrator");
        arbitrator = _arbitrator;
    }

    enum JobStatus {
        Created,
        Delivered,
        Completed,
        Disputed,
        Refunded
    }

    struct Job {
        address client;
        address freelancer;
        string description;
        uint256 amount;
        JobStatus status;
    }

    struct Milestone {
        string description;
        uint256 amount;
        bool completed;
        bool paid;
    }

    uint256 public jobCount;

    mapping(uint256 => Job) public jobs;

    mapping(uint256 => Milestone[]) public jobMilestones;

    mapping(uint256 => uint256) public milestoneTotal;

    // Amount already paid out to the freelancer through milestones, per job
    mapping(uint256 => uint256) public released;

    modifier jobExists(uint256 _jobId) {
        require(_jobId < jobCount, "Job does not exist");
        _;
    }

    // =========================
    // EVENTS
    // =========================

    event JobCreated(uint256 indexed jobId, address indexed client, address indexed freelancer, uint256 amount);

    event JobDelivered(uint256 indexed jobId);

    event JobCancelled(uint256 indexed jobId);

    event JobCompleted(uint256 indexed jobId);

    event DisputeOpened(uint256 indexed jobId);

    event DisputeResolved(uint256 indexed jobId, bool paidFreelancer);

    // =========================
    // CREATE JOB
    // =========================

    function createJob(address _freelancer, string memory _description) external payable {
        require(_freelancer != address(0), "Invalid freelancer");

        require(msg.value > 0, "Payment must be greater than zero");

        jobs[jobCount] = Job({
            client: msg.sender,
            freelancer: _freelancer,
            description: _description,
            amount: msg.value,
            status: JobStatus.Created
        });

        emit JobCreated(jobCount, msg.sender, _freelancer, msg.value);

        jobCount++;
    }

    // =========================
    // MARK JOB AS DELIVERED
    // =========================

    function markDelivered(uint256 _jobId) external jobExists(_jobId) {
        Job storage job = jobs[_jobId];

        require(msg.sender == job.freelancer, "Only freelancer can deliver");

        require(job.status == JobStatus.Created, "Job is not active");

        job.status = JobStatus.Delivered;

        emit JobDelivered(_jobId);
    }

    function cancelJob(uint256 _jobId) external nonReentrant jobExists(_jobId) {
        Job storage job = jobs[_jobId];

        require(msg.sender == job.client, "Only client can cancel");

        require(job.status == JobStatus.Created, "Job cannot be cancelled");

        job.status = JobStatus.Refunded;

        uint256 refund = job.amount - released[_jobId];

        (bool success,) = payable(job.client).call{value: refund}("");

        require(success, "Refund failed");

        emit JobCancelled(_jobId);
    }

    // =========================
    // APPROVE JOB
    // =========================

    function approveJob(uint256 _jobId) external nonReentrant jobExists(_jobId) {
        Job storage job = jobs[_jobId];

        require(msg.sender == job.client, "Only client can approve");

        require(job.status == JobStatus.Delivered, "Job not delivered");

        job.status = JobStatus.Completed;

        emit JobCompleted(_jobId);

        uint256 payout = job.amount - released[_jobId];

        (bool success,) = payable(job.freelancer).call{value: payout}("");

        require(success, "Payment failed");
    }

    // =========================
    // OPEN DISPUTE
    // =========================

    function openDispute(uint256 _jobId) external jobExists(_jobId) {
        Job storage job = jobs[_jobId];

        require(msg.sender == job.client || msg.sender == job.freelancer, "Only parties can dispute");

        require(job.status == JobStatus.Created || job.status == JobStatus.Delivered, "Cannot dispute this job");

        job.status = JobStatus.Disputed;

        emit DisputeOpened(_jobId);
    }

    // =========================
    // RESOLVE DISPUTE
    // =========================

    function resolveDispute(uint256 _jobId, bool _payFreelancer) external nonReentrant jobExists(_jobId) {
        Job storage job = jobs[_jobId];

        require(msg.sender == arbitrator, "Only arbitrator can resolve");

        require(job.status == JobStatus.Disputed, "Job is not disputed");

        uint256 remaining = job.amount - released[_jobId];

        if (_payFreelancer) {
            job.status = JobStatus.Completed;

            (bool success,) = payable(job.freelancer).call{value: remaining}("");

            require(success, "Payment failed");
        } else {
            job.status = JobStatus.Refunded;

            (bool success,) = payable(job.client).call{value: remaining}("");

            require(success, "Refund failed");
        }

        emit DisputeResolved(_jobId, _payFreelancer);
    }

    // =========================
    // ADD MILESTONE
    // =========================

    function addMilestone(uint256 _jobId, string memory _description, uint256 _amount) external jobExists(_jobId) {
        Job storage job = jobs[_jobId];

        require(msg.sender == job.client, "Only client can add");

        require(job.status == JobStatus.Created, "Job already started");

        require(_amount > 0, "Amount must be greater than zero");

        require(milestoneTotal[_jobId] + _amount <= job.amount, "Milestones exceed job amount");

        jobMilestones[_jobId].push(
            Milestone({description: _description, amount: _amount, completed: false, paid: false})
        );

        milestoneTotal[_jobId] += _amount;
    }

    // =========================
    // COMPLETE MILESTONE
    // =========================

    function completeMilestone(uint256 _jobId, uint256 _milestoneId) external jobExists(_jobId) {
        Job storage job = jobs[_jobId];

        require(msg.sender == job.freelancer, "Only freelancer can complete");

        require(job.status == JobStatus.Created || job.status == JobStatus.Delivered, "Job not active");

        require(_milestoneId < jobMilestones[_jobId].length, "Milestone does not exist");

        Milestone storage milestone = jobMilestones[_jobId][_milestoneId];

        require(!milestone.completed, "Milestone already completed");

        milestone.completed = true;
    }

    // =========================
    // APPROVE MILESTONE
    // =========================

    function approveMilestone(uint256 _jobId, uint256 _milestoneId) external nonReentrant jobExists(_jobId) {
        Job storage job = jobs[_jobId];

        require(msg.sender == job.client, "Only client can approve");

        require(job.status == JobStatus.Created || job.status == JobStatus.Delivered, "Job not active");

        require(_milestoneId < jobMilestones[_jobId].length, "Milestone does not exist");

        Milestone storage milestone = jobMilestones[_jobId][_milestoneId];

        require(milestone.completed, "Milestone not completed");

        require(!milestone.paid, "Milestone already paid");

        milestone.paid = true;

        released[_jobId] += milestone.amount;

        if (released[_jobId] == job.amount) {
            job.status = JobStatus.Completed;
        }

        (bool success,) = payable(job.freelancer).call{value: milestone.amount}("");

        require(success, "Payment failed");
    }
}
