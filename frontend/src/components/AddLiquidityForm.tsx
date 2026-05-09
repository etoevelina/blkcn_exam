"use client";

// Write #2 — Add liquidity via PredictionMarket.addLiquidity.
//
// Pre-flight:
//   * ensure ERC-20 collateral allowance(user, market) ≥ amount
//   * read pool reserves to estimate `lpMinted` for the slippage check
//
// Submit:
//   1. (optional) approve collateral
//   2. addLiquidity(collateralIn, minLpOut, deadline)

import { useMemo, useState } from "react";
import type { Address, Hash } from "viem";
import { parseUnits } from "viem";
import { useAccount, useReadContract, useWriteContract } from "wagmi";

import { TxButton } from "./TxButton";
import { addresses } from "@/lib/addresses";
import { erc20Abi, marketAbi } from "@/lib/abi";

interface Props {
  market: Address;
}

const DEFAULT_SLIPPAGE_BPS = 100n;     // 1%
const BPS = 10_000n;

export function AddLiquidityForm({ market }: Props) {
  const { address: user } = useAccount();
  const [collateralRaw, setCollateralRaw] = useState("");

  const collateralIn = useMemo(() => {
    if (!collateralRaw) return 0n;
    try { return parseUnits(collateralRaw, 6); } catch { return 0n; }  // USDC = 6
  }, [collateralRaw]);

  /* ── reads ── */
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: addresses.collateralToken,
    abi: erc20Abi,
    functionName: "allowance",
    args: user ? [user, market] : undefined,
    query: { enabled: Boolean(user) },
  });

  const { data: balance } = useReadContract({
    address: addresses.collateralToken,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: user ? [user] : undefined,
    query: { enabled: Boolean(user) },
  });

  const { data: lpSupply } = useReadContract({
    address: market,
    abi: marketAbi,
    functionName: "totalSupply",
  });

  const { data: reservesData } = useReadContract({
    address: market,
    abi: marketAbi,
    functionName: "reserves",
  });

  const reserveYes = (reservesData as readonly [bigint, bigint] | undefined)?.[0] ?? 0n;
  const reserveNo  = (reservesData as readonly [bigint, bigint] | undefined)?.[1] ?? 0n;

  /** Off-chain mirror of `addLiquidity` math for the slippage estimate. */
  const estimatedLp = useMemo(() => {
    if (collateralIn === 0n) return 0n;
    if (reserveYes === 0n && reserveNo === 0n) {
      // Initial deposit; lpMinted = C - MIN_LIQUIDITY (1000).
      return collateralIn > 1000n ? collateralIn - 1000n : 0n;
    }
    const supply = (lpSupply as bigint | undefined) ?? 0n;
    if (supply === 0n) return 0n;
    if (reserveYes >= reserveNo) {
      return (supply * collateralIn) / reserveYes;
    }
    return (supply * collateralIn) / reserveNo;
  }, [collateralIn, reserveYes, reserveNo, lpSupply]);

  const minLpOut = useMemo(
    () => (estimatedLp * (BPS - DEFAULT_SLIPPAGE_BPS)) / BPS,
    [estimatedLp],
  );

  /* ── writes ── */
  const { writeContractAsync, data: hash, error } = useWriteContract();

  const submitApprove = async (): Promise<Hash | undefined> => {
    const tx = await writeContractAsync({
      address: addresses.collateralToken,
      abi: erc20Abi,
      functionName: "approve",
      args: [market, collateralIn],
    });
    void refetchAllowance();
    return tx;
  };

  const submitAdd = async (): Promise<Hash | undefined> => {
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 600);
    return writeContractAsync({
      address: market,
      abi: marketAbi,
      functionName: "addLiquidity",
      args: [collateralIn, minLpOut, deadline],
    });
  };

  const needsApproval =
    collateralIn > 0n && (allowance === undefined || (allowance as bigint) < collateralIn);
  const insufficient =
    balance !== undefined && (balance as bigint) < collateralIn;

  return (
    <div className="space-y-4 rounded-xl border border-neutral-800 bg-neutral-900 p-5">
      <h3 className="text-base font-semibold">Add liquidity</h3>

      <label className="block text-xs text-neutral-400">
        Collateral (USDC)
        <input
          value={collateralRaw}
          onChange={(e) => setCollateralRaw(e.target.value)}
          inputMode="decimal"
          placeholder="0.0"
          className="mt-1 w-full rounded-md border border-neutral-700 bg-neutral-950 px-3 py-2 text-base text-neutral-100"
        />
        {balance !== undefined ? (
          <span className="mt-1 block text-[10px] text-neutral-500">
            Wallet balance: {(balance as bigint).toString()}
          </span>
        ) : null}
      </label>

      <div className="flex items-center justify-between text-sm">
        <span className="text-neutral-400">Estimated LP minted</span>
        <span className="font-mono">{estimatedLp.toString()}</span>
      </div>
      <div className="flex items-center justify-between text-xs">
        <span className="text-neutral-500">Min LP @ 1% slippage</span>
        <span className="font-mono text-neutral-400">{minLpOut.toString()}</span>
      </div>

      {insufficient ? (
        <p className="text-xs text-amber-400">Insufficient USDC in your wallet.</p>
      ) : null}

      {needsApproval ? (
        <TxButton
          label="Approve USDC"
          onSubmit={submitApprove}
          disabled={!user || insufficient || collateralIn === 0n}
          hash={hash}
          error={error}
        />
      ) : (
        <TxButton
          label="Add liquidity"
          onSubmit={submitAdd}
          disabled={!user || insufficient || collateralIn === 0n}
          hash={hash}
          error={error}
        />
      )}
    </div>
  );
}
