"use client";

import { useMemo } from "react";
import { useQuery } from "urql";

import { ProposalCard, type ProposalSummary } from "./ProposalCard";
import { PROPOSAL_STATE, useProposalStates, type ProposalState } from "@/hooks/useProposalState";
import { ACTIVE_PROPOSALS } from "@/lib/queries";

interface QueryResult {
  proposals: Array<{
    id: string;
    proposer: string;
    description: string;
    forVotes: string;
    againstVotes: string;
    abstainVotes: string;
    voteStart: string;
    voteEnd: string;
    eta: string | null;
    statusSnapshot: string;
  }>;
}

export function ProposalList() {
  const [{ data, fetching, error }] = useQuery<QueryResult>({ query: ACTIVE_PROPOSALS });

  const proposals: ProposalSummary[] = data?.proposals ?? [];

  const ids = useMemo(() => proposals.map((p) => BigInt(p.id)), [proposals]);
  const { states } = useProposalStates(ids);

  if (fetching) return <p className="text-sm text-neutral-400">Loading proposals…</p>;
  if (error)    return <p className="text-sm text-red-400">Subgraph error: {error.message}</p>;
  if (!proposals.length) {
    return (
      <div className="rounded-xl border border-neutral-800 bg-neutral-900 p-6 text-sm text-neutral-400">
        No active proposals right now. Anyone with ≥ 1% of the supply can propose one.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {proposals.map((p, idx) => {
        // Authoritative on-chain state via multicall; falls back to the
        // subgraph snapshot if the multicall is still pending or the
        // governor address isn't deployed yet.
        const onChain = states?.[idx];
        const snapshot = PROPOSAL_STATE.includes(p.statusSnapshot as ProposalState)
          ? (p.statusSnapshot as ProposalState)
          : "Unknown";
        const state: ProposalState | "Unknown" = onChain ?? snapshot;
        return <ProposalCard key={p.id} p={p} state={state} />;
      })}
    </div>
  );
}
