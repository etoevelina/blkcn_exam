"use client";

import { type ReactNode } from "react";
import { useAccount, useSwitchChain } from "wagmi";

import { TARGET_CHAIN } from "@/lib/chain";

/**
 * NetworkGuard
 * ------------
 * Wraps the app body and blocks render when the user's wallet is on the
 * wrong chain. If the wallet is not connected at all, we let the page
 * render — read-only views are still useful. As soon as a wallet
 * connects on a different chain, we show a banner with a one-click
 * "Switch network" button (uses wallet_switchEthereumChain under the hood;
 * `useSwitchChain` falls back to `wallet_addEthereumChain` if the chain
 * isn't yet registered with the wallet).
 */
export function NetworkGuard({ children }: { children: ReactNode }) {
  const { isConnected, chainId } = useAccount();
  const { switchChain, isPending, error } = useSwitchChain();

  if (!isConnected || chainId === TARGET_CHAIN.id) {
    return <>{children}</>;
  }

  return (
    <div className="rounded-xl border border-amber-500/30 bg-amber-500/5 p-6">
      <h2 className="mb-2 text-lg font-semibold text-amber-300">Wrong network</h2>
      <p className="mb-4 text-sm text-amber-100/80">
        This dApp lives on <strong>{TARGET_CHAIN.name}</strong> (chain id{" "}
        <code className="rounded bg-amber-900/40 px-1">{TARGET_CHAIN.id}</code>). Your wallet is
        currently on chain id <code className="rounded bg-amber-900/40 px-1">{chainId}</code>.
      </p>
      <button
        type="button"
        onClick={() => switchChain({ chainId: TARGET_CHAIN.id })}
        disabled={isPending}
        className="rounded-lg bg-amber-400 px-4 py-2 text-sm font-medium text-amber-950 hover:bg-amber-300 disabled:opacity-50"
      >
        {isPending ? "Switching..." : `Switch to ${TARGET_CHAIN.name}`}
      </button>
      {error ? (
        <p className="mt-3 text-xs text-amber-200/70">
          Switch failed: {error.message}. Please change the network manually in your wallet.
        </p>
      ) : null}
    </div>
  );
}
