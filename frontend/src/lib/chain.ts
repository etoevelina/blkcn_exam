// Single source of truth for the target chain. NetworkGuard, wagmi
// config, and any read/write hook compares against this object.
//
// We deliberately import the canonical chain definition from viem so we
// inherit the right RPC URL, block explorer, and native currency, but
// allow overriding the RPC via `NEXT_PUBLIC_RPC_URL` (used by Anvil in dev).

import { arbitrumSepolia } from "wagmi/chains";

const overrideRpc = process.env.NEXT_PUBLIC_RPC_URL;

export const TARGET_CHAIN = overrideRpc
  ? {
      ...arbitrumSepolia,
      rpcUrls: {
        default: { http: [overrideRpc] },
        public: { http: [overrideRpc] },
      },
    }
  : arbitrumSepolia;

export const TARGET_CHAIN_ID = Number(process.env.NEXT_PUBLIC_TARGET_CHAIN_ID ?? TARGET_CHAIN.id);

if (TARGET_CHAIN_ID !== TARGET_CHAIN.id) {
  // Build-time guardrail: env says one chain, code targets another.
  throw new Error(
    `Chain mismatch: NEXT_PUBLIC_TARGET_CHAIN_ID=${TARGET_CHAIN_ID} but TARGET_CHAIN.id=${TARGET_CHAIN.id}.`,
  );
}
