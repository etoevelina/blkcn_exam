/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // wagmi + viem ship pure ESM modules; Next.js needs to transpile them
  // through the server bundler.
  transpilePackages: ["wagmi", "viem", "@wagmi/core"],
  // Force the dApp to refuse rendering outside its expected chain at build
  // time by failing fast if the env contract is missing the target chain.
  env: {
    NEXT_PUBLIC_TARGET_CHAIN_ID: process.env.NEXT_PUBLIC_TARGET_CHAIN_ID ?? "421614",
    NEXT_PUBLIC_SUBGRAPH_URL: process.env.NEXT_PUBLIC_SUBGRAPH_URL ?? "",
  },
};

export default nextConfig;
