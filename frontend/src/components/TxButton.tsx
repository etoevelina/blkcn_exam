"use client";

import { useEffect } from "react";
import toast from "react-hot-toast";
import type { Hash } from "viem";
import { useWaitForTransactionReceipt } from "wagmi";

import { explorerLink, toReadableError } from "@/lib/errors";

interface TxButtonProps {
  label: string;
  /** Triggers the underlying wagmi write call. Returns the hash or throws. */
  onSubmit: () => Promise<Hash | undefined>;
  /** External pending flag (e.g. when waiting for ERC-20 approval first). */
  busy?: boolean;
  disabled?: boolean;
  className?: string;
  /** Latest tx hash returned by useWriteContract — controlled from above. */
  hash?: Hash;
  /** Latest error from useWriteContract / preflight. */
  error?: unknown;
}

/**
 * TxButton
 * --------
 * Unified write-tx UI: handles wallet popup → pending → success → revert
 * states. Maps every error through `toReadableError` (viem/wagmi → human).
 * Mounts `useWaitForTransactionReceipt` to follow the tx after submit.
 */
export function TxButton({
  label,
  onSubmit,
  busy,
  disabled,
  className,
  hash,
  error,
}: TxButtonProps) {
  const {
    isLoading: mining,
    isSuccess,
    isError: receiptIsError,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash });

  // Toast feedback on submit error.
  useEffect(() => {
    if (error) toast.error(toReadableError(error));
  }, [error]);

  // Toast feedback when the tx finishes.
  useEffect(() => {
    if (!hash) return;
    if (isSuccess) {
      toast.success(
        (t) => (
          <span>
            Confirmed.{" "}
            <a
              href={explorerLink(hash)}
              target="_blank"
              rel="noreferrer"
              className="underline"
              onClick={() => toast.dismiss(t.id)}
            >
              View on Arbiscan
            </a>
          </span>
        ),
        { duration: 8_000 },
      );
    } else if (receiptIsError) {
      toast.error(toReadableError(receiptError));
    }
  }, [hash, isSuccess, receiptIsError, receiptError]);

  const handle = async () => {
    try {
      await onSubmit();
    } catch (e) {
      // useWriteContract already exposes the error via the `error` prop,
      // but the throw from `writeContractAsync` would otherwise be
      // swallowed — toast it here too as a belt-and-braces.
      toast.error(toReadableError(e));
    }
  };

  return (
    <button
      type="button"
      onClick={handle}
      disabled={Boolean(busy) || Boolean(disabled) || mining}
      className={
        className ??
        "w-full rounded-lg bg-emerald-500 px-4 py-2 text-sm font-medium text-emerald-950 hover:bg-emerald-400 disabled:opacity-50"
      }
    >
      {mining ? "Mining…" : busy ? "Working…" : label}
    </button>
  );
}
