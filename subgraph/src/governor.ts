import { BigInt, log } from "@graphprotocol/graph-ts";

import {
  ProposalCreated,
  VoteCast,
  VoteCastWithParams,
  ProposalQueued,
  ProposalExecuted,
  ProposalCanceled,
} from "../generated/PredictionGovernor/PredictionGovernor";
import { Proposal, Vote } from "../generated/schema";

function loadProposal(proposalId: BigInt): Proposal | null {
  return Proposal.load(proposalId.toHex());
}

function supportToEnum(support: i32): string {
  if (support == 0) return "Against";
  if (support == 1) return "For";
  return "Abstain";
}

export function handleProposalCreated(event: ProposalCreated): void {
  let p = new Proposal(event.params.proposalId.toHex());
  p.governor = event.address;
  p.proposer = event.params.proposer;
  p.description = event.params.description;
  p.descriptionHash = event.params.proposalId.reverse();

  let targets = event.params.targets;
  let targetBytes: Array<Bytes> = [];
  for (let i = 0; i < targets.length; i++) {
    targetBytes.push(targets[i]);
  }
  p.targets = targetBytes;

  p.values = event.params.values;
  p.signatures = event.params.signatures;
  p.calldatas = event.params.calldatas;
  p.voteStart = event.params.voteStart;
  p.voteEnd = event.params.voteEnd;

  p.forVotes = BigInt.zero();
  p.againstVotes = BigInt.zero();
  p.abstainVotes = BigInt.zero();
  p.statusSnapshot = "Pending";
  p.eta = null;
  p.queuedAt = null;
  p.executedAt = null;
  p.canceledAt = null;
  p.createdAt = event.block.timestamp;
  p.createdAtBlock = event.block.number;

  p.save();
  log.info("Proposal {} created by {}", [p.id, event.params.proposer.toHexString()]);
}

export function handleVoteCast(event: VoteCast): void {
  recordVote(
    event.params.proposalId,
    event.params.voter,
    event.params.support,
    event.params.weight,
    event.params.reason,
    event.block.timestamp,
    event.block.number,
    event.transaction.hash.toHexString(),
    event.transaction.hash,
  );
}

export function handleVoteCastWithParams(event: VoteCastWithParams): void {
  recordVote(
    event.params.proposalId,
    event.params.voter,
    event.params.support,
    event.params.weight,
    event.params.reason,
    event.block.timestamp,
    event.block.number,
    event.transaction.hash.toHexString(),
    event.transaction.hash,
  );
}

function recordVote(
  proposalId: BigInt,
  voter: Bytes,
  support: i32,
  weight: BigInt,
  reason: string,
  ts: BigInt,
  block: BigInt,
  txHashHex: string,
  txHashBytes: Bytes,
): void {
  let p = loadProposal(proposalId);
  if (p === null) {
    log.warning("Vote on unknown proposal {}", [proposalId.toString()]);
    return;
  }

  let vid = proposalId.toHex() + "-" + voter.toHexString();
  let v = new Vote(vid);
  v.proposal = p.id;
  v.voter = voter;
  v.support = supportToEnum(support);
  v.weight = weight;
  v.reason = reason;
  v.timestamp = ts;
  v.blockNumber = block;
  v.transactionHash = txHashBytes;
  v.save();

  if (support == 0)      p.againstVotes = p.againstVotes.plus(weight);
  else if (support == 1) p.forVotes     = p.forVotes.plus(weight);
  else                   p.abstainVotes = p.abstainVotes.plus(weight);

  if (p.statusSnapshot == "Pending") p.statusSnapshot = "Active";
  p.save();
}

export function handleProposalQueued(event: ProposalQueued): void {
  let p = loadProposal(event.params.proposalId);
  if (p === null) return;
  p.statusSnapshot = "Queued";
  p.eta = event.params.eta;
  p.queuedAt = event.block.timestamp;
  p.save();
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  let p = loadProposal(event.params.proposalId);
  if (p === null) return;
  p.statusSnapshot = "Executed";
  p.executedAt = event.block.timestamp;
  p.save();
}

export function handleProposalCanceled(event: ProposalCanceled): void {
  let p = loadProposal(event.params.proposalId);
  if (p === null) return;
  p.statusSnapshot = "Canceled";
  p.canceledAt = event.block.timestamp;
  p.save();
}

import { Bytes } from "@graphprotocol/graph-ts";
