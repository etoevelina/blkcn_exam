import { BigInt, Bytes, log } from "@graphprotocol/graph-ts";

import {
  MarketCreated,
  DefaultsUpdated,
  Upgraded,
} from "../generated/PredictionMarketFactory/PredictionMarketFactory";
import { PredictionMarket as PredictionMarketTemplate } from "../generated/templates";
import { Market } from "../generated/schema";

export function handleMarketCreated(event: MarketCreated): void {
  let marketAddress = event.params.market;
  let id = marketAddress.toHexString();
  let market = new Market(id);

  market.marketId = BigInt.fromU64(event.params.marketId);
  market.factory = event.address;
  market.questionId = event.params.questionId;
  market.oracleThreshold = BigInt.zero();
  market.collateralToken = Bytes.fromHexString("0x0000000000000000000000000000000000000000") as Bytes;
  market.outcomeToken    = Bytes.fromHexString("0x0000000000000000000000000000000000000000") as Bytes;

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

  PredictionMarketTemplate.create(marketAddress);

  log.info("Market {} (id={}) created at block {}", [
    id,
    market.marketId.toString(),
    event.block.number.toString(),
  ]);
}

export function handleDefaultsUpdated(event: DefaultsUpdated): void {
  log.info("Factory defaults updated: feeBps={}, disputeWindow={}", [
    BigInt.fromI32(event.params.defaultFeeBps).toString(),
    BigInt.fromI32(event.params.defaultDisputeWindow).toString(),
  ]);
}

export function handleUpgraded(event: Upgraded): void {
  log.info("Factory upgraded to implementation {}", [event.params.newImplementation.toHexString()]);
}
