// =============================================================================
// PredictionMarket (per-instance) event handlers.
//
// One dynamic data source is created per market by factory.ts, so each
// handler here operates on the market whose address matches event.address.
// =============================================================================

import { Address, BigInt, log } from "@graphprotocol/graph-ts";

import {
  Swap as SwapEvent,
  LiquidityAdded,
  LiquidityRemoved,
  CompleteSetsMinted,
  CompleteSetsRedeemed,
  MarketLocked,
  OutcomeReported,
  DisputeRaised,
  DisputeResolved,
  MarketFinalized,
  MarketInvalidated,
  WinningsClaimed,
} from "../generated/templates/PredictionMarket/PredictionMarket";
import { Market, Trader, Swap, LiquidityEvent, UserPosition } from "../generated/schema";

/* ─── Trader upsert ───────────────────────────────────────────────────────── */

function loadOrCreateTrader(addr: Address, ts: BigInt): Trader {
  let id = addr.toHexString();
  let t = Trader.load(id);
  if (t === null) {
    t = new Trader(id);
    t.swapCount = BigInt.zero();
    t.liquidityEventCount = BigInt.zero();
    t.totalVolumeIn = BigInt.zero();
    t.totalFeesPaid = BigInt.zero();
    t.firstSeenAt = ts;
  }
  t.lastSeenAt = ts;
  return t;
}

function loadOrCreatePosition(user: Address, market: Address, ts: BigInt): UserPosition {
  let id = user.toHexString() + "-" + market.toHexString();
  let p = UserPosition.load(id);
  if (p === null) {
    p = new UserPosition(id);
    p.user = user;
    p.market = market.toHexString();
    p.yesBalance = BigInt.zero();
    p.noBalance = BigInt.zero();
    p.lpBalance = BigInt.zero();
    p.collateralClaimed = BigInt.zero();
  }
  p.lastUpdatedAt = ts;
  return p;
}

function eventId(txHash: string, logIndex: BigInt): string {
  return txHash + "-" + logIndex.toString();
}

function loadMarket(addr: Address): Market | null {
  return Market.load(addr.toHexString());
}

/* -------------------------------------------------------------------------- */
/*  Swap                                                                      */
/* -------------------------------------------------------------------------- */

export function handleSwap(event: SwapEvent): void {
  let market = loadMarket(event.address);
  if (market === null) {
    log.warning("Swap on unknown market {}", [event.address.toHexString()]);
    return;
  }

  let trader = loadOrCreateTrader(event.params.trader, event.block.timestamp);

  // Update market reserves: reserveIn += amountIn, reserveOut -= amountOut.
  if (event.params.outcomeIn.equals(market.yesId)) {
    market.reserveYes = market.reserveYes.plus(event.params.amountIn);
    market.reserveNo  = market.reserveNo.minus(event.params.amountOut);
  } else {
    market.reserveNo  = market.reserveNo.plus(event.params.amountIn);
    market.reserveYes = market.reserveYes.minus(event.params.amountOut);
  }
  market.swapCount = market.swapCount.plus(BigInt.fromI32(1));
  market.lastUpdatedAt = event.block.timestamp;
  market.save();

  trader.swapCount = trader.swapCount.plus(BigInt.fromI32(1));
  trader.totalVolumeIn = trader.totalVolumeIn.plus(event.params.amountIn);
  trader.totalFeesPaid = trader.totalFeesPaid.plus(event.params.feeAccrued);
  trader.save();

  let swap = new Swap(eventId(event.transaction.hash.toHexString(), event.logIndex));
  swap.market = market.id;
  swap.trader = trader.id;
  swap.outcomeInId = event.params.outcomeIn;
  swap.outcomeOutId = event.params.outcomeOut;
  swap.amountIn = event.params.amountIn;
  swap.amountOut = event.params.amountOut;
  swap.feeAccrued = event.params.feeAccrued;
  swap.reserveYesAfter = market.reserveYes;
  swap.reserveNoAfter  = market.reserveNo;
  swap.timestamp = event.block.timestamp;
  swap.blockNumber = event.block.number;
  swap.transactionHash = event.transaction.hash;
  swap.save();

  // Adjust the trader's ERC-1155 position.
  let pos = loadOrCreatePosition(event.params.trader, event.address, event.block.timestamp);
  if (event.params.outcomeIn.equals(market.yesId)) {
    pos.yesBalance = pos.yesBalance.minus(event.params.amountIn);
    pos.noBalance  = pos.noBalance.plus(event.params.amountOut);
  } else {
    pos.noBalance  = pos.noBalance.minus(event.params.amountIn);
    pos.yesBalance = pos.yesBalance.plus(event.params.amountOut);
  }
  pos.save();
}

/* -------------------------------------------------------------------------- */
/*  LiquidityAdded / LiquidityRemoved                                         */
/* -------------------------------------------------------------------------- */

