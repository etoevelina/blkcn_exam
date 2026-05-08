import { http, createConfig } from "wagmi";
import { injected, walletConnect } from "wagmi/connectors";

import { TARGET_CHAIN } from "./chain";

const wcProjectId = process.env.NEXT_PUBLIC_WC_PROJECT_ID;

export const wagmiConfig = createConfig({
  chains: [TARGET_CHAIN],
  // SSR support — Next.js App Router needs this on or hydration warns.
  ssr: true,
  connectors: [
    injected({ shimDisconnect: true }),
    // WalletConnect is opt-in: only register the connector if a project
    // id is configured. Avoids loud console warnings in dev.
    ...(wcProjectId
      ? [
          walletConnect({
            projectId: wcProjectId,
            metadata: {
              name: "Prediction Market",
              description: "BChT2 capstone — binary outcome prediction markets on Arbitrum Sepolia",
              url: "https://localhost:3000",
              icons: [],
            },
            showQrModal: true,
          }),
        ]
      : []),
  ],
  transports: {
    [TARGET_CHAIN.id]: http(),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
