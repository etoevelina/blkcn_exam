import Link from "next/link";

import { subgraphClient } from "@/lib/subgraph";
import { ACTIVE_MARKETS } from "@/lib/queries";

interface Market {
  id: string;
  marketId: string;
  questionId: string;
  feeBps: number;
  status: string;
  tradingEndsAt: string;
  reserveYes: string;
  reserveNo: string;
  totalLpSupply: string;
  swapCount: string;
}

async function fetchMarkets(): Promise<Market[]> {
  const { data, error } = await subgraphClient.query<{ markets: Market[] }>(ACTIVE_MARKETS, {}).toPromise();
  if (error) {
    console.error("Subgraph error:", error);
    return [];
  }
  return data?.markets ?? [];
}

export default async function Page() {
  const markets = await fetchMarkets();

  return (
    <section>
      <header className="mb-6 flex items-baseline justify-between">
        <h1 className="text-2xl font-semibold">Active markets</h1>
        <p className="text-sm text-neutral-400">{markets.length} live</p>
      </header>

      {markets.length === 0 ? (
        <div className="rounded-xl border border-neutral-800 bg-neutral-900 p-6 text-sm text-neutral-400">
          No markets yet. The factory is awaiting its first proposal.
        </div>
      ) : (
        <ul className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {markets.map((m) => (
            <li key={m.id}>
              <Link
                href={`/markets/${m.id}`}
                className="block rounded-xl border border-neutral-800 bg-neutral-900 p-5 transition hover:border-emerald-500/40"
              >
                <p className="text-xs text-neutral-500">marketId {m.marketId}</p>
                <h3 className="mt-1 truncate font-mono text-sm">{m.questionId}</h3>
                <dl className="mt-4 grid grid-cols-3 gap-2 text-xs text-neutral-300">
                  <Stat label="Status"  value={m.status} />
                  <Stat label="Fee"     value={`${m.feeBps / 100}%`} />
                  <Stat label="Swaps"   value={m.swapCount} />
                  <Stat label="R(YES)"  value={m.reserveYes} />
                  <Stat label="R(NO)"   value={m.reserveNo} />
                  <Stat label="LP"      value={m.totalLpSupply} />
                </dl>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-neutral-500">{label}</dt>
      <dd className="font-mono">{value}</dd>
    </div>
  );
}
