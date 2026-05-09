"use client";

// Reads:
//   * collateral (USDC) balance       — erc20.balanceOf(user)
//   * governance token balance        — gov.balanceOf(user)
//   * voting power (current)          — gov.getVotes(user)
//   * delegate address                — gov.delegates(user)
//
// All four come back in a single multicall via useReadContracts.

import { useAccount, useReadContracts } from "wagmi";

import { addresses } from "@/lib/addresses";
import { erc20Abi, governanceTokenAbi } from "@/lib/abi";

function fmt(x: bigint | undefined, decimals = 18): string {
  if (x === undefined) return "—";
  const s = x.toString().padStart(decimals + 1, "0");
  const i = s.length - decimals;
  return `${s.slice(0, i)}.${s.slice(i)}`;
}

export function PortfolioPanel() {
  const { address: user, isConnected } = useAccount();

  const { data, isLoading } = useReadContracts({
    allowFailure: true,
    contracts: user
      ? [
          { address: addresses.collateralToken, abi: erc20Abi,           functionName: "balanceOf", args: [user] },
          { address: addresses.governanceToken, abi: governanceTokenAbi, functionName: "balanceOf", args: [user] },
          { address: addresses.governanceToken, abi: governanceTokenAbi, functionName: "getVotes",  args: [user] },
          { address: addresses.governanceToken, abi: governanceTokenAbi, functionName: "delegates", args: [user] },
        ]
      : [],
    query: { enabled: isConnected },
  });

  if (!isConnected) {
    return <p className="text-sm text-neutral-400">Connect a wallet to see your portfolio.</p>;
  }
  if (isLoading) return <p className="text-sm text-neutral-400">Loading…</p>;

  const [usdcBal, govBal, votes, delegate] = (data ?? []) as readonly {
    result?: bigint | string;
    error?: Error;
  }[];

  return (
    <section className="grid grid-cols-1 gap-3 rounded-xl border border-neutral-800 bg-neutral-900 p-5 sm:grid-cols-2">
      <Stat label="USDC balance"     value={fmt(usdcBal?.result as bigint | undefined, 6)} />
      <Stat label="Governance token" value={fmt(govBal?.result   as bigint | undefined)} />
      <Stat label="Voting power"     value={fmt(votes?.result    as bigint | undefined)} />
      <Stat label="Delegate"         value={(delegate?.result as string | undefined) ?? "—"} mono />
    </section>
  );
}

function Stat({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div>
      <p className="text-xs uppercase tracking-wide text-neutral-500">{label}</p>
      <p className={mono ? "font-mono text-sm" : "text-lg font-semibold"}>{value}</p>
    </div>
  );
}
