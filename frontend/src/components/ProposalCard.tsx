"use client";

import { useState } from "react";
import type { Hash } from "viem";
import { useWriteContract } from "wagmi";

import { TxButton } from "./TxButton";
import { governorAbi } from "@/lib/abi";
import { addresses } from "@/lib/addresses";
import type { ProposalState } from "@/hooks/useProposalState";

export interface ProposalSummary {
  id: string;                // proposalId hex
  proposer: string;
  description: string;
  forVotes: string;
  againstVotes: string;
  abstainVotes: string;
  voteStart: string;
  voteEnd: string;
  eta: string | null;
}

const STATE_CLASS: Record<ProposalState | "Unknown", string> = {
  Pending:   "bg-state-pending text-neutral-900",
  Active:    "bg-state-active   text-white",
  Canceled:  "bg-state-canceled text-white",
  Defeated:  "bg-state-defeated text-white",
  Succeeded: "bg-state-succeeded text-white",
  Queued:    "bg-state-queued   text-neutral-900",
  Expired:   "bg-state-expired  text-neutral-900",
  Executed:  "bg-state-executed text-white",
  Unknown:   "bg-neutral-700    text-neutral-100",
};

interface Props {
  p: ProposalSummary;
  state: ProposalState | "Unknown";
}

export function ProposalCard({ p, state }: Props) {
  const [support, setSupport] = useState<0 | 1 | 2>(1);  // default For
  const [reason, setReason] = useState("");
  const { writeContractAsync, data: hash, error } = useWriteContract();

  const canVote = state === "Active";

  const submitVote = async (): Promise<Hash | undefined> => {
    return writeContractAsync({
      address: addresses.governor,
      abi: governorAbi,
      functionName: "castVoteWithReason",
      args: [BigInt(p.id), support, reason],
    });
  };

  return (
    <article className="space-y-4 rounded-xl border border-neutral-800 bg-neutral-900 p-5">
      <header className="flex items-start justify-between gap-4">
        <div>
          <h3 className="text-base font-semibold text-neutral-100">
            {p.description.split("\n")[0].slice(0, 120) || `Proposal ${p.id.slice(0, 10)}…`}
          </h3>
          <p className="mt-1 text-xs text-neutral-500">
            proposer <code className="font-mono">{p.proposer.slice(0, 10)}…</code>
            {p.eta ? <> · queued for execution at {p.eta}</> : null}
          </p>
        </div>
        <span className={`rounded-md px-2 py-1 text-xs font-medium ${STATE_CLASS[state]}`}>
          {state}
        </span>
      </header>

      <dl className="grid grid-cols-3 gap-3 text-xs text-neutral-300">
        <div>
          <dt className="text-neutral-500">For</dt>
          <dd className="font-mono">{p.forVotes}</dd>
        </div>
        <div>
          <dt className="text-neutral-500">Against</dt>
          <dd className="font-mono">{p.againstVotes}</dd>
        </div>
        <div>
          <dt className="text-neutral-500">Abstain</dt>
          <dd className="font-mono">{p.abstainVotes}</dd>
        </div>
      </dl>

      {canVote ? (
        <div className="space-y-3 rounded-md bg-neutral-950 p-3">
          <div className="flex items-center gap-2">
            {([0, 1, 2] as const).map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => setSupport(s)}
                className={`flex-1 rounded-md px-2 py-1 text-xs ${
                  support === s ? "bg-emerald-500 text-emerald-950" : "bg-neutral-800 text-neutral-300"
                }`}
              >
                {s === 0 ? "Against" : s === 1 ? "For" : "Abstain"}
              </button>
            ))}
          </div>
          <input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Reason (optional)"
            className="w-full rounded-md border border-neutral-700 bg-neutral-950 px-3 py-2 text-sm text-neutral-100"
          />
          <TxButton label="Cast vote" onSubmit={submitVote} hash={hash} error={error} />
        </div>
      ) : (
        <p className="text-xs text-neutral-500">
          Voting is only open while the proposal is <strong>Active</strong>.
        </p>
      )}
    </article>
  );
}
