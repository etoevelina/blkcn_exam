"use client";

// =============================================================================
// useProposalState
//
// Reads `governor.state(proposalId)` for each provided proposalId via
// wagmi's multicall under the hood. This is the *authoritative* source of
// proposal state — the subgraph cache only seeds the list, but a
// proposal might have crossed e.g. Active → Defeated since the last
// indexer block.
// =============================================================================

import { useMemo } from "react";
import { useReadContracts } from "wagmi";

import { governorAbi } from "@/lib/abi";
import { addresses } from "@/lib/addresses";

export const PROPOSAL_STATE = [
  "Pending",
  "Active",
  "Canceled",
  "Defeated",
  "Succeeded",
  "Queued",
  "Expired",
  "Executed",
] as const;
export type ProposalState = (typeof PROPOSAL_STATE)[number];

export function stateName(idx: number | bigint | undefined): ProposalState | "Unknown" {
  if (idx === undefined) return "Unknown";
  const i = typeof idx === "bigint" ? Number(idx) : idx;
  return PROPOSAL_STATE[i] ?? "Unknown";
}

export function useProposalStates(proposalIds: bigint[]) {
  const contracts = useMemo(
    () =>
      proposalIds.map((id) => ({
        address: addresses.governor,
        abi: governorAbi,
        functionName: "state" as const,
        args: [id] as const,
      })),
    [proposalIds],
  );

  const { data, isLoading, refetch } = useReadContracts({
    allowFailure: true,
    contracts,
    query: { enabled: proposalIds.length > 0 && addresses.governor !== "0x0000000000000000000000000000000000000000" },
  });

  const states: ProposalState[] | undefined = data?.map((r) => stateName(r.result as number | undefined) as ProposalState);
  return { states, isLoading, refetch };
}
