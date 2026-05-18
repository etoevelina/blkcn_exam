"use client";

import { useMemo, useState } from "react";
import type { Address, Hash } from "viem";
import { parseUnits } from "viem";
import { useAccount, useReadContract, useReadContracts, useWriteContract } from "wagmi";

import { TxButton } from "./TxButton";
import { addresses } from "@/lib/addresses";
import { marketAbi, outcomeTokenAbi } from "@/lib/abi";

interface Props {
  market: Address;
}

const DEFAULT_SLIPPAGE_BPS = 50n;
const BPS = 10_000n;

export function SwapForm({ market }: Props) {
  const { address: user } = useAccount();
  const [direction, setDirection] = useState<"YES->NO" | "NO->YES">("YES->NO");
  const [amountInRaw, setAmountInRaw] = useState("");
  const [slippageBps, setSlippageBps] = useState<bigint>(DEFAULT_SLIPPAGE_BPS);

  const marketReads = useReadContracts({
    allowFailure: false,
    contracts: [
      { address: market, abi: marketAbi, functionName: "reserves" },
      { address: market, abi: marketAbi, functionName: "yesId" },
      { address: market, abi: marketAbi, functionName: "noId" },
      { address: market, abi: marketAbi, functionName: "feeBps" },
    ],
  });

  const [reserves, yesId, noId, feeBps] = (marketReads.data ?? []) as readonly [
    readonly [bigint, bigint],
    bigint,
    bigint,
    number,
  ];
  const reserveYes = reserves?.[0] ?? 0n;
  const reserveNo  = reserves?.[1] ?? 0n;

  const inId  = direction === "YES->NO" ? yesId : noId;
  const outId = direction === "YES->NO" ? noId  : yesId;
  const reserveIn  = direction === "YES->NO" ? reserveYes : reserveNo;
  const reserveOut = direction === "YES->NO" ? reserveNo  : reserveYes;

  const amountIn = useMemo(() => {
    if (!amountInRaw) return 0n;
    try { return parseUnits(amountInRaw, 18); } catch { return 0n; }
  }, [amountInRaw]);

  const { data: amountOut } = useReadContract({
    address: market,
    abi: marketAbi,
    functionName: "getAmountOut",
    args: [amountIn, reserveIn, reserveOut],
    query: { enabled: amountIn > 0n && reserveIn > 0n && reserveOut > 0n },
  });

  const minOut = useMemo(() => {
    if (!amountOut) return 0n;
    return (amountOut * (BPS - slippageBps)) / BPS;
  }, [amountOut, slippageBps]);

  const { data: isApproved } = useReadContract({
    address: addresses.outcomeToken,
    abi: outcomeTokenAbi,
    functionName: "isApprovedForAll",
    args: user ? [user, market] : undefined,
    query: { enabled: Boolean(user) },
  });

  const { writeContractAsync, data: hash, error } = useWriteContract();

  const submitApprove = async (): Promise<Hash | undefined> => {
    return writeContractAsync({
      address: addresses.outcomeToken,
      abi: outcomeTokenAbi,
      functionName: "setApprovalForAll",
      args: [market, true],
    });
  };

  const submitSwap = async (): Promise<Hash | undefined> => {
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 600);
    return writeContractAsync({
      address: market,
      abi: marketAbi,
      functionName: "swap",
      args: [inId, outId, amountIn, minOut, deadline],
    });
  };

  const ready = amountIn > 0n && (amountOut ?? 0n) > 0n && isApproved && user;

  return (
    <div className="space-y-4 rounded-xl border border-neutral-800 bg-neutral-900 p-5">
      <div className="flex items-center justify-between">
        <h3 className="text-base font-semibold">Swap</h3>
        <div className="text-xs text-neutral-400">fee {(feeBps ?? 30) / 100}%</div>
      </div>

      <div className="flex gap-2">
        <button
          type="button"
          onClick={() => setDirection("YES->NO")}
          className={`flex-1 rounded-md px-3 py-2 text-sm ${
            direction === "YES->NO" ? "bg-emerald-500 text-emerald-950" : "bg-neutral-800"
          }`}
        >
          Sell YES → Buy NO
        </button>
        <button
          type="button"
          onClick={() => setDirection("NO->YES")}
          className={`flex-1 rounded-md px-3 py-2 text-sm ${
            direction === "NO->YES" ? "bg-emerald-500 text-emerald-950" : "bg-neutral-800"
          }`}
        >
          Sell NO → Buy YES
        </button>
      </div>

      <label className="block text-xs text-neutral-400">
        Amount in
        <input
          value={amountInRaw}
          onChange={(e) => setAmountInRaw(e.target.value)}
          inputMode="decimal"
          placeholder="0.0"
          className="mt-1 w-full rounded-md border border-neutral-700 bg-neutral-950 px-3 py-2 text-base text-neutral-100"
        />
      </label>

      <div className="flex items-center justify-between text-sm">
        <span className="text-neutral-400">Estimated out</span>
        <span className="font-mono">{amountOut?.toString() ?? "—"}</span>
      </div>
      <div className="flex items-center justify-between text-xs">
        <span className="text-neutral-500">Min out @ {Number(slippageBps) / 100}% slippage</span>
        <span className="font-mono text-neutral-400">{minOut.toString()}</span>
      </div>

      {!isApproved && user ? (
        <TxButton
          label="Approve outcome shares"
          onSubmit={submitApprove}
          hash={hash}
          error={error}
        />
      ) : (
        <TxButton
          label={`Swap ${direction.replace("->", " → ")}`}
          onSubmit={submitSwap}
          disabled={!ready}
          hash={hash}
          error={error}
        />
      )}
    </div>
  );
}