export function handleLiquidityAdded(event: LiquidityAdded): void {
  let market = loadMarket(event.address);
  if (market === null) return;

  let provider = loadOrCreateTrader(event.params.provider, event.block.timestamp);
  market.reserveYes = market.reserveYes.plus(event.params.yesAdded);
  market.reserveNo  = market.reserveNo.plus(event.params.noAdded);
  market.totalLpSupply = market.totalLpSupply.plus(event.params.lpMinted);
  market.liquidityEventCount = market.liquidityEventCount.plus(BigInt.fromI32(1));
  market.lastUpdatedAt = event.block.timestamp;
  market.save();

  provider.liquidityEventCount = provider.liquidityEventCount.plus(BigInt.fromI32(1));
  provider.save();

  let ev = new LiquidityEvent(eventId(event.transaction.hash.toHexString(), event.logIndex));
  ev.market = market.id;
  ev.provider = provider.id;
  ev.kind = "Add";
  ev.collateralIn = event.params.collateralIn;
  ev.lpAmount = event.params.lpMinted;
  ev.yesAmount = event.params.yesAdded;
  ev.noAmount  = event.params.noAdded;
  ev.timestamp = event.block.timestamp;
  ev.blockNumber = event.block.number;
  ev.transactionHash = event.transaction.hash;
  ev.save();

  let pos = loadOrCreatePosition(event.params.provider, event.address, event.block.timestamp);
  pos.lpBalance = pos.lpBalance.plus(event.params.lpMinted);
  // Leftover YES/NO (collateralIn - yesAdded, collateralIn - noAdded) is
  // sent to the LP — we'll capture those via the ERC-1155 TransferSingle
  // handler in W8 once we add an OutcomeToken1155 data source.
  pos.save();
}

export function handleLiquidityRemoved(event: LiquidityRemoved): void {
  let market = loadMarket(event.address);
  if (market === null) return;

  market.reserveYes = market.reserveYes.minus(event.params.yesOut);
  market.reserveNo  = market.reserveNo.minus(event.params.noOut);
  market.totalLpSupply = market.totalLpSupply.minus(event.params.lpBurnt);
  market.liquidityEventCount = market.liquidityEventCount.plus(BigInt.fromI32(1));
  market.lastUpdatedAt = event.block.timestamp;
  market.save();

  let provider = loadOrCreateTrader(event.params.provider, event.block.timestamp);
  provider.liquidityEventCount = provider.liquidityEventCount.plus(BigInt.fromI32(1));
  provider.save();

  let ev = new LiquidityEvent(eventId(event.transaction.hash.toHexString(), event.logIndex));
  ev.market = market.id;
  ev.provider = provider.id;
  ev.kind = "Remove";
  ev.collateralIn = BigInt.zero();
  ev.lpAmount = event.params.lpBurnt;
  ev.yesAmount = event.params.yesOut;
  ev.noAmount  = event.params.noOut;
  ev.timestamp = event.block.timestamp;
  ev.blockNumber = event.block.number;
  ev.transactionHash = event.transaction.hash;
  ev.save();

  let pos = loadOrCreatePosition(event.params.provider, event.address, event.block.timestamp);
  pos.lpBalance = pos.lpBalance.minus(event.params.lpBurnt);
  pos.save();
}

/* -------------------------------------------------------------------------- */
/*  Complete sets                                                             */
/* -------------------------------------------------------------------------- */

export function handleCompleteSetsMinted(event: CompleteSetsMinted): void {
  let pos = loadOrCreatePosition(event.params.user, event.address, event.block.timestamp);
  pos.yesBalance = pos.yesBalance.plus(event.params.amount);
  pos.noBalance  = pos.noBalance.plus(event.params.amount);
  pos.save();
}

export function handleCompleteSetsRedeemed(event: CompleteSetsRedeemed): void {
  let pos = loadOrCreatePosition(event.params.user, event.address, event.block.timestamp);
  pos.yesBalance = pos.yesBalance.minus(event.params.amount);
  pos.noBalance  = pos.noBalance.minus(event.params.amount);
  pos.save();
}

/* -------------------------------------------------------------------------- */
/*  Lifecycle                                                                 */
/* -------------------------------------------------------------------------- */

export function handleMarketLocked(event: MarketLocked): void {
  let market = loadMarket(event.address);
  if (market === null) return;
  market.status = "Locked";
  market.lastUpdatedAt = event.block.timestamp;
  market.save();
}

export function handleOutcomeReported(event: OutcomeReported): void {
  let market = loadMarket(event.address);
  if (market === null) return;
  market.status = "Reported";
  market.winningOutcome = event.params.outcome;
  market.disputeEndsAt = BigInt.fromU64(event.params.disputeEndsAt);
  market.lastUpdatedAt = event.block.timestamp;
  market.save();
}

export function handleDisputeRaised(event: DisputeRaised): void {
  let market = loadMarket(event.address);
  if (market === null) return;
  market.status = "Disputed";
  market.lastUpdatedAt = event.block.timestamp;
  market.save();
}

export function handleDisputeResolved(event: DisputeResolved): void {
  let market = loadMarket(event.address);
  if (market === null) return;
  market.status = "Finalized";
  market.winningOutcome = event.params.finalOutcome;
  market.lastUpdatedAt = event.block.timestamp;
  market.save();
}

export function handleMarketFinalized(event: MarketFinalized): void {
  let market = loadMarket(event.address);
  if (market === null) return;
  market.status = "Finalized";
  market.winningOutcome = event.params.winningOutcome;
  market.lastUpdatedAt = event.block.timestamp;
  market.save();
}

export function handleMarketInvalidated(event: MarketInvalidated): void {
  let market = loadMarket(event.address);
  if (market === null) return;
  market.status = "Invalid";
  market.lastUpdatedAt = event.block.timestamp;
  market.save();
}

export function handleWinningsClaimed(event: WinningsClaimed): void {
  let pos = loadOrCreatePosition(event.params.user, event.address, event.block.timestamp);
  // The winning shares were burnt by the contract; zero out whichever
  // side actually won (we look it up from the market).
  let market = loadMarket(event.address);
  if (market === null) return;
  if (market.winningOutcome == 0) {
    pos.yesBalance = pos.yesBalance.minus(event.params.sharesBurnt);
  } else {
    pos.noBalance = pos.noBalance.minus(event.params.sharesBurnt);
  }
  pos.collateralClaimed = pos.collateralClaimed.plus(event.params.collateralOut);
  pos.save();
}
