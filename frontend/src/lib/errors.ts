// =============================================================================
// Error normalisation — viem/wagmi -> human-readable UI string.
//
// Every <TxButton/> funnel runs its caught error through `toReadableError`.
// Custom Solidity errors thrown by our contracts (PredictionMarket,
// Factory, OutcomeToken1155) are mapped explicitly so the user never
// sees `0x...` selectors or raw RPC noise.
// =============================================================================

import {
  BaseError,
  ContractFunctionRevertedError,
  UserRejectedRequestError,
  InsufficientFundsError,
  HttpRequestError,
  TimeoutError,
} from "viem";
import { ChainMismatchError, ConnectorNotConnectedError } from "wagmi";

/** Human-readable copy for every custom error the protocol throws. */
const CUSTOM_ERRORS: Record<string, (args: readonly unknown[]) => string> = {
  // PredictionMarket
  InvalidState:               ([cur, req]) => `Market is in state ${cur}; this action requires state ${req}.`,
  DeadlineExpired:            ([now, dl]) => `Transaction took too long (block ${now} > deadline ${dl}). Try again with a later deadline.`,
  ZeroAmount:                 ()          => `Amount must be greater than zero.`,
  InsufficientLiquidity:      ()          => `The pool doesn't have enough liquidity to honour this trade.`,
  InsufficientOutputAmount:   ([got, min])=> `Slippage exceeded: would receive ${got}, but you required at least ${min}.`,
  ExcessiveInputAmount:       ([paid, mx])=> `Slippage exceeded: would pay ${paid}, but you capped at ${mx}.`,
  InvalidOutcomeId:           ([id])      => `Invalid outcome id ${id}.`,
  SameOutcomeSwap:            ()          => `Cannot swap an outcome for itself.`,
  TradingNotEnded:            ([now, end])=> `Trading window still open (until ${end}, now ${now}).`,
  DisputeWindowActive:        ([now, end])=> `Dispute window still active until ${end}.`,
  DisputeWindowOver:          ([now, end])=> `Dispute window already closed (ended at ${end}).`,
  NothingToClaim:             ()          => `You don't hold any winning shares to claim.`,
  KInvariantBroken:           ()          => `Internal AMM invariant violated — please report this.`,

  // Factory
  ZeroAddress:                ()          => `Address parameter cannot be zero.`,
  InvalidWindow:              ()          => `Dispute window must be greater than zero.`,
  InvalidFee:                 ()          => `Fee must be in (0, 1000] basis points.`,
  MarketAlreadyDeployed:      ([addr])    => `A market already exists at ${addr}. Pick a different salt.`,
  UnknownMarket:              ([addr])    => `Address ${addr} isn't registered as a market.`,
  InvalidQuestion:            ()          => `Question id cannot be the zero hash.`,
  AlreadyInitialized:         ()          => `Factory has already been initialised.`,

  // OutcomeToken1155
  NotMarketMinter:            ([caller, id]) => `${caller} is not authorised to mint/burn token id ${id}.`,
  MarketAlreadyRegistered:    ([mid])     => `Market id ${mid} is already registered.`,
  InvalidMarket:              ([addr])    => `Invalid market address ${addr}.`,
};

export function toReadableError(error: unknown): string {
  if (!error) return "Unknown error.";

  // wagmi-level errors first (chain mismatch, no wallet)
  if (error instanceof ChainMismatchError) {
    return "Wrong network. Please switch your wallet to Arbitrum Sepolia.";
  }
  if (error instanceof ConnectorNotConnectedError) {
    return "Please connect your wallet first.";
  }

  // viem BaseError — unwrap the chain.
  if (error instanceof BaseError) {
    // 1. user rejection in the wallet popup
    const rejected = error.walk((e) => e instanceof UserRejectedRequestError);
    if (rejected) return "Transaction rejected in your wallet.";

    // 2. revert from one of our custom errors
    const reverted = error.walk((e) => e instanceof ContractFunctionRevertedError);
    if (reverted instanceof ContractFunctionRevertedError) {
      const name = reverted.data?.errorName ?? "";
      const args = (reverted.data?.args ?? []) as readonly unknown[];
      const mapper = CUSTOM_ERRORS[name];
      if (mapper) return mapper(args);
      return reverted.shortMessage ?? `Transaction would revert (${name || "unknown"}).`;
    }

    // 3. wallet/gas/RPC noise
    if (error.walk((e) => e instanceof InsufficientFundsError)) {
      return "Insufficient ETH in your wallet to cover gas.";
    }
    if (error.walk((e) => e instanceof HttpRequestError)) {
      return "Couldn't reach the RPC endpoint. Check your network connection.";
    }
    if (error.walk((e) => e instanceof TimeoutError)) {
      return "RPC request timed out — try again in a moment.";
    }

    return error.shortMessage ?? error.message ?? "Transaction failed.";
  }

  // Non-viem error (e.g. plain Error).
  if (error instanceof Error) return error.message;
  return String(error);
}

/** Convenience: produce a concise tx receipt string. */
export function explorerLink(hash: `0x${string}`): string {
  return `https://sepolia.arbiscan.io/tx/${hash}`;
}
