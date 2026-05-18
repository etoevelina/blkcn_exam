import { PortfolioPanel } from "@/components/PortfolioPanel";

export default function PortfolioPage() {
  return (
    <div className="space-y-8">
      <header>
        <h1 className="text-2xl font-semibold">Portfolio</h1>
        <p className="mt-1 text-sm text-neutral-400">
          Your collateral, governance balance, voting power, and delegate.
        </p>
      </header>
      <PortfolioPanel />
    </div>
  );
}
