// =============================================================================
// PredictionMarketFactory event handlers.
//
// Spawns a new dynamic `PredictionMarket` data source for every market
// the factory creates, mirroring the on-chain factory pattern.
// =============================================================================

import { BigInt, Bytes, log } from "@graphprotocol/graph-ts";

import {
  MarketCreated,
  DefaultsUpdated,
  Upgraded,
} from "../generated/PredictionMarketFactory/PredictionMarketFactory";
import { PredictionMarket as PredictionMarketTemplate } from "../generated/templates";
import { Market } from "../generated/schema";

/* -------------------------------------------------------------------------- */
/*  MarketCreated                                                             */
/* -------------------------------------------------------------------------- */

export function handleMarketCreated(event: MarketCreated): void {
  let marketAddress = event.params.market;
  let id = marketAddress.toHexString();
  let market = new Market(id);

  market.marketId = BigInt.fromU64(event.params.marketId);
  market.factory = event.address;
  market.questionId = event.params.questionId;
  // oracleThreshold isn't in the MarketCreated event signature; we'll
  // back-fill from a getter call in W9 once the ABI exposes it.
  market.oracleThreshold = BigInt.zero();
  market.collateralToken = Bytes.fromHexString("0x0000000000000000000000000000000000000000") as Bytes;
  market.outcomeToken    = Bytes.fromHexString("0x0000000000000000000000000000000000000000") as Bytes;

  // YES/NO ids are deterministic from marketId.
  market.yesId = BigInt.fromU64(event.params.marketId).times(BigInt.fromI32(2));
  market.noId  = market.yesId.plus(BigInt.fromI32(1));

  market.feeBps = event.params.feeBps;
  market.tradingEndsAt = BigInt.fromU64(event.params.tradingEndsAt);
  market.disputeEndsAt = null;
  market.status = "Open";
  market.winningOutcome = null;

  market.reserveYes = BigInt.zero();
  market.reserveNo  = BigInt.zero();
  market.totalLpSupply = BigInt.zero();
  market.swapCount = BigInt.zero();
  market.liquidityEventCount = BigInt.zero();

  market.deterministic = event.params.deterministic;
  market.creator = event.transaction.from;
  market.createdAt = event.block.timestamp;
  market.createdAtBlock = event.block.number;
  market.lastUpdatedAt = event.block.timestamp;

  market.save();

  // Spawn the dynamic data source for this market.
  PredictionMarketTemplate.create(marketAddress);

  log.info("Market {} (id={}) created at block {}", [
    id,
    market.marketId.toString(),
    event.block.number.toString(),
  ]);
}

/* -------------------------------------------------------------------------- */
/*  DefaultsUpdated, Upgraded — no entity changes, log only.                  */
/* -------------------------------------------------------------------------- */

export function handleDefaultsUpdated(event: DefaultsUpdated): void {
  log.info("Factory defaults updated: feeBps={}, disputeWindow={}", [
    BigInt.fromI32(event.params.defaultFeeBps).toString(),
    BigInt.fromI32(event.params.defaultDisputeWindow).toString(),
  ]);
}

export function handleUpgraded(event: Upgraded): void {
  log.info("Factory upgraded to implementation {}", [event.params.newImplementation.toHexString()]);
}
