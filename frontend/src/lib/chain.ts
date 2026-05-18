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
  throw new Error(
    `Chain mismatch: NEXT_PUBLIC_TARGET_CHAIN_ID=${TARGET_CHAIN_ID} but TARGET_CHAIN.id=${TARGET_CHAIN.id}.`,
  );
}
