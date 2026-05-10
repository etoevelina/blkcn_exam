import { PortfolioPanel } from "@/components/PortfolioPanel";
import { ProposalList } from "@/components/ProposalList";

export default function GovernancePage() {
  return (
    <div className="space-y-8">
      <header>
        <h1 className="text-2xl font-semibold">Governance</h1>
        <p className="mt-1 text-sm text-neutral-400">
          Propose, vote, queue, execute. Powered by OZ Governor + Timelock (2-day delay).
        </p>
      </header>

      <PortfolioPanel />

      <ProposalList />
    </div>
  );
}
