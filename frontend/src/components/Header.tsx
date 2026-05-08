"use client";

import Link from "next/link";
import { useAccount, useConnect, useDisconnect } from "wagmi";

import { TARGET_CHAIN } from "@/lib/chain";

function shortAddress(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function Header() {
  const { address, isConnected, chainId } = useAccount();
  const { connectors, connect, status, error } = useConnect();
  const { disconnect } = useDisconnect();

  return (
    <header className="border-b border-neutral-800 bg-neutral-950/80 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4">
        <nav className="flex items-center gap-6">
          <Link href="/" className="text-base font-semibold">
            🔮 Prediction Market
          </Link>
          <Link href="/" className="text-sm text-neutral-400 hover:text-neutral-100">
            Markets
          </Link>
          <Link href="/governance" className="text-sm text-neutral-400 hover:text-neutral-100">
            Governance
          </Link>
          <Link href="/portfolio" className="text-sm text-neutral-400 hover:text-neutral-100">
            Portfolio
          </Link>
        </nav>

        <div className="flex items-center gap-3">
          {isConnected ? (
            <>
              <span className="rounded-md bg-neutral-800 px-2 py-1 text-xs">
                {chainId === TARGET_CHAIN.id ? TARGET_CHAIN.name : `chain ${chainId}`}
              </span>
              <span className="rounded-md bg-neutral-800 px-3 py-1 text-sm">
                {shortAddress(address ?? "")}
              </span>
              <button
                type="button"
                onClick={() => disconnect()}
                className="text-xs text-neutral-400 hover:text-neutral-100"
              >
                Disconnect
              </button>
            </>
          ) : (
            <div className="flex items-center gap-2">
              {connectors.map((c) => (
                <button
                  key={c.uid}
                  type="button"
                  onClick={() => connect({ connector: c })}
                  disabled={status === "pending"}
                  className="rounded-lg bg-emerald-500 px-3 py-1.5 text-sm font-medium text-emerald-950 hover:bg-emerald-400 disabled:opacity-50"
                >
                  {c.name}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
      {error ? (
        <p className="mx-auto max-w-6xl px-4 pb-2 text-xs text-red-400">
          Wallet error: {error.message}
        </p>
      ) : null}
    </header>
  );
}
